#!/bin/sh
# This code was generated with AI (Claude by Anthropic). MIT License, see LICENSE and README.
# check.sh: syntax checks before installing. Shell scripts with "sh -n", the web page's JavaScript with
# "node --check" (if Node.js is installed), the lights controller with Python. Run: tools/check.sh
cd "$(dirname "$0")/.." || exit 1
fail=0
T=$(mktemp -d)
for f in *.sh tools/*.sh scripts/*.sh; do
  [ -f "$f" ] || continue
  sh -n "$f" || { echo "shell syntax: $f"; fail=1; }
done
sed -n "/<<'EOF_OCHE'/,/^EOF_OCHE/p" scripts/scoreboard-install.sh | sed '1d;$d' > "$T/page.html"
awk '/<script>/{f=1;next}/<\/script>/{f=0}f' "$T/page.html" > "$T/page.js"
if command -v node >/dev/null 2>&1; then node --check "$T/page.js" || { echo "page JavaScript"; fail=1; }; fi
sed -n "/<<'EOF_PY'/,/^EOF_PY/p" scripts/lights-install.sh | sed '1d;$d' > "$T/lights.py"
python3 -m py_compile "$T/lights.py" || { echo "lights controller"; fail=1; }
rm -r "$T"
[ "$fail" = 0 ] && echo "All checks passed." || exit 1
