-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 12 : sondage des copropriétaires et bons de commande
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 11.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- 1. Le gestionnaire ouvre le sondage (recensement validé) : chaque appartement reçoit un lien personnel.
-- 2. Le copropriétaire choisit son matériel dans le catalogue de la marque du chantier (prix TTC),
--    la plaque de propreté et ses badges (Vigik), donne ses coordonnées et signe : c'est son bon de commande.
--    Les prix sont recalculés ici depuis le catalogue : la page ne peut pas les modifier.
-- 3. Il peut revenir sur son choix tant que le sondage est ouvert : le nouveau bon remplace l'ancien.
-- =====================================================================================

alter table public.ps_logements add column if not exists jeton text;
create unique index if not exists ps_logements_jeton on public.ps_logements (jeton) where jeton is not null;

-- { ouvert_le, clos_le, texte, par }
alter table public.ps_copros add column if not exists sondage jsonb not null default '{}'::jsonb;

create table if not exists public.ps_commandes (
  id uuid primary key default gen_random_uuid(),
  copro_id uuid not null references public.ps_copros(id) on delete cascade,
  logement_id uuid not null references public.ps_logements(id) on delete cascade,
  numero text not null default '',
  statut text not null default 'signe',        -- signe | remplace | annule
  lignes jsonb not null default '[]',          -- [{ref, nom, type, qte, prix_ht, tva, total_ht, total_ttc}]
  total_ht numeric(10,2) not null default 0,
  total_ttc numeric(10,2) not null default 0,
  nom text not null default '', prenom text not null default '',
  telephone text not null default '', email text not null default '',
  numero_appt text not null default '',
  qualite text not null default 'occupant',    -- occupant | bailleur
  signature text not null default '',
  signe_le timestamptz not null default now(),
  par text not null default 'proprietaire',    -- proprietaire | gestionnaire | harmonie
  ip text not null default '', navigateur text not null default ''
);
create index if not exists ps_commandes_logement on public.ps_commandes (logement_id, signe_le desc);
alter table public.ps_commandes enable row level security;
revoke all on public.ps_commandes from anon, authenticated;

-- Articles proposés au sondage : postes de la marque d'interphone, plaque de propreté, badge supplémentaire.
create or replace function public.ps__articles_sondage(c public.ps_copros) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(a) - 'cree_le' - 'maj_le' - 'actif' order by a.ordre, a.prix_ht), '[]'::jsonb)
  from ps_catalogue a
  where a.actif and (
    (c.travaux <> 'vigik' and a.marque = c.marque_interphone and a.type in ('combine', 'moniteur', 'plaque'))
    or (c.travaux <> 'interphone' and a.type = 'badge' and a.id = (
      select b.id from ps_catalogue b where b.actif and b.type = 'badge'
      order by (b.marque = c.marque_vigik) desc, (b.marque = c.marque_interphone) desc, b.prix_ht limit 1)));
$$;

create or replace function public.ps__commande_json(k public.ps_commandes, avec_signature boolean default false) returns jsonb
language sql stable as $$
  select (to_jsonb(k) - 'ip' - 'navigateur' - 'signature') || case when avec_signature then jsonb_build_object('signature', k.signature) else '{}'::jsonb end;
$$;

