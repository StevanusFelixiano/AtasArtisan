#!/usr/bin/env python3
"""Builds the legal PDFs from legal/*.md into legal/build/: officecli writes each .docx, officecli renders it to HTML,
and headless Chrome prints that to PDF (officecli has no PDF exporter installed). Then upload the PDFs to Supabase
Storage, bucket `legal` (public), where the app (iOS/Screens/Legal.swift) and App Store Connect link them.

The Markdown is a small subset: '# ' the title, the line after it the date, '## ' headings, '- ' bullets, '|' table
rows (the first row is the header; '|---' rows are skipped), any other line a paragraph.

Usage: python3 legal/build.py"""
import json
import pathlib
import re
import subprocess
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "build"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
DOCS = ["privacy-policy", "terms-of-use", "support"]


def sh(*args: str) -> str:
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=120).stdout


def batch(md: str) -> list[dict]:
    """The officecli batch that writes one document."""
    lines = md.splitlines()
    title = lines[0].removeprefix("# ").strip()
    items = [
        {"command": "set", "path": "/", "props": {"docDefaults.font": "Arial", "docDefaults.fontSize": "11pt"}},
        {"command": "add", "parent": "/body", "type": "paragraph",
         "props": {"text": title, "style": "Title", "size": "24pt", "bold": "true", "spaceAfter": "4pt"}},
        {"command": "add", "parent": "/body", "type": "paragraph",
         "props": {"text": lines[1].strip(), "color": "666666", "spaceAfter": "18pt"}},
    ]
    tables, rows = 0, []

    def table():
        nonlocal tables, rows
        if not rows:
            return
        tables += 1
        items.append({"command": "add", "parent": "/body", "type": "table",
                      "props": {"rows": str(len(rows)), "cols": str(len(rows[0])), "width": "100%"}})
        for i, row in enumerate(rows, 1):
            props = {f"c{j}": cell for j, cell in enumerate(row, 1)}
            if i == 1:
                props["header"] = "true"
            items.append({"command": "set", "path": f"/body/tbl[{tables}]/tr[{i}]", "props": props})
        for j in range(1, len(rows[0]) + 1):
            items.append({"command": "set", "path": f"/body/tbl[{tables}]/tr[1]/tc[{j}]/p[1]/r[1]",
                          "props": {"bold": "true"}})
        rows = []

    for line in lines[2:]:
        line = line.strip()
        if line.startswith("|"):
            if not re.fullmatch(r"\|[-| ]+\|", line):
                rows.append([c.strip() for c in line.strip("|").split("|")])
            continue
        table()
        if not line:
            continue
        if line.startswith("## "):
            props = {"text": line[3:], "style": "Heading1", "size": "16pt", "bold": "true", "color": "111111",
                     "spaceBefore": "18pt", "spaceAfter": "6pt"}
        elif line.startswith("- "):
            props = {"text": line[2:], "listStyle": "bullet", "spaceAfter": "4pt"}
        else:
            props = {"text": line, "spaceAfter": "8pt"}
        items.append({"command": "add", "parent": "/body", "type": "paragraph", "props": props})
    table()
    items.append({"command": "add", "parent": "/", "type": "footer",
                  "props": {"type": "default", "text": f"{title} · Page ", "field": "page", "size": "9pt",
                            "align": "center"}})
    return items


# officecli's HTML lays each page out as a fixed A4 box (595.3 × 841.9 pt, padding 72/90 pt) with the footer after the
# body, made for the screen. Printed as it is, Chrome split that box again: a heading was left alone at the foot of page
# 1 and the footer printed over the text. So the print takes its size, margins and page number from @page, and the box
# and its footer step aside.
PRINT_CSS = """<style>
@page { size: A4; margin: 72pt 90pt;
  @bottom-center { content: "TITLE · Page " counter(page); font: 9pt Arial, sans-serif; color: #666; } }
@media print {
  .page { width: auto !important; min-height: 0 !important; padding: 0 !important; }
  .doc-footer { display: none !important; }
  tr { break-inside: avoid; }
  h1, h2, h3 { break-after: avoid; }
}
</style>"""

OUT.mkdir(exist_ok=True)
for name in DOCS:
    docx, html, pdf = OUT / f"{name}.docx", OUT / f"{name}.html", OUT / f"{name}.pdf"
    md = (HERE / f"{name}.md").read_text()
    docx.unlink(missing_ok=True)
    sh("officecli", "create", str(docx))
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(batch(md), f, ensure_ascii=False)
    sh("officecli", "batch", str(docx), "--input", f.name)
    sh("officecli", "close", str(docx))
    print(name, sh("officecli", "validate", str(docx)).strip())
    sh("officecli", "view", str(docx), "html", "-o", str(html))
    title = md.splitlines()[0].removeprefix("# ").strip()
    page = html.read_text().replace("</head>", PRINT_CSS.replace("TITLE", title) + "</head>", 1)
    # Without officecli's scripts: in print they moved every ’ “ ” onto the next letter ("dont", “Masterplan”calendar;
    # 2026-09-15, found by printing the page without them). The print needs none: @page numbers the pages.
    html.write_text(re.sub(r"<script\b.*?</script>", "", page, flags=re.S))
    # Headless Chrome's own default profile. With an explicit --user-data-dir it wrote the PDF and then never exited
    # (2026-09-15), keychain and first-run flags or not.
    sh(CHROME, "--headless=new", "--disable-gpu", "--no-pdf-header-footer", f"--print-to-pdf={pdf}", html.as_uri())
    print(name, "→", pdf)
