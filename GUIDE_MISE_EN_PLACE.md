# Guide de mise en place de MonVoyage (sans Mac)

Ce guide vous emmène du code jusqu'à l'appli installée sur vos deux iPhone, **sans Mac**.
Suivez les étapes dans l'ordre. Chaque étape dit **quel site ouvrir**, **où cliquer**, **quoi copier** et **comment vérifier**.

> 🔁 **Quand vous voyez ce symbole, revenez vers Claude Code** et collez-lui l'information demandée.

Durée totale : 1 h 30 environ la première fois (dont 20 à 40 min d'attente de build).

---

## 0. Les identifiants (à garder sous la main)

Ils sont centralisés **en haut de `project.yml`** et dans la section `env` de **`.github/workflows/testflight.yml`**. Si vous en changez un, changez-le aux deux endroits.

| Élément | Valeur |
| --- | --- |
| Nom sous l'icône | `MonVoyage` |
| Nom de la fiche App Store Connect | `MonVoyage Planner` |
| Bundle ID de l'appli | `fr.tanguy.monvoyage` |
| Bundle ID du widget | `fr.tanguy.monvoyage.widget` |
| Conteneur iCloud | `iCloud.fr.tanguy.monvoyage2` |
| App Group | `group.fr.tanguy.monvoyage` |
| Identifiant Apple de l'appli | `6837239666` |

Ces identifiants sont **définitifs** : on ne les change plus une fois l'appli publiée (sinon les données iCloud ne suivent pas).

---

## 1. GitHub : créer le dépôt et y mettre le code

### 1.1 Public ou privé ?

| | Dépôt **public** | Dépôt **privé** |
| --- | --- | --- |
| Code visible par tous | oui | non |
| Fichier d'affluence | publié sur la branche `gh-pages` du même dépôt (gratuit) | GitHub Pages n'est pas gratuit en privé → on publie dans un 2e petit dépôt **public** `monvoyage-data` |
| Réglages en plus | aucun | un token + 2 réglages (étape 1.5) |

Le code ne contient aucun secret : un dépôt public est possible. Si vous préférez la discrétion, prenez privé.

### 1.2 Créer le dépôt

1. Ouvrez **https://github.com/new** (connecté à votre compte).
2. **Repository name** : `monvoyage`.
3. Cochez **Public** ou **Private** selon votre choix.
4. **Ne cochez rien d'autre** (pas de README, pas de .gitignore, pas de licence).
5. Cliquez **Create repository**.
6. ✅ Vérification : une page « Quick setup » s'affiche avec une adresse du type `https://github.com/VOTRE-COMPTE/monvoyage.git`.

> 🔁 **Envoyez à Claude Code l'adresse du dépôt** (`https://github.com/VOTRE-COMPTE/monvoyage.git`).
> Claude Code poussera le projet pour vous (`git remote add origin …` puis `git push -u origin main`).
> Si Windows ouvre une fenêtre de connexion GitHub, connectez-vous : c'est normal.

✅ Vérification : en rechargeant la page du dépôt, vous voyez les dossiers `MonVoyage`, `MonVoyageWidget`, `scripts`… et ce guide.

### 1.3 Activer GitHub Actions

1. Dans le dépôt, onglet **Actions**.
2. Si un bouton **I understand my workflows, go ahead and enable them** apparaît, cliquez-le.
3. Dans la liste à gauche, cliquez **Affluence des parcs**, puis **Run workflow** → **Run workflow** (bouton vert).
4. ✅ Vérification : au bout d'une minute, la ligne passe au vert ✔.

### 1.4 Dépôt PUBLIC : activer GitHub Pages

1. Onglet **Settings** → menu de gauche **Pages**.
2. **Source** : *Deploy from a branch*. **Branch** : `gh-pages` / `/ (root)` → **Save**.
   (La branche `gh-pages` existe dès que le workflow de l'étape 1.3 a réussi une fois.)
3. Patientez 1 à 2 minutes puis ouvrez `https://VOTRE-COMPTE.github.io/monvoyage/affluence.json`.
4. ✅ Vérification : un long texte commençant par `{"parks":` s'affiche.
5. **Notez cette adresse** : vous la collerez dans l'appli (Réglages → Affluence des parcs).

### 1.5 Dépôt PRIVÉ : dépôt public séparé + token

1. Créez un 2e dépôt sur **https://github.com/new** : nom `monvoyage-data`, **Public**, cochez **Add a README file**, **Create repository**.
2. Dans `monvoyage-data` : **Settings → Pages** → Source *Deploy from a branch*, Branch `main` / `/ (root)` → **Save**.
3. Créez un token : **https://github.com/settings/personal-access-tokens/new** (token « fine-grained »)
   - **Token name** : `monvoyage-data`
   - **Expiration** : 1 an (pensez à le renouveler)
   - **Repository access** : *Only select repositories* → `monvoyage-data`
   - **Permissions → Repository permissions → Contents** : *Read and write*
   - **Generate token**, puis **copiez** le token (il ne sera plus affiché).
4. Dans le dépôt **privé** `monvoyage` : **Settings → Secrets and variables → Actions**
   - onglet **Secrets** → **New repository secret** : Name `DATA_REPO_TOKEN`, Secret = le token → **Add secret** ;
   - onglet **Variables** → **New repository variable** : `PUBLISH_MODE` = `data-repo` ;
   - **New repository variable** : `DATA_REPO` = `VOTRE-COMPTE/monvoyage-data`.
5. Relancez le workflow (étape 1.3, point 3).
6. ✅ Vérification : `https://VOTRE-COMPTE.github.io/monvoyage-data/affluence.json` s'affiche. **Notez cette adresse.**

---

## 2. Apple Developer : créer les identifiants

Site : **https://developer.apple.com/account** → **Certificates, Identifiers & Profiles** → **Identifiers**.

### 2.1 Conteneur iCloud
1. Bouton **+** (à côté de « Identifiers »).
2. Choisissez **iCloud Containers** → **Continue**.
3. **Description** : `MonVoyage` ; **Identifier** : `iCloud.fr.tanguy.monvoyage2` → **Continue** → **Register**.

### 2.2 App Group
1. **+** → **App Groups** → **Continue**.
2. **Description** : `MonVoyage` ; **Identifier** : `group.fr.tanguy.monvoyage` → **Continue** → **Register**.

### 2.3 App ID de l'appli
1. **+** → **App IDs** → **Continue** → **App** → **Continue**.
2. **Description** : `MonVoyage` ; **Bundle ID** : *Explicit* → `fr.tanguy.monvoyage`.
3. Dans **Capabilities**, cochez :
   - **App Groups**
   - **iCloud** (choisissez *Include CloudKit support* si la question est posée)
   - **Push Notifications**
4. **Continue** → **Register**.
5. Rouvrez l'App ID `fr.tanguy.monvoyage` dans la liste :
   - à côté de **App Groups**, cliquez **Configure** (ou *Edit*) → cochez `group.fr.tanguy.monvoyage` → **Continue** → **Save** ;
   - à côté de **iCloud**, cliquez **Configure** (ou *Edit*) → cochez `iCloud.fr.tanguy.monvoyage2` → **Continue** → **Save**.
6. ✅ Vérification : sur la fiche de l'App ID, App Groups, iCloud et Push Notifications sont cochés, et « Configure » indique 1 groupe / 1 conteneur.

### 2.4 App ID du widget
1. **+** → **App IDs** → **App** → **Continue**.
2. **Description** : `MonVoyage Widget` ; **Bundle ID** *Explicit* : `fr.tanguy.monvoyage.widget`.
3. Cochez **App Groups** → **Continue** → **Register**, puis rouvrez-le → **App Groups → Configure** → cochez `group.fr.tanguy.monvoyage` → **Save**.

> ⚠️ Si vous modifiez plus tard une capacité d'un App ID, allez dans **Profiles** et **supprimez** les profils « MonVoyage » existants : le prochain build les recréera avec les bonnes capacités.

---

## 3. App Store Connect : créer la fiche

Site : **https://appstoreconnect.apple.com** → **Apps**.

1. Bouton **+** → **Nouvelle app**.
2. **Plateformes** : iOS. **Nom** : `MonVoyage Planner`. **Langue principale** : Français.
   **Identifiant de lot (Bundle ID)** : choisissez `fr.tanguy.monvoyage`. **SKU** : `monvoyage`. **Accès** : Accès complet → **Créer**.
3. **Si le nom est refusé** (« déjà utilisé ») : essayez `MonVoyage Planner à deux`, `MonVoyage – Budget voyage`, etc.
   Le nom de la fiche n'a aucune importance pour TestFlight ; le nom **sous l'icône** reste `MonVoyage`.
4. Dans la fiche : menu de gauche **Informations sur l'app** → section *Informations générales* → **Identifiant Apple** : un nombre à 10 chiffres (ex. `6741234567`).

> 🔁 **Notez l'Identifiant Apple numérique.** Vous le mettrez dans `.github/workflows/testflight.yml` (`APP_STORE_APPLE_ID`) — ou envoyez-le à Claude Code qui le fera.

### 3.1 TestFlight : testeurs
1. **Utilisateurs et accès** (menu du haut) → **+** : invitez la 2e personne avec son adresse Apple ID, rôle **Marketing** (le plus restreint suffit). Elle doit accepter l'e-mail d'invitation.
2. Dans la fiche de l'app → onglet **TestFlight** → **Tests internes** → **+** à côté de « Groupes » → nom `Famille`.
3. Ajoutez-vous, ainsi que la 2e personne, au groupe (bouton **+** à côté de *Testeurs*).
4. ✅ Vérification : vous apparaissez tous les deux dans le groupe avec l'état « Invité » ou « Accepté ».

Les deux personnes installent l'appli **TestFlight** depuis l'App Store sur leur iPhone.

---

## 4. Clés Apple dans les secrets GitHub

Les builds tournent sur **GitHub Actions** (machine Mac `xcode-27`, Xcode 27.2), avec les outils open source `codemagic-cli-tools` pour la signature. Tout se règle dans **https://github.com/romandsl8/monvoyage/settings/secrets/actions** → onglet **Secrets** → **New repository secret**.

> Quota : le dépôt est public, les minutes de build GitHub Actions sont donc gratuites et illimitées. Les journaux de build masquent le nom du titulaire du certificat (***).

### 4.1 Clé API App Store Connect
1. **https://appstoreconnect.apple.com/access/integrations/api** → onglet **Clés d'équipe** → **+** (ou **Générer une clé API**).
2. Nom : `GitHub` ; Accès : **Admin** → **Générer**.
3. Notez l'**Issuer ID** (en haut de la page) et le **Key ID** de la clé ; cliquez **Télécharger** (fichier `AuthKey_XXXXXXXXXX.p8`, téléchargeable **une seule fois**).
4. Créez 3 secrets GitHub :
   - `APP_STORE_CONNECT_ISSUER_ID` = l'Issuer ID ;
   - `APP_STORE_CONNECT_KEY_IDENTIFIER` = le Key ID ;
   - `APP_STORE_CONNECT_PRIVATE_KEY` = le **contenu complet** du fichier `.p8` (ouvrez-le avec le Bloc-notes : de `-----BEGIN PRIVATE KEY-----` à `-----END PRIVATE KEY-----`).

### 4.2 Clé privée du certificat
- Secret `CERTIFICATE_PRIVATE_KEY` = le contenu complet du fichier `cert_key` (de `-----BEGIN RSA PRIVATE KEY-----` à `-----END RSA PRIVATE KEY-----`). Utilisez **la même clé** que précédemment : Apple limite le nombre de certificats.
- Si vous n'en avez pas, dans **PowerShell** : `ssh-keygen -t rsa -b 2048 -m PEM -f cert_key -q -N '""'` puis `notepad cert_key`.

---

## 5. Lancer un build TestFlight

1. Onglet **Actions** du dépôt → à gauche **MonVoyage → TestFlight** → **Run workflow** → **Run workflow**.
   Ensuite, chaque modification du code poussée sur `main` lance un build automatiquement.
2. ✅ Toutes les étapes passent au vert (15 à 25 min). App Store Connect traite ensuite le build (5 à 30 min) ; grâce au groupe interne à distribution automatique, il arrive dans TestFlight.

> 🔁 **Si une étape est rouge** : cliquez le build, puis l'étape rouge, copiez les dernières lignes et envoyez-les à Claude Code (voir étape 9).

---

## 6. Schéma CloudKit (une fois, puis après chaque changement du modèle)

Pourquoi : les builds TestFlight utilisent **toujours** l'environnement iCloud **Production**, vide au départ, et l'appli ne peut pas y créer la structure (le « schéma »). Le workflow GitHub **Schéma CloudKit → Development** (sur Mac) importe le schéma dans l'environnement **Development** avec l'outil d'Apple `cktool`, puis vous le déployez en Production depuis la console web.

### 6.1 Jeton de gestion CloudKit
1. https://icloud.developer.apple.com → flèche **⌄** à côté de votre nom → **Settings** → **Tokens** → section **Management Tokens** → **+ Create Management Token** → nom `GitHub` → **Create** → **copiez** le jeton. (Pas « API Token » ni « User Token ».)
2. Secret GitHub `CLOUDKIT_MANAGEMENT_TOKEN` = ce jeton.
3. Variable GitHub (onglet **Variables**) `CLOUDKIT_TEAM_ID` = votre Team ID (`8B47T5AZDA`, visible dans l'adresse de la console CloudKit).

### 6.2 Importer le schéma
1. Onglet **Actions** → **Schéma CloudKit → Development** → **Run workflow** → **Run workflow** (2 à 5 min).
2. ✅ Toutes les étapes vertes. 🔁 Si une étape est rouge, envoyez à Claude Code son nom et ses dernières lignes.

### 6.3 Déployer en Production
1. https://icloud.developer.apple.com → **CloudKit Database** → conteneur `iCloud.fr.tanguy.monvoyage2` → environnement **Development** → **Schema → Record Types** : vous voyez `CD_Trip`, `CD_Expense`, etc. ✅
2. **Deploy Schema Changes…** (bas du menu de gauche) → vérifiez la liste → **Deploy**.
3. Basculez sur **Production** : les mêmes `CD_…` apparaissent. ✅

### 6.4 Vérifier dans l'appli
Installez le dernier build via TestFlight → Réglages de l'appli → 5 appuis sur **Version** → écran CloudKit. Créez un voyage, attendez une minute : dans la console, **Production → Records**, zone `com.apple.coredata.cloudkit.zone`, des enregistrements `CD_Trip` apparaissent. 🔁 Si l'appli signale un champ manquant, envoyez le message à Claude Code (le bouton « Initialiser le schéma » de cet écran ne sert pas en TestFlight).

---

## 7. Installation et test du partage sur les deux iPhone

Pré-requis : **iOS 26 minimum** sur les deux iPhone, chacun connecté à **son propre** compte iCloud.

1. Les deux installent MonVoyage (build Production) via **TestFlight**.
2. **iPhone A** : créez un voyage (bouton **+** → *Nouveau voyage*).
3. Ouvrez le voyage → **Plus** → **Voyage et voyageurs** → **Partager ce voyage** → envoyez l'invitation par **Messages** à la personne B (ou copiez le lien). Autorisation : *Peut modifier*.
4. **iPhone B** : touchez le lien reçu → **Ouvrir** → MonVoyage s'ouvre et accepte le partage. Le voyage apparaît dans la liste (badge « Partagé avec moi ») au bout de quelques secondes à une minute.
5. ✅ Test dans les deux sens : ajoutez une dépense sur B → elle apparaît sur A ; cochez un élément de checklist sur A → il apparaît sur B.
6. Collez l'adresse de `affluence.json` (étape 1.4 ou 1.5) dans **Réglages → Affluence des parcs** sur chaque iPhone.
7. Autorisez les **notifications** quand l'appli le demande. Ajoutez les **widgets** (appui long sur l'écran d'accueil → **Modifier** → **Ajouter un widget** → MonVoyage) et le **contrôle** (Centre de contrôle → **+** → MonVoyage → *Ajouter une dépense*).
8. Siri : « **Dis Siri, ajoute une dépense en repas dans MonVoyage** » → Siri demande le montant → « 12 ». (Siri ne permet pas de mettre le montant directement dans la phrase d'un raccourci d'appli ; il le demande juste après.)

Pour **arrêter le partage** (propriétaire) ou **quitter** (invité) : même écran → **Gérer le partage**.

---

## 8. Mettre à jour l'appli plus tard

1. Ouvrez Claude Code sur ce projet et décrivez la modification (« ajoute… », « corrige… »).
2. Claude Code modifie, puis **commit et push** sur `main`.
3. GitHub Actions se lance tout seul : tests → build (numéro incrémenté automatiquement) → TestFlight.
4. Sur les iPhone : TestFlight → **Mettre à jour**. Les données restent (elles sont dans l'iPhone et dans iCloud).

**Règle d'or des données** (rappelez-la à Claude Code si besoin) : dans le modèle Core Data, on **ajoute** uniquement des attributs optionnels ou avec valeur par défaut, dans une **nouvelle version** du modèle ; on ne **renomme** et on ne **supprime** jamais une entité ou un attribut déjà publiés. Après un changement de modèle : refaire les étapes 6.2 et 6.3 (workflow « Schéma CloudKit » puis déploiement).

Pensez à **exporter** vos voyages de temps en temps (liste des voyages → **+** → *Exporter tous les voyages* → *Enregistrer dans Fichiers*).

---

## 9. Dépannage

### Où trouver les logs
**GitHub → onglet Actions** → cliquez le build rouge → cliquez l'étape rouge pour la déplier → copiez les dernières lignes. Le journal complet des tests est dans **Artifacts → journaux-build**.

> 🔁 **Envoyez à Claude Code** : le **nom de l'étape** rouge + les **30 à 50 dernières lignes**. Pour les tests, joignez l'artefact `xcodebuild-test.log`.

### Erreurs fréquentes

| Message (extrait) | Cause | Solution |
| --- | --- | --- |
| `No matching profiles found` / `doesn't include the com.apple.developer.icloud-container-identifiers entitlement` / `…application-groups…` | L'App ID n'a pas la capacité ou le conteneur/groupe n'est pas coché | Refaire l'étape 2.3 / 2.4, puis **supprimer les profils MonVoyage** dans *Profiles* et relancer le build |
| `There are no certificates` / `maximum number of certificates` | Clé privée différente de celle de l'appli précédente, limite Apple atteinte | Réutiliser l'ancienne `CERTIFICATE_PRIVATE_KEY`, ou révoquer un certificat de distribution inutilisé dans *Certificates* |
| `The bundle version must be higher than the previously uploaded version` | Numéro de build déjà utilisé | Vérifier `APP_STORE_APPLE_ID` (10 chiffres, celui de l'étape 3) ; relancer |
| `Authentication failed` / `401` (App Store Connect) | Secret de clé API incorrect | Vérifier les 3 secrets `APP_STORE_CONNECT_*` (étape 4.1), le `.p8` copié en entier |
| `** TEST FAILED **` | Un test unitaire échoue | Envoyer `xcodebuild-test.log` à Claude Code |
| Dans l'appli : le partage échoue, rien ne se synchronise entre les iPhone | Schéma CloudKit pas déployé en Production | Refaire l'étape 6 (points 4 à 9) |
| Workflow « Schéma CloudKit » : `authentication` / `401` | Jeton ou Team ID incorrect | Recréer le jeton (6.1) et vérifier `CLOUDKIT_TEAM_ID` |
| App Store Connect : « Le nom de l'app est déjà utilisé » | Nom pris sur l'App Store | Choisir une variante (étape 3, point 3) ; le nom sous l'icône reste MonVoyage |
| Build « Invalid Binary » / mail d'Apple après envoi | Problème d'Info.plist ou d'icône | Envoyer le contenu du mail à Claude Code |

### L'appli affiche « Vos données n'ont pas pu être ouvertes »
Rien n'est effacé. Touchez **Préparer l'export de la sauvegarde** → **Partager la sauvegarde** → *Enregistrer dans Fichiers*, puis 🔁 envoyez le message d'erreur affiché à Claude Code.
