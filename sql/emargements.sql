-- À exécuter une seule fois dans Supabase → SQL Editor
-- Feuilles d'émargement numériques (emargement.html) et signatures à distance (signer.html).
-- Même pattern JSONB que notes/checklist/clients/devis/interventions.

create table if not exists public.emargements (
  id text primary key,
  payload jsonb not null,
  created_at timestamptz not null default now()
);

alter table public.emargements enable row level security;

create policy "Allow anon all on emargements"
  on public.emargements
  for all
  to anon
  using (true)
  with check (true);

-- Deux sortes de lignes :
--
-- 1. Un chantier : id = 'CH_…'
--    payload = {
--      "id": "CH_…", "residence": "...", "adresse": "...", "reference": "Réf. 2178399",
--      "donneur": "...", "donneurEmail": "...", "clientId": "...", "residenceId": "...",
--      "technicien": "...", "date": "2026-10-25", "objet": "...", "smsRappel": "...",
--      "modifieLe": 1234567890,           -- la version la plus récente l'emporte entre appareils
--      "resume": { "total": 14, "signes": 6, "absents": 1 },
--      "logements": [ { "id", "batiment", "etage", "porte", "nomAffiche", "occupant", "tel", "email",
--                        "rdvDate", "rdvHeure", "modele", "plaque", "badgesPrevu", "badges": [...],
--                        "observations", "statut": "afaire" | "signe" | "absent",
--                        "sigClient" (PNG data URL), "sigTech", "signataire", "signeLe", "signeDistance",
--                        "photos": { "avant": url, "apres": url }, "distance": { "jeton", "creeLe", "envoyeLe" },
--                        "prevenuLe", "rappelLe", "absentLe", "avisLe", "numeroBon" } ]
--    }
--    Les photos avant / après sont dans le stockage : bon-photos/emargement/<chantier>/<logement>-avant.jpg
--
-- 2. Une demande de signature à distance : id = 'SIG_<jeton de 32 caractères>'
--    payload = { "type": "signature", "statut": "attente" | "signe", "chantierId", "logementId",
--                "bon": { résumé du bon affiché au client }, "creeLe",
--                "signature" (PNG data URL), "signataire", "signeLe" }   -- écrits par signer.html
