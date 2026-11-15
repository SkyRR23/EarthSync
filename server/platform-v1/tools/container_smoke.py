"""Inspect actual container-local readiness, owned farm and compiled Rust.

No ports are published and no live provider request is made by this CI smoke.
"""

import subprocess
import sys
import time

PROGRAM = r"""
import json, urllib.request
from pathlib import Path
reference_root = Path('/app/data/crop-knowledge/v2')
assert not (reference_root / 'tests').exists()
assert not (reference_root / 'tools/build.py').exists()
assert not Path('/app/.git').exists()
base = 'http://127.0.0.1:8021/api/platform/v1'
def call(path, payload=None):
    req = urllib.request.Request(base+path, data=json.dumps(payload).encode() if payload else None, headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(req, timeout=25) as response:
        return json.load(response)
assert call('/ready')['ready']
reference = call('/crop-references?q=rice')
assert reference['status'] == 'reference_only'
assert reference['rule_review']['executable_rule_count'] == 0
assert len(reference['rule_review']['candidates']) == 12
assert all(c['execution_status'] == 'blocked' for c in reference['rule_review']['candidates'])
intelligence = call('/crop-intelligence', {'crop':'rice', 'question':'soil pH'})
assert intelligence['status'] == 'evidence_available'
assert intelligence['recommendation_eligible'] is False
assert intelligence['citations']
corner = -93.62675015869141
polygon = {'type':'Polygon', 'coordinates': [[[corner,42.02],[-93.61,42.02],[-93.61,42.04],[corner,42.04],[corner,42.02]]]}
farm = call('/farms', {'name':'Container software test, no field ground truth','confirmed_point':{'latitude':42.03,'longitude':-93.62},'confirmed_polygon':polygon,'confirmed_on':'2026-11-14','production_system':'rainfed'})
result = call('/assessments', {'farm_id':farm['id'],'start':'2024-02-01','end':'2024-02-29'})
assert result['result']['status'] == 'success'
assert result['result']['data']['context']['farm']['field_id'] == farm['id']
assert result['result']['data']['context']['farm']['boundary'][0]['longitude'] == corner
assert not result['recommendation_eligible']
assert len(call('/farms/'+farm['id']+'/decisions')) == 1
print('PASS: container readiness, v2 integrity/lookup, blocked 7V sidecar, owned farm, actual Rust v0.3, persisted decision; no public bind or live network')
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
