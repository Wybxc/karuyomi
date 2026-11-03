/** Cloudflare Static Assets may canonicalize host.html to the extensionless URL. */
export function isNativeControlPage(
  location: Pick<URL, 'protocol' | 'pathname'>,
): boolean {
  return (
    location.protocol === 'https:' &&
    (location.pathname === '/runtime/host.html' ||
      location.pathname === '/runtime/host')
  );
}
