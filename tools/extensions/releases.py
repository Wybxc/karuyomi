"""GitHub private-release transport and immutable, resumable publication."""
from pathlib import Path
import hashlib
import json
import os
import urllib.error
import urllib.parse
import urllib.request

from catalog import canonical, digest


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        if urllib.parse.urlparse(new_url).scheme != 'https':
            raise ValueError('Refusing insecure GitHub redirect')
        result = super().redirect_request(request, fp, code, message, headers, new_url)
        if result is not None and urllib.parse.urlparse(request.full_url).netloc != urllib.parse.urlparse(new_url).netloc:
            result.remove_header('Authorization')
            result.remove_header('Cookie')
        return result


class GitHub:
    def __init__(self, repository, token=None):
        import re
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
            raise ValueError('Invalid GitHub repository')
        self.repository = repository
        self.token = token or os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
        if not self.token:
            raise ValueError('GH_TOKEN is required for private release access')
        self.opener = urllib.request.build_opener(SafeRedirect())

    def request(self, method, path, data=None, raw=False, content_type='application/json', missing=False):
        url = path if path.startswith('https:') else 'https://api.github.com' + path
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme != 'https' or parsed.netloc not in {'api.github.com', 'uploads.github.com'}:
            raise ValueError('Invalid GitHub API endpoint')
        body = data if isinstance(data, bytes) else canonical(data) if data is not None else None
        request = urllib.request.Request(url, data=body, method=method, headers={
            'Authorization': 'Bearer ' + self.token, 'User-Agent': 'karuyomi-extension-publisher',
            'X-GitHub-Api-Version': '2022-11-28', 'Content-Type': content_type,
            'Accept': 'application/octet-stream' if raw else 'application/vnd.github+json',
        })
        try:
            with self.opener.open(request, timeout=120) as response:
                content = response.read(128 * 1024 * 1024 + 1)
                if len(content) > 128 * 1024 * 1024:
                    raise ValueError('GitHub asset exceeds transport budget')
                return content if raw else json.loads(content) if content else None
        except urllib.error.HTTPError as error:
            if missing and error.code == 404:
                return None
            # Never print credentials, signed download query strings or bodies.
            raise RuntimeError(f'GitHub {method} {parsed.path}: HTTP {error.code}') from None
        except urllib.error.URLError:
            raise RuntimeError('GitHub transport unavailable') from None

    def find_release(self, tag):
        return self.request('GET', f'/repos/{self.repository}/releases/tags/{urllib.parse.quote(tag, safe="")}', missing=True)

    def latest(self):
        return self.request('GET', f'/repos/{self.repository}/releases/latest', missing=True)

    def create_release(self, tag, target):
        return self.request('POST', f'/repos/{self.repository}/releases', {
            'tag_name': tag, 'target_commitish': target, 'name': tag, 'draft': True, 'make_latest': 'false',
        })

    def assets(self, release):
        values, page = [], 1
        while True:
            items = self.request('GET', f'/repos/{self.repository}/releases/{release["id"]}/assets?per_page=100&page={page}')
            values.extend(items)
            if len(items) < 100:
                return values
            page += 1

    def upload(self, release, name, data):
        url = release['upload_url'].split('{', 1)[0]
        expected = f'/repos/{self.repository}/releases/{release["id"]}/assets'
        if urllib.parse.urlparse(url).path != expected:
            raise ValueError('Unexpected release upload endpoint')
        return self.request('POST', url + '?name=' + urllib.parse.quote(name, safe=''), data,
                            content_type='application/octet-stream')

    def download(self, asset):
        # Use the authenticated API URL, never a private browser_download_url.
        return self.request('GET', f'/repos/{self.repository}/releases/assets/{asset["id"]}', raw=True)

    def publish(self, release, latest=False):
        return self.request('PATCH', f'/repos/{self.repository}/releases/{release["id"]}', {
            'draft': False, 'make_latest': 'true' if latest else 'false',
        })


def bytes_of(value):
    return value.read_bytes() if isinstance(value, Path) else value


def publish_immutable(api, tag, files, target, latest=False):
    """Finish a matching draft, or verify an identical published release.

    Never clobber an asset. The final manifest is uploaded last; a draft is made
    visible only after every asset's size and server digest has been checked.
    """
    metadata = {name: {'sha256': digest(bytes_of(value)), 'size': len(bytes_of(value))}
                for name, value in files.items()}
    if 'release-manifest.json' in files or any('/' in name or '\\' in name for name in files):
        raise ValueError('Invalid release asset name')
    release_manifest = canonical({'schemaVersion': 1, 'tag': tag, 'files': metadata}) + b'\n'
    upload_files = {**files, 'release-manifest.json': release_manifest}
    release = api.find_release(tag) or api.create_release(tag, target)
    remote = {asset['name']: asset for asset in api.assets(release)}
    if set(remote) - set(upload_files):
        raise ValueError('Immutable release has unexpected assets: ' + tag)
    for name, value in upload_files.items():
        data = bytes_of(value)
        expected = digest(data)
        asset = remote.get(name)
        if asset is None:
            if not release.get('draft'):
                raise ValueError('Published release is incomplete: ' + tag)
            asset = api.upload(release, name, data)
        if asset['size'] != len(data):
            raise ValueError('Immutable release asset size conflict: ' + name)
        actual = asset.get('digest')
        if actual is None:
            actual = 'sha256:' + digest(api.download(asset))
        if actual != 'sha256:' + expected:
            raise ValueError('Immutable release asset hash conflict: ' + name)
    if release.get('draft') or latest:
        release = api.publish(release, latest=latest)
    return {'tag': tag, 'url': release.get('html_url'), 'releaseManifestSha256': digest(release_manifest)}


def download_release(api, tag, directory):
    release = api.find_release(tag)
    if not release or release.get('draft'):
        return False
    assets = {asset['name']: asset for asset in api.assets(release)}
    if 'release-manifest.json' not in assets:
        raise ValueError('Release lacks immutable manifest: ' + tag)
    manifest_bytes = api.download(assets['release-manifest.json'])
    manifest = json.loads(manifest_bytes)
    if manifest.get('schemaVersion') != 1 or manifest.get('tag') != tag or set(assets) != set(manifest['files']) | {'release-manifest.json'}:
        raise ValueError('Release manifest mismatch: ' + tag)
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    for name, expected in manifest['files'].items():
        if '/' in name or '\\' in name or name in {'.', '..'}:
            raise ValueError('Unsafe asset name')
        data = api.download(assets[name])
        if len(data) != expected['size'] or digest(data) != expected['sha256']:
            raise ValueError('Downloaded asset integrity mismatch: ' + name)
        (directory / name).write_bytes(data)
    (directory / 'release-manifest.json').write_bytes(manifest_bytes)
    return True
