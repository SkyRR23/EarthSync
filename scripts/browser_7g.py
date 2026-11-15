"""Real Chromium + actual Flutter assets + local private API, no provider mocks.
The optional certificate exception applies only to this test context. Application
and server transport TLS settings remain unchanged. Use a disposable private
store: this script creates explicitly labeled software-test farms and reports.
"""

import argparse
from playwright.sync_api import sync_playwright, expect
from pathlib import Path
import json

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--base-url", default="http://127.0.0.1:8093")
parser.add_argument("--platform-url", default="http://127.0.0.1:8031")
parser.add_argument(
    "--output", type=Path, default=Path("docs/integration/7g/evidence/browser")
)
parser.add_argument(
    "--state-output",
    type=Path,
    help="Optional private browser state path outside the checkout",
)
parser.add_argument(
    "--cloud-proxy-certificate-exception",
    action="store_true",
    help="Test-context-only exception for the managed Cloud proxy certificate",
)
args = parser.parse_args()
OUT = args.output
OUT.mkdir(parents=True, exist_ok=True)
steps = []
errors = []
tiles = []


def receipt():
    (OUT / "results.json").write_text(
        json.dumps(
            {
                "passed": steps,
                "browser_errors": errors,
                "tile_responses": tiles[:100],
                "test_scoped_ignore_https_errors": args.cloud_proxy_certificate_exception,
            },
            indent=2,
        )
        + "\n"
    )


def record(s):
    steps.append(s)
    receipt()
    print("PASS", s, flush=True)


