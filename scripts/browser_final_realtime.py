"""Actual Chromium/Flutter/HTTP journey. Only farmer inputs/photos are synthetic.

No environmental HTTP is mocked and no external vision provider is invoked.
Optional OCR absence is reported explicitly, while the manual editor is tested.
"""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import sqlite3
import uuid

import httpx
from PIL import Image, ImageDraw, ImageFont
from playwright.sync_api import expect, sync_playwright

expect.set_options(timeout=20000)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--platform-url", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--platform-directory", type=Path)
    args = parser.parse_args()
    output = args.output.absolute()
    output.mkdir(parents=True, exist_ok=False)
    result = {
        "classification": "ACTUAL_BROWSER_AND_LOCAL_HTTP; synthetic farmer profile/report only",
        "http_mocking": False,
        "steps": [],
        "page_errors": [],
        "render_errors": [],
    }
    base = args.platform_url + "/api/platform/v1"
    farm_id = None
    image_path = output / "synthetic-report.png"
    image = Image.new("RGB", (1500, 650), "white")
    font_path = Path("C:/Windows/Fonts/arial.ttf")
    font = (
        ImageFont.truetype(str(font_path), 30)
        if font_path.exists()
        else ImageFont.load_default(size=30)
    )
    ImageDraw.Draw(image).multiline_text(
        (35, 25),
        "SYNTHETIC SOFTWARE TEST - NOT A REAL LAB REPORT\nLaboratory: Example Test Laboratory\nSample ID: SOFTWARE-TEST\nSample date: 2026-01-15\nTest method: pH in water\nSampling depth: 0-15 cm\npH: 6.4\nPhosphorus: 12 mg/kg\n",
        font=font,
        fill="black",
        spacing=12,
    )
    image.save(image_path)

    def record(step):
        result["steps"].append(step)
        print("PASS", step, flush=True)

    with httpx.Client(timeout=35, trust_env=False) as api, sync_playwright() as driver:
        browser = driver.chromium.launch(headless=True)
        context = browser.new_context(viewport={"width": 1440, "height": 1050})
        page = context.new_page()
        page.set_default_timeout(20000)
        page.on("pageerror", lambda error: result["page_errors"].append(str(error)))
        page.on(
            "console",
            lambda message: result["render_errors"].append(message.text)
            if re.search(r"RenderFlex|overflowed by|EXCEPTION CAUGHT", message.text)
            else None,
        )

        def go(route):
            page.goto(args.base_url + "/#/" + route)
            page.locator("#earthsync-loading").wait_for(state="hidden", timeout=30000)
            page.locator(
                "flt-semantics-placeholder, flt-semantics-host flt-semantics"
            ).first.wait_for(state="attached")
            if page.locator("flt-semantics-placeholder").count():
                page.locator("flt-semantics-placeholder").dispatch_event("click")
            page.wait_for_timeout(700)

        def bring(role, name):
            page.mouse.move(1200, 500)
            page.mouse.wheel(0, -50000)
            page.wait_for_timeout(120)
            for _ in range(75):
                locator = page.get_by_role(role, name=name).first
                if locator.count():
                    box = locator.bounding_box()
                    if (
                        box
                        and 65 < box["y"]
                        and box["y"] + box["height"] < page.viewport_size["height"] - 20
                    ):
                        return locator
                page.mouse.wheel(0, 200)
                page.wait_for_timeout(80)
            raise AssertionError("Control not reachable: " + str(name))

        def click(role, name):
            bring(role, name).click(force=True)
            page.wait_for_timeout(300)

        try:
            go("")
            expect(
                page.get_by_role(
                    "heading", name=re.compile("Your land,? in perspective")
                )
            ).to_be_attached()
            record("Fresh public Ames dashboard without GPS or farm fabrication")
            page.screenshot(path=str(output / "dashboard-desktop.png"))
            # Exercise actual sidebar links, including honest confirmation gates.
            for label, route in [
                ("Real-Time EarthSync", "realtime"),
                ("Satellite NDVI Map", "ndvi"),
                ("Crops", "crops"),
                ("Crop Intelligence", "crop-intelligence"),
                ("Photos / Image Analysis", "image-analysis"),
                ("Laboratory Reports", "lab-reports"),
                ("Farmer Journal", "season"),
                ("Rotation Comparison", "rotations"),
                ("Farm Map", "location"),
            ]:
                go("dashboard")
                page.get_by_text(label, exact=True).first.click(force=True)
                page.wait_for_timeout(400)
                assert route in page.url, (label, page.url)
                record(label + " navigation reaches /" + route)
            go("realtime")
            calls = []
            page.on(
                "response",
                lambda response: calls.append(response.url)
                if response.url.endswith("/realtime/ames")
                else None,
            )
            expect(
                page.get_by_text(re.compile("Current station observations")).first
            ).to_be_attached()
            page.screenshot(path=str(output / "realtime-desktop.png"))
            page.wait_for_timeout(16500)
            assert calls, "Flutter did not automatically poll the local cache"
            record("Automatic Flutter real-time cache refresh without restarting")
            go("ndvi")
            expect(
                page.get_by_role(
                    "group",
                    name=re.compile(
                        "NASA raster unavailable|Cached real acquisition|No verified NDVI"
                    ),
                ).first
            ).to_be_attached()
            click("switch", "Show NDVI overlay")
            page.screenshot(path=str(output / "ndvi-status-desktop.png"))
            record(
                "NDVI map, numerical legend, toggle and honest authorization/cache state"
            )
            go("crops")
            field = bring("textbox", "Search crops or aliases")
            field.fill("rice")
            with page.expect_response(
                lambda response: "/crop-options?" in response.url
            ):
                click("button", re.compile("^Search$"))
            click("button", "Add to reference comparison")
            click("button", re.compile("Crop intelligence"))
            with page.expect_response(
                lambda response: response.url.endswith("/crop-intelligence")
            ) as response:
                click("button", "Retrieve evidence")
            packet = response.value.json()
            assert packet["citations"] and packet["recommendation_eligible"] is False
            page.screenshot(path=str(output / "crop-rag.png"))
            record(
                "Actual crop FTS5 search and cited RAG; recommendation eligibility false"
            )

            local_id = "synthetic-browser-" + uuid.uuid4().hex[:12]
            revision = datetime.now(timezone.utc).isoformat()
            farm = {
                "id": local_id,
                "name": "AUTOMATED SYNTHETIC BROWSER FIELD - NO GROUND TRUTH",
                "point": {"latitude": 42.0308, "longitude": -93.6319},
                "confirmed_at": revision,
                "confirmed_polygon": {
                    "type": "Polygon",
                    "coordinates": [
                        [
                            [-93.633, 42.03],
                            [-93.6308, 42.03],
                            [-93.6308, 42.0316],
                            [-93.633, 42.0316],
                            [-93.633, 42.03],
                        ]
                    ],
                },
            }
            linked = api.post(
                base + "/farm-links",
                json={
                    "local_profile_id": local_id,
                    "revision": revision,
                    "farm": {
                        "name": farm["name"],
                        "confirmed_point": farm["point"],
                        "confirmed_polygon": farm["confirmed_polygon"],
                        "confirmed_on": revision[:10],
                        "production_system": "rainfed",
                    },
                },
            )
            assert linked.status_code == 201, linked.status_code
            farm_id = linked.json()["farm"]["id"]
            profile = {
                "version": 1,
                "onboarded": True,
                "user_location": {"kind": "unknown", "reason": "unknown"},
                "active_farm_id": local_id,
                "farms": [farm],
            }
            context.add_init_script(
                "localStorage.setItem('flutter.earthsync.home.v1', "
                + json.dumps(json.dumps(json.dumps(profile)))
                + ");"
            )
            # Hash navigation preserves Dart's in-memory profile. Reload once
            # to apply this explicitly synthetic test fixture before farm routes.
            page.reload()
            go("image-analysis")
            with page.expect_file_chooser() as chooser:
                click("button", "Choose image")
            chooser.value.set_files(str(image_path))
            with page.expect_response(
                lambda response: response.url.endswith("/analyze")
            ) as analysis:
                click("button", "Analyze image")
            assert analysis.value.json()["status"] == "vision_unavailable"
            record("Actual private image upload, preview and disabled-vision response")
            click("button", "Crop / Leaf")
            page.keyboard.press("ArrowDown")
            page.keyboard.press("ArrowDown")
            page.keyboard.press("Enter")
            expect(
                page.get_by_role("button", name="Soil Laboratory Report").first
            ).to_be_attached()
            with page.expect_response(
                lambda response: response.url.endswith("/lab-extraction")
            ) as extraction:
                click("button", "Analyze image")
            report = extraction.value.json()
            result["ocr"] = {
                "status": report["original"]["status"],
                "provider": report["original"].get("provider"),
            }
            assert report["confirmed"] is None
            click("button", re.compile("Report "))
            click("button", "Check, correct and confirm sample")
            expect(
                page.get_by_text("Confirm laboratory sample values", exact=True)
            ).to_be_attached()
            page.screenshot(path=str(output / "lab-correction-editor.png"))
            record(
                "Laboratory category, original image and manual correction editor; OCR status recorded separately"
            )
            page.keyboard.press("Escape")
            for route in ("season", "rotations", "farm-evidence"):
                go(route)
                assert (
                    "Farm confirmation needed"
                    not in page.locator("body").aria_snapshot()
                )
                record("Linked synthetic field opens /" + route)
            go("lab-reports")
            expect(
                page.get_by_role("button", name="Soil Laboratory Report").first
            ).to_be_attached()
            record("Dedicated laboratory navigation preselects report workflow")
            for width in (390, 768, 1440):
                page.set_viewport_size({"width": width, "height": 1000})
                go("realtime")
                assert page.evaluate(
                    "document.documentElement.scrollWidth <= window.innerWidth"
                )
                page.screenshot(path=str(output / f"realtime-{width}.png"))
                record(f"Real-time layout at {width}px without document overflow")
            assert not result["page_errors"], result["page_errors"]
            assert not result["render_errors"], result["render_errors"]
            result["status"] = "PASS"
        except BaseException:
            result["status"] = "FAIL"
            page.screenshot(path=str(output / "failure.png"))
            (output / "failure-aria.txt").write_text(
                page.locator("body").aria_snapshot(), encoding="utf-8"
            )
            raise
        finally:
            browser.close()
            if farm_id:
                photos = api.get(base + f"/farms/{farm_id}/photos")
                if photos.status_code == 200:
                    for photo in photos.json():
                        api.delete(
                            base + f"/farms/{farm_id}/photos/{photo['id']}"
                        ).raise_for_status()
                if args.platform_directory:
                    with sqlite3.connect(
                        args.platform_directory / "platform.sqlite3"
                    ) as db:
                        db.execute("PRAGMA foreign_keys=ON")
                        row = db.execute(
                            "SELECT document FROM farms WHERE id=? AND owner=?",
                            (farm_id, "local-single-user"),
                        ).fetchone()
                        if (
                            row
                            and json.loads(row[0])["name"]
                            == "AUTOMATED SYNTHETIC BROWSER FIELD - NO GROUND TRUTH"
                        ):
                            db.execute(
                                "DELETE FROM farm_links WHERE farm_id=? AND owner=?",
                                (farm_id, "local-single-user"),
                            )
                            db.execute(
                                "DELETE FROM farms WHERE id=? AND owner=?",
                                (farm_id, "local-single-user"),
                            )
            (output / "results.json").write_text(
                json.dumps(result, indent=2), encoding="utf-8"
            )


if __name__ == "__main__":
    main()
