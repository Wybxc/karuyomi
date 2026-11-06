import { openDB, type DBSchema, type IDBPDatabase } from 'idb';
import type { BundleArtifact } from '@karuyomi/contracts';
import { RuntimeFailure } from './errors.js';

export const EXTENSION_CACHE_BYTES = 256 * 1024 * 1024;
export const EXTENSION_CACHE_ARTIFACTS = 128;
export interface CachedExtensionArtifact {
  sha256: string;
  byteLength: number;
  contentType: string;
}
export interface ExtensionArtifactPin {
  release(): void;
  released: Promise<void>;
}
interface ExtensionArtifacts extends DBSchema {
  metadata: { key: string; value: CachedExtensionArtifact };
  bytes: { key: string; value: ArrayBuffer };
}

/** Public AOT code only. Account choices and Source storage live elsewhere. */
export class ExtensionArtifactCache {
  private database: Promise<IDBPDatabase<ExtensionArtifacts>> | undefined;
  constructor(
    private readonly name = 'karuyomi-extension-artifacts-v1',
    readonly maxBytes = EXTENSION_CACHE_BYTES,
    readonly maxArtifacts = EXTENSION_CACHE_ARTIFACTS,
  ) {
    if (
      !Number.isSafeInteger(maxBytes) ||
      maxBytes < 1 ||
      maxBytes > EXTENSION_CACHE_BYTES ||
      !Number.isSafeInteger(maxArtifacts) ||
      maxArtifacts < 1 ||
      maxArtifacts > EXTENSION_CACHE_ARTIFACTS
    )
      throw new Error('Invalid extension cache budget');
  }

  private open(): Promise<IDBPDatabase<ExtensionArtifacts>> {
    if (this.database) return this.database;
    let connection: IDBPDatabase<ExtensionArtifacts> | undefined;
    const pending = openDB<ExtensionArtifacts>(this.name, 1, {
      upgrade(database) {
        database.createObjectStore('metadata');
        database.createObjectStore('bytes');
      },
      blocking: () => {
        connection?.close();
        if (this.database === pending) this.database = undefined;
      },
      terminated: () => {
        if (this.database === pending) this.database = undefined;
      },
    }).then(
      (database) => {
        connection = database;
        return database;
      },
      (error: unknown) => {
        if (this.database === pending) this.database = undefined;
        throw error;
      },
    );
    this.database = pending;
    return pending;
  }

  async read(
    artifact: BundleArtifact,
    signal?: AbortSignal,
  ): Promise<Uint8Array<ArrayBuffer> | undefined> {
    signal?.throwIfAborted();
    const database = await this.open();
    signal?.throwIfAborted();
    const transaction = database.transaction(['metadata', 'bytes']);
    try {
      const metadata = await transaction
        .objectStore('metadata')
        .get(artifact.sha256);
      const bytes = metadata
        ? await transaction.objectStore('bytes').get(artifact.sha256)
        : undefined;
      await transaction.done;
      signal?.throwIfAborted();
      if (!metadata || !bytes) return undefined;
      // The receipt records a verified download; stored bytes are not rehashed.
      if (
        metadata.sha256 !== artifact.sha256 ||
        metadata.byteLength !== artifact.size ||
        bytes.byteLength !== artifact.size ||
        metadata.contentType !== artifact.contentType
      )
        throw new RuntimeFailure(
          'integrity_error',
          'Prepared artifact metadata does not match its receipt',
        );
      return new Uint8Array(bytes);
    } catch (error) {
      await transaction.done.catch(() => {});
      throw error;
    }
  }

  /** Bytes must already have passed the loader's download integrity boundary. */
  async storeVerified(
    artifact: BundleArtifact,
    bytes: Uint8Array<ArrayBuffer>,
    signal?: AbortSignal,
  ): Promise<void> {
    signal?.throwIfAborted();
    if (bytes.byteLength !== artifact.size)
      throw new RuntimeFailure(
        'integrity_error',
        'Verified artifact size changed',
      );
    const storedBytes = bytes.slice().buffer;
    const { sha256, size, contentType } = artifact;
    const database = await this.open();
    signal?.throwIfAborted();
    const transaction = database.transaction(
      ['metadata', 'bytes'],
      'readwrite',
    );
    const abort = () => {
      try {
        transaction.abort();
      } catch {
        /* Already settled. */
      }
    };
    signal?.addEventListener('abort', abort, { once: true });
    try {
      const records = await transaction.objectStore('metadata').getAll();
      const others = records.filter((record) => record.sha256 !== sha256);
      const byteLength = others.reduce(
        (total, record) => total + record.byteLength,
        0,
      );
      if (
        others.length + 1 > this.maxArtifacts ||
        byteLength + size > this.maxBytes
      )
        throw new RuntimeFailure(
          'limit_exceeded',
          'Extension cache is full; remove unused local artifacts before preparing another build',
        );
      signal?.throwIfAborted();
      await transaction.objectStore('bytes').put(storedBytes, sha256);
      await transaction
        .objectStore('metadata')
        .put({ sha256, byteLength: size, contentType }, sha256);
      await transaction.done;
      signal?.throwIfAborted();
    } catch (error) {
      abort();
      await transaction.done.catch(() => {});
      signal?.throwIfAborted();
      throw error;
    } finally {
      signal?.removeEventListener('abort', abort);
    }
  }

  async entries(): Promise<CachedExtensionArtifact[]> {
    const database = await this.open();
    return (await database.getAll('metadata')).sort((a, b) =>
      a.sha256.localeCompare(b.sha256),
    );
  }

  async retain(
    sha256: string,
    signal: AbortSignal,
  ): Promise<ExtensionArtifactPin> {
    const locks = globalThis.navigator?.locks;
    if (!locks)
      throw new RuntimeFailure(
        'unsupported_capability',
        'Extension cache requires Web Locks',
      );
    return new Promise((resolve, reject) => {
      const released = locks.request(
        `karuyomi:extension-artifact:${sha256}`,
        { mode: 'shared', signal },
        () =>
          new Promise<void>((release) => {
            resolve({ release, released });
          }),
      );
      void released.catch(reject);
    });
  }

  async remove(sha256: string): Promise<void> {
    const locks = globalThis.navigator?.locks;
    if (!locks)
      throw new RuntimeFailure(
        'unsupported_capability',
        'Extension cache requires Web Locks',
      );
    await locks.request(
      `karuyomi:extension-artifact:${sha256}`,
      { mode: 'exclusive', ifAvailable: true },
      async (lock) => {
        if (!lock)
          throw new RuntimeFailure(
            'storage_busy',
            'This extension artifact is in use; close the active build before clearing it',
          );
        const database = await this.open();
        const transaction = database.transaction(
          ['metadata', 'bytes'],
          'readwrite',
        );
        try {
          await Promise.all([
            transaction.objectStore('metadata').delete(sha256),
            transaction.objectStore('bytes').delete(sha256),
          ]);
          await transaction.done;
        } catch (error) {
          await transaction.done.catch(() => {});
          throw error;
        }
      },
    );
  }

  async close(): Promise<void> {
    const database = this.database;
    this.database = undefined;
    (await database)?.close();
  }
}
