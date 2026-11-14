#!/bin/zsh
# Liste les textes d'interface (à traduire) trouvés dans les sources Swift de l'appli.
cd "$(dirname "$0")/.."
grep -hoE '(Text|Button|Toggle|Label|LabeledContent|Picker|Section|String\(localized:|LocalizedStringKey\(|title:|text:|detail:|low:|high:|DoneBadge\(text:|case \.[a-zA-Z]+:)[ (]*"[^"]+"' Sources/AirPodsMouse/**/*.swift \
  | grep -v 'verbatim' \
  | sed -E 's/^[^"]*"//; s/"$//' \
  | grep -vE '^(gearshape|cursorarrow|hand\.|target|info\.|airpods|timer|gyroscope|accessibility|arrow\.|contextualmenu|checkmark|exclamationmark|pause|antenna|party|circle)' \
  | sort -u
