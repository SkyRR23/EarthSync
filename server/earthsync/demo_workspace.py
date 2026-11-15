"""Provision one private local-demo workspace without printing its secret."""

import argparse
import os
import secrets
from pathlib import Path


def provision(directory):
    directory = Path(directory).absolute()
    if directory.resolve() != directory:
        raise ValueError("Use a private absolute directory without symlinks")
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory.chmod(0o700)
    path = directory / "workspace-token.txt"
    if path.is_symlink():
        raise ValueError("Token file cannot be a symlink")
    if not path.exists():
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as stream:
            stream.write(secrets.token_urlsafe(36))
    path.chmod(0o600)
    read_token(path)
    return path


def read_token(path):
    path = Path(path)
    if not path.is_absolute() or path.is_symlink() or path.resolve() != path:
        raise ValueError("Use an absolute private token file without symlinks")
    token = path.read_text().strip()
    if (
        len(token) < 32
        or len(token) > 512
        or any(ord(c) < 33 or ord(c) > 126 for c in token)
    ):
        raise ValueError("Invalid private workspace token configuration")
    if os.name != "nt" and path.stat().st_mode & 0o077:
        raise ValueError("Private workspace token requires owner-only permissions")
    return token


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory")
    args = parser.parse_args()
    path = provision(args.directory)
    print(f"Private local workspace configured. Token file: {path}")
