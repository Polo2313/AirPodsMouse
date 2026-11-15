# Alignement tête ↔ curseur

*Design court · 14 novembre 2026 · approuvé*

## Pourquoi
« Quand je regarde sur le côté et que le curseur touche le bord, ça le décale : en revenant je dois décaler
ma tête. » L'utilisateur veut qu'en face de l'écran, le curseur reste en face (au centre), avec un recalibrage
fréquent, sans perdre la précision actuelle (« prends le plus précis »).

Causes (mode relatif actuel, curseur = intégrale de la vitesse de la tête) :
1. au bord, le surplus de rotation est perdu ;
2. le gain dépend de la vitesse : un aller rapide et un retour lent du même angle ne s'annulent pas.

## Objectifs
- Revenir en face → curseur revient près du centre (cible : < 60 px sur un écran 1470 px).
- Garder la précision actuelle en visée lente (gain lent 1400 px/rad inchangé).
- Garder les clics : rejeu `motion2` = 5 clics, 0 faux clic ; `motion1` = 0 faux clic.

## Non-objectifs / anti-objectifs
- Pas de mode « absolu » pur (moins précis). Pas de défilement (sujet suivant).
- Anti-objectif : un curseur qui « glisse tout seul » pendant qu'on vise finement.

## Approches
| | | |
|---|---|---|
| A | Absolu : direction de la tête = position | Alignement parfait, mais visée fine moins précise |
| **B renforcé ✅** | Relatif actuel + mémoire des bords + réalignement pendant les mouvements rapides + « en face » recalibré en continu | Précision conservée ; alignement tenu |

Choisie : B renforcé (l'utilisateur a demandé « le plus précis »).

## Conception (dans `PointerEngine`, testable par rejeu et simulation)
- Le moteur suit en plus l'**angle** de la tête (lacet, tangage), filtré, et une **référence « en face »**.
- **Position idéale** = centre écran + angle relatif × gain d'alignement (≈ ±12° couvrent la largeur ;
  vertical × ratio vertical). Le moteur ne connaît pas l'écran : il reçoit la taille d'écran et la position
  courante du curseur, et renvoie un déplacement corrigé.
- **Mémoire des bords** : si le curseur est bloqué à un bord et que la position idéale est au-delà, aucun
  mouvement vers l'intérieur n'est émis tant que la position idéale n'est pas revenue dans l'écran.
- **Réalignement** : à chaque mesure, une fraction de l'écart (idéal − réel) est ajoutée, pondérée par la
  vitesse : 0 en dessous de 0,3 rad/s (visée fine), croissante jusqu'à 1 rad/s.
- **« En face » recalibré** : la référence suit lentement (constante ~120 s) la direction moyenne de la tête,
  uniquement quand le curseur n'est pas bloqué à un bord.
- **Recentrer** (⌃⌥C et bouton dans Pointeur) : référence = direction actuelle, curseur au centre de l'écran.
  Le calibrage haut/bas reste accessible depuis les réglages.

## Laissé au constructeur
Valeurs exactes des constantes (gain d'alignement, fractions), validées par les tests simulés et le rejeu.
