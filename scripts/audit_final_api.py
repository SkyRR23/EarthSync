"""Enumerate real FastAPI OpenAPI operations, including mounted photo routes.

No service startup, private credentials, provider requests or production data.
The resulting JSON retains request/response schema gaps rather than inventing them.
"""

import argparse
import json
from pathlib import Path
import tempfile

from earthsync.evidence.store import PhotoStore
from earthsync.platform_v1.api import create_app as create_platform
from earthsync.platform_v1.store import Store
from earthsync.web_demo import create_demo_app


def schemas():
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory).resolve()
        app = create_demo_app(
            static_dir=root / "absent",
            evidence_store=PhotoStore(root / "workspace"),
            evidence_token="openapi-audit-placeholder-not-a-live-token",
        )
        result = {"application": app.openapi()}
        for route in app.routes:
            if getattr(route, "path", None) == "/api/evidence":
                result["workspace_photos"] = route.app.openapi()
        result["local_platform"] = create_platform(
            store=Store(root / "platform"), local_enabled=True
        ).openapi()
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = []
    for service, schema in schemas().items():
        (args.output / f"{service}-openapi.json").write_text(
            json.dumps(schema, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        prefix = "/api/evidence" if service == "workspace_photos" else ""
        for path, methods in schema["paths"].items():
            for method, operation in methods.items():
                manifest.append(
                    {
                        "service": service,
                        "method": method.upper(),
                        "endpoint": prefix + path,
                        "operation_id": operation["operationId"],
                        "request": operation.get("requestBody"),
                        "parameters": operation.get("parameters", []),
                        "responses": operation["responses"],
                    }
                )
    (args.output / "operations.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"{len(manifest)} actual OpenAPI operations exported")


if __name__ == "__main__":
    main()
