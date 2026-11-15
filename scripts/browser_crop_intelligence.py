"""Actual Flutter/local API smoke with explicit synthetic profile and lab image.

No mocked HTTP or external vision; all output stays outside the checkout.
Start scripts/run_final_local.py first and generate the labeled report fixture.
"""

import argparse
import json
import re
import shutil
from pathlib import Path

from playwright.sync_api import expect, sync_playwright
from release_privacy import private_output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:8091")
    parser.add_argument("--platform-url", default="http://127.0.0.1:8021")
    parser.add_argument("--lab-image", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--chromium", default=shutil.which("chromium"))
    args = parser.parse_args()
    output = private_output(args.output)
    profile = {
        "version": 1,
        "onboarded": True,
        "user_location": {"kind": "unknown", "reason": "unknown"},
        "active_farm_id": "crop-intelligence-software-test",
        "farms": [
            {
                "id": "crop-intelligence-software-test",
                "point": {"latitude": 42.03, "longitude": -93.62},
                "confirmed_at": "2026-11-15T00:00:00Z",
                "name": "Synthetic software test; no ground truth",
            }
        ],
    }
    steps, errors = [], []
    with sync_playwright() as driver:
        browser = driver.chromium.launch(
            executable_path=args.chromium, headless=True, args=["--no-sandbox"]
        )
        context = browser.new_context(viewport={"width": 1440, "height": 1100})
        context.add_init_script(
            "localStorage.setItem('flutter.earthsync.home.v1', "
            + json.dumps(json.dumps(json.dumps(profile)))
            + ");"
        )
        page = context.new_page()
        farm = profile["farms"][0]
        linked = context.request.post(
            args.platform_url + "/api/platform/v1/farm-links",
            data={
                "local_profile_id": farm["id"],
                "revision": farm["confirmed_at"],
                "farm": {
                    "name": farm["name"],
                    "confirmed_point": farm["point"],
                    "confirmed_on": "2026-11-15",
                    "production_system": "rainfed",
                },
            },
        )
        assert linked.status == 201
        page.set_default_timeout(20000)
        page.on("pageerror", lambda error: errors.append(str(error)))

        def go(route):
            page.goto(args.base_url + "/#/" + route)
            page.locator(
                "flt-semantics-placeholder, flt-semantics-host flt-semantics"
            ).first.wait_for(state="attached")
            if page.locator("flt-semantics-placeholder").count():
                page.locator("flt-semantics-placeholder").dispatch_event("click")
            page.wait_for_timeout(500)

        def bring(role, name):
            for _ in range(3):
                page.mouse.move(1250, 500)
                page.mouse.wheel(0, -50000)
                page.wait_for_timeout(80)
            for _ in range(100):
                locator = page.get_by_role(role, name=name).first
                if locator.count():
                    box = locator.bounding_box()
                    if box and 65 < box["y"] and box["y"] + box["height"] < 1070:
                        return locator
                    if box and box["y"] < 65:
                        page.mouse.wheel(0, -160)
                        page.wait_for_timeout(100)
                        continue
                page.mouse.wheel(0, 220)
                page.wait_for_timeout(100)
            (output / "failure-aria.txt").write_text(
                page.locator("body").aria_snapshot()
            )
            page.screenshot(path=str(output / "failure.png"))
            raise AssertionError("Missing control: " + str(name))

        def click(role, name):
            bring(role, name).click(force=True)
            page.wait_for_timeout(350)

        try:
            go("crops")
            field = bring("textbox", "Search crops or aliases")
            field.click(force=True)
            page.wait_for_timeout(150)
            page.keyboard.press("ControlOrMeta+A")
            page.keyboard.type("rice", delay=20)
            page.keyboard.press("Tab")
            expect(field).to_have_value("rice")
            with page.expect_response(
                lambda response: "/crop-options?" in response.url
            ) as search_response:
                click("button", re.compile("^Search$"))
            assert (
                search_response.value.json()["crops"][0]["scientific_name"]
                == "Oryza sativa"
            )
            click("button", "Add to reference comparison")
            click("button", re.compile("Crop intelligence"))
            with page.expect_response(
                lambda response: response.url.endswith("/crop-intelligence")
            ) as evidence_response:
                click("button", "Retrieve evidence")
            packet = evidence_response.value.json()
            assert packet["crop"]["scientific_name"] == "Oryza sativa"
            assert packet["citations"] and not packet["recommendation_eligible"]
            assert (
                "No field recommendation is approved"
                in page.locator("body").aria_snapshot()
            )
            page.mouse.wheel(0, -50000)
            page.wait_for_timeout(250)
            page.mouse.wheel(0, 400)
            page.wait_for_timeout(250)
            steps.append("Actual FTS5 crop evidence and preserved non-eligibility")
            page.screenshot(path=str(output / "crop-intelligence.png"))
            go("farm-photos")
            with page.expect_file_chooser() as chooser:
                click("button", "Choose image")
            chooser.value.set_files(str(args.lab_image))
            with page.expect_response(lambda r: r.url.endswith("/analyze")) as analysis:
                click("button", "Analyze image")
            assert analysis.value.json()["status"] == "vision_unavailable"
            steps.append("Actual image upload and honest disabled-vision fallback")
            click("button", "Crop / Leaf")
            # Flutter renders the menu through accessibility roles, not DOM text.
            choice = page.get_by_role("menuitem", name="Soil Laboratory Report", exact=True)
            if choice.count():
                choice.click(force=True)
            else:
                # Exercise the real keyboard path when the browser flattens the
                # menu semantics: selected crop -> soil -> laboratory report.
                page.keyboard.press("ArrowDown")
                page.keyboard.press("ArrowDown")
                page.keyboard.press("Enter")
            expect(page.get_by_role("button", name="Soil Laboratory Report").first).to_be_attached()
            with page.expect_response(lambda r: r.url.endswith("/lab-extraction")) as extraction:
                click("button", "Analyze image")
            report = extraction.value.json()
            assert report["confirmed"] is None
            assert report["original"]["provider"] == "local-tesseract"
            assert next(v for v in report["original"]["values"] if v["parameter"] == "ph")["value"] == 6.4
            page.wait_for_timeout(1500)
            click("button", re.compile("Report "))
            click("button", "Check, correct and confirm sample")
            expect(
                page.get_by_text("Confirm laboratory sample values", exact=True)
            ).to_be_attached()
            steps.append("Actual private upload, local Tesseract and correction editor")
            page.screenshot(path=str(output / "lab-editor.png"))
            # A confirmation is deliberately user gated; the widget/API tests exercise correction submission.
            assert not errors, errors
            (output / "results.json").write_text(
                json.dumps(
                    {
                        "status": "PASS",
                        "steps": steps,
                        "browser_errors": errors,
                        "inputs": "Explicit synthetic profile and labeled laboratory fixture",
                        "http_mocking": False,
                        "external_vision": "unavailable",
                        "human_agronomic_approval": False,
                    },
                    indent=2,
                )
            )
            print(
                "PASS: actual Flutter evidence retrieval and private laboratory workflow; zero browser errors"
            )
        except BaseException:
            (output / "failure-aria.txt").write_text(
                page.locator("body").aria_snapshot()
            )
            page.screenshot(path=str(output / "failure.png"))
            raise
        finally:
            browser.close()


if __name__ == "__main__":
    main()
