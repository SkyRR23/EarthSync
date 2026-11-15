"""Generate a versioned, public-static-only offline shell after Flutter Web build.

No API response, private photo, token, tile or raster enters the service worker.
A new worker activates only after old tabs close, keeping one consistent build.
"""

import argparse
import hashlib
import json
from pathlib import Path

SHELL = {
    "index.html",
    "main.dart.js",
    "flutter.js",
    "flutter_bootstrap.js",
    "manifest.json",
    "version.json",
    "favicon.png",
}


def finalize(directory):
    root = Path(directory).resolve()
    if not (root / "main.dart.js").is_file() or not (root / "index.html").is_file():
        raise ValueError("Build Flutter Web before preparing offline assets")
    resources = {}
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        if path.is_file() and (
            relative in SHELL
            or relative.startswith(("assets/", "canvaskit/", "icons/"))
        ):
            if path.is_symlink() or path.suffix in {
                ".sqlite",
                ".sqlite3",
                ".db",
                ".env",
            }:
                raise ValueError("Private files cannot enter offline assets")
            resources[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    if sum((root / name).stat().st_size for name in resources) > 100 * 1024 * 1024:
        raise ValueError("Offline shell exceeds 100 MiB limit")
    digest = hashlib.sha256(json.dumps(resources, sort_keys=True).encode()).hexdigest()
    worker = """'use strict';
const CACHE = 'earthsync-public-shell-' + BUILD;
const PATHS = RESOURCES;
const base = self.registration.scope;
const urls = PATHS.map(path => new URL(path, base).href);
const allowed = new Set(urls);
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(urls)));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key.startsWith('earthsync-public-shell-') && key !== CACHE).map(key => caches.delete(key)))));
});
self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== new URL(base).origin || url.search) return;
  const root = new URL(base);
  const shell = request.mode === 'navigate' && (url.pathname === root.pathname || url.href === new URL('index.html', base).href);
  const key = shell ? new URL('index.html', base).href : url.href;
  if (!allowed.has(key)) return;
  event.respondWith(caches.open(CACHE).then(cache => cache.match(key)).then(saved => saved || fetch(request)));
});
""".replace("BUILD", json.dumps(digest)).replace(
        "RESOURCES", json.dumps(list(resources))
    )
    (root / "earthsync-offline.js").write_text(worker, encoding="utf-8", newline="\n")
    manifest = {
        "schema_version": "earthsync.offline-shell.v1",
        "build_sha256": digest,
        "public_assets": resources,
        "private_api_cached": False,
        "activation": "after all previous tabs close",
    }
    (root / "offline-assets.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n"
    )
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("web_directory")
    args = parser.parse_args()
    result = finalize(args.web_directory)
    print(
        f"Prepared {len(result['public_assets'])} public offline assets; build {result['build_sha256']}"
    )
