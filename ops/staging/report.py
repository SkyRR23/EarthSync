"""Small, private, machine-readable operations reports."""

from datetime import datetime, timezone
import json
from pathlib import Path


class Report:
    def __init__(self):
        self.checks = []

    def add(self, name, status, detail):
        self.checks.append(dict(name=name, status=status, detail=detail))
        print(f"{status}: {name} — {detail}", flush=True)

    def check(self, name, action):
        try:
            detail = action()
            self.add(name, "PASS", detail or "Verified")
            return True
        except Exception as exc:
            # Do not copy raw HTTP, user input, tokens, coordinates or SQL rows.
            self.add(name, "FAIL", f"{type(exc).__name__}; inspect this check locally")
            return False

    def write(self, path):
        status = (
            "FAIL"
            if any(c["status"] == "FAIL" for c in self.checks)
            else (
                "INCOMPLETE"
                if any(c["status"] in ("BLOCKED", "SKIP") for c in self.checks)
                else "PASS"
            )
        )
        path = Path(path)
        if path.exists():
            raise ValueError("Report destination must be new")
        with path.open("x") as stream:
            path.chmod(0o600)
            json.dump(
                {
                    "generated_at": datetime.now(timezone.utc).isoformat(),
                    "status": status,
                    "checks": self.checks,
                },
                stream,
                indent=2,
            )
            stream.write("\n")
        print(f"RESULT: {status}")
        return {"PASS": 0, "FAIL": 1, "INCOMPLETE": 2}[status]
