"""Offline tests for production preservation, freshness, and rejection paths."""
import copy
import io
import json
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch, Mock
import urllib.error
import urllib.request
import zipfile

import publish_audio_preview as p


class FakeGitHub:
    def __init__(self):
        self.runs = [self.run(2, 'new', '2026-09-30T08:00:00Z'),
                     self.run(1, 'old', '2026-09-29T08:00:00Z')]
        self.expired = False
        self.deploy_result = 'success'
        self.master = 'new'
        self.log_id = None

    @staticmethod
    def run(number, sha, updated):
        return dict(id=number, head_sha=sha, head_branch='master', event='push',
                    status='completed', conclusion='success', updated_at=updated, run_attempt=1)

    def collection(self, path, key):
        if key == 'workflow_runs':
            return self.runs
        number = int(path.split('/')[2])
        if key == 'jobs':
            return [dict(id=number * 100, name='Deploy GitHub Pages', conclusion=self.deploy_result)]
        run = next(r for r in self.runs if r['id'] == number)
        return [dict(id=number * 10, name='github-pages', expired=self.expired,
                     digest='sha256:' + 'a' * 64, workflow_run={'head_sha': run['head_sha']})]

    def json(self, path):
        if path == 'pages':
            return {'build_type': 'workflow', 'html_url': p.BASE_URL}
        return {'object': {'sha': self.master}}

    def get(self, path):
        number = int(path.split('/')[2]) // 100
        run = next(r for r in self.runs if r['id'] == number)
        return (f'"artifact_id": {self.log_id or number * 10},\n'
                f'"pages_build_version": "{run["head_sha"]}"\nReported success!').encode()


def artifact(entries):
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode='w') as tar:
        for name, data, kind in entries:
            info = tarfile.TarInfo(name)
            if kind == 'link':
                info.type = tarfile.SYMTYPE
                info.linkname = '/etc/passwd'
                tar.addfile(info)
            else:
                info.size = len(data)
                tar.addfile(info, io.BytesIO(data))
    zipped = io.BytesIO()
    with zipfile.ZipFile(zipped, 'w') as archive:
        archive.writestr('artifact.tar', raw.getvalue())
    return zipped.getvalue()


class LatestProductionTests(unittest.TestCase):
    def test_selects_newest_deployed_artifact_not_old_constant(self):
        api = FakeGitHub()
        result = p.latest_production(api)
        self.assertEqual((result['source_sha'], result['artifact_id']), ('new', 20))
        api.runs.reverse()
        self.assertEqual(p.latest_production(api), result)

    def test_rerun_order_uses_updated_time(self):
        api = FakeGitHub()
        api.runs[1]['updated_at'] = '2026-10-01T08:00:00Z'
        api.master = 'old'
        self.assertEqual(p.latest_production(api)['artifact_id'], 10)

    def test_missing_expired_latest_never_falls_back(self):
        api = FakeGitHub()
        api.expired = True
        with self.assertRaisesRegex(p.Stop, 'expired'):
            p.latest_production(api)

    def test_failed_deployment_never_falls_back(self):
        api = FakeGitHub()
        api.deploy_result = 'failure'
        with self.assertRaisesRegex(p.Stop, 'ambiguous/failed'):
            p.latest_production(api)

    def test_active_production_is_rejected(self):
        api = FakeGitHub()
        api.runs[0]['status'] = 'queued'
        with self.assertRaisesRegex(p.Stop, 'still active'):
            p.latest_production(api)

    def test_master_advance_is_rejected(self):
        api = FakeGitHub()
        api.master = 'not-yet-deployed'
        with self.assertRaisesRegex(p.Stop, 'advanced'):
            p.latest_production(api)

    def test_deploy_log_must_prove_exact_artifact(self):
        api = FakeGitHub()
        api.log_id = 999
        with self.assertRaisesRegex(p.Stop, 'selected artifact'):
            p.latest_production(api)


