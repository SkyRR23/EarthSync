"""Actual compiled-browser empty-cache acceptance; all farm inputs synthetic.

Creates a fresh confirmed/link revision with no historical evidence. Verifies
online unavailable and cold offline unavailable states without substituting data.
Raw fixture and receipts must stay in the requested private output directory.
"""

import argparse
import json
from pathlib import Path
from uuid import uuid4

import httpx
from playwright.sync_api import sync_playwright
from release_privacy import private_output

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--fixture", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--base-url", default="http://127.0.0.1:8780")
parser.add_argument("--platform-url", default="http://127.0.0.1:8771")
args = parser.parse_args()
out = private_output(args.output)
original = json.loads(args.fixture.read_text())
link = original["link"]
link["local_profile_id"] = "empty-software-test-" + uuid4().hex[:12]
link["farm"]["name"] = "Synthetic empty-cache software-test farm"
with httpx.Client(base_url=args.platform_url, trust_env=False) as client:
    response = client.post("/api/platform/v1/farm-links", json=link)
    response.raise_for_status()
local = {
    "id": link["local_profile_id"],
    "point": link["farm"]["confirmed_point"],
    "confirmed_at": link["revision"],
    "name": link["farm"]["name"],
    "confirmed_polygon": link["farm"]["confirmed_polygon"],
}
profile = {
    "version": 1,
    "onboarded": True,
    "farms": [local],
    "active_farm_id": local["id"],
    "user_location": {"kind": "unknown", "reason": "unknown"},
}
errors = []
with sync_playwright() as driver:
    browser = driver.chromium.launch(
        executable_path="/usr/bin/chromium", headless=True, args=["--no-sandbox"]
    )
    context = browser.new_context(viewport={"width": 1440, "height": 1050})
    context.add_init_script(
        "if(!localStorage.getItem('flutter.earthsync.home.v1'))localStorage.setItem('flutter.earthsync.home.v1',"
        + json.dumps(json.dumps(json.dumps(profile)))
        + ");"
    )
    page = context.new_page()
    page.on("pageerror", lambda e: errors.append(str(e)))

    def enable():
        page.locator(
            "flt-semantics-placeholder, flt-semantics-host flt-semantics"
        ).first.wait_for(state="attached")
        if page.locator("flt-semantics-placeholder").count():
            page.locator("flt-semantics-placeholder").dispatch_event("click")
        page.wait_for_timeout(2000)

    page.goto(args.base_url + "/#/historical")
    enable()
    online = page.locator("body").aria_snapshot()
    assert "Historical evidence unavailable" in online
    assert "No accepted historical evidence" in online
    page.wait_for_function(
        "async()=>{const names=await caches.keys();return names.some(n=>n.startsWith('earthsync-public-'))}"
    )
    page.wait_for_timeout(1500)
    context.set_offline(True)
    page.reload()
    enable()
    offline = page.locator("body").aria_snapshot()
    assert "Historical evidence unavailable" in offline
    assert "Saved simulated results" not in offline
    assert "Selected historical day" not in offline
    assert "Historical records unavailable" in offline
    assert not errors, errors
    page.screenshot(path=str(out / "unavailable.png"))
    (out / "receipt.json").write_text(
        json.dumps(
            {
                "online_no_evidence": "passed",
                "offline_no_cache": "passed",
                "fabricated_values": False,
                "page_errors": errors,
                "farm_inputs": "synthetic software test",
            },
            indent=2,
        )
    )
    print(
        "PASS online no-evidence and offline no-cache unavailable states; no fabricated values or page errors",
        flush=True,
    )
    browser.close()
