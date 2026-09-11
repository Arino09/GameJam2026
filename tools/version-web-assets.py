"""Give every exported asset a content-versioned URL to prevent stale Pages caches."""
import hashlib
from pathlib import Path

root = Path(__file__).resolve().parents[1] / 'build' / 'web'
version = hashlib.sha256((root / 'index.pck').read_bytes()).hexdigest()[:12]
prefix = f'game-{version}'
html = (root / 'index.html').read_text()
# Godot derives WASM, PCK and audio-worklet paths from the executable prefix.
for path in root.glob('index.*'):
    if path.suffix == '.html':
        continue
    if path.suffix == '.import':
        path.unlink()  # Editor-generated sidecars are not runtime assets.
        continue
    name = prefix + path.name[len('index'):]
    html = html.replace(path.name, name)
    path.rename(root / name)
html = html.replace('"executable":"index"', f'"executable":"{prefix}"')
(root / 'index.html').write_text(html)
print(f'Versioned Web assets: {prefix}')