-- Gestionnaire : ouvrir (ou rouvrir) le sondage ; un lien personnel par appartement.
create or replace function public.ps_syndic_sondage_ouvrir(p_session text, p_copro uuid, p_texte text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; c ps_copros;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  select * into c from ps_copros where id = p_copro;
  if coalesce(c.recensement->>'etape', '') <> 'pret' then raise exception 'RECENSEMENT_A_VALIDER'; end if;
  update ps_logements set jeton = ps__jeton() where copro_id = p_copro and type = 'logement' and jeton is null;
  update ps_copros set sondage = (sondage - 'clos_le') || jsonb_build_object('ouvert_le', coalesce(sondage->>'ouvert_le', now()::text),
      'texte', left(coalesce(p_texte, ''), 3000), 'par', coalesce(nullif(u.nom, ''), u.email)), maj_le = now()
  where id = p_copro;
  perform ps__log(p_copro, coalesce(nullif(u.nom, ''), u.email), 'sondage_ouvert');
  return jsonb_build_object('ok', true);
end $$;

-- Gestionnaire : clore le sondage (plus aucune réponse par les liens).
create or replace function public.ps_syndic_sondage_clore(p_session text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  update ps_copros set sondage = sondage || jsonb_build_object('clos_le', now()), maj_le = now() where id = p_copro;
  perform ps__log(p_copro, coalesce(nullif(u.nom, ''), u.email), 'sondage_clos');
  return jsonb_build_object('ok', true);
end $$;

-- Suivi du sondage (gestionnaire et administrateur).
create or replace function public.ps__sondage_suivi(p_copro uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'sondage', c.sondage, 'articles', ps__articles_sondage(c),
    'copro', jsonb_build_object('id', c.id, 'nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference,
      'travaux', c.travaux, 'marque_interphone', c.marque_interphone, 'marque_vigik', c.marque_vigik, 'recensement', c.recensement),
    'logements', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'numero', l.numero, 'lot', l.lot, 'nom', l.nom, 'telephone', l.telephone,
        'emails', l.emails, 'jeton', l.jeton,
        'commande', (select ps__commande_json(k) from ps_commandes k where k.logement_id = l.id and k.statut = 'signe' order by k.signe_le desc limit 1))
      order by l.ordre) from ps_logements l where l.copro_id = c.id and l.type = 'logement'), '[]'::jsonb))
  from ps_copros c where c.id = p_copro;
$$;

