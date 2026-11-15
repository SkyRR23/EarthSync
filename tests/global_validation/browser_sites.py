"""Actual compiled Web reopening of synthetic saved plans at all public sites.

Fixtures are created through unchanged production Store/Orchestrator contracts;
every farm/plan remains a hypothetical software test, not local agronomic advice.
"""

import argparse
import asyncio
import hashlib
import json
import os
import time
from pathlib import Path
from playwright.sync_api import sync_playwright
from run import rotation
from earthsync.platform_v1.api import OWNER
from earthsync.platform_v1.models import FarmInput, FarmLinkInput, Farm
from earthsync.platform_v1.store import Store
from earthsync.platform_v1.engine import RustEngine

ROOT = Path(__file__).resolve().parents[2]


async def seed(private, engine):
    store = Store(private / "ui-platform")
    farms = []
    for site in json.loads((ROOT / "tests/global_validation/sites.json").read_text())[
        "sites"
    ]:
        lat, lon = site["latitude"], site["longitude"]
        local = "validation-" + site["id"]
        polygon = {
            "type": "Polygon",
            "coordinates": [
                [
                    [lon - 0.0001, lat - 0.0001],
                    [lon + 0.0001, lat - 0.0001],
                    [lon + 0.0001, lat + 0.0001],
                    [lon - 0.0001, lat + 0.0001],
                    [lon - 0.0001, lat - 0.0001],
                ]
            ],
        }
        value = FarmInput(
            name="SYNTHETIC " + site["id"],
            confirmed_point={"latitude": lat, "longitude": lon},
            confirmed_polygon=polygon,
            confirmed_on="2026-11-14",
            production_system="rainfed",
        )
        linked = store.link_farm(
            OWNER,
            FarmLinkInput(
                local_profile_id=local, revision="2026-11-14T12:00:00Z", farm=value
            ),
        )
        data = json.loads(
            (private / "runtime" / site["id"] / "2024-07-01.json").read_text()
        )
        records = data["production_result"]["records"] + [data["rust_calculation"]]
        await rotation(
            store,
            engine,
            site,
            records,
            ["2024-07-01", "2024-07-07"],
            owner=OWNER,
            farm=Farm.model_validate(linked["farm"]),
        )
        farms.append(
            {
                "id": local,
                "name": "SYNTHETIC " + site["id"],
                "point": {"latitude": lat, "longitude": lon},
                "confirmed_polygon": polygon,
                "confirmed_at": "2026-11-14T12:00:00Z",
            }
        )
    profile = {
        "version": 1,
        "onboarded": True,
        "user_location": {"kind": "unknown", "reason": "unknown"},
        "farms": farms,
        "active_farm_id": farms[0]["id"],
        "approximate_device_location": None,
    }
    (private / "ui-home.json").write_text(json.dumps(profile))
    print(
        "Seeded 12 synthetic owned field links and 36 real-native reference assessments; no fabricated provider observations"
    )


