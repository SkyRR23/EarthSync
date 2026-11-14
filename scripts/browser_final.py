"""Final farmer journey using actual Flutter, private API, Rust and real providers.

Farmer inputs and a generated photo are explicitly software-test records. No
provider responses are substituted. Offline/outage steps are explicit fault tests.
Requires the state produced by browser_7g.py and both loopback services.
"""

import argparse
import json
import re
from pathlib import Path
from datetime import datetime, timezone
from urllib.parse import urlencode

from playwright.sync_api import sync_playwright, expect

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--base-url", default="http://127.0.0.1:8091")
parser.add_argument("--platform-url", default="http://127.0.0.1:8021")
parser.add_argument("--state", required=True)
parser.add_argument(
    "--resume-strategies",
    action="store_true",
    help="Continue from the three actual saved native assessment receipts; no provider substitution",
)
parser.add_argument(
    "--output", type=Path, default=Path("docs/release/evidence/browser-final")
)
args = parser.parse_args()
out = args.output
out.mkdir(parents=True, exist_ok=True)
steps, errors = [], []
if args.resume_strategies:
    steps = json.loads((out / "results.json").read_text())["steps"]


def receipt(name, value):
    (out / f"{name}.json").write_text(
        json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


def record(name, classification):
    steps.append({"step": name, "classification": classification})
    receipt(
        "results",
        {
            "status": "IN_PROGRESS",
            "steps": steps,
            "resumed_from_saved_native_decisions": args.resume_strategies,
            "browser_errors": errors,
            "farmer_records": "SYNTHETIC software-test inputs; no field ground truth",
            "ndvi": "UNAVAILABLE: no accepted authorized raster observation; no fabricated pixels",
        },
    )
    print("PASS", classification, name, flush=True)


with sync_playwright() as p:
    browser = p.chromium.launch(
        executable_path="/usr/bin/chromium", headless=True, args=["--no-sandbox"]
    )
    context = browser.new_context(
        storage_state=args.state, viewport={"width": 1440, "height": 1050}
    )
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
        page.wait_for_timeout(600)

    def raw_scroll(dy):
        page.mouse.move(page.viewport_size["width"] * 0.7, 500)
        page.mouse.wheel(0, dy)
        page.wait_for_timeout(300)

    def visible(text, exact=False, role=None):
        current = (
            page.get_by_role(role, name=text, exact=exact)
            if role
            else page.get_by_text(text, exact=exact)
        )
        if current.count() and current.first.is_visible():
            box = current.first.bounding_box()
            if (
                box
                and box["y"] >= 30
                and box["y"] + box["height"] < page.viewport_size["height"] - 2
            ):
                return current.first
        # A focused HTML editing overlay can consume wheel/scroll requests in
        # Flutter Web. End native editing before scanning the outer viewport.
        page.evaluate("document.activeElement?.blur()")
        for _ in range(3):
            raw_scroll(-50000)
        scans = []
        for _ in range(180):
            snapshot = page.locator("body").aria_snapshot()
            scans.append(snapshot)
            if role is None and (
                text.search(snapshot) if hasattr(text, "search") else text in snapshot
            ):
                return page.locator("body")
            loc = (
                page.get_by_role(role, name=text, exact=exact)
                if role
                else page.get_by_text(text, exact=exact)
            )
            if loc.count() and loc.first.is_visible():
                box = loc.first.bounding_box()
                if (
                    box
                    and box["y"] >= 30
                    and box["y"] + box["height"] < page.viewport_size["height"] - 2
                ):
                    return loc.first
                if box and box["y"] < 30:
                    raw_scroll(-160)
                    continue
            raw_scroll(200)
        (out / "scroll-scans.json").write_text(json.dumps(scans), encoding="utf-8")
        (out / "failed-aria.txt").write_text(
            page.locator("body").aria_snapshot(), encoding="utf-8"
        )
        raise AssertionError("Rendered control/text missing: " + str(text))

    def button(name):
        visible(name, exact=True, role="button").click()
        page.wait_for_timeout(250)

    def fill(name, value):
        loc = visible(name, exact=True, role="textbox")
        loc.click()
        page.wait_for_timeout(150)
        page.keyboard.press("ControlOrMeta+A")
        page.wait_for_timeout(50)
        page.keyboard.type(value, delay=2)
        page.keyboard.press("Tab")
        page.wait_for_timeout(120)

    def choose(label, value, exact=True):
        loc = visible(re.compile("^" + re.escape(label)), role="button")
        loc.click()
        page.wait_for_timeout(300)
        target = page.get_by_role("menuitem", name=value, exact=exact)
        if not target.count():
            box = page.get_by_role("menu").bounding_box()
            if box:
                page.mouse.move(
                    box["x"] + box["width"] / 2, box["y"] + box["height"] / 2
                )
                page.mouse.wheel(0, -10000)
                page.wait_for_timeout(400)
                for _ in range(25):
                    if target.count():
                        break
                    page.mouse.wheel(0, 300)
                    page.wait_for_timeout(150)
        target.click()
        page.wait_for_timeout(250)

    def pick_date(label, value=None):
        visible(label, exact=True, role="button").click()
        if value is not None:
            page.get_by_role("button", name=re.compile("^Switch to input")).click()
            field = page.get_by_role("textbox").last
            field.click()
            page.wait_for_timeout(150)
            page.keyboard.press("ControlOrMeta+A")
            page.wait_for_timeout(50)
            page.keyboard.type(value)
        page.get_by_role("button", name="OK", exact=True).click()
        page.wait_for_timeout(300)

    def check(loc):
        if not loc.is_checked():
            loc.click()
        expect(loc).to_be_checked()
        page.wait_for_timeout(150)

    def shot(name):
        page.screenshot(path=str(out / f"{name}.png"))

    try:
        go("season")
        visible("Last retrieved")
        profile = page.evaluate(
            """()=>{let value=localStorage.getItem('flutter.earthsync.home.v1');while(typeof value==='string'){try{value=JSON.parse(value)}catch(e){break}}return value}"""
        )
        local = next(
            f for f in profile["farms"] if f["id"] == profile["active_farm_id"]
        )
        linked = context.request.get(
            args.platform_url
            + "/api/platform/v1/farm-links/"
            + local["id"]
            + "?"
            + urlencode({"revision": local["confirmed_at"]})
        )
        assert linked.status == 200, linked.text()
        farm = linked.json()["farm"]
        assert farm["confirmed_polygon"] is not None
        farm_id = farm["id"]
        receipt("farm", farm)
        record("Reopen confirmed polygon and unified farmer timeline", "SYNTHETIC")

        if args.resume_strategies:
            saved = {
                d["id"]: d["assessment"]
                for d in context.request.get(
                    args.platform_url
                    + "/api/platform/v1/farms/"
                    + farm_id
                    + "/decisions"
                ).json()
            }
            decisions = []
            for index in range(3):
                original = json.loads((out / f"strategy-{index}.json").read_text())
                ident = original.pop("decision_id")
                assert saved[ident] == original
                decisions.append(ident)
            comparison_name = "Software-test exploration " + datetime.now(
                timezone.utc
            ).strftime("%H%M%S")
            record(
                "Reopen three exact persisted native assessments after browser restart",
                "SYNTHETIC",
            )
        else:
            # Retrieve real NASA data through the same existing Flutter/Rust journey.
            go("rotations")
            fill("Water / first crop start (YYYY-MM-DD)", "2024-07-03")
            fill("Water / first crop end (YYYY-MM-DD)", "2024-07-07")
            with page.expect_response(
                lambda r: r.url.endswith("/water/jobs") and r.request.method == "POST"
            ) as sent:
                button("Retrieve NASA inputs & calculate ET0")
            assert sent.value.status == 202
            initial = sent.value.json()
            for _ in range(100):
                job = context.request.get(
                    args.platform_url + "/api/platform/v1/jobs/" + initial["id"]
                ).json()
                if job["status"] in ("failed", "succeeded"):
                    break
                page.wait_for_timeout(1500)
            assert job["status"] == "succeeded" and not job["result"]["gaps"], job
            receipt("nasa-water-job", job)
            source_mode = "CACHED REAL" if job["result"]["cache_hit"] else "REAL"
            derived = next(
                r
                for r in job["result"]["records"]
                if r["source_metadata"]["policy"] == "fao56-daily-pm.v1"
            )
            calculation = derived["source_metadata"]["calculation"]
            assert calculation["et0_total_mm"] is not None
            visible(str(calculation["et0_total_mm"]))
            record(
                "Real NASA inputs → actual Rust FAO-56 ET0 → persisted source values",
                source_mode,
            )
            button("Use this saved calculation and source snapshots")

            # Explicit per-crop source scopes are kept distinct, never inferred as farm regions.
            for crop in ("rice", "mung bean", "sesame", "groundnut"):
                print("LOOKUP", crop, flush=True)
                fill("Exact crop name or identity (7P v2)", crop)
                with page.expect_response(
                    lambda r: "/crop-references?" in r.url
                ) as refs:
                    button("Look up crop references")
                assert refs.value.status == 200
                assert refs.value.json().get("crop"), refs.value.json()
            visible("Choose soil / forecast reference snapshots", role="button").click()
            page.wait_for_timeout(300)
            # The source selections are deliberate; only the displayed snapshots are attached.
            for kind in ("soil_map", "forecast"):
                loc = page.get_by_role("checkbox", name=re.compile("^" + kind))
                if loc.count():
                    loc.first.click()
            record(
                "Select real soil and forecast snapshots as non-executable reference context",
                "CACHED REAL",
            )

            comparison_name = "Software-test exploration " + datetime.now(
                timezone.utc
            ).strftime("%H%M%S")
            decisions = []
            for index, second in enumerate(
                (
                    "mung_bean.mm.rainfed-research@1",
                    "sesame.mm.calendar-75-sessions-0@1",
                    "groundnut.mm.calendar-65-sessions-0@1",
                )
            ):
                choose(
                    "First reference profile (exact scope)",
                    "rice.mm.calendar-5-sessions-0@1",
                )
                choose("Optional second profile for declared sequence", second)
                fill("Water / first crop start (YYYY-MM-DD)", "2024-07-03")
                fill("Water / first crop end (YYYY-MM-DD)", "2024-07-04")
                fill(
                    "Second declared planting (YYYY-MM-DD)",
                    "2024-07-04" if index == 2 else "2024-07-05",
                )
                fill("Second declared harvest (YYYY-MM-DD)", "2024-07-07")
                with page.expect_response(
                    lambda r: r.url.endswith("/assessments")
                    and r.request.method == "POST"
                ) as result:
                    button("Save crop & water evidence assessment")
                assert result.value.status == 200, result.value.text()
                assessment = result.value.json()
                receipt(f"strategy-{index}", assessment)
                assert assessment["recommendation_eligible"] is False
                assert (
                    len(
                        assessment["result"]["data"]["context"]["scenarios"][0]["plans"]
                    )
                    == 2
                )
                assert all(
                    not p["rules"]
                    for p in assessment["result"]["data"]["context"]["catalog"]
                )
                assert assessment["result"]["data"]["context"]["region_id"] is None
                assert assessment["environmental_snapshots"]
                decisions.append(assessment["decision_id"])
            record(
                "Create three actual Rust rotation assessments with unchanged scientific gates",
                "SYNTHETIC",
            )
            assert any(
                f["status"] == "conflicts_with_supplied_evidence"
                for f in json.loads((out / "strategy-2.json").read_text())["result"][
                    "data"
                ]["findings"]
            )
            record("Actual Rust detects declared inclusive date overlap", "SYNTHETIC")

        if args.resume_strategies and (out / "saved-comparison.json").exists():
            group = json.loads((out / "saved-comparison.json").read_text())
            saved_groups = context.request.get(
                args.platform_url + "/api/platform/v1/farms/" + farm_id + "/comparisons"
            ).json()
            assert group in saved_groups
            comparison_name = group["name"]
            record(
                "Reopen exact persisted comparison group after browser restart",
                "SYNTHETIC",
            )
        else:
            go("rotations")
            # Menu labels retain the IDs, source profile sequence and original assessment date.
            for label, ident in zip(
                (
                    "Baseline · farmer-declared existing plan",
                    "Alternative A saved decision",
                    "Alternative B saved decision",
                ),
                decisions,
            ):
                choose(label, re.compile(re.escape(ident)), exact=False)
            check(
                visible(
                    re.compile(
                        "^I declare that the baseline reflects my existing plan"
                    ),
                    exact=False,
                    role="checkbox",
                )
            )
            fill("Name this comparison", comparison_name)
            fill(
                "Why are you exploring these strategies?",
                "Software test: explore water conservation and compare chronology; no real farmer practice or benefit is claimed.",
            )
            fill(
                "Irrigation, budget, labor, equipment & other practical constraints",
                "Software-test farmer declaration: limited labor and irrigation. No market price or profit assumed.",
            )
            for priority in (
                "Water conservation",
                "Nitrogen-fixing potential",
                "Equipment limits",
            ):
                check(visible(priority, exact=True, role="checkbox"))
            with page.expect_response(
                lambda r: r.url.endswith("/comparisons") and r.request.method == "POST"
            ) as grouped:
                button("Confirm & save comparison")
                button("Save comparison")
            assert grouped.value.status == 201, grouped.value.text()
            group = grouped.value.json()
            receipt("saved-comparison", group)
            assert group["baseline_decision_id"] == decisions[0]
            assert group["alternative_decision_ids"] == decisions[1:]
            assert group["baseline_declared_existing_plan"] is True
            assert set(group["priorities"]) == {
                "less_water",
                "nitrogen_potential",
                "equipment",
            }
            assert not group["recommendation_eligible"]
            record(
                "Explicitly declare baseline, priorities and save the three-strategy group",
                "SYNTHETIC",
            )
        go("rotations")
        choose(
            "Reopen saved comparison",
            re.compile(re.escape(comparison_name)),
            exact=False,
        )
        visible("Baseline · existing plan", role=None)
        shot("three-strategies-desktop")
        record(
            "Reopen three saved strategies with evidence, constraints and source explanations",
            "SYNTHETIC",
        )
        page.set_viewport_size({"width": 390, "height": 844})
        visible("Baseline · existing plan")
        shot("three-strategies-phone")
        record("Responsive mobile strategy comparison", "SYNTHETIC")
        page.set_viewport_size({"width": 1440, "height": 1050})

        if args.resume_strategies and (out / "explicit-reassessment.json").exists():
            report = json.loads((out / "observation.json").read_text())
            actual = context.request.get(
                args.platform_url + "/api/platform/v1/farms/" + farm_id + "/journal"
            ).json()
            assert report in actual
            reassessment = json.loads((out / "explicit-reassessment.json").read_text())
            stored = {
                d["id"]: d["assessment"]
                for d in context.request.get(
                    args.platform_url
                    + "/api/platform/v1/farms/"
                    + farm_id
                    + "/decisions"
                ).json()
            }
            ident = reassessment.pop("decision_id")
            assert stored[ident] == reassessment
            record(
                "Reopen exact photo-linked report and explicit reassessment after browser restart",
                "SYNTHETIC",
            )
        else:
            # Explicit software-test planting/harvest history; not field ground truth.
            go("season")
            choose("Record type", "Actual crop season")
            button("Search crops or aliases")
            field = page.get_by_role(
                "textbox", name="Search crops or aliases", exact=True
            )
            field.fill("rice")
            page.get_by_role("button", name="Search", exact=True).click()
            page.get_by_text(re.compile("^rice · paddy")).click()
            pick_date("Date / planting", "07/03/2024")
            pick_date("Actual harvest", "07/04/2024")
            fill(
                "What did you observe?",
                "Synthetic software-test crop period for history plumbing. These short test dates are not a validated growing duration.",
            )
            with page.expect_response(
                lambda r: r.url.endswith("/journal") and r.request.method == "POST"
            ) as season:
                button("Confirm & save report")
                button("Save")
            assert season.value.status == 201, season.value.text()
            receipt("reported-season", season.value.json())
            visible(re.compile("^Actual crop season · 2024"), role="button").click()
            with page.expect_response(
                lambda r: r.url.endswith("/confirm-history")
            ) as history:
                button("Confirm completed period for Rust history")
                button("Confirm history")
            assert history.value.status == 201, history.value.text()
            receipt("history-confirmation", history.value.json())
            record(
                "Confirm a completed farmer-reported crop period for Rust history separately",
                "SYNTHETIC",
            )

            go("farm-photos")
            with page.expect_file_chooser() as chooser:
                button("Choose and confirm photo")
            chooser.value.set_files(
                str(Path("app/test/photo_evidence/fixtures/synthetic.png").resolve())
            )
            with page.expect_response(
                lambda r: r.url.endswith("/photos") and r.request.method == "POST"
            ) as photo:
                button("Save photo")
            assert photo.value.status == 201, photo.value.text()
            receipt(
                "synthetic-photo",
                {
                    **photo.value.json(),
                    "classification": "SYNTHETIC software-test image; no field ground truth",
                },
            )
            record(
                "Sanitize and save a farm-owned photo without GPS or original EXIF",
                "SYNTHETIC",
            )

            go("season")
            fill(
                "What did you observe?",
                "Synthetic software-test photo observation: no observed agricultural fact or diagnosis.",
            )
            pick_date("Date / planting")
            visible("Attach selected photos", role="button").click()
            check(page.get_by_role("checkbox", name=re.compile("^Photo")).first)
            with page.expect_response(
                lambda r: r.url.endswith("/journal") and r.request.method == "POST"
            ) as reported:
                button("Confirm & save report")
                button("Save")
            assert reported.value.status == 201, reported.value.text()
            observation = reported.value.json()
            assert photo.value.json()["id"] in observation["photo_ids"]
            receipt("observation", observation)
            record("Connect a dated farmer observation to the owned photo", "SYNTHETIC")
            visible("Review changed or unselected context")
            record(
                "New saved context offers explicit reassessment without background monitoring",
                "SYNTHETIC",
            )
            go("rotations")
            choose(
                "Reopen an assessment as an editable proposal",
                re.compile(re.escape(decisions[0])),
                exact=False,
            )
            visible("Choose farmer reports for this assessment", role="button").click()
            check(page.get_by_role("checkbox", name=re.compile("^observation")).first)
            with page.expect_response(
                lambda r: r.url.endswith("/assessments") and r.request.method == "POST"
            ) as reassessed:
                button("Save crop & water evidence assessment")
            assert reassessed.value.status == 200, reassessed.value.text()
            assert observation["id"] in [
                r["id"] for r in reassessed.value.json()["farmer_reports"]
            ]
            assert reassessed.value.json()["decision_id"] not in decisions
            receipt("explicit-reassessment", reassessed.value.json())
            record(
                "Reopen and edit a proposal; explicitly selected report reaches a new immutable Rust assessment",
                "SYNTHETIC",
            )
            go("season")
            button("Keep for offline viewing")
            record(
                "Explicitly cache farm history, assessments and original evidence timestamps",
                "SYNTHETIC",
            )

        if args.resume_strategies:
            go("season")
            button("Keep for offline viewing")
            visible("Offline copy saved on this device.")
        assert page.evaluate(
            "localStorage.getItem('flutter.earthsync.home.v1') !== null"
        )
        go("assistant")
        fill("Ask a question", "Explain my crop rotation and saved comparison")
        with page.expect_response(
            lambda r: r.url.endswith("/api/assistant/v1/chat")
        ) as reply:
            button("Send")
        assert reply.value.status == 200, reply.value.text()
        answer = reply.value.json()
        receipt("assistant-comparison", answer)
        assert any("baseline" in c["text"] for c in answer["claims"])
        assert answer["decisions"] and answer["citations"]
        shot("assistant-saved-comparison")
        record(
            "Deterministic assistant explains the saved comparison and original citations",
            "SYNTHETIC",
        )

        go("settings")
        button("English")
        page.get_by_role("menuitem", name="မြန်မာ", exact=True).click()
        page.wait_for_timeout(500)
        visible("ဘာသာစကား")
        shot("burmese-settings")
        go("season")
        visible("စိုက်ပျိုးရာသီနှင့် မှတ်တမ်းများ")
        shot("burmese-season")
        record(
            "Burmese core interface and saved English scientific source text",
            "SYNTHETIC",
        )
        go("settings")
        button("မြန်မာ")
        page.get_by_role("menuitem", name="English", exact=True).click()
        page.wait_for_timeout(500)

        go("season")
        # Only the explicit read-only offline cache is used after injected API failure.
        page.route(
            "**/api/platform/v1/**", lambda route: route.abort("internetdisconnected")
        )
        button("Refresh")
        visible("Cached copy · may be stale")
        assert page.get_by_role(
            "button", name="Confirm & save report", exact=True
        ).is_disabled()
        shot("cached-offline-records")
        page.unroute("**/api/platform/v1/**")
        record(
            "Injected provider/backend outage uses timestamped cache and disables writes",
            "MOCKED",
        )

        # Close the online tab so the fully cached, versioned shell can activate.
        page.evaluate("navigator.serviceWorker.ready")
        page.close()
        context.set_offline(True)
        page = context.new_page()
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.goto(args.base_url + "/#/season")
        enable()
        visible("Cached copy · may be stale")
        shot("offline-cold-reopen")
        cache_keys = page.evaluate(
            "async()=>{const names=await caches.keys();return (await Promise.all(names.map(async n=>(await (await caches.open(n)).keys()).map(r=>r.url)))).flat()}"
        )
        assert not any("/api/" in key for key in cache_keys)
        assert not any(":8021" in key for key in cache_keys)
        receipt(
            "offline-public-cache", {"keys": cache_keys, "private_api_cached": False}
        )
        record(
            "Reopen static app offline with cached read-only farm data; private API excluded from service worker",
            "MOCKED",
        )
        context.set_offline(False)
        assert not errors, errors
        record("Zero unhandled page errors in final farmer journey", "REAL")
        complete = json.loads((out / "results.json").read_text())
        complete["status"] = "PASS"
        receipt("results", complete)
    except Exception:
        if not page.is_closed():
            shot("failure")
            (out / "failure-aria.txt").write_text(
                page.locator("body").aria_snapshot(), encoding="utf-8"
            )
        receipt(
            "results", {"steps": steps, "browser_errors": errors, "status": "FAILED"}
        )
        raise
    finally:
        context.storage_state(
            path=str(Path(args.state).with_name("browser-final-state.json"))
        )
        browser.close()
