"""Developer-only credential and backup tools. Secrets go to a new private file."""

import argparse
import json
import os
import time
from pathlib import Path

from .storage import ResearchStore, SCOPES


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("provision")
    create.add_argument("--tenant", required=True)
    create.add_argument("--subject", required=True)
    create.add_argument(
        "--scope", action="append", choices=sorted(SCOPES), required=True
    )
    create.add_argument("--hours", type=float, default=24)
    create.add_argument("--farm", action="append", default=[])
    create.add_argument("--secret-file", type=Path, required=True)
    revoke = commands.add_parser("revoke")
    revoke.add_argument("key_id")
    backup = commands.add_parser("backup")
    backup.add_argument("destination", type=Path)
    args = parser.parse_args()
    store = ResearchStore(args.directory)
    if args.command == "provision":
        path = args.secret_file.absolute()
        root = Path(__file__).resolve().parents[3]
        if (
            root == path
            or root in path.parents
            or any(p.is_symlink() for p in [path, *path.parents])
        ):
            parser.error("Secret file must be outside the checkout, without symlinks")
        fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        try:
            result = store.provision(
                args.tenant,
                args.subject,
                args.scope,
                time.time() + args.hours * 3600,
                args.farm,
            )
            with os.fdopen(fd, "w", encoding="utf-8") as output:
                json.dump(result, output)
                output.write("\n")
        except BaseException:
            path.unlink(missing_ok=True)
            raise
        print(json.dumps({k: v for k, v in result.items() if k != "token"}))
        print(
            "Secret written once to the requested private file. Transfer through your approved secret manager."
        )
    elif args.command == "revoke":
        store.revoke(args.key_id)
        print("Credential revoked")
    else:
        store.backup(args.destination)
        print("Private backup created; protect it like the live database")


if __name__ == "__main__":
    main()
