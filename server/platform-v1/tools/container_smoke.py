"""Inspect actual container-local readiness, owned farm and compiled Rust.

No ports are published and no live provider request is made by this CI smoke.
"""

import subprocess
import sys
import time

PROGRAM = r"""
import json, urllib.request
base = 'http://127.0.0.1:8021/api/platform/v1'
def call(path, payload=None):
    req = urllib.request.Request(base+path, data=json.dumps(payload).encode() if payload else None, headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(req, timeout=25) as response:
        return json.load(response)
assert call('/ready')['ready']
farm = call('/farms', {'name':'Container software test, no field ground truth','confirmed_point':{'latitude':42.03,'longitude':-93.62},'confirmed_on':'2026-11-14','production_system':'rainfed'})
result = call('/assessments', {'farm_id':farm['id'],'start':'2024-02-01','end':'2024-02-29'})
assert result['result']['status'] == 'success'
assert result['result']['data']['context']['farm']['field_id'] == farm['id']
assert not result['recommendation_eligible']
assert len(call('/farms/'+farm['id']+'/decisions')) == 1
print('PASS: container readiness, owned farm, actual Rust v0.3, persisted decision; no public bind or live network')
"""


def main():
    container = sys.argv[1]
    deadline = time.monotonic() + 45
    ready_program = "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8021/api/platform/v1/ready', timeout=2)"
    while time.monotonic() < deadline:
        ready = subprocess.run(
            ["docker", "exec", container, "python", "-c", ready_program],
            capture_output=True,
        )
        if ready.returncode == 0:
            break
        time.sleep(0.5)
    else:
        raise SystemExit(
            "Container readiness failed; inspect sanitized container logs locally"
        )
    result = subprocess.run(
        ["docker", "exec", "-i", container, "python", "-"],
        input=PROGRAM,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        raise SystemExit(
            "Container assessment smoke failed; inspect sanitized container logs locally"
        )
    print(result.stdout.strip())


if __name__ == "__main__":
    main()
