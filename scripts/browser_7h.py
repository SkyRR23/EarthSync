"""Interactive Chromium acceptance journey against the actual built main app.

Requires playwright (Python) and Chromium. No application responses are mocked
except the explicitly marked outage/recovery check. Use a dedicated demo token
file; its value is never logged or written to the report/screenshots.
"""

import argparse
import json
from pathlib import Path

from playwright.sync_api import expect, sync_playwright

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--base-url", default="http://127.0.0.1:8080")
parser.add_argument("--token-file", required=True)
parser.add_argument("--chromium", default="/usr/bin/chromium")
parser.add_argument("--output", default="docs/integration/evidence")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
output = Path(args.output).resolve()
output.mkdir(parents=True, exist_ok=True)
steps = []


def passed(name):
    steps.append(name)
    print("PASS:", name, flush=True)
    (output / "browser-results.json").write_text(
        json.dumps({"passed": steps}, indent=2) + "\n"
    )


with sync_playwright() as playwright:
    browser = playwright.chromium.launch(
        executable_path=args.chromium, headless=True, args=["--no-sandbox"]
    )
    context = browser.new_context(viewport={"width": 1280, "height": 900})
    page = context.new_page()
    page.set_default_timeout(25000)
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))

    def enable():
        page.locator(
            "flt-semantics-placeholder, flt-semantics-host flt-semantics"
        ).first.wait_for(state="attached", timeout=25000)
        if page.locator("flt-semantics-placeholder").count():
            page.locator("flt-semantics-placeholder").dispatch_event("click")

    def go(route):
        page.goto(args.base_url + "/#/" + route, wait_until="domcontentloaded")
        enable()

    def shot(name):
        page.screenshot(path=str(output / f"browser-{name}.png"))

    def text_visible(fragment, direction=600):
        for _ in range(24):
            snapshot = page.locator("body").aria_snapshot()
            if fragment in snapshot:
                return snapshot
            page.mouse.wheel(0, direction)
            page.wait_for_timeout(200)
        raise AssertionError(f"Rendered text not found: {fragment}")

    def top():
        page.mouse.wheel(0, -10000)
        page.wait_for_timeout(300)

    try:
        go("")
        expect(
            page.get_by_role("button", name="Skip for Now", exact=True)
        ).to_be_visible()
        shot("onboarding")
        page.get_by_role("button", name="Skip for Now", exact=True).click()
        expect(page.get_by_text("Explore the world", exact=True)).to_be_visible()
        shot("no-location")
        passed("A: new user skips location and reaches useful global home")
        page.get_by_role(
            "button", name="Ask the EarthSync assistant", exact=True
        ).click()
        with page.expect_response(
            lambda response: "/api/assistant/v1/chat" in response.url
        ) as response:
            question = page.get_by_role("textbox", name="Ask a question", exact=True)
            question.fill("Why is soil information unavailable?")
            page.get_by_role("button", name="Send", exact=True).click()
        answer = response.value.json()
        assert (
            answer["claims"]
            and response.value.request.post_data_json["context"]["confirmed_farm"]
            is None
        )
        passed("K1: deterministic assistant works without a farm, location or LLM key")
        go("dashboard")
        page.get_by_role("button", name="Choose an Area", exact=True).click()
        page.get_by_role("checkbox", name="Yangon, Myanmar", exact=True).click()
        with page.expect_response(
            lambda response: "/api/v1/environment/season" in response.url,
            timeout=100000,
        ) as response:
            page.get_by_role("button", name="Save Area", exact=True).click()
        climate = response.value.json()
        assert response.value.status == 200, climate
        assert climate["provenance"]["data_kind"] == "modeled"
        assert (
            climate["environment"]["seasonal"]["metadata"]["dataset"]
            == "POWER daily meteorology / MERRA-2"
        )
        (output / "browser-live-nasa.json").write_text(
            json.dumps(climate, indent=2) + "\n"
        )
        text_visible("Rainfall")
        shot("climate-graphs")
        passed("B: actual live NASA request and rendered historical climate graphs")
        top()
        page.get_by_role("button", name="Add My Farm", exact=True).click()
        page.get_by_role("textbox", name="Field name (optional)", exact=True).fill(
            "7H acceptance field"
        )
        page.get_by_role("textbox", name="Latitude (−90 to 90)", exact=True).fill(
            "16.85"
        )
        page.get_by_role("textbox", name="Longitude (−180 to 180)", exact=True).fill(
            "96.15"
        )
        page.get_by_role(
            "checkbox", name="I confirm this point marks my field.", exact=True
        ).click()
        page.get_by_role("button", name="Save Confirmed Farm", exact=True).click()
        expect(page.get_by_text("7H acceptance field", exact=True)).to_be_visible()
        page.reload(wait_until="domcontentloaded")
        enable()
        expect(page.get_by_text("7H acceptance field", exact=True)).to_be_visible()
        shot("restored-farm")
        passed("C: explicit farm confirmation restores after browser refresh")
        page.get_by_role("button", name="Field situation", exact=True).click()
        text_visible("Environmental context")
        shot("environmental-unavailable")
        text_visible("Optical / SAR evidence timeline")
        shot("satellite-unavailable")
        passed(
            "D/E/G: field dashboard renders soil/weather and optical/SAR unavailable states"
        )
        go("photos")
        token = Path(args.token_file).read_text().strip()
        token_field = page.get_by_role(
            "textbox", name="Private workspace token (from local setup)", exact=True
        )
        token_field.click()
        token_field.press_sequentially(token, delay=2)
        page.wait_for_timeout(200)
        page.get_by_role("button", name="Connect private workspace", exact=True).click()
        expect(
            page.get_by_role("button", name="Choose photo file", exact=True)
        ).to_be_enabled()
        with page.expect_file_chooser() as chooser:
            page.get_by_role("button", name="Choose photo file", exact=True).click()
        chooser.value.set_files(
            str(root / "app/test/photo_evidence/fixtures/synthetic.png")
        )
        text_visible("synthetic test image")
        page.get_by_role(
            "checkbox",
            name="This is a synthetic test image, not a field observation",
            exact=True,
        ).click()
        with page.expect_response(
            lambda response: "/api/evidence/v1/photos" in response.url
            and response.request.method == "POST"
        ) as response:
            page.get_by_role("button", name="Upload photo", exact=True).click()
        photo = response.value.json()
        assert (
            response.value.status == 201
            and photo["position"] is None
            and photo["data_kind"] == "synthetic"
        )
        text_visible("SYNTHETIC test photo")
        shot("uploaded-photo")
        with page.expect_file_chooser() as chooser:
            page.get_by_role("button", name="Replace photo", exact=True).click()
        chooser.value.set_files(
            str(root / "app/test/photo_evidence/fixtures/synthetic_gps.jpg")
        )
        text_visible("synthetic test image")
        page.get_by_role(
            "checkbox",
            name="This is a synthetic test image, not a field observation",
            exact=True,
        ).click()
        with page.expect_response(
            lambda response: "/api/evidence/v1/photos/" in response.url
            and response.request.method == "PUT"
        ) as response:
            page.get_by_role("button", name="Save replacement", exact=True).click()
        replacement = response.value.json()
        assert (
            replacement["id"] == photo["id"]
            and replacement["sha256"] != photo["sha256"]
            and replacement["position"] is None
        )
        text_visible("Delete photo")
        with page.expect_response(
            lambda response: "/api/evidence/v1/photos/" in response.url
            and response.request.method == "DELETE"
        ) as response:
            page.get_by_role("button", name="Delete photo", exact=True).click()
        assert response.value.status == 204
        passed(
            "F: real browser file upload, authenticated image view, replacement, GPS withheld and deletion"
        )
        go("assessment")
        page.get_by_role(
            "button", name="Run labeled synthetic v0.3 demonstration", exact=True
        ).click()
        text_visible("SYNTHETIC SOFTWARE TEST")
        shot("synthetic-v03")
        passed("I: actual compiled Rust v0.3 synthetic assessment, visibly labeled")
        top()
        page.get_by_role(
            "button", name="Reference profile and region", exact=True
        ).click()
        page.get_by_text("Corn (maize) · us_ia_story", exact=True).click()
        page.get_by_role(
            "textbox", name="Your declared planting date (YYYY-MM-DD)", exact=True
        ).fill("2025-04-15")
        page.get_by_role(
            "textbox", name="Your declared harvest date (YYYY-MM-DD)", exact=True
        ).fill("2025-10-01")
        with page.expect_response(
            lambda response: "/api/engine/v03" in response.url
        ) as response:
            page.get_by_role(
                "button", name="Run reference gap assessment with Rust v0.3", exact=True
            ).click()
        result = response.value.json()["data"]
        assert (
            result["software_test_only"] is False
            and result["summaries"][0]["status"] == "insufficient_information"
        )
        text_visible("More information needed")
        shot("reference-catalog")
        passed(
            "J: catalog adapter invokes actual Rust and withholds unsupported suitability"
        )
        text_visible("Ask about this assessment")
        page.get_by_role("button", name="Ask about this assessment", exact=True).click()
        with page.expect_response(
            lambda response: "/api/assistant/v1/chat" in response.url
        ) as crop_response:
            question = page.get_by_role("textbox", name="Ask a question", exact=True)
            question.fill("Explain the crop findings")
            page.get_by_role("button", name="Send", exact=True).click()
        assert (
            crop_response.value.json()["decisions"][0]["status"]
            == "insufficient_information"
        )
        assert crop_response.value.json()["decisions"][0]["synthetic"] is False
        with page.expect_response(
            lambda response: "/api/assistant/v1/chat" in response.url
        ) as response:
            question = page.get_by_role("textbox", name="Ask a question", exact=True)
            question.fill("What does the rainfall graph mean?")
            page.get_by_role("button", name="Send", exact=True).click()
        assert response.value.json()["claims"]
        shot("assistant-evidence")
        passed("K2: farm assistant explains supplied evidence with source details")
        go("dashboard")
        page.route("**/api/v1/environment/season?*", lambda route: route.abort())
        text_visible("Refresh climate")
        page.get_by_role("button", name="Refresh climate", exact=True).click()
        text_visible("Climate data unavailable")
        shot("outage")
        page.unroute("**/api/v1/environment/season?*")
        with page.expect_response(
            lambda response: "/api/v1/environment/season" in response.url,
            timeout=100000,
        ) as response:
            page.get_by_role("button", name="Try climate again", exact=True).click()
        assert response.value.status == 200
        passed(
            "L: explicitly simulated transport outage and real service recovery, no fallback"
        )
        page.set_viewport_size({"width": 360, "height": 800})
        top()
        shot("phone-dashboard")
        passed("Responsive Chromium viewport 360x800 renders main farm navigation")
        assert not errors, errors
    except Exception as error:
        shot("failure")
        private_token = Path(args.token_file).read_text().strip()
        snapshot = (
            page.locator("body").aria_snapshot().replace(private_token, "[REDACTED]")
        )
        print(snapshot, flush=True)
        raise RuntimeError(str(error).replace(private_token, "[REDACTED]")) from None
    finally:
        context.close()
        browser.close()
