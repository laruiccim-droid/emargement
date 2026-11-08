# Harmonie Électricité — relevés et émargement

L'accueil (`index.html`) donne accès à deux activités, chacune avec ses chantiers rangés par client (A → Z),
une recherche et la création d'un nouveau chantier à partir des clients de l'app métier (ou d'un nouveau client) :

- **Relevés de consommation** des bornes de recharge : index et photo par place, copropriétaire, relève suivante
  avec consommation et montant à refacturer, rapport PDF envoyé au syndic, rappel de la prochaine relève.
- **Émargement interphonie** : feuille d'émargement numérique, chantiers par résidence, fiche par logement
(nom affiché, contact, rendez-vous, combiné ou moniteur, plaque, badges scannés à la caméra, photos avant / après,
signatures), bons d'intervention, avis de passage et bon de livraison en PDF, rappels SMS depuis le téléphone,
signature à distance par lien.

## Fichiers

| Fichier | Rôle |
|---|---|
| `index.html` | Accueil : tuiles Relevés / Interphonie, listes par client, création, fiche client, « Cette semaine » |
| `emargement.html` | L'émargement du technicien (`?chantier=CH_…` ouvre un chantier, `?listing=1&client=…` l'import du listing) |
| `commun.js` | Outils partagés par l'accueil et les relevés : Supabase, clients de l'app métier, envoi Gmail, lien agenda |
| `signer.html` | Page publique où le client relit et signe son bon depuis le lien reçu |
| `releves.html` | Relevé des bornes de recharge, une page par relève (`?c=RB_…`, sans paramètre : Land’Art) : index, photo, copropriétaire, consommation et montant, rapport PDF / CSV, envoi au syndic, synchronisé entre appareils |
| `logos.js`, `assets/` | Logos et icônes du design system Harmonie |
| `manifest.webmanifest`, `sw.js` | App installable sur l'écran d'accueil, ouverture sans réseau |
| `sql/emargements.sql` | Table Supabase à créer une fois |

## Données

- Supabase, projet `bqzebkobyfktemnwfwbt`, table **`emargements`** propre à cette app
  (chantiers `CH_…`, demandes de signature `SIG_…` et relevés des bornes `RB_…`). La table `clients` est seulement lue, pour créer un chantier.
- Photos : stockage Supabase, `bon-photos/emargement/<chantier>/` (relevés des bornes : `bon-photos/emargement/releves-bornes/<RB_…>/`).
- Tout est d'abord enregistré sur l'appareil, puis envoyé en ligne : l'app marche sans réseau.
- Envoi des e-mails : service Gmail Harmonie (`send-email-harmonie…workers.dev`). Sans jeton Google,
  le PDF passe par la messagerie du téléphone.

## Mise en route

1. **Table Supabase** : Supabase → SQL Editor → coller `sql/emargements.sql` → Run.
   Vérifier : `select table_schema, table_name from information_schema.tables where table_name = 'emargements';`
   doit renvoyer `public | emargements`.
2. **Dépôt GitHub** : créer un dépôt vide `emargement` sur le compte `laruiccim-droid` (sans README).
3. **Envoi** : `git remote add origin https://github.com/laruiccim-droid/emargement.git` puis `git push -u origin main`.
4. **GitHub Pages** : dépôt → Settings → Pages → Source « Deploy from a branch », branche `main`, dossier `/ (root)`.
   L'app est alors sur `https://laruiccim-droid.github.io/emargement/`.
5. Sur le téléphone, ouvrir cette adresse puis « Ajouter à l'écran d'accueil ».

La caméra (scan des badges) et la signature à distance demandent l'adresse en https : elles ne marchent pas
en ouvrant le fichier directement depuis le PC.

## Revenir en arrière

Chaque mise en ligne est un commit. Pour annuler la dernière : `git revert HEAD` puis `git push`.
Penser à changer `VERSION` dans `sw.js` à chaque mise en ligne pour que les téléphones prennent la nouvelle version.

## Clients

La liste des clients vient de la table `clients` de l'app métier (lue en entier, par pages de 1000, gardée sur l'appareil
pour travailler sans réseau). Un client créé depuis l'accueil y est ajouté comme un client créé à la main dans l'app métier
(`id` = `C_<horodatage>`, champs `name`, `email`, `phone`, `address`, `addressChantier`, `createdAt`) ; hors ligne, il part au retour du réseau.
Le nom du client pré-remplit la résidence : « Le saint François SC CHAMBÉRY SYNDIC » donne la résidence « Le saint François »
et le syndic « CHAMBÉRY SYNDIC ».

## Relevés : données sur l'appareil

Land’Art garde ses clés d'origine dans IndexedDB (`releves-bornes` → `config`, `releves`) ; les autres relèves sont sous
`config:RB_…` / `releves:RB_…`, et `campagnes` liste celles de l'appareil. Aucune donnée n'est déplacée lors des mises à jour.