class PreservationTests(unittest.TestCase):
    def test_valid_archive_preserves_all_bytes(self):
        data = artifact([('./index.html', b'formal', 'file'), ('./.nojekyll', b'', 'file')])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            p.extract_pages(data, root, 'sha256:' + p.sha256(data))
            manifest = p.file_manifest(root)
            self.assertEqual(manifest['index.html']['sha256'], p.sha256(b'formal'))
            self.assertEqual(set(manifest), {'index.html', '.nojekyll'})

    def test_bad_digest_is_rejected_before_extraction(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(p.Stop, 'digest mismatch'):
                p.extract_pages(b'wrong', Path(directory), 'sha256:' + '0' * 64)

    def test_traversal_links_duplicates_are_rejected(self):
        cases = [[('../escape', b'x', 'file')], [('/escape', b'x', 'file')],
                 [('index.html', b'', 'link')],
                 [('index.html', b'a', 'file'), ('./index.html', b'b', 'file')]]
        for entries in cases:
            with self.subTest(entries=entries), tempfile.TemporaryDirectory() as directory:
                data = artifact(entries)
                with self.assertRaises(p.Stop):
                    p.extract_pages(data, Path(directory), 'sha256:' + p.sha256(data))

    def test_only_new_preview_subtree_is_allowed(self):
        original = {'index.html': {'sha256': 'original', 'size': 8}}
        valid = dict(original, **{'preview/audio/game/index.html': {'sha256': 'preview', 'size': 7}})
        p.assert_preserved(original, valid)
        for bad in [{}, {'index.html': {'sha256': 'changed', 'size': 8}},
                    dict(valid, **{'outside.txt': {'sha256': 'x', 'size': 1}})]:
            with self.subTest(bad=bad), self.assertRaises(p.Stop):
                p.assert_preserved(original, bad)

    def test_snapshot_change_stops_before_publish(self):
        api = FakeGitHub()
        proof = {'preview_sha': 'preview', 'production_snapshot': p.latest_production(api)}
        api.master = 'old'
        api.runs[1]['updated_at'] = '2026-10-01T08:00:00Z'
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, GITHUB_SHA='preview'):
            root = Path(directory)
            (root / 'proof.json').write_text(json.dumps(proof))
            with self.assertRaisesRegex(p.Stop, 'changed during'):
                p.recheck(api, root)

    def test_payload_tamper_is_rejected(self):
        api = FakeGitHub()
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, GITHUB_SHA='preview'):
            root = Path(directory)
            (root / 'site').mkdir()
            (root / 'site/index.html').write_text('original')
            manifest = p.file_manifest(root / 'site')
            (root / 'proof.json').write_text(json.dumps(dict(preview_sha='preview',
                production_snapshot=p.latest_production(api), combined_files=manifest, production_files=manifest)))
            (root / 'site/index.html').write_text('tampered')
            with self.assertRaisesRegex(p.Stop, 'verified manifest'):
                p.recheck(api, root)


class AccessAndScopeTests(unittest.TestCase):
    def test_push_master_and_missing_opt_in_are_rejected(self):
        env = dict(GITHUB_REPOSITORY=p.REPO, GITHUB_REF=p.BRANCH,
                   GITHUB_EVENT_NAME='workflow_dispatch', PUBLISH_AUDIO_PREVIEW='true')
        with patch.dict(os.environ, env):
            p.guard_environment()
        for key, value in [('GITHUB_REF', 'refs/heads/master'), ('GITHUB_EVENT_NAME', 'push'),
                           ('PUBLISH_AUDIO_PREVIEW', 'false'), ('GITHUB_REPOSITORY', 'other/repo')]:
            with self.subTest(key=key), patch.dict(os.environ, dict(env, **{key: value})):
                with self.assertRaises(p.Stop):
                    p.guard_environment()

    def test_permission_denial_has_no_alternate_credential_retry(self):
        with patch.dict(os.environ, GH_TOKEN='test-token'):
            api = p.GitHub()
        api.opener = Mock()
        api.opener.open.side_effect = urllib.error.HTTPError('https://api.github.com', 403, 'Forbidden', {}, None)
        with self.assertRaisesRegex(p.Stop, 'HTTP 403'):
            api.get('actions/artifacts/20/zip')
        self.assertEqual(api.opener.open.call_count, 1)

    def test_redirect_strips_api_authorization(self):
        req = urllib.request.Request('https://api.github.com/repos/a/b/actions/artifacts/1/zip',
                                     headers={'Authorization': 'Bearer test-token'})
        redirected = p.SafeRedirect().redirect_request(req, None, 302, 'Found', {}, 'https://example.com/archive.zip')
        self.assertIsNone(redirected.get_header('Authorization'))
        with self.assertRaises(p.Stop):
            p.SafeRedirect().redirect_request(req, None, 302, 'Found', {}, 'http://example.com/archive.zip')

    def test_preview_cache_scope_and_resources_required(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            name = 'game-123.service.worker.js'
            config = dict(serviceWorker=name, ensureCrossOriginIsolationHeaders=True)
            (root / 'index.html').write_text('const GODOT_CONFIG = ' + json.dumps(config) + ';\nnavigator.serviceWorker.ready')
            worker = "encodeURIComponent(self.registration.scope);\nconst CACHED_FILES = [\"index.html\"];\nconst CACHEABLE_FILES = [];"
            (root / name).write_text(worker)
            p.validate_preview(root)
            (root / name).write_text(worker.replace('index.html', '../formal.html'))
            with self.assertRaisesRegex(p.Stop, 'cache resource'):
                p.validate_preview(root)
            (root / name).write_text(worker.replace('encodeURIComponent(self.registration.scope)', 'unscoped'))
            with self.assertRaisesRegex(p.Stop, 'scope'):
                p.validate_preview(root)

    def test_https_root_alias_and_hash_are_checked(self):
        seen = []
        def response(req, **kwargs):
            seen.append(req.full_url)
            result = Mock()
            result.__enter__ = Mock(return_value=result)
            result.__exit__ = Mock(return_value=False)
            result.geturl.return_value = req.full_url
            result.read.return_value = b'formal'
            return result
        files = {'index.html': {'sha256': p.sha256(b'formal'), 'size': 6},
                 '.nojekyll': {'sha256': p.sha256(b''), 'size': 0}}
        with patch.object(p.urllib.request, 'urlopen', side_effect=response):
            p.verify_live(files)
        self.assertEqual(set(seen), {p.BASE_URL, p.BASE_URL + 'index.html'})
        files['index.html']['sha256'] = 'wrong'
        with patch.object(p.urllib.request, 'urlopen', side_effect=response), self.assertRaises(p.Stop):
            p.verify_live(files)


if __name__ == '__main__':
    unittest.main()
