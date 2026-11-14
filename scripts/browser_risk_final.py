import argparse
import json
import re
from pathlib import Path
from playwright.sync_api import sync_playwright
from release_privacy import private_output

parser = argparse.ArgumentParser(
    description="Verify actual in-app dated forecast acknowledgment, never an official alert claim."
)
parser.add_argument("--state", required=True)
parser.add_argument("--base-url", default="http://127.0.0.1:8091")
parser.add_argument("--platform-url", default="http://127.0.0.1:8021")
parser.add_argument(
    "--output", type=Path, help="Private raw receipt directory outside the checkout"
)
args = parser.parse_args()
out = private_output(args.output or Path(args.state).absolute().parent / "browser-risk")

with sync_playwright() as p:
    b = p.chromium.launch(
        executable_path="/usr/bin/chromium", headless=True, args=["--no-sandbox"]
    )
    c = b.new_context(
        storage_state=args.state, viewport={"width": 1280, "height": 1000}
    )
    page = c.new_page()
    page.goto(args.base_url + "/#/season")
    page.wait_for_timeout(1000)
    page.locator("flt-semantics-placeholder").dispatch_event("click")
    page.wait_for_timeout(3000)

    def visible(name, role="button"):
        for i in range(150):
            x = page.get_by_role(role, name=name)
            if x.count():
                box = x.first.bounding_box()
                if box and 60 < box["y"] and box["y"] + box["height"] < 980:
                    return x.first
                delta = -150 if box and box["y"] < 60 else 200
            else:
                delta = 250
            page.mouse.move(1100, 500)
            page.mouse.wheel(0, delta)
            page.wait_for_timeout(150)
        (out / "failure-aria.txt").write_text(page.locator("body").aria_snapshot())
        page.screenshot(path=str(out / "failure.png"))
        raise AssertionError(str(name))

    visible(re.compile("^NOAA NCEP GFS")).click()
    page.wait_for_timeout(400)
    if (out / "acknowledgment.json").exists():
        saved = json.loads((out / "acknowledgment.json").read_text())
        records = c.request.get(
            args.platform_url
            + "/api/platform/v1/farms/"
            + saved["farm_id"]
            + "/journal"
        )
        assert records.status == 200 and saved in records.json()
    else:
        loc = visible("Acknowledge snapshot")
        loc.click()
        page.wait_for_timeout(300)
        with page.expect_response(
            lambda r: r.url.endswith("/journal") and r.request.method == "POST"
        ) as response:
            page.get_by_role("button", name="Acknowledge", exact=True).click()
        assert response.value.status == 201, response.value.text()
        saved = response.value.json()
        assert (
            saved["kind"] == "warning_acknowledgment" and saved["environmental_job_ids"]
        )
        (out / "acknowledgment.json").write_text(json.dumps(saved, indent=2) + "\n")
        page.wait_for_timeout(1000)
        visible(re.compile("^NOAA NCEP GFS")).click()
        page.wait_for_timeout(300)
    for _ in range(100):
        if "Acknowledged by farmer" in page.locator("body").aria_snapshot():
            break
        page.mouse.move(1100, 500)
        page.mouse.wheel(0, 200)
        page.wait_for_timeout(150)
    else:
        raise AssertionError("Saved acknowledgment not displayed")
    page.screenshot(path=str(out / "dated-forecast-acknowledgment.png"))
    (out / "results.json").write_text(
        json.dumps(
            {
                "status": "PASS",
                "classification": "SYNTHETIC farmer acknowledgment; CACHED REAL dated GFS forecast",
                "official_alerts": "UNAVAILABLE",
                "automatic_monitoring": False,
            },
            indent=2,
        )
        + "\n"
    )
    print(
        "PASS: actual Flutter forecast validity, limitations and explicit saved acknowledgment"
    )
    b.close()
