// WebCrypto provider for the bounded JCA API in java/compat. No keys are logged.
(() => {
  const decode = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
  const encode = (b) => {
    let s = '';
    b = new Uint8Array(b);
    for (let i = 0; i < b.length; i += 16384)
      s += String.fromCharCode(...b.subarray(i, i + 16384));
    return btoa(s);
  };
  self.teaCrypto = async (r) => {
    try {
      const keyBytes = decode(r.key),
        input = decode(r.body);
      let result;
      if (r.algorithm === 'HMAC') {
        const key = await crypto.subtle.importKey(
          'raw',
          keyBytes,
          { name: 'HMAC', hash: 'SHA-256' },
          false,
          ['sign'],
        );
        result = await crypto.subtle.sign('HMAC', key, input);
      } else {
        if (
          !['AES-CBC', 'AES-GCM'].includes(r.algorithm) ||
          !['encrypt', 'decrypt'].includes(r.operation)
        )
          throw Error('Unsupported crypto operation');
        const key = await crypto.subtle.importKey(
          'raw',
          keyBytes,
          r.algorithm,
          false,
          [r.operation],
        );
        const algorithm = { name: r.algorithm, iv: decode(r.iv) };
        if (r.algorithm === 'AES-GCM') {
          algorithm.tagLength = r.tagLength;
          algorithm.additionalData = decode(r.aad);
        }
        result = await crypto.subtle[r.operation](algorithm, key, input);
      }
      return { body: encode(result) };
    } catch (e) {
      return { error: e.name + ': ' + e.message };
    }
  };
})();
