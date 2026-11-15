"""Bounded NASA authorization probe using the official earthaccess login.

Install earthaccess==0.19.0 separately; configure EARTHDATA_TOKEN securely.
This checks access to a 1 KiB asset range, NOT numeric scientific acceptance.
No global HDF5 download or credentials enter the browser or Git repository.
"""

import argparse
import asyncio
from contextlib import redirect_stdout
from datetime import datetime, timezone
import io
import json
import os
from pathlib import Path
from urllib.parse import urlsplit

import httpx

from earthsync.platform_v1.store import Store
from earthsync.realtime.http import CachedHttp, USER_AGENT
from earthsync.realtime.nasa import ASSET_HOSTS, NasaCatalog
from earthsync.realtime.service import REFERENCES, Repository


async def discover(directory):
    async with httpx.AsyncClient(timeout=25) as client:
        return await NasaCatalog(
            CachedHttp(client, Repository(Store(directory)))
        ).fetch(REFERENCES[0], None, datetime.now(timezone.utc))


def probe(args):
    directory = args.directory.absolute()
    root = Path(__file__).resolve().parents[1]
    if (
        directory.exists()
        or directory.resolve() != directory
        or root in directory.parents
        or directory in root.parents
    ):
        raise ValueError("Use a new private directory outside the checkout")
    directory.mkdir(mode=0o700, parents=True)
    data = asyncio.run(discover(directory))
    session = None
    if args.authenticated:
        if not os.environ.get("EARTHDATA_TOKEN") and not (
            os.environ.get("EARTHDATA_USERNAME")
            and os.environ.get("EARTHDATA_PASSWORD")
        ):
            raise ValueError(
                "Configure EARTHDATA_TOKEN in the environment secret manager; never paste credentials into chat"
            )
        import earthaccess

        with redirect_stdout(io.StringIO()):
            auth = earthaccess.login(strategy="environment", persist=False)
        if not auth.authenticated:
            raise ValueError("Earthdata login did not authenticate")
        session = auth.get_session()
    outcomes = []
    try:
        for product in data["products"]:
            assets = product.get("assets", [])
            target = next(
                (u for u in assets if u.endswith(".NDVI.tif")),
                next((u for u in assets if u.endswith((".h5", ".HDF5"))), None),
            )
            result = {
                k: product.get(k)
                for k in (
                    "product",
                    "version",
                    "granule_id",
                    "acquired_start",
                    "acquired_end",
                    "catalog_revision_at",
                )
            }
            result["numeric_observation"] = False
            if not target or urlsplit(target).hostname not in ASSET_HOSTS:
                result["status"] = "NO_SUPPORTED_ASSET"
            else:
                try:
                    if session:
                        response = session.get(
                            target,
                            headers={"Range": "bytes=0-1023", "User-Agent": USER_AGENT},
                            timeout=25,
                            stream=True,
                            allow_redirects=True,
                        )
                        with response:
                            status = response.status_code
                            content_range = response.headers.get("content-range")
                    else:
                        with httpx.stream(
                            "GET",
                            target,
                            headers={"Range": "bytes=0-1023", "User-Agent": USER_AGENT},
                            timeout=25,
                            follow_redirects=False,
                        ) as response:
                            status = response.status_code
                            content_range = response.headers.get("content-range")
                    result.update(
                        http_status=status,
                        status="AUTHORIZED_RANGE_AVAILABLE_NOT_SCIENTIFICALLY_VALIDATED"
                        if status == 206 and content_range
                        else "AUTHENTICATION_REQUIRED"
                        if status in (301, 302, 303, 307, 308, 401)
                        else "AUTHORIZATION_DENIED"
                        if status == 403
                        else "PROVIDER_ACCESS_FAILED",
                    )
                except Exception as exc:
                    # Exception names only: provider bodies/headers can include tokens.
                    result.update(
                        status="TRANSPORT_FAILURE", error_type=type(exc).__name__
                    )
            outcomes.append(result)
    finally:
        if session:
            session.close()
    output = {
        "classification": "ACTUAL_PROVIDER_ACCESS_TEST",
        "authenticated": bool(session),
        "numeric_acceptance": "NOT_COMPLETED",
        "results": outcomes,
    }
    target = directory / "nasa-access.json"
    target.write_text(json.dumps(output, indent=2) + "\n")
    target.chmod(0o600)
    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--authenticated", action="store_true")
    os.umask(0o077)
    probe(parser.parse_args())