create or replace function public.ps_syndic_sondage(p_session text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  return ps__sondage_suivi(p_copro);
end $$;

create or replace function public.ps_admin_sondage(p_admin text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return ps__sondage_suivi(p_copro);
end $$;

-- Bon de commande complet (avec la signature), pour le PDF.
create or replace function public.ps_syndic_commande(p_session text, p_commande uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; k ps_commandes;
begin
  u := ps__user(p_session);
  select * into k from ps_commandes where id = p_commande;
  if k.id is null or not ps__copro_visible(k.copro_id, u) then raise exception 'INTROUVABLE'; end if;
  return ps__commande_json(k, true) || jsonb_build_object('copro', (select jsonb_build_object('nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference) from ps_copros c where c.id = k.copro_id));
end $$;

create or replace function public.ps_admin_commande(p_admin text, p_commande uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k ps_commandes;
begin
  perform ps__admin(p_admin);
  select * into k from ps_commandes where id = p_commande;
  if k.id is null then raise exception 'INTROUVABLE'; end if;
  return ps__commande_json(k, true) || jsonb_build_object('copro', (select jsonb_build_object('nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference) from ps_copros c where c.id = k.copro_id));
end $$;

-- Copropriétaire : ouvrir son lien personnel.
create or replace function public.ps_sondage_lire(p_jeton text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l ps_logements; c ps_copros;
begin
  if coalesce(p_jeton, '') !~ '^[0-9a-f]{32}$' then raise exception 'LIEN_INVALIDE'; end if;
  select * into l from ps_logements where jeton = p_jeton;
  if l.id is null then raise exception 'LIEN_INVALIDE'; end if;
  select * into c from ps_copros where id = l.copro_id;
  return jsonb_build_object(
    'copro', jsonb_build_object('nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'travaux', c.travaux,
      'marque_interphone', c.marque_interphone, 'marque_vigik', c.marque_vigik),
    'syndic', (select jsonb_build_object('nom', s.nom) from ps_syndics s where s.id = c.syndic_id),
    'texte', coalesce(c.sondage->>'texte', ''), 'ouvert', c.sondage ? 'ouvert_le' and not (c.sondage ? 'clos_le'),
    'logement', jsonb_build_object('numero', l.numero, 'lot', l.lot, 'nom', l.nom, 'telephone', l.telephone, 'emails', l.emails),
    'articles', ps__articles_sondage(c),
    'commande', (select ps__commande_json(k) from ps_commandes k where k.logement_id = l.id and k.statut = 'signe' order by k.signe_le desc limit 1));
end $$;

-- Copropriétaire : signer son bon de commande.
-- p = { lignes: [{ref, qte}], nom, prenom, telephone, email, numero_appt, qualite, signature }
create or replace function public.ps_sondage_signer(p_jeton text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l ps_logements; c ps_copros; x jsonb; a jsonb; v_lignes jsonb := '[]'; v_qte int; v_ht numeric := 0; v_ttc numeric := 0;
  v_lht numeric; v_lttc numeric; v_postes int := 0; k ps_commandes; v_num int;
begin
  if coalesce(p_jeton, '') !~ '^[0-9a-f]{32}$' then raise exception 'LIEN_INVALIDE'; end if;
  select * into l from ps_logements where jeton = p_jeton;
  if l.id is null then raise exception 'LIEN_INVALIDE'; end if;
  select * into c from ps_copros where id = l.copro_id;
  if not (c.sondage ? 'ouvert_le') or c.sondage ? 'clos_le' then raise exception 'SONDAGE_CLOS'; end if;
  if coalesce(trim(p->>'nom'), '') = '' or coalesce(trim(p->>'prenom'), '') = '' or coalesce(trim(p->>'telephone'), '') = '' then raise exception 'NOM_OBLIGATOIRE'; end if;
  if coalesce(p->>'qualite', '') not in ('occupant', 'bailleur') then raise exception 'QUALITE_OBLIGATOIRE'; end if;
  if p->>'qualite' = 'occupant' and coalesce(trim(p->>'numero_appt'), '') = '' then raise exception 'APPARTEMENT_OBLIGATOIRE'; end if;
  if coalesce(p->>'signature', '') !~ '^data:image/png;base64,' or length(p->>'signature') > 800000 then raise exception 'SIGNATURE_INVALIDE'; end if;

  for x in select * from jsonb_array_elements(case when jsonb_typeof(p->'lignes') = 'array' then p->'lignes' else '[]'::jsonb end) loop
    v_qte := least(greatest(coalesce(nullif(x->>'qte', '')::int, 0), 0), 20);
    if v_qte = 0 then continue; end if;
    a := null;
    select e into a from jsonb_array_elements(ps__articles_sondage(c)) e where e->>'ref' = x->>'ref' limit 1;
    if a is null then raise exception 'ARTICLE_INCONNU'; end if;
    v_lht := round((a->>'prix_ht')::numeric * v_qte, 2);
    v_lttc := round(v_lht * (1 + (a->>'tva')::numeric / 100), 2);
    v_ht := v_ht + v_lht; v_ttc := v_ttc + v_lttc;
    if a->>'type' in ('combine', 'moniteur') then v_postes := v_postes + v_qte; end if;
    v_lignes := v_lignes || jsonb_build_array(jsonb_build_object('ref', a->>'ref', 'nom', a->>'nom', 'type', a->>'type', 'marque', a->>'marque', 'qte', v_qte,
      'prix_ht', (a->>'prix_ht')::numeric, 'tva', (a->>'tva')::numeric, 'total_ht', v_lht, 'total_ttc', v_lttc));
  end loop;
  if c.travaux <> 'vigik' and v_postes = 0 then raise exception 'POSTE_OBLIGATOIRE'; end if;

  update ps_commandes set statut = 'remplace' where logement_id = l.id and statut = 'signe';
  select count(*) + 1 into v_num from ps_commandes where copro_id = c.id;
  insert into ps_commandes (copro_id, logement_id, numero, lignes, total_ht, total_ttc, nom, prenom, telephone, email, numero_appt, qualite, signature, ip, navigateur)
  values (c.id, l.id, 'BC-' || coalesce(nullif(regexp_replace(c.reference, '[^A-Za-z0-9]', '', 'g'), ''), upper(left(replace(c.id::text, '-', ''), 6))) || '-' || lpad(v_num::text, 3, '0'),
    v_lignes, v_ht, v_ttc, left(trim(p->>'nom'), 80), left(trim(p->>'prenom'), 80), left(trim(p->>'telephone'), 30), left(lower(trim(coalesce(p->>'email', ''))), 120),
    left(trim(coalesce(p->>'numero_appt', '')), 30), p->>'qualite', p->>'signature', ps__ip(), left(coalesce(p->>'navigateur', ''), 300))
  returning * into k;
  perform ps__log(c.id, trim(p->>'prenom') || ' ' || trim(p->>'nom'), 'commande_signee', jsonb_build_object('logement', l.numero, 'numero', k.numero, 'total_ttc', v_ttc));
  return ps__commande_json(k, true) || jsonb_build_object('copro', jsonb_build_object('nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference),
    'logement', jsonb_build_object('numero', l.numero, 'lot', l.lot));
end $$;

-- Gestionnaire : la fiche du chantier indique aussi l'état du sondage et le nombre de bons signés.
create or replace function public.ps_syndic_copro(p_session text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  return (select jsonb_build_object(
    'copro', jsonb_build_object('id', c.id, 'nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference, 'type', c.type, 'etat', c.etat,
      'travaux', c.travaux, 'vigik', c.vigik, 'marque_interphone', c.marque_interphone, 'marque_vigik', c.marque_vigik, 'recensement', c.recensement, 'sondage', c.sondage,
      'nb_logements_saisis', (select count(*) from ps_logements l where l.copro_id = c.id and l.type = 'logement'),
      'nb_commandes', (select count(distinct k.logement_id) from ps_commandes k where k.copro_id = c.id and k.statut = 'signe')),
    'compteurs', ps__compteurs(c.id),
    'badges', coalesce((select jsonb_agg(jsonb_build_object('numero', b.numero, 'statut', b.statut, 'droit', b.droit, 'remise_id', b.remise_id) order by b.numero)
                from ps_badges b where b.copro_id = c.id), '[]'::jsonb),
    'remises', coalesce((select jsonb_agg(ps__remise_resume(r) order by r.cree_le desc) from ps_remises r where r.copro_id = c.id), '[]'::jsonb))
  from ps_copros c where c.id = p_copro);
end $$;

revoke execute on function public.ps__articles_sondage(public.ps_copros) from public, anon, authenticated;
revoke execute on function public.ps__commande_json(public.ps_commandes, boolean) from public, anon, authenticated;
revoke execute on function public.ps__sondage_suivi(uuid) from public, anon, authenticated;
revoke execute on function public.ps_syndic_sondage_ouvrir(text, uuid, text) from public, anon, authenticated;
grant execute on function public.ps_syndic_sondage_ouvrir(text, uuid, text) to anon, authenticated;
revoke execute on function public.ps_syndic_sondage_clore(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_syndic_sondage_clore(text, uuid) to anon, authenticated;
revoke execute on function public.ps_syndic_sondage(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_syndic_sondage(text, uuid) to anon, authenticated;
revoke execute on function public.ps_admin_sondage(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_admin_sondage(text, uuid) to anon, authenticated;
revoke execute on function public.ps_syndic_commande(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_syndic_commande(text, uuid) to anon, authenticated;
revoke execute on function public.ps_admin_commande(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_admin_commande(text, uuid) to anon, authenticated;
revoke execute on function public.ps_sondage_lire(text) from public, anon, authenticated;
grant execute on function public.ps_sondage_lire(text) to anon, authenticated;
revoke execute on function public.ps_sondage_signer(text, jsonb) from public, anon, authenticated;
grant execute on function public.ps_sondage_signer(text, jsonb) to anon, authenticated;
