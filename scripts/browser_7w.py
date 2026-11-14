"""Real Chromium → Flutter → live POWER → hash-pinned Rust → SQLite acceptance.

No provider responses are mocked. The named transport-outage test aborts the
browser request explicitly. Run against disposable private single-user stores.
"""

import argparse
import json
from pathlib import Path
import re

from playwright.sync_api import expect, sync_playwright

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--base-url", default="http://127.0.0.1:8091")
parser.add_argument("--platform-url", default="http://127.0.0.1:8021")
parser.add_argument("--output", default="docs/integration/7w/evidence/browser")
args = parser.parse_args()
out = Path(args.output).resolve()
out.mkdir(parents=True, exist_ok=True)
steps, errors = [], []


def receipt(name, value):
    (out / (name + ".json")).write_text(json.dumps(value, indent=2) + "\n")


def record(name):
    steps.append(name)
    print("PASS:", name, flush=True)
    receipt("results", {"passed": steps, "browser_errors": errors})


with sync_playwright() as p:
    browser = p.chromium.launch(
        executable_path="/usr/bin/chromium", headless=True, args=["--no-sandbox"]
    )
    context = browser.new_context(viewport={"width": 1280, "height": 1000})
    page = context.new_page()
    page.set_default_timeout(30000)
    page.on("pageerror", lambda e: errors.append(str(e)))

    def enable():
        page.locator(
            "flt-semantics-placeholder, flt-semantics-host flt-semantics"
        ).first.wait_for(state="attached")
        if page.locator("flt-semantics-placeholder").count():
            page.locator("flt-semantics-placeholder").dispatch_event("click")

    def go(route):
        page.goto(args.base_url + "/#/" + route, wait_until="domcontentloaded")
        enable()

    def fill(name, text):
        visible(name)
        locator = page.get_by_role("textbox", name=name, exact=True)
        locator.click()
        page.wait_for_timeout(150)
        page.keyboard.press("ControlOrMeta+A")
        page.wait_for_timeout(50)
        page.keyboard.type(text, delay=3)
        page.keyboard.press("Tab")
        page.wait_for_timeout(100)

    def visible(text):
        viewport = page.viewport_size
        page.mouse.move(viewport["width"] / 2, viewport["height"] * 0.6)
        page.mouse.wheel(0, -40000)
        page.wait_for_timeout(250)
        for _ in range(40):
            if text in page.locator("body").aria_snapshot():
                return
            page.mouse.wheel(0, 500)
            page.wait_for_timeout(150)
        raise AssertionError("Rendered text not found: " + text)

    def shot(name):
        page.screenshot(path=str(out / (name + ".png")))

    try:
        go("")
        page.get_by_role("button", name="Skip for Now", exact=True).click()
        go("location")
        fill(
            "Field name (optional)", "7W software-test Iowa farm; no field ground truth"
        )
        fill("Latitude (−90 to 90)", "42.0308")
        fill("Longitude (−180 to 180)", "-93.6319")
        page.get_by_role(
            "checkbox", name="I confirm this point marks my field.", exact=True
        ).click()
        page.get_by_role("button", name="Save Confirmed Farm", exact=True).click()
        visible("7W software-test Iowa farm")
        go("farm-evidence")
        page.get_by_role(
            "button", name=re.compile("Farmer-declared production system")
        ).click()
        page.get_by_role("menuitem", name="rainfed", exact=True).click()
        with page.expect_response(
            lambda r: r.url.endswith("/farm-links") and r.request.method == "POST"
        ) as link:
            page.get_by_role(
                "button", name="Confirm local farm persistence", exact=True
            ).click()
        assert link.value.status == 201
        farm_id = link.value.json()["farm"]["id"]
        receipt("farm-confirmation", link.value.json())
        record(
            "User confirms global point, farm and rainfed system; explicit database link"
        )

        fill("Water / first crop start (YYYY-MM-DD)", "2024-07-03")
        fill("Water / first crop end (YYYY-MM-DD)", "2024-07-07")
        with page.expect_response(
            lambda r: r.url.endswith("/water/jobs") and r.request.method == "POST"
        ) as submission:
            page.get_by_role(
                "button", name="Retrieve NASA inputs & calculate ET0", exact=True
            ).click()
        assert submission.value.status == 202
        initial = submission.value.json()
        receipt("water-submission", initial)
        for _ in range(100):
            job = context.request.get(
                args.platform_url + "/api/platform/v1/jobs/" + initial["id"]
            ).json()
            if job["status"] == "succeeded":
                break
            if job["status"] == "failed":
                raise AssertionError(job)
            page.wait_for_timeout(2000)
        else:
            raise AssertionError("Water job did not complete within bounded wait")
        job = context.request.get(
            args.platform_url + "/api/platform/v1/jobs/" + initial["id"]
        ).json()
        receipt("live-water-job", job)
        assert job["status"] == "succeeded" and not job["result"]["gaps"], job
        rows = job["result"]["records"]
        assert len(rows) == 8
        derived = next(
            r for r in rows if r["source_metadata"]["policy"] == "fao56-daily-pm.v1"
        )
        calculated = derived["source_metadata"]["calculation"]
        expect(
            page.get_by_role(
                "button", name="Retrieve NASA inputs & calculate ET0", exact=True
            )
        ).to_be_enabled()
        (out / "after-job.txt").write_text(page.locator("body").aria_snapshot())
        assert (
            calculated["et0_usable_days"] == 5
            and calculated["et0_total_mm"] is not None
        )
        visible(str(calculated["et0_total_mm"]))
        visible(str(calculated["rainfall_total_mm"]))
        shot("real-water-calculation-desktop")
        record(
            "Real NASA inputs validated, actual Rust ET0 and rainfall persist and render exactly"
        )

        visible("Use this saved calculation and source snapshots")
        page.get_by_role(
            "button", name="Use this saved calculation and source snapshots", exact=True
        ).first.click()
        fill("Exact crop name or identity (7P v2)", "rice")
        with page.expect_response(lambda r: "/crop-references?" in r.url) as reference:
            page.get_by_role(
                "button", name="Look up crop references", exact=True
            ).click()
        assert reference.value.status == 200, reference.value.text()
        receipt("v2-reference-lookup", reference.value.json())
        assert reference.value.json()["status"] == "reference_only", (
            reference.value.url,
            reference.value.text(),
        )
        expect(
            page.get_by_role("button", name="Look up crop references", exact=True)
        ).to_be_enabled()
        visible("First reference profile (exact scope)")
        page.get_by_role(
            "button", name="First reference profile (exact scope)", exact=True
        ).click()
        page.get_by_role(
            "menuitem", name="rice.mm.calendar-5-sessions-0@1", exact=True
        ).click()
        shot("source-reviewed-reference")
        visible("Save crop & water evidence assessment")
        with page.expect_response(lambda r: r.url.endswith("/assessments")) as saved:
            page.get_by_role(
                "button", name="Save crop & water evidence assessment", exact=True
            ).click()
        assessment = saved.value.json()
        assert saved.value.status == 200, assessment
        receipt("saved-rust-v2-assessment", assessment)
        assert assessment["recommendation_eligible"] is False
        assert len(assessment["result"]["data"]["context"]["climate"]) == 4
        assert assessment["result"]["data"]["context"]["region_id"] is None
        assert assessment["result"]["data"]["context"]["catalog"][0]["rules"] == []
        assert assessment["environmental_metrics"][0] == calculated
        visible("More information needed")
        shot("crop-constraints-and-water-gaps")
        record(
            "7P exact profile and separate source sidecar reach Rust with zero executable rules"
        )

        go("farm-evidence")
        visible(str(calculated["et0_total_mm"]))
        visible("Saved decision ")
        record("Browser refresh restores saved calculations and Rust decisions")

        go("assistant")
        for question, expected in [
            ("What does ET0 mean?", str(calculated["et0_total_mm"])[:6]),
            ("What is this crop's reference growing period?", "135"),
        ]:
            fill("Ask a question", question)
            with page.expect_response(
                lambda r: r.url.endswith("/api/assistant/v1/chat")
            ) as answer:
                page.get_by_role("button", name="Send", exact=True).click()
            assert answer.value.status == 200, answer.value.text()
            reply = answer.value.json()
            receipt(
                "assistant-" + ("water" if "ET0" in question else "reference"), reply
            )
            assert any(expected in c["text"] for c in reply["claims"]), reply
            assert reply["citations"]
        shot("assistant-persisted-reference-and-water")
        record(
            "Deterministic assistant explains the same persisted water values and cited reference duration"
        )

        page.set_viewport_size({"width": 390, "height": 844})
        go("farm-evidence")
        visible("Crop references & water intelligence")
        visible(str(calculated["et0_total_mm"]))
        shot("water-phone")
        record("Phone layout renders evidence and actions")

        page.set_viewport_size({"width": 1280, "height": 1000})
        go("farm-evidence")
        fill("Water / first crop start (YYYY-MM-DD)", "2024-08-03")
        fill("Water / first crop end (YYYY-MM-DD)", "2024-08-07")
        page.route("**/water/jobs", lambda route: route.abort())
        page.get_by_role(
            "button", name="Retrieve NASA inputs & calculate ET0", exact=True
        ).click()
        visible("Action unavailable")
        shot("explicit-simulated-transport-outage")
        page.unroute("**/water/jobs")
        record(
            "Explicit simulated transport outage displays a gap and never invents new results"
        )
        assert not errors, errors
        record("Zero unhandled Chromium page errors")
    except Exception:
        shot("failure")
        (out / "failure.txt").write_text(page.locator("body").aria_snapshot())
        raise
    finally:
        browser.close()
