# Émargement Harmonie Électricité

Feuille d'émargement numérique, indépendante de l'app métier : chantiers par résidence, fiche par logement
(nom affiché, contact, rendez-vous, combiné ou moniteur, plaque, badges scannés à la caméra, photos avant / après,
signatures), bons d'intervention, avis de passage et bon de livraison en PDF, rappels SMS depuis le téléphone,
signature à distance par lien.

## Fichiers

| Fichier | Rôle |
|---|---|
| `index.html` | L'app du technicien |
| `signer.html` | Page publique où le client relit et signe son bon depuis le lien reçu |
| `logos.js`, `assets/` | Logos et icônes du design system Harmonie |
| `manifest.webmanifest`, `sw.js` | App installable sur l'écran d'accueil, ouverture sans réseau |
| `sql/emargements.sql` | Table Supabase à créer une fois |

## Données

- Supabase, projet `bqzebkobyfktemnwfwbt`, table **`emargements`** propre à cette app
  (chantiers `CH_…` et demandes de signature `SIG_…`). La table `clients` est seulement lue, pour créer un chantier.
- Photos : stockage Supabase, `bon-photos/emargement/<chantier>/`.
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
