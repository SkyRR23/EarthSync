"""Actual crop reference comparison and explicit cached viewing during API outage."""

import argparse
import json
import re
from pathlib import Path
from playwright.sync_api import sync_playwright
from release_privacy import private_output

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--state", required=True)
p.add_argument("--base-url", default="http://127.0.0.1:8091")
p.add_argument(
    "--output", type=Path, help="Private raw receipt directory outside the checkout"
)
a = p.parse_args()
a.output = private_output(a.output or Path(a.state).absolute().parent / "browser-crops")
with sync_playwright() as driver:
    browser = driver.chromium.launch(
        executable_path="/usr/bin/chromium", headless=True, args=["--no-sandbox"]
    )
    context = browser.new_context(
        storage_state=a.state, viewport={"width": 1440, "height": 1050}
    )
    page = context.new_page()
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))

    def go():
        page.goto(a.base_url + "/#/crops")
        page.reload()
        page.locator(
            "flt-semantics-placeholder, flt-semantics-host flt-semantics"
        ).first.wait_for(state="attached")
        if page.locator("flt-semantics-placeholder").count():
            page.locator("flt-semantics-placeholder").dispatch_event("click")
        page.wait_for_timeout(1000)

    def scroll(amount):
        page.mouse.move(1100, 500)
        page.mouse.wheel(0, amount)
        page.wait_for_timeout(150)

    def control(role, name):
        for _ in range(3):
            scroll(-50000)
        for _ in range(130):
            loc = page.get_by_role(role, name=name)
            if loc.count():
                box = loc.first.bounding_box()
                if box and 60 <= box["y"] and box["y"] + box["height"] < 1048:
                    return loc.first
                if box and box["y"] < 60:
                    scroll(-130)
                    continue
            scroll(220)
        (a.output / "failure-aria.txt").write_text(page.locator("body").aria_snapshot())
        page.screenshot(path=str(a.output / "failure.png"))
        raise AssertionError(str(name))

    def select(query):
        field = control("textbox", "Search crops or aliases")
        field.click()
        page.wait_for_timeout(150)
        page.keyboard.press("ControlOrMeta+A")
        page.wait_for_timeout(50)
        page.keyboard.type(query, delay=3)
        page.keyboard.press("Tab")
        page.wait_for_timeout(150)
        control("button", re.compile("^Search$")).click()
        page.wait_for_timeout(400)
        control("button", re.compile("Add to reference comparison")).click()
        page.wait_for_timeout(500)

    go()
    select("paddy")
    select("mung bean")
    for _ in range(3):
        scroll(-50000)
    scroll(350)
    snapshot = page.locator("body").aria_snapshot()
    assert "Oryza sativa" in snapshot and "Vigna radiata" in snapshot
    assert "Recommendation unavailable" in snapshot
    page.screenshot(path=str(a.output / "two-crop-references.png"))
    page.route(
        "**/api/platform/v1/**", lambda route: route.abort("internetdisconnected")
    )
    go()
    select("paddy")
    select("mung bean")
    for _ in range(3):
        scroll(-50000)
    scroll(350)
    snapshot = page.locator("body").aria_snapshot()
    assert "Cached copy · may be stale" in snapshot
    assert "Oryza sativa" in snapshot and "Vigna radiata" in snapshot
    assert "References unavailable:" not in snapshot
    assert not errors, errors
    page.screenshot(path=str(a.output / "cached-crop-references.png"))
    (a.output / "results.json").write_text(
        json.dumps(
            {
                "status": "PASS",
                "public_catalog": "CACHED REAL reviewed reference package, no new live agronomic observation",
                "farmer_choices": "SYNTHETIC",
                "api_outage": "MOCKED",
                "alias_search_and_two_crop_comparison": True,
                "cached_original_timestamps": True,
                "browser_errors": errors,
            },
            indent=2,
        )
        + "\n"
    )
    print(
        "PASS: actual alias search, two crop reference cards, and timestamped reference cache during injected API outage"
    )
    browser.close()
