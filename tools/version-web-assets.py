"""Version Godot assets and keep the built-in PWA cache references consistent."""
import argparse
import hashlib
import re
from pathlib import Path


def version_assets(root: Path) -> str:
    version = hashlib.sha256((root / 'index.pck').read_bytes()).hexdigest()[:12]
    prefix = f'game-{version}'
    renames = {}
    for path in root.glob('index.*'):
        if path.suffix == '.html':
            continue
        if path.suffix == '.import':
            path.unlink()
            continue
        renames[path.name] = prefix + path.name[len('index'):]

    # Godot derives WASM/PCK/worklet names from the executable prefix. Its PWA
    # worker and manifest also contain explicit names; update those before
    # renaming, otherwise cache.addAll fails and isolation never becomes active.
    for path in root.glob('index.*'):
        if path.suffix not in ('.html', '.json') and not path.name.endswith('.service.worker.js'):
            continue
        content = path.read_text()
        for old, new in renames.items():
            content = content.replace(old, new)
        if path.name == 'index.html':
            content = content.replace('"executable":"index"', f'"executable":"{prefix}"')
            if (root / 'index.service.worker.js').exists():
                # The single-thread engine does not require isolation itself,
                # but Wwise does. Route first visits through Godot's existing
                # worker installation/reload flow when isolation was requested.
                marker = '\tif (missing.length !== 0) {'
                if marker not in content:
                    raise ValueError('Godot Web loader changed; review the PWA isolation bootstrap.')
                bootstrap = '''\tif (GODOT_CONFIG['ensureCrossOriginIsolationHeaders'] && !window.crossOriginIsolated) {
\t\tmissing.push('Cross-origin isolation');
\t}

'''
                content = content.replace(marker, bootstrap + marker, 1)
                # installServiceWorker resolves at registration, before the
                # built-in worker finishes caching/activation. Wait for ready
                # before the first reload; a timeout must fail, not reload early.
                content = content.replace(
                    '.then(() => engine.installServiceWorker()),',
                    '.then(() => engine.installServiceWorker()).then(() => navigator.serviceWorker.ready),')
                content = content.replace(
                    "return Promise.reject(new Error('Service worker already exists.'));",
                    'return registration;')
                content = content.replace(
                    'new Promise((resolve) => {\n\t\t\t\t\tsetTimeout(() => resolve(), 2000);',
                    "new Promise((resolve, reject) => {\n\t\t\t\t\tsetTimeout(() => reject(new Error('Audio isolation setup timed out. Reload to retry.')), 15000);")
        if path.name.endswith('.service.worker.js'):
            # CacheStorage is origin-wide. Keep built-in worker cleanup within
            # this preview's own scope, even if another Godot game shares origin.
            content = re.sub(r"(const CACHE_PREFIX = [^;\n]+);",
                             r"\1 + encodeURIComponent(self.registration.scope) + ':';", content)
        path.write_text(content)
    for old, new in renames.items():
        (root / old).rename(root / new)
    print(f'Versioned Web assets: {prefix}')
    return prefix


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', nargs='?', type=Path,
                        default=Path(__file__).resolve().parents[1] / 'build' / 'web')
    version_assets(parser.parse_args().directory)
