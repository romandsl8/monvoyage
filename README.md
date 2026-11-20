# MonVoyage

Application iPhone native (SwiftUI, iOS 26, Liquid Glass) pour **budgétiser et préparer un voyage à deux** :
budget et échéancier, calculateur taxes/pourboire, checklists, planning jour par jour avec météo et affluence des parcs,
réservations et vols, vue « Aujourd'hui », widgets, Live Activity, Siri, scan de tickets — le tout **hors ligne**
et **partagé entre deux comptes iCloud**.

> Pas de Mac nécessaire : le code est sur GitHub, **Codemagic** génère le projet, lance les tests, signe et envoie sur
> **TestFlight**. Le pas à pas complet est dans [GUIDE_MISE_EN_PLACE.md](GUIDE_MISE_EN_PLACE.md).

---

## Fonctionnalités

| Module | Contenu |
| --- | --- |
| Voyages | Liste avec compte à rebours et jauge de budget ; créer, modifier, dupliquer, archiver, supprimer ; ville via le géocodage Open-Meteo (coordonnées + fuseau) ; partage iCloud. |
| Budget | Catégories modifiables avec budget prévu, dépenses en EUR ou USD (taux du jour stocké), échéancier facultatif (acompte en montant ou %, solde en N fois égales avec reliquat sur le dernier, avertissement d'écart, statuts à venir / payé / en retard, conversion au taux du jour de paiement), totaux prévu / payé / reste à payer / écart, graphiques Swift Charts (anneau + barres). |
| Échéances | Tous les versements triés par date, retards en rouge, total par mois, « payé » par balayage. |
| Taxes et pourboire | Prix HT en USD + taxe (6,5 % par défaut) + pourboire (0/15/18/20/22 % ou libre), résultat en USD et EUR, « Ajouter comme dépense ». |
| Checklists | Plusieurs listes, éléments réordonnables, échéance, voyageur assigné, progression, retour haptique. |
| Planning | Un jour par date, activités triées par heure, météo, affluence et horaires les jours de parc, vols au bon jour en heure locale. |
| Réservations | Fiches typées, n° copiable, pièces jointes photo/PDF consultables hors ligne (QuickLook), dépense liée ; fiche vol détaillée (trajets multiples, compagnie déduite du code, heures locales par aéroport, durée avec décalage, rappels d'enregistrement et de départ, statut du vol). |
| Parcs | Affluence /10 datée (fichier publié par GitHub Actions, ou saisie manuelle), import des attractions Queue-Times, priorités, Express, taille mini, jour assigné, temps d'attente en direct, progression. |
| Aujourd'hui | Prochaines activités, météo, parcs du jour, budget restant par jour (EUR/USD, vert/orange/rouge), dépenses du jour, échéances et rappels. Grille 2 colonnes sur grand écran. |
| Outils | Siri / Raccourcis / bouton Action / contrôle du Centre de contrôle, scan de tickets (Vision, sur l'iPhone), Live Activity, alertes passeport/ESTA, double horloge, conversions, tailles US ↔ FR. |

Mentions : météo [Open-Meteo](https://open-meteo.com), taux BCE via [Frankfurter](https://frankfurter.dev),
attractions et temps d'attente **Powered by [Queue-Times.com](https://queue-times.com)** (mention affichée partout où ces données apparaissent),
horaires des parcs via [ThemeParks.wiki](https://themeparks.wiki).

---

## Architecture

```
project.yml                  Projet XcodeGen (identifiants centralisés en haut)
codemagic.yaml               CI/CD : génération, tests, signature, build, TestFlight
.github/workflows/           affluence.yml (publication quotidienne de affluence.json)
scripts/                     fetch_affluence.py, make_icon.py
design/icon.svg              Source vectorielle de l'icône
MonVoyage/
  App/                       Point d'entrée, AppDelegate/SceneDelegate (acceptation du partage), routeur, racine
  Persistence/               Modèle Core Data (.xcdatamodeld v1), pile CloudKit, sauvegarde, partage CKShare
  Core/                      Logique pure et testable (argent, échéancier, vols, tickets, météo, ZIP, jours)
  Services/                  Réseau et caches, taux, météo, parcs/affluence, notifications, widget, Live Activity, export/import
  Features/                  Écrans SwiftUI par module
  Intents/                   App Intents (Siri, Raccourcis, bouton Action)
  UI/                        Composants (cartes, chiffres clés, états vides, verre)
  Resources/Assets.xcassets  Icône (claire, sombre, teintée) et couleur d'accent
MonVoyageWidget/             Widgets, Live Activity / Dynamic Island, contrôle du Centre de contrôle
Shared/                      Code commun appli + widget (App Group, instantané widget, attributs Live Activity, intention d'ajout express)
MonVoyageTests/              Tests unitaires
```

- **Swift 5 (mode de langage)** avec le compilateur Swift 6, concurrence stricte « minimal », `@MainActor` sur les services observés et les vues.
- **Aucune dépendance tierce.** Le ZIP (export/import) est implémenté à la main (stockage + lecture deflate via `Compression`).
- **Core Data + `NSPersistentCloudKitContainer`** : magasin privé + magasin partagé, `CKShare` par voyage. Toutes les entités sont reliées à `Trip` : partager le voyage partage tout son contenu.
- **Caches réseau** (taux, météo, affluence, temps d'attente, instantané du widget) : fichiers JSON dans le conteneur App Group, jamais dans Core Data.
- **Mise en page** : uniquement selon la largeur (`horizontalSizeClass`, `ViewThatFits`). Compact → barre d'onglets ; large → `NavigationSplitView`. Les feuilles de saisie sont présentées au-dessus du choix de disposition : plier/déplier un iPhone Duo ou tourner l'écran ne perd pas la saisie. Le module ouvert est conservé (`@SceneStorage` + modèle de navigation).

---

## Conservation des données — règles impératives

1. Le **bundle ID** et le **conteneur iCloud** ne changent jamais.
2. Le code ne supprime ni ne recrée **jamais** la base. Avant chaque chargement, la base est copiée dans `Backup/*.backup`.
   Si le chargement ou la migration échoue, rien n'est effacé : un écran d'erreur permet d'exporter la sauvegarde.
3. Migrations automatiques activées (`NSMigratePersistentStoresAutomaticallyOption`, `NSInferMappingModelAutomaticallyOption`).
4. **Règle pour les versions futures du modèle** :
   - créer une **nouvelle version** du modèle (`MonVoyage 2.xcdatamodel`) et la déclarer courante dans `.xccurrentversion` ;
   - **ajouter uniquement** des attributs optionnels ou avec valeur par défaut, ou de nouvelles entités ;
   - **ne jamais renommer ni supprimer** une entité, un attribut ou une relation déjà publiés ;
   - après le build, **redéployer le schéma CloudKit** (Development → Production) avant de publier la version.
5. Export / import `.zip` (JSON + pièces jointes) d'un voyage ou de tous, via la feuille de partage. L'import recrée à l'identique avec de nouveaux UUID. Rappel discret après 30 jours sans export.

---

## Partage CloudKit et TestFlight

Les builds TestFlight utilisent l'environnement CloudKit **Production**, vide tant que le schéma n'y est pas déployé.
L'entitlement `com.apple.developer.icloud-container-environment` est piloté par `CLOUDKIT_ENV` (dans `project.yml`, remplacé par la variable de `codemagic.yaml`).

Procédure (validée : un build signé App Store peut cibler l'environnement Development grâce à cet entitlement) :
1. 1er build avec `CLOUDKIT_ENV = Development` ;
2. dans l'appli : Réglages → 5 appuis sur la version → « Initialiser le schéma CloudKit » (`initializeCloudKitSchema()`) ;
3. [console CloudKit](https://icloud.developer.apple.com) (navigateur, pas besoin de Mac) → *Deploy Schema Changes* vers Production ;
4. passer `CLOUDKIT_ENV` à `Production` et relancer un build.

Alternative si le bouton échoue : avec le build Development, créer un voyage, une dépense de chaque type et partager un voyage
(CloudKit crée le schéma « à la volée » en Development), puis déployer de la même façon.

---

## Affluence des parcs : choix de la source

Il n'existe pas d'API gratuite de **prévisions** d'affluence. Les calendriers d'affluence publics (Touring Plans, Thrill Data, etc.)
interdisent la collecte automatisée dans leurs conditions d'utilisation, et l'API Queue-Times ne fournit que des temps d'attente en direct.
Le script `scripts/fetch_affluence.py` utilise donc des **adaptateurs** :

| Adaptateur | Rôle | Pourquoi c'est acceptable |
| --- | --- | --- |
| `calendar` (défaut) | Estimation /10 calculée localement : saisonnalité de la Floride, jours fériés US, vacances (spring break, Pâques, Thanksgiving, fêtes), jour de la semaine, spécificités par parc. | Aucune donnée tierce. Affichée comme « Estimation calendaire ». |
| `themeparks_wiki` (défaut) | Horaires d'ouverture officiels par parc et par date. | API ouverte et gratuite de ThemeParks.wiki, sans clé, prévue pour un usage automatisé. |
| `empty` | Fichier vide valide. | L'appli bascule sur la saisie manuelle. |

Le script ne publie jamais un fichier invalide : en cas d'erreur il conserve le précédent. Choix des adaptateurs : variable de dépôt `AFFLUENCE_ADAPTERS`.
Publication : branche `gh-pages` (dépôt public) ou dépôt public séparé `monvoyage-data` (dépôt privé), voir le guide.

---

## Icône

`design/icon.svg` est la source ; `scripts/make_icon.py` (Python 3 standard, sans dépendance) régénère les trois PNG 1024 × 1024
sans transparence (clair, sombre, teinté) et le symbole des widgets (`Glyph.png`). Les PNG sont versionnés.

```bash
python3 scripts/make_icon.py
```

---

## Tests

`MonVoyageTests` couvre : conversion de devises, taxes et pourboire (50 $ + 6,5 % + 20 %), répartition du solde avec arrondi,
échéancier 1 200 € (300 € + 3 × 300 €) et baisse du reste à payer, statuts des versements, budget restant par jour,
durée de vol avec fuseaux (été/hiver), lecture du total d'un ticket, choix prévision/normales, limite des 64 notifications,
ZIP, et export → import aller-retour. Codemagic échoue si un test échoue.

---

## Mettre à jour l'appli

Demandez la modification à Claude Code, poussez sur `main` : Codemagic teste, incrémente le numéro de build et livre sur TestFlight.
Respectez la règle de migration ci-dessus pour toute modification du modèle de données.
