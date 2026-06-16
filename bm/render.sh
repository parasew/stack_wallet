#!/usr/bin/env bash
# ==============================================================================
# render.sh — Generate report and convert to PDF
# Usage: ./bm/render.sh [results_dir] [--pdf] [--html] [--open]
#
# Tries multiple PDF engines, falling back gracefully.
#   pandoc + weasyprint  >  pandoc + wkhtmltopdf  >  pandoc + basictex  >  HTML only
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_DIR="${1:-$REPO_ROOT/bm/results}"
OUTPUT_NAME="benchmark_report"
OUT_HTML=0
OUT_PDF=1
OPEN=0

# ---- parse flags ----
shift 2>/dev/null || true
while [ $# -gt 0 ]; do
  case "$1" in
    --html) OUT_PDF=0; OUT_HTML=1 ;;
    --pdf)  OUT_PDF=1 ;;
    --open) OPEN=1 ;;
    *)      RESULTS_DIR="$1" ;;
  esac
  shift
done

if [ ! -d "$RESULTS_DIR" ]; then
  echo "ERROR: '$RESULTS_DIR' is not a directory"
  exit 1
fi

# ---- generate charts ----
echo "=== Generating charts ==="
python3 "$SCRIPT_DIR/charts.py" "$RESULTS_DIR" "$RESULTS_DIR" 2>&1 || \
  echo "  (charts skipped — run: pip3 install --break-system-packages matplotlib)"
echo ""

# ---- generate markdown ----
echo "=== Generating markdown report ==="
MD_FILE="$RESULTS_DIR/${OUTPUT_NAME}.md"
python3 "$SCRIPT_DIR/analyze.py" "$RESULTS_DIR" > "$MD_FILE"
echo "  → $MD_FILE"

# ---- HTML ----
HTML_FILE="$RESULTS_DIR/${OUTPUT_NAME}.html"
PDF_FILE="$RESULTS_DIR/${OUTPUT_NAME}.pdf"
CSS_FILE="$SCRIPT_DIR/report.css"

if [ ! -f "$CSS_FILE" ]; then
  # Minimal inline CSS if the file doesn't exist
  cat > "$CSS_FILE" << 'EOF'
body { font-family: -apple-system, Helvetica, Arial, sans-serif; max-width: 900px; margin: 40px auto; padding: 0 20px; color: #222; line-height: 1.6; }
h1 { border-bottom: 2px solid #333; padding-bottom: 8px; }
h2 { border-bottom: 1px solid #ddd; padding-bottom: 4px; margin-top: 32px; }
table { border-collapse: collapse; width: 100%; margin: 12px 0; font-size: 0.9em; }
th, td { border: 1px solid #ddd; padding: 6px 10px; text-align: left; }
th { background: #f5f5f5; font-weight: 600; }
tr:nth-child(even) { background: #fafafa; }
code { background: #f0f0f0; padding: 1px 4px; border-radius: 3px; font-size: 0.95em; }
strong { color: #111; }
EOF
fi

echo "=== Converting to HTML ==="

# Use a temp CSS path — pandoc/weasyprint resolves relative CSS paths
# relative to the HTML file's directory, not the script dir.
# We embed CSS inline via --include-in-header for portability.
{
  echo '<style>'
  cat "$CSS_FILE"
  echo '</style>'
} > /tmp/_bm_report_css.html

pandoc "$MD_FILE" \
  --standalone \
  --metadata title="Stack Wallet — Build Benchmark Report" \
  --include-in-header /tmp/_bm_report_css.html \
  -o "$HTML_FILE"

rm -f /tmp/_bm_report_css.html
echo "  → $HTML_FILE"

# ---- PDF ----
if [ "$OUT_PDF" -eq 1 ]; then
  echo "=== Converting to PDF ==="

  pdf_ok=0

  # Engine 1: weasyprint (pure Python, no LaTeX)
  if command -v weasyprint >/dev/null 2>&1; then
    echo "  Trying weasyprint..."
    weasyprint "$HTML_FILE" "$PDF_FILE" 2>/dev/null && pdf_ok=1
  elif nix eval nixpkgs#weasyprint --raw 2>/dev/null; then
    echo "  Trying weasyprint (via nix)..."
    nix shell nixpkgs#weasyprint -c weasyprint "$HTML_FILE" "$PDF_FILE" 2>/dev/null && pdf_ok=1
  elif pip3 install weasyprint 2>/dev/null; then
    weasyprint "$HTML_FILE" "$PDF_FILE" 2>/dev/null && pdf_ok=1
  fi

  # Engine 2: wkhtmltopdf
  if [ "$pdf_ok" -eq 0 ] && command -v wkhtmltopdf >/dev/null 2>&1; then
    echo "  Trying wkhtmltopdf..."
    wkhtmltopdf --enable-local-file-access "$HTML_FILE" "$PDF_FILE" 2>/dev/null && pdf_ok=1
  fi

  # Engine 3: pandoc with basictex/xelatex
  if [ "$pdf_ok" -eq 0 ]; then
    if command -v xelatex >/dev/null 2>&1 || command -v pdflatex >/dev/null 2>&1; then
      echo "  Trying pandoc + LaTeX..."
      pandoc "$MD_FILE" -o "$PDF_FILE" --pdf-engine=xelatex 2>/dev/null && pdf_ok=1 || \
      pandoc "$MD_FILE" -o "$PDF_FILE" --pdf-engine=pdflatex 2>/dev/null && pdf_ok=1
    fi
  fi

  # Engine 4: macOS built-in (cupsfilter / textutil)
  if [ "$pdf_ok" -eq 0 ] && [ "$(uname -s)" = "Darwin" ]; then
    echo "  Trying macOS cupsfilter..."
    cupsfilter "$HTML_FILE" > "$PDF_FILE" 2>/dev/null && pdf_ok=1 || true
  fi

  if [ "$pdf_ok" -eq 1 ] && [ -f "$PDF_FILE" ]; then
    echo "  → $PDF_FILE ($(du -h "$PDF_FILE" | cut -f1))"
  else
    echo ""
    echo "  ⚠ No PDF engine available. Install one of:"
    echo "    nix profile install nixpkgs#weasyprint     (recommended, light)"
    echo "    brew install --cask wkhtmltopdf            (macOS)"
    echo "    nix profile install nixpkgs#texliveBasic   (full LaTeX)"
    echo ""
    echo "  HTML report ready: $HTML_FILE"
  fi
fi

# ---- open ----
if [ "$OPEN" -eq 1 ] && [ -f "$PDF_FILE" ]; then
  open "$PDF_FILE" 2>/dev/null || xdg-open "$PDF_FILE" 2>/dev/null || true
elif [ "$OPEN" -eq 1 ] && [ -f "$HTML_FILE" ]; then
  open "$HTML_FILE" 2>/dev/null || xdg-open "$HTML_FILE" 2>/dev/null || true
fi

echo "=== Done ==="
