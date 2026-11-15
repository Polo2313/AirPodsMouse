# Défilement par glissement sur la tige des AirPods

*Design court · 14 novembre 2026 · approche validée (« moyen »)*

## Pourquoi
Défiler sans souris : l'utilisateur veut utiliser la tige tactile des AirPods Pro.

## Ce que le Mac laisse capter (essai réel, AirPods Pro 2)
- Appui simple / double : rien reçu (commandes de lecture non transmises). Appui long : réservé au bruit.
- **Glisser haut / bas : chaque glissement change le volume des AirPods d'un cran exact (1/16 = 0,0625)**,
  notifié aussitôt sur les canaux 1 et 2 (plusieurs notifications identiques par glissement).

## Conception
- Quand l'option est active et que les AirPods sont la sortie audio : écouter leur volume.
- Un changement **d'un cran** (0,0625 ± 0,02) par rapport au volume de référence = un glissement :
  hausse → défilement **vers le haut**, baisse → **vers le bas** ; puis le volume est **remis à la référence**.
- Pas un glissement (la référence suit simplement) : changement de plus ou moins d'un cran (curseur du menu
  Son), touche volume du clavier vue dans les 0,4 s précédentes, ou notification qui ramène à la référence.
- Pas « moyen » : ¼ de la hauteur de l'écran (≈ 240 px sur 956). Glissements rapprochés (< 0,8 s) :
  × 1,5 à chaque fois, jusqu'à × 3. Défilement fluide : réparti sur ~150 ms par la boucle à 120 Hz.
- Réglage « Glisser sur la tige pour défiler » (désactivé par défaut : il détourne le réglage du volume),
  pas Petit / Moyen / Grand (⅛, ¼, ½ écran). Journal : « Défilement haut/bas ».

## Non-objectifs
Appuis sur la tige ; défilement horizontal ; AirPods sans glissement (AirPods 3/4, Pro 1) — l'option n'a alors
aucun effet.

## Logique testable (AirPodsMouseCore)
- `StemSwipeDetector` : volume reçu + instant + touche clavier récente → `.up`, `.down` ou rien ; référence.
- `ScrollStepper` : instants des glissements → distance en px (pas × accélération).
