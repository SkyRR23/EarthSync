"""Actual Chromium → Flutter → cached FastAPI → live providers, public Ames.

The one named outage aborts ONLY the browser's local cache request. It is never
reported as a real provider outage. No provider responses or numeric values are
substituted. Outputs must remain in a private directory outside the checkout.
"""

import argparse
from datetime import datetime, timezone
import json
import re
from pathlib import Path
import time

import httpx
from playwright.sync_api import expect, sync_playwright


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:8091")
    parser.add_argument("--platform-url", default="http://127.0.0.1:8021")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--watch-seconds", type=int, default=180)
    args = parser.parse_args()
    out = args.output.absolute()
    root = Path(__file__).resolve().parents[1]
    if out.resolve() != out or root in out.parents or out in root.parents:
        raise ValueError("Use a private output directory outside the checkout")
    out.mkdir(mode=0o700, parents=True, exist_ok=False)
    endpoint = args.platform_url + "/api/platform/v1/realtime/ames"
    results = {
        "classification": "ACTUAL_BROWSER_AND_LIVE_PROVIDERS",
        "steps": [],
        "page_errors": [],
        "tls_verification_disabled": False,
    }

    def save():
        (out / "results.json").write_text(json.dumps(results, indent=2) + "\n")

    def record(step, classification="PASS"):
        results["steps"].append({"step": step, "status": classification})
        save()
        print(classification, step, flush=True)

    def station_time(snapshot):
        return next(
            m["observed_at"]
            for m in snapshot["sources"]["iowa_station"]["data"]["measurements"]
            if m["station_id"] == "AMFI4" and m["variable"] == "air_temperature"
        )

    with sync_playwright() as p, httpx.Client(timeout=10) as api:
        browser = p.chromium.launch(
            executable_path="/usr/bin/chromium", headless=True, args=["--no-sandbox"]
        )
        context = browser.new_context(viewport={"width": 1440, "height": 1050})
        page = context.new_page()
        page.on("pageerror", lambda e: results["page_errors"].append(str(e)))
        page.set_default_timeout(30000)

        def go(route):
            page.goto(args.base_url + "/#/" + route)
            page.locator(
                "flt-semantics-placeholder, flt-semantics-host flt-semantics"
            ).first.wait_for(state="attached")
            if page.locator("flt-semantics-placeholder").count():
                page.locator("flt-semantics-placeholder").dispatch_event("click")

        def top():
            style = page.add_style_tag(
                content="flt-semantics-host, flt-semantics-host * { pointer-events: none !important; }"
            )
            page.mouse.move(page.viewport_size["width"] - 50, 400)
            page.mouse.wheel(0, -50000)
            page.wait_for_timeout(300)
            style.evaluate("e=>e.remove()")

        try:
            start = api.get(endpoint).json()
            assert start["sources"]["iowa_station"]["status"] == "FRESH"
            original = station_time(start)
            go("realtime")
            expect(
                page.get_by_role(
                    "button", name="Public reference location Ames, Iowa", exact=True
                )
            ).to_be_visible()
            expect(page.get_by_text(original, exact=False).first).to_be_visible()
            record("Render actual public Ames station values and acquisition times")
            page.screenshot(path=str(out / "public-ames-desktop.png"))

            timings = []
            for _ in range(12):
                before = time.perf_counter()
                response = api.get(endpoint)
                response.raise_for_status()
                timings.append((time.perf_counter() - before) * 1000)
            results["cached_api_ms"] = {
                "samples": len(timings),
                "mean": sum(timings) / len(timings),
                "max": max(timings),
            }
            record("Measure genuine local cached HTTP response time")

            deadline = time.monotonic() + args.watch_seconds
            updated = None
            while time.monotonic() < deadline:
                candidate = api.get(endpoint).json()
                if station_time(candidate) != original:
                    updated = candidate
                    break
                page.wait_for_timeout(5000)
            if updated:
                noticed = time.perf_counter()
                noticed_at = datetime.now(timezone.utc).isoformat()
                latest = station_time(updated)
                expect(page.get_by_text(latest, exact=False).first).to_be_visible(
                    timeout=25000
                )
                results["refresh"] = {
                    "before_observed_at": original,
                    "after_observed_at": latest,
                    "backend_first_noticed_at": noticed_at,
                    "browser_visible_at": datetime.now(timezone.utc).isoformat(),
                    "display_after_backend_notice_ms": (time.perf_counter() - noticed)
                    * 1000,
                    "source_latency": updated["sources"]["iowa_station"]["latency"],
                    "publication_to_ingestion_seconds": None,
                }
                record(
                    "Display a newer genuine station observation without restarting or manual refresh"
                )
            else:
                record(
                    "No newer station timestamp observed during bounded watch",
                    "PARTIAL",
                )

            # Explicitly injected local transport failure, with existing real data.
            context.route(endpoint, lambda route: route.abort("failed"))
            top()
            refresh = page.get_by_role("button", name="Refresh", exact=True)
            expect(refresh).to_be_enabled(timeout=65000)
            refresh.click()
            expect(
                page.get_by_text(
                    "Local monitoring service could not be reached.", exact=False
                )
            ).to_be_visible()
            assert (
                "No active official alerts found at the last successful check."
                not in page.locator("body").aria_snapshot()
            )
            record(
                "Injected LOCAL cache transport failure shows unverified alert status",
                "PASS · INJECTED LOCAL OUTAGE",
            )
            context.unroute(endpoint)
            refresh.click()
            expect(
                page.get_by_text(
                    "Local monitoring service could not be reached.", exact=False
                )
            ).to_have_count(0)
            record("Recover current cached data after the injected local outage")

            page.set_viewport_size({"width": 390, "height": 844})
            top()
            page.screenshot(path=str(out / "public-ames-phone.png"))
            assert page.evaluate("document.documentElement.scrollWidth <= innerWidth")
            record("Render monitoring at phone width without horizontal overflow")
            page.set_viewport_size({"width": 1440, "height": 1050})
            go("settings")
            page.get_by_role("button", name=re.compile("^Language English")).click()
            page.get_by_role("menuitem", name="မြန်မာ", exact=True).click()
            go("realtime")
            expect(
                page.get_by_role(
                    "heading", name="လက်ရှိအချက်အလက် EarthSync", exact=True
                ).first
            ).to_be_visible()
            record("Preserve Burmese monitoring labels through actual settings")
            assert results["page_errors"] == [], results["page_errors"]
            results["final_sources"] = {
                k: {
                    "status": v["status"],
                    "error": v["error"],
                    "last_success_at": v["last_success_at"],
                }
                for k, v in api.get(endpoint).json()["sources"].items()
            }
            save()
        finally:
            save()
            browser.close()


if __name__ == "__main__":
    main()