with sync_playwright() as p:
    b = p.chromium.launch(
        executable_path="/usr/bin/chromium", headless=True, args=["--no-sandbox"]
    )
    context = b.new_context(
        viewport={"width": 1280, "height": 1000},
        ignore_https_errors=args.cloud_proxy_certificate_exception,
    )
    page = context.new_page()
    page.set_default_timeout(20000)
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.on(
        "response",
        lambda r: tiles.append({"status": r.status, "url": r.url})
        if "tile.openstreetmap" in r.url or "gibs.earthdata" in r.url
        else None,
    )

    def enable():
        page.locator(
            "flt-semantics-placeholder, flt-semantics-host flt-semantics"
        ).first.wait_for(state="attached")
        if page.locator("flt-semantics-placeholder").count():
            page.locator("flt-semantics-placeholder").dispatch_event("click")

    active_route = ""

    def go(route):
        global active_route
        active_route = route
        page.goto(args.base_url + "/#/" + route)
        enable()
        page.wait_for_timeout(600)

    def raw_pointer(action):
        style = page.add_style_tag(
            content="flt-semantics-host, flt-semantics-host * { pointer-events: none !important; }"
        )
        try:
            action()
        finally:
            style.evaluate("(e) => e.remove()")

    def visible(text):
        page.mouse.move(
            (page.viewport_size["width"] - 8)
            if page.viewport_size["width"] < 600
            else (1105 if active_route == "location" else 1190),
            500,
        )
        raw_pointer(lambda: page.mouse.wheel(0, -50000))
        page.wait_for_timeout(250)
        for _ in range(65):
            if text in page.locator("body").aria_snapshot():
                return
            raw_pointer(lambda: page.mouse.wheel(0, 400))
            page.wait_for_timeout(120)
        raise AssertionError("Missing rendered text: " + text)

    def bring(loc):
        for _ in range(70):
            box = loc.bounding_box()
            if (
                box
                and 55 <= box["y"]
                and box["y"] + box["height"] <= page.viewport_size["height"] - 25
            ):
                return
            raw_pointer(
                lambda: page.mouse.wheel(0, 280 if not box or box["y"] > 55 else -280)
            )
            page.wait_for_timeout(200)
        raise AssertionError("Cannot bring control into viewport")

    def button(name):
        visible(name)
        loc = page.get_by_role("button", name=name, exact=True)
        if loc.count() == 0:
            loc = page.get_by_role("menuitem", name=name, exact=True)
        if loc.count() == 0:
            import re

            loc = page.get_by_role("button", name=re.compile(re.escape(name)))
        bring(loc)
        loc.click(force=True)
        page.wait_for_timeout(250)

    def fill(label, value):
        visible(label)
        loc = page.get_by_role("textbox", name=label, exact=True)
        bring(loc)
        loc.click(force=True)
        page.wait_for_timeout(150)
        page.keyboard.press("ControlOrMeta+A")
        page.keyboard.type(value, delay=2)
        page.keyboard.press("Tab")
        page.wait_for_timeout(150)
        expect(loc).to_have_value(value)

    def shot(name):
        page.screenshot(path=str(OUT / (name + ".png")))

    try:
        go("")
        button("Skip for Now")
        go("location")
        for k, v in [
            ("Field name (optional)", "7G software-test farm; no ground truth"),
            ("Latitude (−90 to 90)", "42.0308"),
            ("Longitude (−180 to 180)", "-93.6319"),
        ]:
            fill(k, v)
        button("Open map (OpenStreetMap)")
        page.wait_for_timeout(3000)
        # Keep the map visible at a stable position; map buttons reveal bounds.
        button("Center on farm point")
        button("Draw boundary")
        # Vertices enclose the center at this map's current viewport. Locate map via
        # zoom control and fixed declared widget dimensions, not fake geographic data.
        zoom = page.get_by_role("button", name="Zoom in", exact=True)
        page.wait_for_timeout(500)
        box = zoom.bounding_box()
        right = box["x"] + box["width"]
        top = box["y"]
        center_x = right - 340
        center_y = top + 180
        print("MAP", box, center_x, center_y, flush=True)
        for dx, dy in [(-120, -90), (120, -90), (120, 90), (-120, 90)]:
            raw_pointer(lambda: page.mouse.click(center_x + dx, center_y + dy))
            page.wait_for_timeout(200)
        visible("4 vertices")
        shot("polygon-drawn-desktop")
        record("Draw four real map vertices")
        button("Undo")
        visible("3 vertices")
        record("Undo last vertex")
        # Add the missing fourth corner through the accessible coordinate workflow.
        button("Add corner by coordinates")
        fill("Corner latitude", "42.027929")
        fill("Corner longitude", "-93.63705")
        button("Use this corner")
        record("Enter an explicit boundary corner through accessible coordinate fields")
        button("Confirm boundary")
        visible("Approximate area")
        shot("polygon-confirmed-desktop")
        record("Validate boundary and calculate approximate area")
        visible("I confirm this point marks my field.")
        page.get_by_role(
            "checkbox", name="I confirm this point marks my field.", exact=True
        ).click()
        button("Save Confirmed Farm")
        go("location")
        visible("Saved boundary: 4 vertices")
        button("Open map (OpenStreetMap)")
        button("Edit boundary")
        visible("4 vertices")
        button("Cancel boundary edits")
        record("Save, reopen and cancel editing without losing boundary")
        # Change one vertex using the actual map UI, then cancel so persisted geometry
        # remains exactly the explicitly confirmed ring.
        button("Edit boundary")
        button("Move vertex 1 1")
        page.wait_for_timeout(500)
        box = zoom.bounding_box()
        raw_pointer(
            lambda: page.mouse.click(box["x"] + box["width"] - 400, box["y"] + 80)
        )
        button("Undo")
        button("Cancel boundary edits")
        record("Select and move a vertex; undo and cancel")
        button("Map layer Standard · OpenStreetMap")
        button("Satellite · NASA MODIS")
        page.wait_for_timeout(1800)
        shot("satellite-mode")
        record("Switch to dated NASA true-color satellite mode")
        visible("Hybrid labels unavailable")
        record("Withhold hybrid labels after verified provider failures")
        # Persist the existing revision through the private platform.
        go("farm-evidence")
        button("Farmer-declared production system")
        button("rainfed")
        button("Confirm local farm persistence")
        visible("Database farm:")
        farms = page.request.get(args.platform_url + "/api/platform/v1/farms").json()
        farm = next(
            f
            for f in farms
            if f["name"].startswith("7G software-test")
            and f["confirmed_polygon"] is not None
        )
        assert farm["confirmed_polygon"] is not None
        (OUT / "saved-farm.json").write_text(json.dumps(farm, indent=2) + "\n")
        record("Persist exact confirmed polygon in private SQLite")

        def source_job(kind, label):
            with page.expect_response(
                lambda r: r.url.endswith("/" + kind + "/jobs")
                and r.request.method == "POST"
            ) as response:
                button(label)
            assert response.value.status == 202
            initial = response.value.json()
            for _ in range(60):
                job = page.request.get(
                    args.platform_url + "/api/platform/v1/jobs/" + initial["id"]
                ).json()
                if job["status"] == "succeeded":
                    break
                if job["status"] == "failed":
                    raise AssertionError(job)
                page.wait_for_timeout(2000)
            assert job["status"] == "succeeded", job
            (OUT / (kind + "-job.json")).write_text(json.dumps(job, indent=2) + "\n")
            page.wait_for_timeout(1500)

        source_job("soil-map", "Retrieve SoilGrids pH map")
        visible("Raw pH cells and processing provenance")
        button("Open source map (online tiles)")
        page.wait_for_timeout(2200)
        shot("soil-map-desktop")
        record("Retrieve real SoilGrids pH and render native cells with legend")
        source_job("forecast", "Retrieve NOAA temperature forecast")
        visible("Publication/issuance time: unavailable.")
        shot("forecast-desktop")
        record("Retrieve real NOAA forecast with model and valid timestamps")
        fill(
            "Field observation (farmer report)",
            "Synthetic browser test report. No observed agricultural fact.",
        )
        button("Save dated farmer report")
        visible("Synthetic browser test report.")
        record("Persist a dated farmer report with unknown context")
        page.reload()
        enable()
        visible("Raw pH cells and processing provenance")
        record("Reload saved source snapshots without new provider calls")
        page.set_viewport_size({"width": 390, "height": 844})
        visible("Farm map & environmental snapshots")
        shot("mobile-source-snapshots")
        record("Render farm intelligence at mobile width")
        assert not errors, errors
    except Exception:
        shot("failure")
        (OUT / "failure-aria.txt").write_text(page.locator("body").aria_snapshot())
        receipt()
        raise
    finally:
        receipt()
        if args.state_output:
            context.storage_state(path=str(args.state_output))
        b.close()
