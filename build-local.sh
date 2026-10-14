#!/usr/bin/env bash
# build-local.sh -- the whole site build. Used locally AND by .github/workflows/pages.yml,
# so what you test here is what gets deployed.
#
# Run from the repo root (next to ecl/ and resolutions/):
#   ./build-local.sh                  # generate + render both books, build Jekyll (if present), mount, check links
#   ./build-local.sh --serve          # ...then serve _site at http://localhost:4000
#   ./build-local.sh --no-jekyll      # books only: skip the Jekyll build
#   ./build-local.sh --port=8080
#
# Preview a future date (e.g. to test effective dates):
#   COMPILE_AS_OF=2026-12-31 ./build-local.sh --serve

set -euo pipefail
cd "$(dirname "$0")"

# "Today" for effective dates is decided in this time zone (an IANA name, so it handles
# EST/EDT automatically). CI runs this same script, so local and deployed builds agree.
# For a fixed UTC-5 all year (no daylight saving) use "Etc/GMT+5" instead.
SITE_TZ="America/New_York"
export TZ="$SITE_TZ"

JEKYLL=auto; SERVE=0; PORT=4000
for arg in "$@"; do
  case "$arg" in
    --no-jekyll) JEKYLL=0 ;;
    --serve)     SERVE=1 ;;
    --port=*)    PORT="${arg#--port=}" ;;
    -h|--help)   sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required tool: $1" >&2; exit 1; }; }
need Rscript; need quarto; need python3

if [ "$JEKYLL" = auto ]; then
  if [ -f Gemfile ] && command -v bundle >/dev/null 2>&1; then JEKYLL=1; else JEKYLL=0; fi
fi

echo "== 1/4  generate + render ecl (compiled law)"
( cd ecl && Rscript generate.R && quarto render )

echo "== 2/4  render resolutions"
( cd resolutions && quarto render )

echo "== 3/4  assemble _site"
rm -rf _site
if [ "$JEKYLL" = 1 ]; then
  bundle exec jekyll build --destination _site --baseurl ""
else
  echo "(skipping Jekyll)"; mkdir -p _site
fi
if [ -d landing ]; then cp -R landing/. _site/; fi     # root landing page, 404 page, etc.
mkdir -p _site/ecl _site/resolutions
cp -R ecl/_book/.    _site/ecl/
cp -R resolutions/_book/. _site/resolutions/

echo "== 4/4  check internal links and images in the books"
python3 - <<'PY' || echo "!! link check found problems (see above); the site was still assembled"
import glob, os, re, sys
bad, checked = [], 0
for page in glob.glob("_site/ecl/**/*.html", recursive=True) + glob.glob("_site/resolutions/**/*.html", recursive=True):
    html = open(page, encoding="utf-8").read()
    for url in re.findall(r'(?:href|src)="([^"]+)"', html):
        if re.match(r'(?i)(https?:|mailto:|tel:|data:|javascript:|//|#)', url):
            continue
        path = url.split("#")[0].split("?")[0]
        if not path or path.endswith("/"):
            continue
        checked += 1
        if not os.path.exists(os.path.normpath(os.path.join(os.path.dirname(page), path))):
            bad.append((page.replace("_site/", ""), url))
# The coat of arms is inserted by a script on Act pages, so the scan above can't see it.
try:
    m = re.search(r'COAT_OF_ARMS\s*=\s*"([^"]*)"', open("ecl/act-breadcrumb.html", encoding="utf-8").read())
    if m and m.group(1) and not os.path.exists(os.path.join("_site/ecl", m.group(1))):
        bad.append(("ecl/act-breadcrumb.html", "coat of arms file not found: ecl/" + m.group(1)))
except FileNotFoundError:
    pass
print(f"checked {checked} internal links/images; {len(bad)} missing")
for page, url in sorted(set(bad))[:40]:
    print(f"  MISSING  {page}  ->  {url}")
if len(set(bad)) > 40:
    print(f"  ... and {len(set(bad)) - 40} more")
sys.exit(1 if bad else 0)
PY

echo
echo "Done: _site/ is ready (ecl at _site/ecl/, resolutions at _site/resolutions/)."
if [ "$SERVE" = 1 ]; then
  echo "Serving at http://localhost:$PORT  (Ctrl-C to stop)"
  exec python3 -m http.server "$PORT" --directory _site
fi
