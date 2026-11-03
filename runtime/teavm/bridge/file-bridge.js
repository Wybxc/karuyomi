/* Durable Java files. Every mutation commits before its Java continuation resumes. */
(() => {
  const params = new URL(location.href).searchParams;
  const namespace =
    self.karuyomiWorkerContext?.fsNamespace ||
    self.karuyomiWorkerContext?.plugin ||
    params.get('fsNamespace') ||
    params.get('plugin');
  if (!namespace) throw new Error('Runtime filesystem namespace is required');
  const owner = crypto.randomUUID(),
    handles = new Map();
  const stores = ['paths', 'nodes', 'handles', 'owners'];
  let opening,
    starting,
    tail = Promise.resolve(),
    releaseOwner,
    closed = false;
  const lockName = (id) =>
    'teavm-java-files:' + JSON.stringify([namespace, id]);
  const key = (path) => [namespace, path];
  const request = (r) =>
    new Promise((resolve, reject) => {
      r.onsuccess = () => resolve(r.result);
      r.onerror = () => reject(r.error);
    });
  const parent = (path) => path.slice(0, path.lastIndexOf('/')) || '/';
  function normalize(path) {
    if (typeof path !== 'string' || path.includes('\0'))
      throw Error('Invalid file path');
    const parts = [];
    for (const part of path.split('/')) {
      if (!part || part === '.') continue;
      if (part === '..') parts.pop();
      else parts.push(part);
    }
    return '/' + parts.join('/');
  }
  function encode(bytes) {
    let text = '';
    for (let i = 0; i < bytes.length; i += 16384)
      text += String.fromCharCode(...bytes.subarray(i, i + 16384));
    return btoa(text);
  }
  const decode = (text) => Uint8Array.from(atob(text), (c) => c.charCodeAt(0));
  function open() {
    return (opening ||= new Promise((resolve, reject) => {
      const r = indexedDB.open('teavm-java-files-v1', 1);
      r.onupgradeneeded = () => {
        const db = r.result;
        db.createObjectStore('paths', { keyPath: 'key' });
        db.createObjectStore('nodes', { keyPath: 'key' });
        const h = db.createObjectStore('handles', { keyPath: 'key' });
        h.createIndex('inode', 'inode');
        h.createIndex('owner', 'owner');
        db.createObjectStore('owners', { keyPath: 'key' });
      };
      r.onsuccess = () => {
        r.result.onversionchange = () => {
          r.result.close();
          opening = undefined;
        };
        resolve(r.result);
      };
      r.onerror = () => {
        opening = undefined;
        reject(r.error);
      };
      r.onblocked = () => {
        opening = undefined;
        reject(Error('Java filesystem database upgrade blocked'));
      };
    }));
  }
  async function transaction(action) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(stores, 'readwrite', { durability: 'strict' });
      const s = Object.fromEntries(
        stores.map((name) => [name, tx.objectStore(name)]),
      );
      let value, failure, commit;
      tx.oncomplete = () => {
        if (commit) commit();
        resolve(value);
      };
      tx.onabort = () =>
        reject(
          failure || tx.error || Error('Java filesystem transaction aborted'),
        );
      tx.onerror = () => {};
      Promise.resolve()
        .then(() =>
          action(s, (fn) => {
            commit = fn;
          }),
        )
        .then(
          (result) => {
            value = result;
          },
          (error) => {
            failure = error;
            try {
              tx.abort();
            } catch {
              reject(error);
            }
          },
        );
    });
  }
  const nodeFor = async (s, path) => {
    const link = await request(s.paths.get(key(path)));
    return link ? request(s.nodes.get(key(link.id))) : undefined;
  };
  async function children(s, path) {
    const prefix = path === '/' ? '/' : path + '/';
    return (
      await request(
        s.paths.getAll(IDBKeyRange.bound(key(prefix), key(prefix + '\uffff'))),
      )
    ).filter((row) => row.path !== path && row.path.startsWith(prefix));
  }
  async function collect(s, node) {
    if (
      !node.linked &&
      !(await request(s.handles.index('inode').getAllKeys(node.key))).length
    )
      s.nodes.delete(node.key);
  }
  async function dropOwner(s, id) {
    const rows = await request(s.handles.index('owner').getAll(key(id)));
    for (const row of rows) s.handles.delete(row.key);
    for (const inode of new Set(rows.map((row) => row.inode[1]))) {
      const node = await request(s.nodes.get(key(inode)));
      if (node) await collect(s, node);
    }
    s.owners.delete(key(id));
  }
  function touch(s, node) {
    node.modified = Date.now();
    s.nodes.put(node);
  }
  function create(s, path, directory, parentNode) {
    const id = crypto.randomUUID(),
      node = {
        key: key(id),
        id,
        directory,
        readOnly: false,
        modified: Date.now(),
        linked: true,
        body: new Uint8Array(),
      };
    s.nodes.add(node);
    s.paths.add({ key: key(path), path, id });
    if (parentNode) touch(s, parentNode);
    return node;
  }
  async function start() {
    if (closed) throw Error('Java filesystem is closed');
    return (starting ||= (async () => {
      if (!navigator.locks)
        throw Error(
          'Java filesystem requires the Web Locks API for Worker lifetime tracking',
        );
      await new Promise((resolve, reject) => {
        navigator.locks
          .request(lockName(owner), () => {
            resolve();
            return new Promise((done) => {
              releaseOwner = done;
            });
          })
          .catch(reject);
      });
      const owners = await transaction(async (s) =>
        request(s.owners.getAll(IDBKeyRange.bound(key(''), key('\uffff')))),
      );
      for (const row of owners)
        await navigator.locks.request(
          lockName(row.key[1]),
          { ifAvailable: true },
          async (lock) => {
            if (lock) await transaction((s) => dropOwner(s, row.key[1]));
          },
        );
      await transaction(async (s) => {
        for (const path of ['/', '/tmp'])
          if (!(await nodeFor(s, path))) create(s, path, true);
        s.owners.put({ key: key(owner) });
      });
    })());
  }
  function validInteger(value) {
    if (!Number.isInteger(value) || value < 0 || value > 2147483647)
      throw Error('File offset exceeds TeaVM filesystem range');
    return value;
  }
  async function operate(r) {
    await start();
    const path = normalize(r.path || '/');
    if (r.operation === 'initialize') return { ready: true };
    const h = r.handle && handles.get(r.handle);
    if (r.handle && !h) throw Error('Stream is closed');
    if (r.operation === 'tell') return { position: h.position };
    if (r.operation === 'seek') {
      h.position = validInteger(r.position);
      return {};
    }
    if (r.operation === 'skip') {
      h.position = validInteger(h.position + r.count);
      return {};
    }
    return transaction(async (s, afterCommit) => {
      const node = h
        ? await request(s.nodes.get(key(h.inode)))
        : await nodeFor(s, path);
      if (h && !node) throw Error('Open file inode is missing');
      switch (r.operation) {
        case 'stat':
          return node
            ? {
                exists: true,
                directory: node.directory,
                file: !node.directory,
                readable: true,
                writable: !node.readOnly,
                modified: node.modified,
                size: node.directory ? 0 : node.body.length,
              }
            : { exists: false };
        case 'list':
          return node?.directory
            ? {
                names: (await children(s, path))
                  .filter((row) => parent(row.path) === path)
                  .map((row) => row.path.slice(row.path.lastIndexOf('/') + 1))
                  .sort(),
              }
            : {};
        case 'create':
        case 'mkdir': {
          if (node) return { changed: false };
          const dir = await nodeFor(s, parent(path));
          if (!dir?.directory || dir.readOnly) {
            if (r.operation === 'create')
              throw Error('Parent directory does not exist or is not writable');
            return { changed: false };
          }
          create(s, path, r.operation === 'mkdir', dir);
          return { changed: true };
        }
        case 'delete': {
          if (!node || path === '/') return { changed: false };
          const dir = await nodeFor(s, parent(path));
          if (
            !dir ||
            dir.readOnly ||
            (node.directory && (await children(s, path)).length)
          )
            return { changed: false };
          s.paths.delete(key(path));
          node.linked = false;
          s.nodes.put(node);
          await collect(s, node);
          touch(s, dir);
          return { changed: true };
        }
        case 'rename': {
          const source = normalize(r.source),
            from = await nodeFor(s, source),
            dir = await nodeFor(s, parent(path));
          const oldDir = await nodeFor(s, parent(source));
          if (
            !from ||
            source === '/' ||
            path === '/' ||
            !dir?.directory ||
            dir.readOnly ||
            oldDir?.readOnly
          )
            return { changed: false };
          if (source === path) return { changed: true };
          if (from.directory && path.startsWith(source + '/'))
            return { changed: false };
          if (
            node &&
            (node.directory !== from.directory ||
              (node.directory && (await children(s, path)).length))
          )
            return { changed: false };
          const moving = [
            { key: key(source), path: source, id: from.id },
            ...(from.directory ? await children(s, source) : []),
          ];
          if (node) {
            node.linked = false;
            s.nodes.put(node);
            await collect(s, node);
          }
          for (const row of moving) s.paths.delete(row.key);
          for (const row of moving) {
            const next = path + row.path.slice(source.length);
            s.paths.put({ key: key(next), path: next, id: row.id });
          }
          touch(s, dir);
          if (oldDir.id !== dir.id) touch(s, oldDir);
          return { changed: true };
        }
        case 'modified':
        case 'readonly': {
          if (!node) return { changed: false };
          if (r.operation === 'modified') node.modified = r.modified;
          else node.readOnly = !!r.readOnly;
          s.nodes.put(node);
          return { changed: true };
        }
        case 'open': {
          if (!node || node.directory || (r.writable && node.readOnly))
            return {};
          // RandomAccessFile opens readable+writable and must preserve existing bytes.
          if (r.writable && !r.readable && !r.append) {
            node.body = new Uint8Array();
            node.modified = Date.now();
            s.nodes.put(node);
          }
          const handle = crypto.randomUUID();
          s.handles.add({
            key: [namespace, owner, handle],
            owner: key(owner),
            inode: node.key,
          });
          afterCommit(() =>
            handles.set(handle, {
              inode: node.id,
              position: r.append ? node.body.length : 0,
              readable: !!r.readable,
              writable: !!r.writable,
              append: !!r.append,
            }),
          );
          return { handle };
        }
        case 'read': {
          if (!h.readable) throw Error('File is not open for reading');
          const end = Math.min(
            node.body.length,
            h.position + validInteger(r.length),
          );
          const body = node.body.subarray(h.position, end),
            next = h.position + body.length;
          afterCommit(() => {
            h.position = next;
          });
          return { body: encode(body), eof: body.length === 0 };
        }
        case 'write':
        case 'resize': {
          if (!h.writable) throw Error('File is not open for writing');
          const body = r.operation === 'write' ? decode(r.body) : undefined;
          if (body && body.length === 0) return {};
          const offset = h.append && body ? node.body.length : h.position;
          const length = validInteger(
            body ? Math.max(node.body.length, offset + body.length) : r.size,
          );
          const next = new Uint8Array(length);
          next.set(node.body.subarray(0, length));
          if (body) next.set(body, offset);
          node.body = next;
          node.modified = Date.now();
          s.nodes.put(node);
          afterCommit(() => {
            h.position = body
              ? offset + body.length
              : Math.min(h.position, length);
          });
          return {};
        }
        case 'size':
          return { size: node.body.length };
        case 'flush':
          return {};
        case 'close': {
          s.handles.delete([namespace, owner, r.handle]);
          await collect(s, node);
          afterCommit(() => handles.delete(r.handle));
          return {};
        }
        default:
          throw Error('Unknown Java filesystem operation ' + r.operation);
      }
    });
  }
  // Keep each descriptor's cursor updates ordered, including callers from different Java fibers.
  self.teaFile = (input) => {
    const job = tail.then(() => operate(JSON.parse(input)));
    tail = job.catch(() => {});
    return job.then(JSON.stringify);
  };
  self.teaFileSystemClose = () => {
    const job = tail.then(async () => {
      if (starting) await starting;
      if (releaseOwner) await transaction((s) => dropOwner(s, owner));
      handles.clear();
      closed = true;
      releaseOwner?.();
      if (opening) (await opening).close();
    });
    tail = job.catch(() => {});
    return job;
  };
})();
