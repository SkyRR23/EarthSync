"""Actual Chromium acceptance of the combined 7N build and local services.

No provider responses are mocked. Only the named outage check aborts transport.
Use disposable private test stores: this creates a software-test farm/history and
uploads/deletes a generated nonprivate image. The token never enters receipts.
"""

import argparse
import io
import json
import re
from pathlib import Path

from PIL import Image
from playwright.sync_api import expect, sync_playwright

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--base-url", default="http://127.0.0.1:8091")
parser.add_argument("--token-file", required=True)
parser.add_argument("--output", default="docs/integration/7n/evidence/browser")
args = parser.parse_args()
output = Path(args.output).resolve()
output.mkdir(parents=True, exist_ok=True)
steps, errors, jobs = [], [], []
token = Path(args.token_file).read_text(encoding="utf-8").strip()


def record(name):
    steps.append(name)
    print("PASS:", name, flush=True)
    (output / "results.json").write_text(
        json.dumps(
            {"passed": steps, "browser_errors": errors, "job_statuses": jobs}, indent=2
        )
        + "\n",
        encoding="utf-8",
    )


with sync_playwright() as p:
    browser = p.chromium.launch(
        executable_path="/usr/bin/chromium", headless=True, args=["--no-sandbox"]
    )
    context = browser.new_context(viewport={"width": 1280, "height": 1000})
    page = context.new_page()
    page.set_default_timeout(20000)
    page.on("pageerror", lambda error: errors.append(str(error)))

    def enable():
        page.locator(
            "flt-semantics-placeholder, flt-semantics-host flt-semantics"
        ).first.wait_for(state="attached")
        if page.locator("flt-semantics-placeholder").count():
            page.locator("flt-semantics-placeholder").dispatch_event("click")

    def go(route):
        page.goto(args.base_url + "/#/" + route, wait_until="domcontentloaded")
        enable()

    def fill(locator, value):
        locator.click()
        page.wait_for_timeout(150)
        page.keyboard.press("ControlOrMeta+A")
        page.wait_for_timeout(50)
        page.keyboard.type(value, delay=3)
        page.keyboard.press("Tab")
        page.wait_for_timeout(100)

    def visible(text):
        viewport = page.viewport_size
        page.mouse.move(viewport["width"] / 2, viewport["height"] * 0.6)
        page.mouse.wheel(0, -40000)
        page.wait_for_timeout(250)
        for _ in range(25):
            if text in page.locator("body").aria_snapshot():
                return
            page.mouse.wheel(0, 550)
            page.wait_for_timeout(150)
        raise AssertionError("Rendered text not found: " + text)

    def shot(name):
        page.screenshot(path=str(output / (name + ".png")))

    def receipt(name, value):
        text = json.dumps(value, indent=2)
        assert token not in text
        (output / (name + ".json")).write_text(text + "\n", encoding="utf-8")

    try:
        go("")
        expect(
            page.get_by_role("button", name="Skip for Now", exact=True)
        ).to_be_visible()
        shot("onboarding")
        page.get_by_role("button", name="Skip for Now", exact=True).click()
        visible("Explore the world")
        record("Onboarding and useful global home without location permission")

        go("location")
        fill(
            page.get_by_role("textbox", name="Field name (optional)", exact=True),
            "7N software test farm (no ground truth)",
        )
        fill(
            page.get_by_role("textbox", name="Latitude (−90 to 90)", exact=True),
            "42.030234",
        )
        fill(
            page.get_by_role("textbox", name="Longitude (−180 to 180)", exact=True),
            "-93.620234",
        )
        page.get_by_role(
            "checkbox", name="I confirm this point marks my field.", exact=True
        ).click()
        page.get_by_role("button", name="Save Confirmed Farm", exact=True).click()
        visible("7N software test farm (no ground truth)")
        page.reload(wait_until="domcontentloaded")
        enable()
        visible("7N software test farm (no ground truth)")
        record("Confirmed local farm restores after browser refresh")

        go("farm-evidence")
        page.get_by_role(
            "button", name=re.compile("Farmer-declared production system")
        ).click()
        page.get_by_role("menuitem", name="rainfed", exact=True).click()
        with page.expect_response(
            lambda r: r.url.endswith("/farm-links") and r.request.method == "POST"
        ) as linked:
            page.get_by_role(
                "button", name="Confirm local farm persistence", exact=True
            ).click()
        assert linked.value.status == 201
        farm_id = linked.value.json()["farm"]["id"]
        receipt("farm-link", linked.value.json())
        visible("Database farm: " + farm_id)
        record("Explicit 201 farm link and database UUID displayed")

        page.get_by_role(
            "button", name="Retrieve daily climate for this farm", exact=True
        ).click()
        page.get_by_role("button", name="Choose historical dates", exact=True).click()
        page.get_by_role("button", name="Switch to input", exact=True).click()
        fill(
            page.get_by_role("textbox", name=re.compile(r"^Start Date")),
            "02/01/2024",
        )
        fill(page.get_by_role("textbox", name=re.compile(r"^End Date")), "02/29/2024")
        page.get_by_role("button", name="OK", exact=True).click()
        with page.expect_response(
            lambda r: "/climate/jobs" in r.url and r.request.method == "POST"
        ) as submitted:
            page.get_by_role("button", name="Request daily climate", exact=True).click()
        assert submitted.value.status == 202
        initial = submitted.value.json()
        jobs.append(initial["status"])
        assert initial["status"] in ("queued", "running")
        receipt("daily-submission", initial)
        for _ in range(50):
            if "Job: succeeded" in page.locator("body").aria_snapshot():
                break
            page.wait_for_timeout(2000)
        else:
            raise AssertionError(
                "Daily processing did not succeed within its bounded wait"
            )
        # Read the actual completed job over the same admitted loopback boundary.
        completed = context.request.get(
            "http://127.0.0.1:8021/api/platform/v1/jobs/" + initial["id"]
        ).json()
        jobs.append(completed["status"])
        assert completed["status"] == "succeeded" and not completed["result"]["gaps"]
        assert len(completed["result"]["records"]) == 3
        assert all(len(r["measurements"]) == 29 for r in completed["result"]["records"])
        assert all(
            r["source_metadata"]["policy"] == "power-daily-merra2.v1"
            for r in completed["result"]["records"]
        )
        receipt("daily-completed-live-or-live-cache", completed)
        shot("daily-evidence")
        record(
            "Actual POWER daily job, bounded polling and three persisted 29-day source records"
        )

        go("farm-evidence")
        # Flutter only exposes on-screen semantics. The added water panel can
        # put these rows below the viewport; select each actual source explicitly.
        for parameter in ("PRECTOTCORR", "T2M_MAX", "T2M_MIN"):
            visible(parameter)
            checkbox = page.get_by_role("checkbox", name=re.compile(parameter))
            checkbox.click()
            expect(checkbox).to_be_checked()
        page.get_by_role(
            "button", name="Optional reference profile", exact=True
        ).click()
        page.get_by_role(
            "menuitem", name="Corn (maize) · us_ia_story", exact=True
        ).click()
        fill(
            page.get_by_role("textbox", name="Start date (YYYY-MM-DD)", exact=True),
            "2024-02-01",
        )
        fill(
            page.get_by_role("textbox", name="End date (YYYY-MM-DD)", exact=True),
            "2024-02-29",
        )
        with page.expect_response(
            lambda r: "/api/platform/v1/assessments" in r.url
        ) as assessment:
            page.get_by_role(
                "button", name="Run and save actual Rust assessment", exact=True
            ).click()
        result = assessment.value.json()
        assert (
            assessment.value.status == 200
            and result["recommendation_eligible"] is False
        )
        assert len(result["result"]["data"]["context"]["climate"]) == 3
        assert (
            result["result"]["data"]["summaries"][0]["status"]
            == "insufficient_information"
        )
        receipt("actual-rust-assessment", result)
        visible("More information needed")
        shot("persisted-rust")
        record(
            "Selected database evidence reaches actual Rust and rendered reference gap findings"
        )

        go("farm-evidence")
        fill(
            page.get_by_role("textbox", name="Start date (YYYY-MM-DD)", exact=True),
            "2023-02-01",
        )
        fill(
            page.get_by_role("textbox", name="End date (YYYY-MM-DD)", exact=True),
            "2023-02-28",
        )
        with page.expect_response(
            lambda r: r.url.endswith("/history") and r.request.method == "POST"
        ) as history:
            page.get_by_role(
                "button", name="Save period as farmer-reported history", exact=True
            ).click()
        assert (
            history.value.status == 201
            and history.value.json()["data_type"] == "farmer_reported"
        )
        page.reload(wait_until="domcontentloaded")
        enable()
        visible("Saved decision ")
        visible("More information needed")
        record("201 historical report and persisted decisions survive refresh")

        go("assistant")
        question = page.get_by_role("textbox", name="Ask a question", exact=True)
        fill(question, "Explain the crop findings")
        with page.expect_response(
            lambda r: "/api/assistant/v1/chat" in r.url
        ) as answer:
            page.get_by_role("button", name="Send", exact=True).click()
        payload = answer.value.request.post_data_json
        response = answer.value.json()
        assert answer.value.status == 200, response
        assert any(
            d["status"] == "insufficient_information"
            for d in payload["context"]["decisions"]
        )
        assert any(e["id"].startswith("ev_") for e in payload["context"]["evidence"])
        assert any(
            d["status"] == "insufficient_information" for d in response["decisions"]
        )
        assert token not in json.dumps(payload)
        assert (
            "photo_bytes" not in json.dumps(payload)
            and "exif" not in json.dumps(payload).lower()
        )
        receipt("assistant", response)
        shot("assistant")
        record(
            "Deterministic assistant consumes permitted saved evidence and exact decision states"
        )

        go("photos")
        assert (
            context.request.get(args.base_url + "/api/evidence/v1/photos").status == 401
        )
        fill(
            page.get_by_role(
                "textbox", name="Private workspace token (from local setup)", exact=True
            ),
            token,
        )
        page.get_by_role("button", name="Connect private workspace", exact=True).click()
        expect(
            page.get_by_role("button", name="Disconnect workspace", exact=True)
        ).to_be_visible()
        image = io.BytesIO()
        Image.new("RGB", (36, 24), (20, 100, 60)).save(image, format="PNG")
        with page.expect_file_chooser() as chooser:
            page.get_by_role("button", name="Choose photo file", exact=True).click()
        chooser.value.set_files(
            {
                "name": "generated-software-test.png",
                "mimeType": "image/png",
                "buffer": image.getvalue(),
            }
        )
        visible("Upload photo")
        page.get_by_role(
            "checkbox",
            name="This is a synthetic test image, not a field observation",
            exact=True,
        ).click()
        with page.expect_response(
            lambda r: r.url.endswith("/photos") and r.request.method == "POST"
        ) as photo:
            page.get_by_role("button", name="Upload photo", exact=True).click()
        assert photo.value.status == 201
        photo_id = photo.value.json()["id"]
        assert (
            context.request.get(
                args.base_url + "/api/evidence/v1/photos/" + photo_id + "/image"
            ).status
            == 401
        )
        visible("Delete photo")
        page.get_by_role("button", name="Delete photo", exact=True).click()
        with page.expect_response(
            lambda r: "/photos/" in r.url and r.request.method == "DELETE"
        ) as deleted:
            page.get_by_role("button", name="Delete", exact=True).click()
        assert deleted.value.status == 204
        page.reload(wait_until="domcontentloaded")
        enable()
        visible("Private workspace token (from local setup)")
        record(
            "Private photo auth, sanitized browser upload, confirmed 204 deletion, session-only token"
        )

        for route, title in [
            ("field", "Field situation"),
            ("explore", "Explore"),
            ("assessment", "Agricultural evidence assessment"),
            ("sources", "Sources"),
            ("settings", "Settings"),
        ]:
            go(route)
            page.wait_for_timeout(350)
            assert page.locator("body").aria_snapshot()
        shot("settings-desktop")
        record("All primary and supporting navigation destinations render")

        page.set_viewport_size({"width": 390, "height": 844})
        go("dashboard")
        visible("7N software test farm (no ground truth)")
        shot("dashboard-phone")
        go("farm-evidence")
        visible("Database farm: " + farm_id)
        shot("farm-phone")
        record(
            "Phone layouts preserve farm identity, evidence and responsive navigation"
        )

        page.set_viewport_size({"width": 1280, "height": 1000})
        go("dashboard")
        visible("Refresh climate")
        page.route("**/api/v1/environment/season?*", lambda route: route.abort())
        page.get_by_role("button", name="Refresh climate", exact=True).click()
        visible("Climate data unavailable")
        shot("simulated-outage")
        page.unroute("**/api/v1/environment/season?*")
        visible("Try climate again")
        with page.expect_response(
            lambda r: "/api/v1/environment/season" in r.url, timeout=100000
        ) as recovered:
            page.get_by_role("button", name="Try climate again", exact=True).click()
        assert recovered.value.status == 200
        receipt("monthly-live-recovery", recovered.value.json())
        record(
            "Explicit simulated outage followed by real monthly API recovery; no synthetic fallback"
        )
        assert not errors, errors
        record("Zero unhandled browser errors")
    except Exception:
        shot("failure")
        snapshot = page.locator("body").aria_snapshot().replace(token, "[REDACTED]")
        (output / "failure.txt").write_text(snapshot, encoding="utf-8")
        raise
    finally:
        browser.close()
