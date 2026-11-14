"""Shell-free actual Rust v0.3 process with bounded queues and output."""

import asyncio
from builtins import ExceptionGroup
import hashlib
import json
from pathlib import Path

from .errors import PlatformError
from .models import ENGINE_VERSION


class RustEngine:
    def __init__(
        self, executable=None, expected_sha256=None, timeout=20, concurrency=2
    ):
        self.path = Path(executable) if executable else None
        self.expected_sha256 = expected_sha256
        self.timeout = timeout
        self.slots = asyncio.Semaphore(concurrency)
        self.sha256 = None
        if self.path:
            if (
                not self.path.is_absolute()
                or not self.path.is_file()
                or self.path.resolve() != self.path
            ):
                raise ValueError("Require an absolute fixed Rust executable")
            self.sha256 = hashlib.sha256(self.path.read_bytes()).hexdigest()
            if not expected_sha256 or self.sha256 != expected_sha256:
                raise ValueError("Rust executable requires a reviewed SHA-256")

    @property
    def ready(self):
        return self.path is not None

    async def probe(self):
        return await self.analyze(
            {
                "schema_version": ENGINE_VERSION,
                "mode": "evidence_assessment",
                "day_basis": "NASA_POWER_LST",
                "region_id": None,
                "approximate_user_location": None,
                "farm": None,
                "photos": [],
                "climate_intent": "historical",
                "sources": [],
                "catalog": [],
                "observations": [],
                "climate": [],
                "history_complete": False,
                "history": [],
                "scenarios": [],
                "sequential_field": False,
                "candidate_window": None,
            }
        )

    async def analyze(self, request):
        if not self.ready:
            raise PlatformError("RUST_NOT_CONFIGURED", 503)
        raw = json.dumps(request, allow_nan=False, separators=(",", ":")).encode()
        if len(raw) > 2_000_000:
            raise PlatformError("REQUEST_TOO_LARGE", 413)
        process = None
        try:
            async with asyncio.timeout(self.timeout):
                async with self.slots:
                    process = await asyncio.create_subprocess_exec(
                        str(self.path),
                        "--stdin",
                        stdin=asyncio.subprocess.PIPE,
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.DEVNULL,
                    )

                    async def write():
                        process.stdin.write(raw)
                        await process.stdin.drain()
                        process.stdin.close()

                    async def read():
                        output = bytearray()
                        while part := await process.stdout.read(65536):
                            if len(output) + len(part) > 4_000_000:
                                raise PlatformError("RUST_OUTPUT_LIMIT", 502)
                            output.extend(part)
                        return bytes(output)

                    # Cancel/join sibling tasks on failure; nothing runs after cleanup.
                    async with asyncio.TaskGroup() as group:
                        group.create_task(write())
                        output_task = group.create_task(read())
                    output = output_task.result()
                    if await process.wait() != 0:
                        raise PlatformError("RUST_EXECUTION_FAILURE", 502)
            data = json.loads(output)
            if not isinstance(data, dict) or data.get("status") not in (
                "success",
                "error",
            ):
                raise PlatformError("RUST_SCHEMA_MISMATCH", 502)
            if data["status"] == "error":
                raise PlatformError("SCIENTIFIC_QUALITY_REJECTION", 422)
            value = data.get("data")
            if (
                not isinstance(value, dict)
                or value.get("schema_version") != ENGINE_VERSION
                or value.get("context") != request
                or value.get("software_test_only") is not False
            ):
                raise PlatformError("RUST_SCHEMA_MISMATCH", 502)
            for key in ("findings", "summaries", "candidates", "limitations"):
                if not isinstance(value.get(key), list):
                    raise PlatformError("RUST_SCHEMA_MISMATCH", 502)
            return data
        except PlatformError:
            raise
        except TimeoutError as exc:
            raise PlatformError("RUST_TIMEOUT", 504, True) from exc
        except (OSError, ValueError, ExceptionGroup) as exc:
            raise PlatformError("RUST_EXECUTION_FAILURE", 502) from exc
        finally:
            if process and process.returncode is None:
                try:
                    process.kill()
                except ProcessLookupError:
                    pass
                await process.wait()
