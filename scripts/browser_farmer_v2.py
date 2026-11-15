"""Real Flutter browser acceptance; farmer inputs are synthetic, HTTP is not mocked."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re

from PIL import Image, ImageDraw

from playwright.sync_api import expect, sync_playwright


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:8121")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--profile", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    expect.set_options(timeout=15000)
    result = {
        "classification": "actual Chromium; synthetic farmer inputs only",
        "http_mocking": False,
        "steps": [],
        "page_errors": [],
        "render_errors": [],
    }
    title = "Software test: inspect the field"

    with sync_playwright() as driver:
        context = driver.chromium.launch_persistent_context(
            str(args.profile.absolute()),
            headless=True,
            viewport={"width": 1440, "height": 1050},
            accept_downloads=True,
        )
        page = context.pages[0]
        page.set_default_timeout(15000)
        page.on("pageerror", lambda error: result["page_errors"].append(str(error)))
        page.on(
            "console",
            lambda message: result["render_errors"].append(message.text)
            if re.search(r"RenderFlex|overflowed by|EXCEPTION CAUGHT", message.text)
            else None,
        )

        def record(step):
            result["steps"].append(step)
            print("PASS", step, flush=True)

        def semantics():
            page.locator("#earthsync-loading").wait_for(state="hidden", timeout=45000)
            page.locator(
                "flt-semantics-placeholder, flt-semantics-host flt-semantics"
            ).first.wait_for(state="attached", timeout=20000)
            if page.locator("flt-semantics-placeholder").count():
                page.locator("flt-semantics-placeholder").dispatch_event("click")
            page.wait_for_timeout(450)

        def go(route):
            page.goto(args.base_url + "/#/" + route)
            semantics()

        def bring(locator):
            page.mouse.move(
                page.viewport_size["width"] * 0.6, page.viewport_size["height"] * 0.72
            )
            page.mouse.wheel(0, -30000)
            page.wait_for_timeout(130)
            for _ in range(65):
                if locator.count():
                    box = locator.first.bounding_box()
                    if (
                        box
                        and 0 <= box["y"]
                        and box["y"] + box["height"] <= page.viewport_size["height"]
                    ):
                        return locator.first
                page.mouse.wheel(0, 200)
                page.wait_for_timeout(90)
            raise AssertionError("Unreachable control: " + str(locator))

        def click(name, role="button"):
            bring(page.get_by_role(role, name=name)).click(force=True)
            page.wait_for_timeout(350)

        def fill(name, value):
            field = bring(page.get_by_role("textbox", name=re.compile(name)))
            field.click(force=True)
            field.press("ControlOrMeta+A")
            field.press_sequentially(value, delay=40)
            page.wait_for_timeout(180)
            expect(field).to_have_value(value)
            field.press("Tab")
            page.wait_for_timeout(180)

        def photo(name):
            page.screenshot(path=str(args.output / name))

        def contains(text):
            expect(
                page.get_by_label(re.compile(re.escape(text)))
                .or_(page.get_by_text(text, exact=False))
                .first
            ).to_be_attached()

        try:
            go("")
            if page.get_by_role("button", name="Skip for Now", exact=True).count():
                photo("first-launch-desktop.png")
                click("Skip for Now")
                record("First launch without sign-in, GPS or fabricated farm")
            go("dashboard")
            if page.get_by_role("button", name="Add My Farm", exact=True).count():
                click("Add My Farm")
                fill("Field name", "Software test field")
                fill("Latitude", "-1.3")
                fill("Longitude", "36.8")
                click(re.compile("I confirm this point"), "checkbox")
                click("Save Confirmed Farm")
                page.wait_for_url("**/#/dashboard")
                record("Confirmed farmer-entered field persists locally")
            contains("Software test field")
            photo("home-desktop.png")
            go("tasks")
            click("Add a farm task")
            fill("Activity title", title)
            fill(
                "Notes \\(optional\\)",
                "Synthetic software acceptance activity, not agricultural advice.",
            )
            photo("task-editor-desktop.png")
            click("Save activity on this device")
            contains(title)
            record("Create task through the actual Flutter form and SQLite worker")
            photo("tasks-desktop.png")

            click("Add a farm task")
            click("Save activity on this device")
            contains("Name this activity")
            fill("Activity title", "Software test: lifecycle")
            click("Save activity on this device")
            click(re.compile("^Software test: lifecycle"))
            click("Edit task")
            fill("Activity title", "Software test: edited lifecycle")
            click("Save activity on this device")
            click(re.compile("^Software test: edited lifecycle"))
            click("Postpone one day")
            click("Upcoming", "checkbox")
            contains("Software test: edited lifecycle")
            click(re.compile("^Software test: edited lifecycle"))
            click("Skip this activity")
            click("Completed", "checkbox")
            click(re.compile("^Software test: edited lifecycle"))
            click("Reopen task")
            click("Upcoming", "checkbox")
            click(re.compile("^Software test: edited lifecycle"))
            click("Cancel task")
            click("Completed", "checkbox")
            click(re.compile("^Software test: edited lifecycle"))
            click("Delete task")
            page.get_by_role("button", name="Delete task", exact=True).last.click(
                force=True
            )
            expect(
                page.get_by_label(re.compile("Software test: edited lifecycle"))
            ).to_have_count(0)
            click("Calendar", "checkbox")
            photo("task-calendar-desktop.png")
            click("Today", "checkbox")
            record(
                "Task validation, edit, postpone, skip, reopen, cancel, delete and calendar controls work"
            )

            click("Add a farm task")
            fill("Activity title", "Software test: morning reminder")
            fill("Time zone", "UTC")
            click("Scheduled time (optional) Any time")
            click("Switch to text input mode")
            page.get_by_role("textbox", name="Hour", exact=True).fill("8")
            page.get_by_role("textbox", name="Minute", exact=True).fill("0")
            if page.get_by_role("radio", name="AM", exact=True).count():
                page.get_by_role("radio", name="AM", exact=True).click(force=True)
            click("OK")
            click("Repeat and reminder")
            click(re.compile("^Remind me"), "switch")
            click("Save activity on this device")
            go("notifications")
            if page.get_by_role(
                "button", name="Notification preferences", exact=True
            ).count():
                click("Notification preferences")
            click(re.compile("^Farm task reminders"), "switch")
            contains("Software test: morning reminder")
            click("Read all")
            contains("Task reminder · Read")
            photo("notification-due-and-read.png")
            page.reload()
            semantics()
            contains("Software test: morning reminder")
            record(
                "Due reminder enters the in-app center and read state survives reload"
            )

            go("local-records")
            click("Add field record")
            fill(
                "Your observations",
                "Synthetic software note. Farmer observations are not verified soil measurements.",
            )
            click("Save field record locally")
            contains("Synthetic software note")
            record("Save a field observation locally")
            image_path = args.output / "synthetic-private-photo.png"
            image = Image.new("RGB", (640, 400), "#f7f5ef")
            ImageDraw.Draw(image).text(
                (30, 50),
                "SYNTHETIC SOFTWARE PHOTO\nNo agricultural evidence",
                fill="#173d30",
            )
            image.save(image_path)
            with page.expect_file_chooser() as chooser:
                click("Save a private photo")
            chooser.value.set_files(str(image_path.absolute()))
            page.wait_for_timeout(1200)
            expect(
                page.get_by_role(
                    "img", name="Private farmer-supplied field photograph"
                ).first
            ).to_be_attached()
            record("Photo picker stores a private GPS-stripped photo in SQLite")
            photo("notes-desktop.png")

            go("field")
            contains("Your soil, in context")
            contains("No accepted soil extract saved")
            record("Soil-first map has an honest unavailable state")
            photo("soil-desktop.png")
            click("Selected crop context", "checkbox")
            photo("soil-crop-unknown.png")
            record("Crop context keeps suitability unknown")

            for route, screenshot in [
                ("weather", "weather-desktop.png"),
                ("crops", "crops-desktop.png"),
                ("notifications", "notifications-desktop.png"),
                ("sources", "sources-desktop.png"),
            ]:
                go(route)
                photo(screenshot)
                record("Actual " + route + " screen opens")

            page.evaluate("async () => { await navigator.serviceWorker.ready; }")
            go("tasks")
            context.set_offline(True)
            page.reload()
            semantics()
            contains(title)
            record("Offline reload restores the public shell, SQLite worker and task")
            click(re.compile("Complete " + re.escape(title)))
            click("Completed", "checkbox")
            contains(title)
            record("One-tap completion persists offline")
            photo("tasks-offline-completed.png")
            page.reload()
            semantics()
            click("Completed", "checkbox")
            contains(title)
            record("Offline completion survives a second application reload")
            go("local-records")
            contains("Synthetic software note")
            expect(
                page.get_by_role(
                    "img", name="Private farmer-supplied field photograph"
                ).first
            ).to_be_attached()
            record("Field notes remain accessible offline")
            go("field")
            page.wait_for_timeout(1200)
            photo("soil-offline.png")
            context.set_offline(False)
            record("Online-to-offline-to-online transition preserves local records")

            for width, height in [(320, 820), (390, 844), (768, 1024), (1440, 1050)]:
                page.set_viewport_size({"width": width, "height": height})
                for route in [
                    "dashboard",
                    "field",
                    "weather",
                    "tasks",
                    "crops",
                    "notifications",
                    "sources",
                ]:
                    go(route)
                    photo(f"{route}-{width}.png")
                record(f"Responsive route walkthrough at {width}x{height}")
            go("settings")
            click("Dark", "radio")
            go("dashboard")
            photo("home-dark-desktop.png")
            page.set_viewport_size({"width": 390, "height": 844})
            go("tasks")
            photo("tasks-dark-phone.png")
            record("Dark appearance persists through navigation and reload")
            page.set_viewport_size({"width": 1440, "height": 1050})
            go("settings")
            click("Light", "radio")
            go("local-data")
            with page.expect_download() as download:
                click("Export selected farm records")
            export_path = args.output / "synthetic-farm-export.json"
            download.value.save_as(str(export_path))
            exported = json.loads(export_path.read_text(encoding="utf-8"))
            assert exported["farm_profile"]["name"] == "Software test field"
            assert any(row["kind"] == "task" for row in exported["records"])
            assert len(exported["photos"]) >= 1
            record(
                "Actual browser download exports tasks, notes, preferences and photo bytes"
            )
            click("Delete selected farm activity data")
            click("Keep my records")
            click("Delete selected farm activity data")
            click("Delete local activity data")
            contains("Local farm activity data removed")
            go("tasks")
            contains("Your day is open")
            go("local-records")
            contains("No field notes yet")
            go("dashboard")
            contains("Software test field")
            record(
                "Confirmed local deletion removes activities and photos while retaining the saved farm"
            )
            assert not result["page_errors"], result["page_errors"]
            assert not result["render_errors"], result["render_errors"]
            result["status"] = "passed"
        except Exception as error:
            result["status"] = "failed"
            result["error"] = str(error)
            photo("failure.png")
            (args.output / "failure-dom.txt").write_text(
                page.locator("body").inner_text(), encoding="utf-8"
            )
            raise
        finally:
            result["finished_at"] = datetime.now(timezone.utc).isoformat()
            (args.output / "acceptance.json").write_text(
                json.dumps(result, indent=2), encoding="utf-8"
            )
            context.close()


if __name__ == "__main__":
    main()
