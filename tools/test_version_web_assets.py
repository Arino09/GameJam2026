"""Check PWA cache integrity and first-visit isolation after asset versioning."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('version_assets', Path(__file__).with_name('version-web-assets.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class VersionAssetsTest(unittest.TestCase):
    def test_pwa_references_and_bootstrap(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ['index.pck', 'index.wasm', 'index.side.wasm', 'index.js', 'index.icon.png']:
                (root / name).write_bytes(b'test asset')
            (root / 'index.html').write_text('''"executable":"index"
index.manifest.json
index.service.worker.js
	if (missing.length !== 0) {
.then(() => engine.installServiceWorker()),
return Promise.reject(new Error('Service worker already exists.'));
new Promise((resolve) => {
					setTimeout(() => resolve(), 2000);
''')
            (root / 'index.offline.html').write_text('index.icon.png')
            (root / 'index.manifest.json').write_text('{"start_url":"index.html","icons":[{"src":"index.icon.png"}]}')
            (root / 'index.service.worker.js').write_text('const CACHED_FILES = ["index.html","index.js","index.offline.html"]; const CACHEABLE_FILES = ["index.wasm","index.side.wasm","index.pck"];')
            prefix = module.version_assets(root)
            html = (root / 'index.html').read_text()
            worker = (root / f'{prefix}.service.worker.js').read_text()
            self.assertIn("!window.crossOriginIsolated", html)
            self.assertIn("navigator.serviceWorker.ready", html)
            self.assertNotIn("resolve(), 2000", html)
            self.assertNotIn("Service worker already exists.", html)
            self.assertIn(f'{prefix}.manifest.json', html)
            for suffix in ['js', 'wasm', 'side.wasm', 'pck']:
                self.assertIn(f'{prefix}.{suffix}', worker)
                self.assertTrue((root / f'{prefix}.{suffix}').exists())
            self.assertIn('index.offline.html', worker)
            self.assertIn(f'{prefix}.icon.png', (root / f'{prefix}.manifest.json').read_text())
            self.assertIn(f'{prefix}.icon.png', (root / 'index.offline.html').read_text())

    def test_non_pwa_does_not_request_isolation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'index.pck').write_bytes(b'pack')
            (root / 'index.html').write_text('"executable":"index"\nindex.pck')
            (root / 'index.png.import').write_text('editor only')
            prefix = module.version_assets(root)
            html = (root / 'index.html').read_text()
            self.assertIn(f'"executable":"{prefix}"', html)
            self.assertNotIn('crossOriginIsolated', html)
            self.assertFalse((root / 'index.png.import').exists())


if __name__ == '__main__':
    unittest.main()
