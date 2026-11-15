# Nouvelles fonctions (lot « utiles »)

*Design court · 14 novembre 2026 · demandé : « mets-les en place » (liste proposée 1 → 8 ; la 9, mises à jour,
attend la publication GitHub)*

Toutes les logiques non graphiques vont dans `AirPodsMouseCore` avec des vérifications ; chaque fonction a un
réglage (volet indiqué). Choix faits par Claude, à corriger au besoin.

| # | Fonction | Comportement | Réglage (défaut) |
|---|---|---|---|
| 1 | **Pause pendant la frappe** | Une touche du clavier fige le pointeur à la tête (mouvement, clics tête, clic auto) jusqu'à 1 s après la dernière touche ; à la reprise, pas de saut. Raccourcis ⌃⌥ ignorés. | Général, **activé** |
| 2 | **Recentrage au changement d'écran** | Branchement/débranchement d'un écran → recentrer (curseur au centre de l'écran courant, « en face » = tête actuelle). | aucun (toujours) |
| 3 | **Glisser-déposer** | « Attraper » (bouton gauche enfoncé) puis le curseur glisse ; le clic suivant (hochement, clic auto, raccourci) « lâche ». Déclenché par ⌃⌥D ou le menu de clic rapide. Anneau en forme de main pendant le glisser. | — |
| 4 | **Défilement à la tête** | Mode activé par ⌃⌥S ou le menu de clic rapide : curseur figé ; pencher la tête vers le haut/bas au-delà de 3° fait défiler en continu (plus on penche, plus vite). Sortie : hochement, ⌃⌥S, ou regarder de côté (> 15°). | — |
| 5 | **Menu de clic rapide** | Avec le clic automatique : au lieu de cliquer, un menu circulaire s'ouvre autour du curseur (clic, double-clic, clic droit, glisser, défiler) ; viser une action et rester immobile 0,6 s l'exécute à l'endroit d'origine ; s'éloigner ou attendre 4 s annule. | Clic, désactivé |
| 6 | **Aimant vers les boutons** | Au-dessus d'un élément cliquable (bouton, lien, case, menu… lu via l'Accessibilité ~10×/s), le curseur ralentit (× 0,5) en visée lente : plus facile de s'arrêter dessus. | Pointeur, **activé** |
| 7 | **Geste « non » = Échap** | Secouer la tête gauche-droite (≥ 3 inversions de lacet > 1,2 rad/s en < 1,2 s, amplitude < 25°, peu de tangage) envoie Échap. Seuils prudents, à confirmer sur enregistrement. | Clic, désactivé |
| 8 | **Clavier visuel et dictée** | Menu et Réglages › Général : « Clavier visuel » ouvre le clavier d'accessibilité de macOS ; « Dictée » actionne « Démarrer la dictée » du menu Édition de l'appli au premier plan. | — |

## Non-objectifs
Commandes vocales ; mises à jour automatiques (après publication) ; défilement horizontal.

## Anti-objectifs
Clics ou Échap involontaires ; curseur qui saute à la reprise après frappe ou défilement.
