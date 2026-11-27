#!/bin/zsh
# Vérifie, compile et installe AirPodsMouse, puis l'ouvre. Double-clic depuis le Finder.
# Le détail est dans build.log (même dossier).
cd "$(dirname "$0")" || exit 1
{
  echo "== Build $(date '+%Y-%m-%d %H:%M:%S') =="
  swift run AirPodsMouseChecks && ./scripts/build-app.sh
  code=$?
  [[ $code == 0 ]] && echo "BUILD OK" || echo "BUILD FAILED ($code)"
} > build.log 2>&1
tail -n 25 build.log
grep -q "BUILD OK" build.log && open /Applications/AirPodsMouse.app
