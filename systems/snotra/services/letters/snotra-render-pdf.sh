#!/usr/bin/env bash
# snotra-render-pdf.sh — one printable PDF from a meeting record.
#
#   snotra-render-pdf.sh <meeting-dir> [out.pdf]
#
# Renders the Meeting Record, decisions, actions, a dependency table and the
# per-person briefs, then prints the HTML to PDF with Chromium. The Markdown
# files stay the source; the PDF is a rendering, never an edit target.
set -euo pipefail
DIR="${1-}"; [ -n "$DIR" ] && [ -d "$DIR" ] || { echo "usage: snotra-render-pdf.sh <meeting-dir> [out.pdf]" >&2; exit 2; }
OUT="${2:-$DIR/record.pdf}"
command -v chromium >/dev/null || { echo "error: chromium missing" >&2; exit 1; }
python3 -c "import markdown" 2>/dev/null || { echo "error: python markdown missing" >&2; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
python3 - "$DIR" "$TMP/record.html" <<'PY'
import sys, os, json, html
import markdown
d, out = sys.argv[1], sys.argv[2]
def read(name):
    p=os.path.join(d,name)
    return open(p, encoding='utf-8').read() if os.path.isfile(p) else ''
def md(name):
    return markdown.markdown(read(name), extensions=['tables','fenced_code','sane_lists'])
rec={}
for n in ('record.json','meeting.json'):
    p=os.path.join(d,n)
    if os.path.isfile(p): rec=json.load(open(p)); break
m=rec.get('meeting',rec)
rows=[]
for a in rec.get('actions',[]):
    dep=', '.join(a.get('depends_on') or []) or '—'
    rows.append(f"<tr><td>{html.escape(str(a.get('owner') or 'unresolved'))}</td><td>{html.escape(a.get('description',''))}</td><td>{html.escape(str(a.get('due') or 'unresolved'))}</td><td>{html.escape(dep)}</td></tr>")
dep_table = ("<h2>Dependency table</h2><table><thead><tr><th>Owner</th><th>Action</th><th>Due</th><th>Waits on</th></tr></thead><tbody>"
             + ''.join(rows) + "</tbody></table>") if rows else ""
briefs=''
bd=os.path.join(d,'briefs')
if os.path.isdir(bd):
    for f in sorted(os.listdir(bd)):
        if f.endswith('.md'):
            briefs += f'<section class="brief">{markdown.markdown(open(os.path.join(bd,f),encoding="utf-8").read(), extensions=["tables","sane_lists"])}</section>'
doc=f"""<!doctype html><html><head><meta charset="utf-8"><title>{html.escape(m.get('title','Meeting Record'))}</title>
<style>
@page {{ size: A4; margin: 18mm 16mm; }}
body {{ font-family: "Source Sans 3", "DejaVu Sans", sans-serif; font-size: 10.5pt; color:#1b1b1b; line-height:1.45; }}
h1 {{ font-size: 22pt; margin:0 0 2mm; color:#12263f; }}
h2 {{ font-size: 14pt; margin:8mm 0 2mm; color:#12263f; border-bottom:1px solid #d8dee6; padding-bottom:1mm; page-break-after:avoid; }}
h3 {{ font-size: 11.5pt; margin:5mm 0 1mm; page-break-after:avoid; }}
table {{ width:100%; border-collapse:collapse; margin:2mm 0 4mm; font-size:9.2pt; }}
th,td {{ border:1px solid #d8dee6; padding:1.6mm 2mm; vertical-align:top; text-align:left; }}
th {{ background:#f2f5f8; }}
blockquote {{ margin:2mm 0; padding:1mm 0 1mm 4mm; border-left:3px solid #b9c4d0; color:#444; }}
code, pre {{ font-family:"DejaVu Sans Mono", monospace; font-size:8.6pt; background:#f6f7f9; }}
pre {{ padding:2mm; overflow-wrap:anywhere; white-space:pre-wrap; }}
.cover {{ border-bottom:2px solid #12263f; padding-bottom:4mm; margin-bottom:6mm; }}
.meta {{ color:#5b6b7c; font-size:9.5pt; }}
section.brief {{ page-break-before: always; }}
footer {{ margin-top:8mm; border-top:1px solid #d8dee6; padding-top:2mm; color:#5b6b7c; font-size:8.5pt; }}
.sig {{ margin-top:6mm; font-size:9.5pt; color:#333; }}
</style></head><body>
<div class="cover"><h1>{html.escape(m.get('title','Meeting Record'))}</h1>
<div class="meta">{html.escape(str(m.get('started_at',''))[:10])} · {m.get('duration_minutes','')} minutes · {html.escape(m.get('classification',''))}</div>
<div class="meta">Present: {html.escape(', '.join(p.get('name','') for p in rec.get('participants',[])))}</div></div>
{md('minutes.md')}
{md('decisions.md')}
{md('actions.md')}
{dep_table}
{md('questions.md')}
{md('signoff.md')}
{briefs}
<footer>Prepared with Snotra, Ymir's meeting assistant. Reviewed by Lars-<the operator> <the operator>.</footer>
</body></html>"""
open(out,'w',encoding='utf-8').write(doc)
PY
chromium --headless=new --no-sandbox --disable-gpu --user-data-dir="$TMP/chrome" \
  --no-pdf-header-footer --print-to-pdf="$OUT" "file://$TMP/record.html" >/dev/null 2>&1 \
  || chromium --headless --no-sandbox --disable-gpu --user-data-dir="$TMP/chrome" --print-to-pdf="$OUT" "file://$TMP/record.html" >/dev/null 2>&1
[ -s "$OUT" ] && printf 'pdf\t%s\t%s\n' "$OUT" "$(du -h "$OUT" | cut -f1)" || { echo "error: pdf not written" >&2; exit 1; }

**2026-11-03 (correction, appended):** the operator's name was redacted — it is personal data and belongs in the home, not in a public repository (RULES/04, RULES/06).