def browse(private):
    profile = json.loads((private / "ui-home.json").read_text())
    results = []
    errors = []
    with sync_playwright() as p:
        c = p.chromium.launch_persistent_context(
            str(private / "chromium-global"),
            executable_path="/usr/bin/chromium",
            headless=True,
            args=["--no-sandbox"],
            viewport={"width": 1440, "height": 1050},
        )
        page = c.pages[0]
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.goto("http://127.0.0.1:8097/")
        page.evaluate(
            '(v)=>localStorage.setItem("flutter.earthsync.home.v1",JSON.stringify(JSON.stringify(v)))',
            profile,
        )
        page.reload()
        page.wait_for_timeout(1500)

        def go(route):
            page.goto("http://127.0.0.1:8097/#/" + route)
            page.wait_for_timeout(1000)
            if page.locator("flt-semantics-placeholder").count():
                page.locator("flt-semantics-placeholder").dispatch_event("click")
            page.wait_for_timeout(700)

        def find(role, name):
            import re

            page.evaluate("document.activeElement?.blur()")
            page.mouse.move(1150, 500)
            page.mouse.wheel(0, -50000)
            page.wait_for_timeout(200)
            for _ in range(60):
                loc = page.get_by_role(role, name=re.compile("^" + re.escape(name)))
                if loc.count():
                    box = loc.first.bounding_box()
                    if box and box["y"] >= 30 and box["y"] + box["height"] < 1048:
                        return loc.first
                    delta = -150 if box and box["y"] < 30 else 250
                else:
                    delta = 250
                page.mouse.wheel(0, delta)
                page.wait_for_timeout(150)
            raise AssertionError("Missing rendered control: " + name)

        for farm in profile["farms"]:
            if (
                os.getenv("EARTHSYNC_VALIDATION_SITE")
                and farm["id"]
                != "validation-" + os.environ["EARTHSYNC_VALIDATION_SITE"]
            ):
                continue
            ident = farm["id"].removeprefix("validation-")
            start = time.perf_counter()
            try:
                print(ident, "Selecting saved farm", flush=True)
                go("settings")
                # Settings dropdown label is supplied by the actual screen, not an injected route state.
                text = page.locator("body").aria_snapshot()
                (private / "last-settings-aria.txt").write_text(text)
                import re

                field = page.get_by_role(
                    "button",
                    name=re.compile(
                        "^(Active farm|Saved farm|Selected farm|Choose farm)"
                    ),
                )
                if not field.count():
                    field = page.get_by_role(
                        "button", name=re.compile("SYNTHETIC")
                    ).first
                field.first.click()
                page.get_by_role("menuitem", name=farm["name"], exact=True).click()
                print(ident, "Reopening comparison", flush=True)
                go("rotations")
                find("button", "Reopen saved comparison").click()
                items = page.get_by_role("menuitem")
                items.nth(1).wait_for(state="visible", timeout=10000)
                assert items.count() == 2, (
                    "One saved comparison and New comparison expected"
                )
                label = items.nth(1).get_attribute("aria-label") or ""
                assert "SYNTHETIC baseline/A/B " + ident in label, label
                items.nth(1).click()
                page.wait_for_timeout(700)
                find("button", "Priority alignment & practical limits")
                page.screenshot(path=str(private / (ident + "-priority.png")))
                (private / (ident + "-priority-aria.txt")).write_text(
                    page.locator("body").aria_snapshot()
                )
                session = c.new_cdp_session(page)
                ax = session.send("Accessibility.getFullAXTree")
                session.detach()
                (private / (ident + "-ax.json")).write_text(json.dumps(ax))
                # Flutter merges static explanations into a named group. The
                # Playwright aria snapshot omits that group name; Chromium's
                # non-ignored native AX tree preserves the actual rendered text.
                text = "\n".join(
                    n.get("name", {}).get("value", "")
                    for n in ax["nodes"]
                    if not n.get("ignored", True)
                )
                for label in [
                    "Baseline · existing plan",
                    "Alternative A",
                    "Alternative B",
                    "Local review required",
                    "Historical period",
                    "recommendation unavailable",
                ]:
                    assert label in text, label
                assert text.count("Local review required") >= 3
                assert "Farm confirmation needed" not in text
                results.append(
                    {
                        "site_id": ident,
                        "status": "PASS",
                        "three_saved_strategies_reopened": True,
                        "native_accessibility_explanations_present": True,
                        "local_review_warnings": text.count("Local review required"),
                        "elapsed_seconds": time.perf_counter() - start,
                    }
                )
                print(ident, "BROWSER PASS", flush=True)
            except Exception as exc:
                (private / (ident + "-failure-aria.txt")).write_text(
                    page.locator("body").aria_snapshot()
                )
                page.screenshot(path=str(private / (ident + "-failure.png")))
                results.append(
                    {"site_id": ident, "status": "FAILED", "error": str(exc)[:150]}
                )
                print(ident, "BROWSER FAILED", str(exc)[:250], flush=True)
        c.close()
    (ROOT / "docs/validation/evidence/browser-sites.json").write_text(
        json.dumps(
            {
                "release_sha": "660b479c3ffb714cd1d489e1241c026ceae6ed67",
                "classification": "SYNTHETIC farmer fixture inputs; real compiled Flutter, native Rust/SQLite and cached-real provider evidence",
                "scope": "Native fixture creation then actual saved-farm selection and saved-comparison UI reopening; not 12 manual planting demonstrations",
                "results": results,
                "unhandled_page_errors": errors,
            },
            indent=2,
        )
        + "\n"
    )


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("command", choices=["seed", "browser"])
    p.add_argument("--private", type=Path, required=True)
    p.add_argument("--engine", type=Path)
    a = p.parse_args()
    if a.command == "seed":
        asyncio.run(
            seed(
                a.private,
                RustEngine(
                    str(a.engine), hashlib.sha256(a.engine.read_bytes()).hexdigest()
                ),
            )
        )
    else:
        browse(a.private)
