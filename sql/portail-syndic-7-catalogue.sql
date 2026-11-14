-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 7 : catalogue matériel multi-marques
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 6.
-- Ne touche pas à la table « emargements ».
--
-- Un catalogue unique (Golmar, Bticino, Fermax, Intratone, Noralsy, Urmet, Comelit…) dans lequel on
-- pioche pour chaque chantier. Les prix de vente sont visibles par tous (choix de l'utilisateur) :
-- la lecture du catalogue est publique, la modification réservée à l'administrateur.
-- Pré-rempli avec Golmar (devis D01486, brochure Evicom, notices de la bibliothèque).
-- =====================================================================================

create table if not exists public.ps_catalogue (
  id uuid primary key default gen_random_uuid(),
  marque text not null,
  ref text not null default '',
  type text not null default 'combine',   -- combine | moniteur | plaque | badge | telecommande | option | chantier
  nom text not null,
  argument text not null default '',      -- une phrase pour le copropriétaire
  points jsonb not null default '[]',     -- 3 à 5 points clés
  prix_ht numeric(10,2) not null default 0,
  tva numeric(5,2) not null default 10,
  photo text not null default '',         -- adresse publique de la photo
  notice text not null default '',        -- adresse publique de la notice PDF
  ordre integer not null default 0,
  actif boolean not null default true,
  cree_le timestamptz not null default now(),
  maj_le timestamptz not null default now()
);
create unique index if not exists ps_catalogue_marque_ref on public.ps_catalogue (marque, ref) where ref <> '';
alter table public.ps_catalogue enable row level security;
revoke all on public.ps_catalogue from anon, authenticated;

-- Lecture publique : articles actifs (d'une marque, ou tous).
create or replace function public.ps_catalogue_lire(p_marque text default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(a) - 'cree_le' - 'maj_le' order by a.marque, a.ordre, a.prix_ht), '[]'::jsonb)
  from ps_catalogue a where a.actif and (p_marque is null or a.marque = p_marque);
$$;

-- Administrateur : tout le catalogue, articles désactivés compris.
create or replace function public.ps_admin_catalogue(p_admin text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return coalesce((select jsonb_agg(to_jsonb(a) order by a.marque, a.ordre, a.prix_ht) from ps_catalogue a), '[]'::jsonb);
end $$;

create or replace function public.ps_admin_catalogue_enregistrer(p_admin text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := nullif(p->>'id', '')::uuid;
begin
  perform ps__admin(p_admin);
  if coalesce(trim(p->>'nom'), '') = '' or coalesce(trim(p->>'marque'), '') = '' then raise exception 'NOM_OBLIGATOIRE'; end if;
  if v_id is null then
    insert into ps_catalogue (marque, ref, type, nom, argument, points, prix_ht, tva, photo, notice, ordre, actif)
    values (trim(p->>'marque'), coalesce(trim(p->>'ref'), ''), coalesce(nullif(p->>'type', ''), 'combine'), trim(p->>'nom'), coalesce(p->>'argument', ''),
      coalesce(p->'points', '[]'), coalesce(nullif(p->>'prix_ht', '')::numeric, 0), coalesce(nullif(p->>'tva', '')::numeric, 10),
      coalesce(p->>'photo', ''), coalesce(p->>'notice', ''), coalesce(nullif(p->>'ordre', '')::int, 0), coalesce((p->>'actif')::boolean, true))
    returning id into v_id;
  else
    update ps_catalogue set marque = trim(p->>'marque'), ref = coalesce(trim(p->>'ref'), ''), type = coalesce(nullif(p->>'type', ''), 'combine'),
      nom = trim(p->>'nom'), argument = coalesce(p->>'argument', ''), points = coalesce(p->'points', '[]'),
      prix_ht = coalesce(nullif(p->>'prix_ht', '')::numeric, 0), tva = coalesce(nullif(p->>'tva', '')::numeric, 10),
      photo = coalesce(p->>'photo', ''), notice = coalesce(p->>'notice', ''), ordre = coalesce(nullif(p->>'ordre', '')::int, 0),
      actif = coalesce((p->>'actif')::boolean, true), maj_le = now()
    where id = v_id;
  end if;
  return jsonb_build_object('id', v_id);
exception when unique_violation then raise exception 'REFERENCE_EXISTANTE';
end $$;

create or replace function public.ps_admin_catalogue_supprimer(p_admin text, p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  delete from ps_catalogue where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function public.ps_catalogue_lire(text) from public, anon, authenticated;
grant execute on function public.ps_catalogue_lire(text) to anon, authenticated;
revoke execute on function public.ps_admin_catalogue(text) from public, anon, authenticated;
grant execute on function public.ps_admin_catalogue(text) to anon, authenticated;
revoke execute on function public.ps_admin_catalogue_enregistrer(text, jsonb) from public, anon, authenticated;
grant execute on function public.ps_admin_catalogue_enregistrer(text, jsonb) to anon, authenticated;
revoke execute on function public.ps_admin_catalogue_supprimer(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_admin_catalogue_supprimer(text, uuid) to anon, authenticated;

-- ---------- Golmar (prix de vente HT du devis D01486, TVA 10 %) ----------
insert into public.ps_catalogue (marque, ref, type, nom, argument, points, prix_ht, tva, photo, notice, ordre) values
('Golmar', 'GTART', 'combine', 'Poste audio à combiné', 'Tout simplement audio, pratique et économique',
  '["Combiné avec cordon", "Touches sensitives", "Ouverture de 2 portes", "Réglage et coupure de la sonnerie", "Appel palier"]', 40, 10,
  'https://bqzebkobyfktemnwfwbt.supabase.co/storage/v1/object/public/bon-photos/emargement/catalogue/golmar/GTART.jpg',
  'https://bqzebkobyfktemnwfwbt.supabase.co/storage/v1/object/public/bon-photos/emargement/notices/Lmvrafvw7z70s.pdf', 10),
('Golmar', 'GART1', 'combine', 'Poste audio mains-libres', 'Audio mains-libres, discret et facile',
  '["Mains libres, sans combiné", "Touches sensitives", "Ouverture de 2 portes", "Réglage et coupure de la sonnerie", "Appel palier"]', 60, 10,
  'https://bqzebkobyfktemnwfwbt.supabase.co/storage/v1/object/public/bon-photos/emargement/catalogue/golmar/GART1.jpg',
  'https://bqzebkobyfktemnwfwbt.supabase.co/storage/v1/object/public/bon-photos/emargement/notices/Lmvrafuz2iqeo.pdf', 20),
('Golmar', 'GART4H/XLITE', 'moniteur', 'Moniteur vidéo ART4 mains-libres, écran 4,3"', 'Voir qui sonne avant d''ouvrir',
  '["Écran couleur 4,3\"", "Mains libres", "Boucle magnétique pour malentendants appareillés", "Ouverture automatique", "Ouverture de 2 portes"]', 170, 10,
  'https://bqzebkobyfktemnwfwbt.supabase.co/storage/v1/object/public/bon-photos/emargement/catalogue/golmar/GART4H-XLITE.jpg',
  'https://bqzebkobyfktemnwfwbt.supabase.co/storage/v1/object/public/bon-photos/emargement/notices/Lmvrafvbbaqoa.pdf', 30),
('Golmar', 'GART4TH/LITE', 'moniteur', 'Moniteur vidéo ART4 4,3" mains-libres et à combiné', 'La vidéo, avec le décroché en plus',
  '["Écran couleur 4,3\"", "Combiné pour décrocher comme un téléphone", "Boucle magnétique pour malentendants appareillés", "Ouverture de 2 portes"]', 180, 10,
  'https://bqzebkobyfktemnwfwbt.supabase.co/storage/v1/object/public/bon-photos/emargement/catalogue/golmar/GART4TH-LITE.jpg',
  'https://bqzebkobyfktemnwfwbt.supabase.co/storage/v1/object/public/bon-photos/emargement/notices/Lmvrafvn9utnr.pdf', 40),
('Golmar', 'GART4WH', 'moniteur', 'Moniteur vidéo connecté ART4 mains-libres, écran 4,3"', 'Répondez à l''interphone même absent',
  '["Écran couleur 4,3\"", "Répondre et ouvrir depuis son smartphone (application G2Call+)", "Mémoire d''images et vidéos (carte micro SD non fournie)", "Boucle magnétique"]', 242, 10,
  'https://bqzebkobyfktemnwfwbt.supabase.co/storage/v1/object/public/bon-photos/emargement/catalogue/golmar/GART4WH.jpg',
  'https://bqzebkobyfktemnwfwbt.supabase.co/storage/v1/object/public/bon-photos/emargement/notices/Lmvraftvzwta0.pdf', 50),
('Golmar', 'GART7/LITE', 'moniteur', 'Moniteur vidéo couleur ART7 mains-libres, écran 7"', 'Le confort d''un grand écran',
  '["Grand écran couleur 7\"", "Mains libres", "Mémoire d''images et vidéos (carte micro SD non fournie)", "Boucle magnétique pour malentendants appareillés"]', 242, 10,
  'https://bqzebkobyfktemnwfwbt.supabase.co/storage/v1/object/public/bon-photos/emargement/catalogue/golmar/GART7-LITE.jpg',
  'https://bqzebkobyfktemnwfwbt.supabase.co/storage/v1/object/public/bon-photos/emargement/notices/Lmvraftcv05d4.pdf', 60),
('Golmar', 'GART7W', 'moniteur', 'Moniteur vidéo couleur connecté ART7, écran 7" tactile WiFi', 'Le haut de gamme connecté et tactile',
  '["Écran couleur tactile 7\"", "Répondre et ouvrir depuis son smartphone (application G2Call+)", "Mémoire d''images et vidéos (carte micro SD non fournie)", "WiFi"]', 368, 10,
  'https://bqzebkobyfktemnwfwbt.supabase.co/storage/v1/object/public/bon-photos/emargement/catalogue/golmar/GART7W.jpg',
  'https://bqzebkobyfktemnwfwbt.supabase.co/storage/v1/object/public/bon-photos/emargement/notices/Lmvrafskw4kwl.pdf', 70),
('Golmar', 'PLAQUE-PROPRETE', 'plaque', 'Plaque de propreté blanche', 'Une finition propre, sans travaux de reprise',
  '["Se pose derrière le nouveau poste", "Cache les anciens perçages et les traces de peinture"]', 12, 10, '', '', 80),
('Golmar', 'BADGE-SUPP', 'badge', 'Badge d''accès supplémentaire', 'Un badge de plus pour un membre de la famille',
  '["Badge de proximité Vigik", "Programmé avec vos droits d''accès"]', 9, 10, '', '', 90),
('Golmar', 'PLATINE-SUPRA-2M', 'chantier', 'Platine de rue SUPRA 2 modules (vidéo, Vigik, boutons rétroéclairés)', 'Prix donné pour 6 logements : à ajuster selon la taille',
  '["Caméra couleur HD grand angle, vision nocturne", "Lecteur Vigik intégré", "Boutons d''appel rétroéclairés", "Aluminium anodisé, IP65 / IK08"]', 1657.15, 10, '', '', 200),
('Golmar', 'AFFICADRE-A4', 'chantier', 'Afficadre A4 pour l''affichage des noms', '', '["Clic-clap rabattable", "Finition aluminium"]', 27, 10, '', '', 210),
('Golmar', 'DEPLACEMENT-Z1', 'chantier', 'Déplacement zone 1', '', '[]', 40, 10, '', '', 220)
on conflict (marque, ref) where ref <> '' do nothing;
