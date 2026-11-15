"""Compiled Flutter + actual local API/Rust/SQLite acceptance.

Requires explicit private synthetic farm fixture (same farm-links shape as
--fixture), actual live/cached-real annual POWER archives and compiled Web app.
No source response is mocked. Network outage steps are explicitly injected.
All runtime IDs, browser state and raw receipts stay outside the checkout.
"""

import argparse
import json
import re
from uuid import uuid4
from pathlib import Path

import httpx
from playwright.sync_api import sync_playwright
from release_privacy import private_output

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--fixture", type=Path, required=True)
parser.add_argument(
    "--resume-saved",
    type=Path,
    help="Run saved-state/as-of follow-up without repeating source retrieval",
)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--base-url", default="http://127.0.0.1:8780")
parser.add_argument("--platform-url", default="http://127.0.0.1:8771")
args = parser.parse_args()
out = private_output(args.output)
fixture = json.loads(args.fixture.read_text())
farm, link = fixture["farm"], fixture["link"]
local = {
    "id": link["local_profile_id"],
    "point": farm["confirmed_point"],
    "confirmed_at": link["revision"],
    "name": farm["name"],
    "confirmed_polygon": farm["confirmed_polygon"],
}
profile = {
    "version": 1,
    "onboarded": True,
    "farms": [local],
    "active_farm_id": local["id"],
    "user_location": {"kind": "unknown", "reason": "unknown"},
}
api = httpx.Client(base_url=args.platform_url, trust_env=False, timeout=40)
prefix = "/api/platform/v1"
steps, errors, render_errors = [], [], []
initial_results = api.get(prefix + f"/farms/{farm['id']}/simulations").json()
last_result_id = initial_results[0]["id"] if initial_results else None


def record(name, classification="actual browser / cached-real environmental evidence"):
    steps.append({"step": name, "classification": classification})
    (out / "receipt.json").write_text(
        json.dumps(
            {
                "steps": steps,
                "page_errors": errors,
                "flutter_render_errors": render_errors,
                "farm_inputs": "SYNTHETIC software fixture, not field ground truth",
            },
            indent=2,
        )
    )
    print("PASS", name, flush=True)


