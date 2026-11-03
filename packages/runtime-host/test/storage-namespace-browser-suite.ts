/** Actual product manager/Worker/loader/driver + controlled TS ABI + real IDB/Web Locks. */
import { create } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import { SourceRuntimeManager } from '../src/manager.js';
import { VerifiedLoader } from '../src/verified-loader.js';
import {
  integer,
  object,
  text,
} from '../../../runtime/teavm/bridge/bridge-common.js';
import { openDB, deleteDB, type DBSchema } from 'idb';

function check(value: unknown, label: string): asserts value {
  if (!value) throw Error(label);
}
// Cleanup only reads/deletes generic keys after Workers stop; it never decodes business values.
interface CleanupSchema extends DBSchema {
  [store: string]: { key: IDBValidKey; value: unknown };
}
interface Target {
  manifestPath: string;
  buildId: string;
  identity: string;
}
export async function runStorageNamespaceSuite() {
  const configuration = object(
      await (await fetch('/fixture.json', { cache: 'no-store' })).json(),
    ),
    run = text(configuration.run);
  const target = (
    name: string,
    identity = 'controlled-owner-' + run,
  ): Target => ({
    manifestPath: '/extensions/builds/storage-' + name + '/manifest.json',
    buildId: 'storage-' + name,
    identity,
  });
  const managers: SourceRuntimeManager[] = [],
    namespaces = new Set<string>(),
    urls: string[] = [],
    checks: string[] = [];
  const make = () => {
    const manager = new SourceRuntimeManager(
      new URL('/worker.js', location.href),
      (url) => {
        const plugin = url.searchParams.get('plugin');
        check(
          plugin &&
            /^[a-f0-9]{64}$/.test(plugin) &&
            plugin === url.searchParams.get('fsNamespace'),
          'Real manager sets identical 64hex keys',
        );
        namespaces.add(plugin);
        urls.push(url.href);
        return new Worker(url);
      },
      new VerifiedLoader(location.origin),
      60000,
    );
    managers.push(manager);
    return manager;
  };
  const open = async (manager: SourceRuntimeManager, value: Target) =>
    manager.open({
      manifestPath: value.manifestPath,
      expectedBuildId: value.buildId,
      identity: value.identity,
    });
  const call = async (
    manager: SourceRuntimeManager,
    generation: string,
    command: Record<string, unknown>,
  ) => {
    const result = await manager.invoke(
      create(pb.SourceCallSchema, {
        requestId: crypto.randomUUID(),
        generation,
        sourceId: '1',
        timeoutMs: 300000,
        request: {
          case: 'search',
          value: { page: 1, query: JSON.stringify(command) },
        },
      }),
    );
    check(
      result.payload.case === 'mangaPage',
      'Controlled ABI uses actual typed Source result',
    );
    const report = object(
      JSON.parse(result.payload.value.mangas[0]?.title ?? '') as unknown,
    );
    check(
      report.controlledAbi === true,
      'Report identifies controlled supplier',
    );
    check(
      namespaces.has(text(report.namespace)),
      'Worker stores use actual manager namespace',
    );
    return report;
  };
  let failure: unknown,
    completed: Record<string, unknown> | undefined,
    cleanupPassed = false;
  try {
    const first = make(),
      baseline = target('a'),
      one = await open(first, baseline);
    const seeded = await call(first, one.generation, {
        action: 'seed',
        seed: 17,
      }),
      originalNamespace = text(seeded.namespace);
    const staged = await call(first, one.generation, { action: 'stage' });
    check(
      integer(object(staged.cache).editors) === 1 &&
        integer(object(staged.files).handles) === 1,
      'Old real Worker retains staging and unlinked handle before replacement',
    );
    const updated = target('b'),
      two = await open(first, updated);
    check(
      two.generation !== one.generation &&
        two.workerInstanceId !== one.workerInstanceId &&
        two.buildId !== one.buildId,
      'New manifest/build replaces real Worker and generation',
    );
    const retained = await call(first, two.generation, {
      action: 'verify',
      seed: 17,
    });
    check(
      retained.namespace === originalNamespace && retained.build === 'b',
      'Different fetched build uses retained key',
    );
    check(
      object(retained.cache).editors === 0 &&
        object(retained.files).handles === 0 &&
        object(retained.files).logicalBytes === 131079,
      'Death recovery discards old staging/unlinked inode, preserving only complete data',
    );
    checks.push(
      'build-version-update-retains-real-cache-and-files-after-worker-death',
    );
    await first.dispose();
    const recreated = make(),
      reopened = await open(recreated, updated);
    const persisted = await call(recreated, reopened.generation, {
      action: 'verify',
      seed: 17,
    });
    check(
      persisted.namespace === originalNamespace,
      'New manager instance retains committed data',
    );
    checks.push('manager-recreation-retains-idb-data');
    for (const [boundary, name, identity] of [
      ['identity', 'b', 'other-owner-' + run],
      ['repo', 'repo', baseline.identity],
      ['package', 'package', baseline.identity],
      ['schema', 'schema', baseline.identity],
    ] as const) {
      const isolated = target(name, identity),
        session = await open(recreated, isolated);
      const absent = await call(recreated, session.generation, {
        action: 'verify',
        seed: 91,
        absent: true,
      });
      check(
        absent.namespace !== originalNamespace,
        'Changed ' + boundary + ' isolates actual IDB',
      );
      await call(recreated, session.generation, { action: 'seed', seed: 91 });
      await call(recreated, session.generation, { action: 'verify', seed: 91 });
      await call(recreated, session.generation, { action: 'cleanup' });
      const back = await open(recreated, updated);
      await call(recreated, back.generation, { action: 'verify', seed: 17 });
      checks.push(boundary + '-isolates-both-stores-and-cannot-clear-baseline');
    }
    const pressureSession = await open(recreated, updated),
      pressure = await call(recreated, pressureSession.generation, {
        action: 'pressure',
      });
    check(
      Array.isArray(pressure.checks) &&
        pressure.checks.length === 5 &&
        pressure.checks.every((value) => typeof value === 'string'),
      'All combination pressure checks completed',
    );
    checks.push(...pressure.checks);
    check(
      integer(pressure.totalReservationBytes) <= 262 * 1024 * 1024,
      'Combined reservation cap',
    );
    completed = {
      passed: true,
      controlledAbi: true,
      checks,
      namespace: originalNamespace,
      workerUrls: urls,
      pressure,
      userAgent: navigator.userAgent,
      scope:
        'Actual manager, verified static loader, product WorkerRuntime/TeaVMDriver, Cache/files and IDB/Web Locks; controlled TypeScript host ABI. No Java/official Source/production Access/Native/disk-memory claim.',
    };
  } catch (error) {
    failure = error;
  } finally {
    const cleanupErrors: unknown[] = [];
    for (const manager of managers)
      try {
        await manager.dispose();
      } catch (error) {
        cleanupErrors.push(error);
      }
    // This removes only this random run's namespaces after all real Workers stop.
    // These maintenance deletes never contribute to the product quota assertions.
    const existing = new Set(
      (await indexedDB.databases()).map((value) => value.name),
    );
    for (const name of ['teavm-http-cache-v3', 'teavm-java-files-v2']) {
      if (!existing.has(name)) continue;
      try {
        const db = await openDB<CleanupSchema>(name);
        try {
          if (db.objectStoreNames.length === 0) {
            db.close();
            await deleteDB(name);
            continue;
          }
          for (const store of db.objectStoreNames) {
            const tx = db.transaction(store, 'readwrite'),
              table = tx.objectStore(store);
            if (
              name === 'teavm-http-cache-v3' &&
              (store === 'editors' || store === 'readers')
            ) {
              let cursor = await table.openCursor();
              while (cursor) {
                const value = cursor.value;
                if (
                  typeof value === 'object' &&
                  value !== null &&
                  'namespace' in value &&
                  typeof value.namespace === 'string' &&
                  namespaces.has(value.namespace)
                )
                  await table.delete(cursor.primaryKey);
                cursor = await cursor.continue();
              }
            } else {
              let cursor = await table.openKeyCursor();
              while (cursor) {
                const key: unknown = cursor.primaryKey;
                if (
                  typeof key === 'string'
                    ? namespaces.has(key)
                    : Array.isArray(key) && namespaces.has(String(key[0]))
                )
                  await table.delete(cursor.primaryKey);
                cursor = await cursor.continue();
              }
            }
            await tx.done;
          }
        } finally {
          db.close();
        }
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    if (cleanupErrors.length) {
      const errors = [
        ...(failure === undefined ? [] : [failure]),
        ...cleanupErrors,
      ];
      failure = new AggregateError(
        errors,
        'Runtime storage gate cleanup failed: ' +
          errors.map(String).join(' | '),
      );
    } else cleanupPassed = true;
  }
  if (failure !== undefined)
    return {
      passed: false,
      controlledAbi: true,
      checks,
      error: String(failure),
      cleanupPassed,
      userAgent: navigator.userAgent,
    };
  check(completed, 'No successful storage report');
  return { ...completed, cleanupPassed };
}
