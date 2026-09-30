"""Fail-closed preparation/checks for the manually approved Pages audio preview.

This helper only performs GET requests. Publishing is exclusively deploy-pages
in the existing GitHub Pages environment, with its unchanged protection rules.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import tarfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

REPO = 'Arino09/GameJam2026'
BRANCH = 'refs/heads/integration/audio-pr1-20260930'
BASE_URL = 'https://arino09.github.io/GameJam2026/'
PREVIEW = 'preview/audio'
API = 'https://api.github.com'
MAX_ARCHIVE = 512 * 1024 * 1024
MAX_FILES = 10000


class Stop(RuntimeError):
    pass


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if urllib.parse.urlsplit(newurl).scheme != 'https':
            raise Stop('Refusing a non-HTTPS redirect.')
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        if urllib.parse.urlsplit(newurl).netloc != 'api.github.com':
            redirected.remove_header('Authorization')
        return redirected


class GitHub:
    def __init__(self):
        self.token = os.environ.get('GH_TOKEN', '')
        if not self.token:
            raise Stop('Missing existing GitHub token; no credentials will be created.')
        self.opener = urllib.request.build_opener(SafeRedirect())

    def get(self, path, limit=16 * 1024 * 1024):
        url = f'{API}/repos/{REPO}/{path}'
        request = urllib.request.Request(url, headers={
            'Authorization': f'Bearer {self.token}',
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'GameJam2026-preserving-preview',
        })
        try:
            with self.opener.open(request, timeout=60) as response:
                body = response.read(limit + 1)
        except urllib.error.HTTPError as error:
            raise Stop(f'GitHub GET {path.split("?")[0]} returned HTTP {error.code}. '
                       'Existing permissions only; no retry with other credentials or permission changes. '
                       'Cross-run artifact/log access may require Actions read, which this workflow does not add.') from None
        except urllib.error.URLError:
            raise Stop(f'Cannot reach GitHub GET {path.split("?")[0]}; no deployment permitted.') from None
        if len(body) > limit:
            raise Stop('GitHub response exceeds the allowed size.')
        return body

    def json(self, path):
        return json.loads(self.get(path))

    def collection(self, path, key):
        result = []
        separator = '&' if '?' in path else '?'
        for page in range(1, 11):
            data = self.json(f'{path}{separator}per_page=100&page={page}')
            batch = data[key]
            result.extend(batch)
            if len(batch) < 100:
                return result
        raise Stop('Pagination exceeded 1000 items; cannot establish the latest production snapshot.')


def latest_production(api):
    pages = api.json('pages')
    if pages.get('build_type') != 'workflow' or pages.get('html_url') != BASE_URL:
        raise Stop('Pages source or destination changed; refusing to publish to an unverified target.')
    # Query every master run, not a pinned artifact and not merely the newest
    # build. updated_at also catches re-runs of an older production commit.
    runs = api.collection('actions/workflows/godot-web.yml/runs?branch=master', 'workflow_runs')
    runs = [r for r in runs if r['head_branch'] == 'master' and r['event'] in ('push', 'workflow_dispatch')]
    if any(r['status'] != 'completed' for r in runs):
        raise Stop('A production workflow is still active; retry after it finishes.')
    for run in sorted(runs, key=lambda r: r['updated_at'], reverse=True):
        jobs = api.collection(f'actions/runs/{run["id"]}/jobs?filter=latest', 'jobs')
        deploys = [j for j in jobs if j['name'] == 'Deploy GitHub Pages']
        if not deploys or all(j['conclusion'] == 'skipped' for j in deploys):
            continue
        if len(deploys) != 1 or deploys[0]['conclusion'] != 'success' or run['conclusion'] != 'success':
            raise Stop('A newer production deployment has an ambiguous/failed outcome; refusing an older fallback.')
        artifacts = api.collection(f'actions/runs/{run["id"]}/artifacts', 'artifacts')
        matches = [a for a in artifacts if a['name'] == 'github-pages']
        if len(matches) != 1 or matches[0]['expired']:
            raise Stop('Latest deployed production artifact is missing/expired/ambiguous; no older fallback.')
        artifact = matches[0]
        if not re.fullmatch(r'sha256:[0-9a-f]{64}', artifact.get('digest', '')):
            raise Stop('Production artifact has no verifiable SHA-256 digest.')
        if artifact['workflow_run']['head_sha'] != run['head_sha']:
            raise Stop('Artifact and production run disagree about the source SHA.')
        logs = api.get(f'actions/jobs/{deploys[0]["id"]}/logs').decode('utf-8-sig')
        if not re.search(r'"artifact_id"\s*:\s*' + str(artifact['id']) + r'\s*[,}]', logs):
            raise Stop('Deploy log does not prove that the selected artifact was deployed.')
        if f'"pages_build_version": "{run["head_sha"]}"' not in logs or 'Reported success!' not in logs:
            raise Stop('Deploy log does not prove successful publication of the selected production SHA.')
        master_sha = api.json('git/ref/heads/master')['object']['sha']
        if master_sha != run['head_sha']:
            raise Stop('master has advanced beyond the deployed snapshot; wait for production and retry.')
        return {
            'run_id': run['id'], 'run_attempt': run['run_attempt'],
            'source_sha': run['head_sha'], 'master_sha': master_sha,
            'deployment_job_id': deploys[0]['id'],
            'artifact_id': artifact['id'], 'digest': artifact['digest'],
        }
    raise Stop('No successful production Pages deployment can be proven.')


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def extract_pages(data, destination, expected_digest):
    if 'sha256:' + sha256(data) != expected_digest:
        raise Stop('Production artifact digest mismatch.')
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        if archive.namelist() != ['artifact.tar'] or archive.getinfo('artifact.tar').file_size > 1024**3:
            raise Stop('Unexpected Pages artifact format or size.')
        with tarfile.open(fileobj=io.BytesIO(archive.read('artifact.tar'))) as tar:
            members = tar.getmembers()
            if len(members) > MAX_FILES or sum(m.size for m in members) > 1024**3:
                raise Stop('Production artifact exceeds file/count limits.')
            seen = set()
            for member in members:
                path = PurePosixPath(member.name)
                if path.is_absolute() or '..' in path.parts or '\\' in member.name:
                    raise Stop('Unsafe path in production artifact.')
                if not (member.isdir() or member.isfile()):
                    raise Stop('Links/special files are forbidden in the production artifact.')
                if member.isfile():
                    name = path.as_posix().removeprefix('./')
                    if name in seen:
                        raise Stop('Duplicate file in production artifact.')
                    seen.add(name)
            tar.extractall(destination, filter='data')
    if not (destination / 'index.html').is_file():
        raise Stop('Production artifact has no index.html.')


def file_manifest(root):
    files = {}
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            raise Stop('Symlinks are forbidden in a Pages payload.')
        if path.is_file():
            content = path.read_bytes()
            files[path.relative_to(root).as_posix()] = {'sha256': sha256(content), 'size': len(content)}
    if len(files) > MAX_FILES:
        raise Stop('Too many files in Pages payload.')
    return files


def verify_live(files, attempts=1):
    # .nojekyll is a deployment control file, not a publicly served resource.
    # Its bytes are still strictly checked in both artifact and output manifests.
    def check(item):
        path, expected = item
        if path == '.nojekyll' or path.endswith('/.nojekyll'):
            return
        url = BASE_URL + urllib.parse.quote(path, safe='/')
        for attempt in range(attempts):
            try:
                request = urllib.request.Request(url, headers={'Cache-Control': 'no-cache', 'Accept-Encoding': 'identity'})
                with urllib.request.urlopen(request, timeout=45) as response:
                    if (urllib.parse.urlsplit(response.geturl()).netloc != 'arino09.github.io'
                            or urllib.parse.urlsplit(response.geturl()).scheme != 'https'):
                        raise Stop('Unexpected redirect while checking production content.')
                    body = response.read(expected['size'] + 1)
                if len(body) == expected['size'] and sha256(body) == expected['sha256']:
                    return
            except (urllib.error.URLError, TimeoutError):
                pass
            if attempt + 1 < attempts:
                time.sleep(3)
        raise Stop(f'HTTPS content is unavailable or differs at {path}; refusing to claim preservation.')
    paths = dict(files)
    for name, expected in files.items():
        if name == 'index.html' or name.endswith('/index.html'):
            paths[name[:-len('index.html')]] = expected
    with ThreadPoolExecutor(max_workers=4) as executor:
        list(executor.map(check, paths.items()))


def validate_preview(root):
    file_manifest(root)
    html = (root / 'index.html').read_text()
    match = re.search(r'const GODOT_CONFIG = (\{.*?\});', html)
    if not match:
        raise Stop('No Godot configuration in preview HTML.')
    config = json.loads(match.group(1))
    worker_name = config.get('serviceWorker', '')
    if not re.fullmatch(r'game-[0-9a-f]+\.service\.worker\.js', worker_name):
        raise Stop('Preview worker must be versioned and located in its own directory.')
    worker = (root / worker_name).read_text()
    if 'encodeURIComponent(self.registration.scope)' not in worker or 'navigator.serviceWorker.ready' not in html:
        raise Stop('Preview cache scope / first-load activation guard is missing.')
    if not config.get('ensureCrossOriginIsolationHeaders'):
        raise Stop('Preview isolation is disabled.')
    for variable in ('CACHED_FILES', 'CACHEABLE_FILES'):
        found = re.search(r'const ' + variable + r' = (\[.*?\]);', worker)
        if not found:
            raise Stop('Cannot verify built-in worker cache references.')
        for name in json.loads(found.group(1)):
            if PurePosixPath(name).name != name or not (root / name).is_file():
                raise Stop(f'Invalid or missing worker cache resource: {name}')


def assert_preserved(production, combined):
    if any(combined.get(name) != value for name, value in production.items()):
        raise Stop('A production file was removed or changed.')
    if any(not name.startswith(PREVIEW + '/') for name in combined.keys() - production.keys()):
        raise Stop('A file was added outside the authorized preview subtree.')


def guard_environment():
    if os.environ.get('GITHUB_REPOSITORY') != REPO or os.environ.get('GITHUB_REF') != BRANCH:
        raise Stop('Preview publication is restricted to the authorized repository and integration branch.')
    if os.environ.get('GITHUB_EVENT_NAME') != 'workflow_dispatch':
        raise Stop('Preview publication requires workflow_dispatch.')
    if os.environ.get('PUBLISH_AUDIO_PREVIEW') != 'true':
        raise Stop('Explicit publish_audio_preview=true is required.')


def write_summary(message):
    print(message)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as handle:
            handle.write(message + '\n\n')


def prepare(api, work, preview):
    if work.exists():
        raise Stop('Preparation directory already exists; refusing a stale snapshot.')
    snapshot = latest_production(api)
    work.mkdir(parents=True)
    data = api.get(f'actions/artifacts/{snapshot["artifact_id"]}/zip', MAX_ARCHIVE)
    (work / 'production.zip').write_bytes(data)
    extract_pages(data, work / 'production', snapshot['digest'])
    production = file_manifest(work / 'production')
    if (work / 'production' / PREVIEW).exists():
        raise Stop('Production already owns the reserved preview path; refusing to overwrite it.')
    verify_live(production)
    validate_preview(preview)
    site = work / 'site'
    shutil.copytree(work / 'production', site)
    target = site / PREVIEW
    shutil.copytree(preview, target / 'game')
    shutil.copyfile(Path(__file__).with_name('audio-preview-index.html'), target / 'index.html')
    source_sha = os.environ['GITHUB_SHA']
    (target / 'preview-info.json').write_text(json.dumps({
        'source_sha': source_sha, 'production': snapshot,
        'worker_scope': BASE_URL + PREVIEW + '/game/',
    }, indent=2) + '\n')
    combined = file_manifest(site)
    assert_preserved(production, combined)
    proof = {'production_snapshot': snapshot, 'production_files': production,
             'combined_files': combined, 'preview_sha': source_sha}
    (work / 'proof.json').write_text(json.dumps(proof, indent=2) + '\n')
    recheck(api, work)
    write_summary(f'Prepared preview {source_sha}; preserved {len(production)} production files '
                  f'from run {snapshot["run_id"]}, SHA {snapshot["source_sha"]}, artifact {snapshot["artifact_id"]}. Not deployed yet.')


def recheck(api, work):
    proof = json.loads((work / 'proof.json').read_text())
    if proof['preview_sha'] != os.environ['GITHUB_SHA']:
        raise Stop('Prepared preview SHA differs from this immutable workflow run SHA.')
    if latest_production(api) != proof['production_snapshot']:
        raise Stop('Production changed during preview preparation; discard and retry with the new snapshot.')
    combined = file_manifest(work / 'site')
    if combined != proof['combined_files']:
        raise Stop('Pages payload differs from the verified manifest.')
    assert_preserved(proof['production_files'], combined)
    verify_live(proof['production_files'])


def verify_published(work):
    proof = json.loads((work / 'proof.json').read_text())
    verify_live(proof['combined_files'], attempts=5)
    write_summary(f'HTTPS verification passed for all served files. Production preserved. '
                  f'Preview SHA: {proof["preview_sha"]}\n\n试听预览：{BASE_URL}{PREVIEW}/\n\n'
                  '请横屏、打开媒体音量，进入游戏后轻点画面解锁声音。手机实际听感需人工确认。')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['prepare', 'recheck', 'verify'])
    parser.add_argument('--work', type=Path, default=Path('build/audio-preview-publish'))
    parser.add_argument('--preview', type=Path, default=Path('build/web'))
    args = parser.parse_args()
    guard_environment()
    if args.command == 'prepare':
        prepare(GitHub(), args.work, args.preview)
    elif args.command == 'recheck':
        recheck(GitHub(), args.work)
    else:
        verify_published(args.work)


if __name__ == '__main__':
    try:
        main()
    except (Stop, ValueError, KeyError, OSError, tarfile.TarError, zipfile.BadZipFile) as error:
        print(f'::error::Audio preview stopped: {error}', file=sys.stderr)
        sys.exit(1)