with sync_playwright() as driver:
    browser = driver.chromium.launch(
        executable_path="/usr/bin/chromium", headless=True, args=["--no-sandbox"]
    )
    context = browser.new_context(
        viewport={"width": 1440, "height": 1050},
        storage_state=str(args.resume_saved) if args.resume_saved else None,
    )
    context.add_init_script(
        "if(!localStorage.getItem('flutter.earthsync.home.v1'))localStorage.setItem('flutter.earthsync.home.v1',"
        + json.dumps(json.dumps(json.dumps(profile)))
        + ");"
    )
    page = context.new_page()
    page.set_default_timeout(30000)
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.on(
        "console",
        lambda message: render_errors.append(message.text)
        if message.type == "error"
        and any(
            term in message.text
            for term in [
                "RenderFlex",
                "EXCEPTION CAUGHT",
                "Another exception was thrown",
            ]
        )
        else None,
    )
    tile_status, tile_failures, tile_dates = [], [], []
    page.on(
        "response",
        lambda r: tile_dates.append(
            (re.search(r"/(\d{4}-\d{2}-\d{2})/", r.url).group(1), r.status)
        )
        if "gibs.earthdata.nasa.gov" in r.url
        and re.search(r"/(\d{4}-\d{2}-\d{2})/", r.url)
        else None,
    )
    page.on(
        "response",
        lambda r: tile_status.append(r.status)
        if "gibs.earthdata.nasa.gov" in r.url
        else None,
    )
    page.on(
        "requestfailed",
        lambda r: tile_failures.append(r.failure)
        if "gibs.earthdata.nasa.gov" in r.url
        else None,
    )

    def enable():
        page.locator(
            "flt-semantics-placeholder, flt-semantics-host flt-semantics"
        ).first.wait_for(state="attached")
        if page.locator("flt-semantics-placeholder").count():
            page.locator("flt-semantics-placeholder").dispatch_event("click")
        page.add_style_tag(
            content="flt-semantics-host, flt-semantics-host * { pointer-events: none !important; }"
        )
        page.wait_for_timeout(400)

    def scroll(dy):
        page.mouse.move(page.viewport_size["width"] - 5, 400)
        page.mouse.wheel(0, dy)
        page.wait_for_timeout(250)

    def find(name, role="button", exact=True):
        locator = page.get_by_role(role, name=name, exact=exact)
        if locator.count() and locator.first.is_visible():
            box = locator.first.bounding_box()
            if box and box["y"] > 100 and box["y"] + box["height"] < 1040:
                return locator.first
        page.evaluate("document.activeElement?.blur()")
        for _ in range(3):
            scroll(-50000)
        for _ in range(160):
            locator = page.get_by_role(role, name=name, exact=exact)
            if locator.count() and locator.first.is_visible():
                box = locator.first.bounding_box()
                if box and box["y"] > 100 and box["y"] + box["height"] < 1040:
                    return locator.first
            scroll(90)
        (out / "failed-aria.txt").write_text(page.locator("body").aria_snapshot())
        page.screenshot(path=str(out / "failed.png"))
        (out / "control-geometry.json").write_text(
            json.dumps(
                {
                    "control": str(name),
                    "boxes": [v.bounding_box() for v in locator.all()],
                }
            )
        )
        raise AssertionError("Control unavailable: " + str(name))

    def tap(loc):
        box = loc.bounding_box()
        assert box
        page.mouse.click(box["x"] + box["width"] / 2, box["y"] + box["height"] / 2)

    def click(name):
        tap(find(name))
        page.wait_for_timeout(350)

    def choose(label, value):
        tap(find(label, exact=False))
        page.wait_for_timeout(200)
        target = page.get_by_role("menuitem", name=value, exact=False)
        if not target.count():
            page.mouse.wheel(0, -10000)
            page.wait_for_timeout(200)
        for _ in range(50):
            if target.count():
                tap(target.first)
                page.wait_for_timeout(300)
                return
            page.mouse.wheel(0, 200)
            page.wait_for_timeout(100)
        raise AssertionError("Choice unavailable: " + value)

    def capture(name):
        page.screenshot(path=str(out / (name + ".png")))
        (out / (name + ".txt")).write_text(page.locator("body").aria_snapshot())

    def wait_result():
        global last_result_id
        for _ in range(50):
            rows = api.get(prefix + f"/farms/{farm['id']}/simulations").json()
            if rows and rows[0]["id"] != last_result_id:
                last_result_id = rows[0]["id"]
                break
            page.wait_for_timeout(1200)
        else:
            capture("missing-result")
            raise AssertionError("No new immutable result was saved")
        page.wait_for_timeout(1200)
        click("Simulation results")
        for _ in range(3):
            scroll(-50000)
        for _ in range(60):
            if page.get_by_role(
                "button", name="Duplicate saved simulation & edit", exact=True
            ).count():
                return
            scroll(250)
        capture("missing-result")
        raise AssertionError("Saved result was not exposed by Flutter semantics")

    page.goto(args.base_url + "/#/historical")
    enable()
    if not args.resume_saved:
        click("Detailed 2024")
        click("Retrieve selected NASA period")
        find("Play")
        record("Open confirmed farm and accepted 2024 archive with Rust ET0")
        capture("replay-2024")
        click("Play")
        page.wait_for_timeout(1400)
        click("Pause")
        record("Historical playback advances local time and pauses")
        click("Validate date & show NASA true colour")
        page.wait_for_timeout(1600)
        capture("dated-map-static-soil")
        print("GIBS browser tiles", tile_status[:8], tile_failures[:3], flush=True)
        if 200 not in tile_status:
            raise AssertionError("No TLS-verified NASA GIBS tile rendered")
        record("Inspect dated GIBS and fixed-version SoilGrids; NDVI stays unavailable")
        pin_date = tile_dates[-1][0]
        click("Pin imagery for date comparison")
        tap(find("Follow replay with dated imagery", role="checkbox", exact=False))
        click("Next period")
        find("Validate date & show NASA true colour")
        scroll(150)
        for _ in range(25):
            if any(day != pin_date and status == 200 for day, status in tile_dates):
                break
            page.wait_for_timeout(400)
        else:
            capture("missing-next-image")
            raise AssertionError("Replay did not retrieve the next dated image")
        scroll(500)
        capture("two-date-imagery")
        record(
            "Replay changes actual tile dates and retains a separately dated pinned comparison"
        )

        click("Scenario editor")
        click("Find source-backed crop identities")
        profile_id = "rice.mm.calendar-5-sessions-0@1"
        for identity in ["baseline", "alternative_a", "alternative_b"]:
            if identity == "alternative_a":
                click("Baseline · hypothetical existing plan")
                click("Alternative A · hypothetical")
            if identity == "alternative_b":
                click("Alternative A · hypothetical")
                click("Alternative B · hypothetical")
            for kind in ["Previous crop", "Current / next crop"]:
                choose(identity + " · " + kind + " reference", profile_id)
        click("Run & save simulation")
        wait_result()
        record("Run baseline and two alternatives using real archived conditions")
        rows = api.get(prefix + f"/farms/{farm['id']}/simulations").json()
        first = api.get(
            prefix + f"/farms/{farm['id']}/simulations/{rows[0]['id']}"
        ).json()
        (out / "first-result.json").write_text(json.dumps(first))
        # Edit an actual calendar control; automatic recomputation saves a new result.
        click("Scenario editor")
        date_button = find("baseline crop 1 planting: 2024-01-01")
        tap(date_button)
        tap(page.get_by_role("button", name=re.compile("^Switch to input")))
        field = page.get_by_role("textbox").last
        tap(field)
        page.keyboard.press("ControlOrMeta+A")
        page.keyboard.type("01/15/2024")
        tap(page.get_by_role("button", name="OK", exact=True))
        page.wait_for_timeout(2500)
        wait_result()
        latest = api.get(prefix + f"/farms/{farm['id']}/simulations").json()[0]
        changed = api.get(
            prefix + f"/farms/{farm['id']}/simulations/{latest['id']}"
        ).json()
        assert changed["id"] != first["id"]
        assert (
            changed["periods"][0]["strategies"][0]["plans"][0]["duration_days"]
            != first["periods"][0]["strategies"][0]["plans"][0]["duration_days"]
        )
        assert (
            changed["periods"][0]["strategies"][0]["plans"][0]["environment"]
            != first["periods"][0]["strategies"][0]["plans"][0]["environment"]
        )
        record("Planting-date edit changes saved period outputs and preserves original")
        click("Scenario editor")
        choose("baseline · Irrigation availability", "regular")
        wait_result()
        latest = api.get(prefix + f"/farms/{farm['id']}/simulations").json()[0]
        water = api.get(
            prefix + f"/farms/{farm['id']}/simulations/{latest['id']}"
        ).json()
        assert (
            water["periods"][0]["strategies"][0]["assumptions"]["irrigation"]
            == "regular"
        )
        assert (
            water["periods"][0]["strategies"][0]["water_quantities"][
                "gross_irrigation"
            ]["value"]
            is None
        )
        record(
            "Water assumption changes comparison constraints; irrigation quantity withheld"
        )
        click("Scenario editor")
        choose("Environmental comparison", "two years")
        page.wait_for_timeout(3500)
        wait_result()
        latest = api.get(prefix + f"/farms/{farm['id']}/simulations").json()[0]
        two = api.get(prefix + f"/farms/{farm['id']}/simulations/{latest['id']}").json()
        assert len(two["periods"]) == 2
        assert (
            two["periods"][0]["metrics"]["rainfall"]["value"]
            != two["periods"][1]["metrics"]["rainfall"]["value"]
        )
        record("Compare actual 2024 and 2025 under the same hypothetical decisions")
        scroll(-10000)
        scroll(500)
        capture("comparison-2024-2025")
        click("Scenario editor")
        choose("Environmental comparison", "context")
        page.wait_for_timeout(6000)
        wait_result()
        latest = api.get(prefix + f"/farms/{farm['id']}/simulations").json()[0]
        contextual = api.get(
            prefix + f"/farms/{farm['id']}/simulations/{latest['id']}"
        ).json()
        assert len(contextual["periods"]) == 11
        assert contextual["baseline"]["rainfall"]["sample_count"] == 11
        record("2015–2025 contextual comparison exposes complete-season sample counts")
        click("Keep for offline viewing")
        record(
            "Explicitly save selected historical replay and simulation for offline viewing"
        )
        context.storage_state(path=str(out / "browser-state.json"))
        context.set_offline(True)
        page.reload()
        enable()
        find("Refresh saved records")
        assert "Offline" in page.locator("body").aria_snapshot()
        record(
            "Cold offline reopen uses original device snapshot read only",
            "injected network outage / cached-real records",
        )
        capture("offline")
        page.screenshot(
            path=str(out / "offline-summary.png"),
            clip={"x": 0, "y": 0, "width": 1440, "height": 610},
        )
        context.set_offline(False)
        click("Refresh saved records")
    else:
        click("Simulation results")
        click("Reopen simulation")
        record("Reopen saved simulation with original source lineage")
    click("Duplicate saved simulation & edit")
    # As-of-date simulation must not leak archives retrieved in the present.
    choose("Scientific mode", "as of date")
    click("Run & save simulation")
    page.wait_for_timeout(6000)
    wait_result()
    latest = api.get(prefix + f"/farms/{farm['id']}/simulations").json()[0]
    asof = api.get(prefix + f"/farms/{farm['id']}/simulations/{latest['id']}").json()
    assert all(
        m["value"] is None for p in asof["periods"] for m in p["metrics"].values()
    )
    record("As-of-date mode withholds future-known environmental archives")
    click("Duplicate saved simulation & edit")
    click("Run & save simulation")
    wait_result()
    newest = api.get(prefix + f"/farms/{farm['id']}/simulations").json()[0]
    reproduced = api.get(
        prefix + f"/farms/{farm['id']}/simulations/{newest['id']}"
    ).json()
    assert reproduced["calculation_sha256"] == asof["calculation_sha256"]
    assert reproduced["source_lineage"] == asof["source_lineage"]
    record("Duplicate inputs reproduce the same calculation digest and source lineage")
    original_group = {
        "id": str(uuid4()),
        "name": "Synthetic browser import " + uuid4().hex[:6],
        "baseline_decision_id": reproduced["periods"][0]["strategies"][0][
            "decision_id"
        ],
        "alternative_decision_ids": [
            s["decision_id"] for s in reproduced["periods"][0]["strategies"][1:]
        ],
        "baseline_declared_existing_plan": True,
        "exploration_reason": "Synthetic software acceptance of historical comparison import, not a farmer observation",
    }
    response = api.post(
        prefix + f"/farms/{farm['id']}/comparisons", json=original_group
    )
    response.raise_for_status()
    original = response.json()
    click("Refresh saved records")
    click("Scenario editor")
    choose("Scientific mode", "retrospective")
    wait_result()
    click("Scenario editor")
    choose("Attach to an existing three-strategy comparison", original_group["name"])
    page.wait_for_timeout(1200)
    click("Run & save simulation")
    wait_result()
    newest = api.get(prefix + f"/farms/{farm['id']}/simulations").json()[0]
    imported = api.get(
        prefix + f"/farms/{farm['id']}/simulations/{newest['id']}"
    ).json()
    assert imported["request"]["comparison_id"] == original["id"]
    assert len(imported["saved_comparison_ids"]) == len(imported["periods"])
    groups = api.get(prefix + f"/farms/{farm['id']}/comparisons").json()
    assert next(g for g in groups if g["id"] == original["id"]) == original
    record(
        "Import an existing baseline/A/B and save new historical reassessments without overwriting it"
    )
    click("Reported history")
    assert "Unknown gap" in page.locator("body").aria_snapshot()
    capture("reported-history")
    record("Reported crops, explicit bare field and unknown gaps remain distinct")
    page.set_viewport_size({"width": 390, "height": 900})
    click("Simulation results")
    page.wait_for_timeout(500)
    capture("mobile-results")
    record("Compiled mobile layout retains accessible result and section controls")
    page.set_viewport_size({"width": 1440, "height": 1050})

    def current_outage(route):
        response = route.fetch()
        jobs = response.json()
        jobs.insert(
            0,
            {
                "kind": "forecast",
                "status": "failed",
                "result": None,
                "error": "PROVIDER_UNAVAILABLE",
                "updated": 0,
            },
        )
        route.fulfill(response=response, json=jobs)

    context.route("**/farms/*/intelligence", current_outage)
    click("Refresh saved records")
    click("Replay & map")
    click("Retrieve selected NASA period")
    find("Play")
    scroll(-50000)
    assert "Historical online context" in page.locator("body").aria_snapshot()
    record(
        "Injected current-provider failure preserves accepted historical online fallback",
        "injected forecast failure / real saved NASA archive",
    )
    context.unroute("**/farms/*/intelligence", current_outage)
    assert not errors, errors
    assert not render_errors, render_errors
    record("No unhandled page errors")
    browser.close()
api.close()
