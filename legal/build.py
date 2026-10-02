#!/usr/bin/env python3
"""Builds the legal pages from legal/*.md into web/legal/<doc>.html, styled like the rest of Ataste (cream page,
caramel logo pill, white cards, Roundo headings, Manrope text). The VPS serves them at
https://ataste.51-79-240-114.sslip.io/legal/<doc>; the app opens them in-app, and the Supabase `legal` function
(the URL App Store Connect has) redirects there. Deploy: rsync -a --delete web/ vps:/srv/ataste-web/

The Markdown is a small subset: '# ' the title, the line after it the date, '## ' headings, '- ' bullets, '|' table
rows (the first row is the header; '|---' rows are skipped), any other line a paragraph. Email addresses become
mailto links.

Usage: python3 legal/build.py"""
import html
import pathlib
import re

root = pathlib.Path(__file__).resolve().parent
out = root.parent / "web" / "legal"
DOCS = {"privacy-policy.md": "privacy", "terms-of-use.md": "terms", "support.md": "support"}

PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="light">
<meta name="theme-color" content="#FBF3EA">
<title>{title}</title>
<link rel="stylesheet" href="https://api.fontshare.com/v2/css?f[]=roundo@1&display=swap">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Manrope:wght@500;600;700&display=swap">
<style>
  /* Ataste design system: cream #FBF3EA, cocoa #2B1A12, caramel #9D5C1D, ink2 #5A4237, ink3 #7A6257,
     liquorice-100 #EDE2E4, choc-100 #F9CFAF; cards radius 24, hero radius 32. */
  * {{ box-sizing: border-box; }}
  body {{ margin: 0; background: #FBF3EA; color: #2B1A12; font: 500 15px/1.55 Manrope, sans-serif; -webkit-font-smoothing: antialiased; }}
  main {{ max-width: 640px; margin: 0 auto; padding: 24px 16px 48px; display: flex; flex-direction: column; gap: 14px; }}
  .logo {{ align-self: center; background: #9D5C1D; border: 3px solid #9D5C1D; border-radius: 999px; padding: 3px 14px 6px;
          box-shadow: 0 3px 0 #2B1A12; font: 700 24px/1 Roundo, sans-serif; color: #FBF3EA; text-decoration: none; }}
  header {{ padding: 18px 6px 4px; }}
  .eyebrow {{ font: 600 12px/1 Manrope; letter-spacing: .03em; text-transform: uppercase; color: #9D5C1D; }}
  h1 {{ margin: 10px 0 0; font: 700 34px/1.1 Roundo, sans-serif; letter-spacing: -.01em; }}
  .lead {{ margin: 12px 0 0; color: #5A4237; }}
  section {{ background: #fff; border-radius: 24px; padding: 20px 20px 18px; }}
  h2 {{ margin: 0 0 10px; font: 700 20px/1.2 Roundo, sans-serif; }}
  p {{ margin: 0 0 10px; color: #5A4237; }}
  p:last-child, ul:last-child {{ margin-bottom: 0; }}
  ul {{ margin: 0 0 10px; padding: 0; list-style: none; display: flex; flex-direction: column; gap: 8px; }}
  li {{ position: relative; padding-left: 18px; color: #5A4237; }}
  li::before {{ content: ""; position: absolute; left: 2px; top: .62em; width: 7px; height: 7px; border-radius: 50%; background: #F39E60; }}
  table {{ width: 100%; border-collapse: collapse; font-size: 13px; line-height: 1.45; }}
  th {{ text-align: left; font: 600 11px/1.3 Manrope; letter-spacing: .03em; text-transform: uppercase; color: #7A6257; padding: 0 8px 8px 0; }}
  td {{ vertical-align: top; padding: 10px 8px 10px 0; border-top: 1px solid #EDE2E4; color: #5A4237; }}
  td:first-child {{ color: #2B1A12; font-weight: 700; width: 34%; }}
  /* Phones: each table row becomes a small block (the column name above each value). */
  @media (max-width: 520px) {{
    thead {{ display: none; }}
    tr {{ display: block; border-top: 1px solid #EDE2E4; padding: 10px 0; }}
    tr:first-child {{ border-top: 0; padding-top: 0; }}
    td {{ display: block; border: 0; padding: 2px 0; width: auto !important; }}
    td[data-l]::before {{ content: attr(data-l); display: block; font: 600 10px/1.6 Manrope; letter-spacing: .03em; text-transform: uppercase; color: #7A6257; }}
  }}
  a {{ color: #9D5C1D; font-weight: 600; text-decoration: none; }}
  footer {{ text-align: center; font: 500 12px/1.45 Manrope; color: #7A6257; padding: 8px 20px 0; }}
</style>
</head>
<body>
<main>
  <span class="logo">ataste</span>
  <header>
    <span class="eyebrow">{date}</span>
    <h1>{title}</h1>
    {lead}
  </header>
{body}
  <footer>Ataste is an independent app and is not affiliated with Atas Artisan.</footer>
</main>
</body>
</html>
"""


def inline(text: str) -> str:
    t = html.escape(text)
    return re.sub(r"[\w.+-]+@[\w-]+\.[\w.]+", lambda m: f'<a href="mailto:{m[0]}">{m[0]}</a>', t)


def render(md: str) -> str:
    lines = [l.rstrip() for l in md.splitlines() if l.strip()]
    title = lines[0].removeprefix("# ").strip()
    date, rest = lines[1], lines[2:]
    lead = []
    while rest and not rest[0].startswith("## "):
        lead.append(f'<p class="lead">{inline(rest.pop(0))}</p>')
    sections, cur, mode, heads = [], [], None, []

    def close_block():
        nonlocal mode
        if mode == "ul":
            cur.append("</ul>")
        elif mode == "table":
            cur.append("</tbody></table>")
        mode = None

    def close_section():
        if cur:
            close_block()
            sections.append("  <section>\n    " + "\n    ".join(cur) + "\n  </section>")
            cur.clear()

    for line in rest:
        if line.startswith("## "):
            close_section()
            cur.append(f"<h2>{inline(line[3:])}</h2>")
        elif line.startswith("- "):
            if mode != "ul":
                close_block(); cur.append("<ul>"); mode = "ul"
            cur.append(f"<li>{inline(line[2:])}</li>")
        elif line.startswith("|"):
            if line.startswith("|---"):
                continue
            cells = [c.strip() for c in line.strip("|").split("|")]
            if mode != "table":
                close_block()
                heads = cells
                cur.append("<table><thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in cells) + "</tr></thead><tbody>")
                mode = "table"
            else:
                cur.append("<tr>" + "".join(f'<td{"" if i == 0 else f" data-l={chr(34)}{html.escape(heads[i])}{chr(34)}"}>{inline(c)}</td>'
                                            for i, c in enumerate(cells)) + "</tr>")
        else:
            close_block()
            cur.append(f"<p>{inline(line)}</p>")
    close_section()
    return PAGE.format(title=html.escape(title), date=html.escape(date), lead="\n    ".join(lead), body="\n".join(sections))


out.mkdir(parents=True, exist_ok=True)
for src, name in DOCS.items():
    (out / f"{name}.html").write_text(render((root / src).read_text()))
    print("web/legal/" + name + ".html")
