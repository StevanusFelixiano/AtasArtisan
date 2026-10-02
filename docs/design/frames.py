# /// script
# dependencies = ["playwright"]
# ///
"""Render every phone frame (elements with data-screen-label) of the boards to frames/<label>.png at 2x.

Uses the installed Google Chrome (channel="chrome"); no browser download. Run through update.sh.
"""
import re, sys, pathlib
from playwright.sync_api import sync_playwright

here = pathlib.Path(__file__).resolve().parent
boards, out = here / "boards", here / "frames"
out.mkdir(exist_ok=True)
with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome")
    page = b.new_page(viewport={"width": 2400, "height": 1600}, device_scale_factor=2)
    for f in sorted(boards.glob("Ataste Screens*.dc.html")) + sorted(boards.glob("Ataste Notifications.dc.html")):
        page.goto(f.as_uri(), wait_until="networkidle")
        page.wait_for_timeout(1500)
        for el in page.query_selector_all("[data-screen-label]"):
            label = el.get_attribute("data-screen-label")
            if "{{" in label:
                continue
            el.scroll_into_view_if_needed()
            page.wait_for_timeout(100)
            el.screenshot(path=str(out / (re.sub(r"[^\w.-]+", "-", label).strip("-") + ".png")))
    b.close()
print(len(list(out.glob("*.png"))), "frames in", out)
