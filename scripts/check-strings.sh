#!/bin/zsh
# Vérifie que chaque texte d'interface a sa traduction anglaise. Sort avec 1 s'il en manque.
cd "$(dirname "$0")/.."
missing=0
while IFS= read -r key; do
  k=$(printf "%s" "$key" | sed -E "s/\\\\\\([a-zA-Z]+\\)/%@/g")   # interpolation \(x) → %@
  if ! grep -qF "\"$k\" = " Resources/en.lproj/Localizable.strings; then echo "❌ manque en anglais : $k"; missing=1; fi
done < <(scripts/ui-strings.sh | grep -vx "AirPodsMouse")
plutil -lint Resources/en.lproj/Localizable.strings Resources/en.lproj/InfoPlist.strings Resources/fr.lproj/Localizable.strings >/dev/null || { echo "❌ fichier .strings invalide"; missing=1; }
[[ $missing == 0 ]] && echo "✅ toutes les traductions sont présentes"
exit $missing
