-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 15 : campagne d'information et prise de rendez-vous
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 14.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- 1. Harmonie fixe les jours d'intervention (heures, durée d'un rendez-vous, nombre d'équipes).
-- 2. Le gestionnaire envoie à chaque propriétaire occupant son lien de rendez-vous et affiche
--    la feuille (QR code) dans les parties communes pour les locataires.
-- 3. Chacun choisit un créneau. Un locataire est rattaché à l'appartement par son numéro ;
--    sinon le gestionnaire le rattache à la main.
-- campagne = { planifiee_le, envoyee_le, jours: [{date, debut, fin}], duree, capacite, message, jeton_public }
-- fourniture = { envoyee_le, fournisseur, recu_le } : commande du matériel au fournisseur, puis réception.
-- =====================================================================================

alter table public.ps_copros add column if not exists fourniture jsonb not null default '{}'::jsonb;
alter table public.ps_logements add column if not exists rdv_invite_le timestamptz;
alter table public.ps_logements add column if not exists rdv_invite_canal text not null default '';

create table if not exists public.ps_rdv (
  id uuid primary key default gen_random_uuid(),
  copro_id uuid not null references public.ps_copros(id) on delete cascade,
  logement_id uuid references public.ps_logements(id) on delete set null,
  debut timestamptz not null,
  fin timestamptz not null,
  statut text not null default 'confirme',     -- confirme | remplace | annule
  nom text not null default '', prenom text not null default '',
  telephone text not null default '', email text not null default '',
  numero_appt text not null default '',
  qualite text not null default 'occupant',     -- occupant | locataire
  source text not null default 'lien',          -- lien | affiche | gestionnaire | harmonie
  cree_le timestamptz not null default now(),
  ip text not null default ''
);
create index if not exists ps_rdv_copro on public.ps_rdv (copro_id, debut);
alter table public.ps_rdv enable row level security;
revoke all on public.ps_rdv from anon, authenticated;

-- Créneaux de l'intervention, avec les places restantes (heure de Paris), à venir uniquement.
create or replace function public.ps__creneaux(c public.ps_copros) returns jsonb
language sql stable security definer set search_path = public as $$
  with p as (select greatest(coalesce(nullif(c.campagne->>'duree', '')::int, 30), 10) as dur,
                    greatest(coalesce(nullif(c.campagne->>'capacite', '')::int, 1), 1) as cap),
  j as (select (x->>'date')::date as d, (x->>'debut')::time as hd, (x->>'fin')::time as hf
        from jsonb_array_elements(case when jsonb_typeof(c.campagne->'jours') = 'array' then c.campagne->'jours' else '[]'::jsonb end) x
        where coalesce(x->>'date', '') <> '' and coalesce(x->>'debut', '') <> '' and coalesce(x->>'fin', '') <> ''),
  s as (select (t at time zone 'Europe/Paris') as debut, p.dur, p.cap
        from j, p, generate_series(j.d + j.hd, j.d + j.hf - make_interval(mins => p.dur), make_interval(mins => p.dur)) t)
  select coalesce(jsonb_agg(jsonb_build_object('debut', s.debut, 'fin', s.debut + make_interval(mins => s.dur),
      'places', s.cap - (select count(*) from ps_rdv r where r.copro_id = c.id and r.statut = 'confirme' and r.debut = s.debut)) order by s.debut), '[]'::jsonb)
  from s where s.debut > now();
$$;

create or replace function public.ps__rdv_json(r public.ps_rdv) returns jsonb
language sql stable as $$ select to_jsonb(r) - 'ip'; $$;

-- Données d'avancement : avec les rendez-vous.
create or replace function public.ps__avancement(c public.ps_copros) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('travaux', c.travaux, 'recensement', c.recensement, 'sondage', c.sondage, 'campagne', c.campagne - 'jeton_public', 'fourniture', c.fourniture,
    'nb_logements_saisis', (select count(*) from ps_logements l where l.copro_id = c.id and l.type = 'logement'),
    'nb_invites', (select count(*) from ps_logements l where l.copro_id = c.id and l.type = 'logement' and l.invite_le is not null),
    'nb_commandes', (select count(distinct k.logement_id) from ps_commandes k where k.copro_id = c.id and k.statut = 'signe'),
    'nb_rdv', (select count(distinct r.logement_id) from ps_rdv r where r.copro_id = c.id and r.statut = 'confirme' and r.logement_id is not null),
    'nb_rdv_a_rattacher', (select count(*) from ps_rdv r where r.copro_id = c.id and r.statut = 'confirme' and r.logement_id is null));
$$;

-- Suivi de la campagne (gestionnaire et Harmonie).
create or replace function public.ps__campagne_suivi(p_copro uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'campagne', c.campagne, 'creneaux', ps__creneaux(c),
    'copro', jsonb_build_object('id', c.id, 'nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference, 'travaux', c.travaux,
      'marque_interphone', c.marque_interphone, 'marque_vigik', c.marque_vigik),
    'syndic', (select jsonb_build_object('nom', s.nom, 'tel', s.tel, 'email', s.email) from ps_syndics s where s.id = c.syndic_id),
    'logements', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'numero', l.numero, 'lot', l.lot, 'nom', l.nom, 'telephone', l.telephone,
        'emails', l.emails, 'jeton', l.jeton, 'rdv_invite_le', l.rdv_invite_le, 'rdv_invite_canal', l.rdv_invite_canal,
        'commande', (select jsonb_build_object('qualite', k.qualite, 'nom', k.nom, 'prenom', k.prenom, 'telephone', k.telephone, 'email', k.email)
                     from ps_commandes k where k.logement_id = l.id and k.statut = 'signe' order by k.signe_le desc limit 1),
        'rdv', (select ps__rdv_json(r) from ps_rdv r where r.logement_id = l.id and r.statut = 'confirme' order by r.cree_le desc limit 1))
      order by l.ordre) from ps_logements l where l.copro_id = c.id and l.type = 'logement'), '[]'::jsonb),
    'a_rattacher', coalesce((select jsonb_agg(ps__rdv_json(r) order by r.debut) from ps_rdv r where r.copro_id = c.id and r.statut = 'confirme' and r.logement_id is null), '[]'::jsonb),
    'rdv', coalesce((select jsonb_agg(ps__rdv_json(r) || jsonb_build_object('logement', (select l.numero from ps_logements l where l.id = r.logement_id)) order by r.debut)
      from ps_rdv r where r.copro_id = c.id and r.statut = 'confirme'), '[]'::jsonb))
  from ps_copros c where c.id = p_copro;
$$;

-- ---------- Harmonie ----------
create or replace function public.ps_admin_campagne(p_admin text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return ps__campagne_suivi(p_copro);
end $$;

-- Jours d'intervention : p = { jours: [{date, debut, fin}], duree, capacite, message }
create or replace function public.ps_admin_campagne_planifier(p_admin text, p_copro uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_jours jsonb;
begin
  perform ps__admin(p_admin);
  select coalesce(jsonb_agg(jsonb_build_object('date', x->>'date', 'debut', x->>'debut', 'fin', x->>'fin') order by x->>'date', x->>'debut'), '[]'::jsonb) into v_jours
    from jsonb_array_elements(case when jsonb_typeof(p->'jours') = 'array' then p->'jours' else '[]'::jsonb end) x
    where (x->>'date') ~ '^\d{4}-\d{2}-\d{2}$' and (x->>'debut') ~ '^\d{2}:\d{2}$' and (x->>'fin') ~ '^\d{2}:\d{2}$' and (x->>'fin') > (x->>'debut');
  update ps_copros set campagne = campagne || jsonb_build_object('jours', v_jours,
      'duree', least(greatest(coalesce(nullif(p->>'duree', '')::int, 30), 10), 480),
      'capacite', least(greatest(coalesce(nullif(p->>'capacite', '')::int, 1), 1), 20),
      'message', left(coalesce(p->>'message', ''), 2000),
      'planifiee_le', coalesce(campagne->>'planifiee_le', now()::text),
      'jeton_public', coalesce(campagne->>'jeton_public', ps__jeton())), maj_le = now()
  where id = p_copro;
  perform ps__log(p_copro, 'Harmonie', 'campagne_planifiee', jsonb_build_object('jours', v_jours));
  return ps__campagne_suivi(p_copro);
end $$;

-- Commande du matériel au fournisseur, puis réception ; et étiquettes (validées par Harmonie).
-- p_jalon = 'etiquettes' | 'campagne' | 'fourniture_envoyee' | 'fourniture_recue'
create or replace function public.ps_admin_jalon(p_admin text, p_copro uuid, p_jalon text, p_fait boolean, p_info text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  if p_jalon = 'etiquettes' then
    update ps_copros set recensement = case when p_fait then recensement || jsonb_build_object('etiquettes_le', now(), 'etiquettes_par', 'Harmonie')
      else recensement - 'etiquettes_le' - 'etiquettes_par' end, maj_le = now() where id = p_copro;
  elsif p_jalon = 'campagne' then
    update ps_copros set campagne = case when p_fait then campagne || jsonb_build_object('envoyee_le', now()) else campagne - 'envoyee_le' end, maj_le = now() where id = p_copro;
  elsif p_jalon = 'fourniture_envoyee' then
    update ps_copros set fourniture = case when p_fait then fourniture || jsonb_build_object('envoyee_le', now(), 'fournisseur', left(coalesce(p_info, ''), 200))
      else fourniture - 'envoyee_le' - 'recu_le' end,
      etat = case when p_fait and etat in ('commence', 'livres', 'distribution', 'recensement', 'recensement_termine') then 'commande' else etat end, maj_le = now() where id = p_copro;
  elsif p_jalon = 'fourniture_recue' then
    update ps_copros set fourniture = case when p_fait then fourniture || jsonb_build_object('recu_le', now()) else fourniture - 'recu_le' end, maj_le = now() where id = p_copro;
  else raise exception 'INTROUVABLE';
  end if;
  perform ps__log(p_copro, 'Harmonie', 'jalon_' || p_jalon, jsonb_build_object('fait', p_fait, 'info', p_info));
  return jsonb_build_object('ok', true);
end $$;
drop function if exists public.ps_admin_jalon(text, uuid, text, boolean);

-- ---------- Gestionnaire ----------
create or replace function public.ps_syndic_campagne(p_session text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  return ps__campagne_suivi(p_copro);
end $$;

create or replace function public.ps_syndic_campagne_invite(p_session text, p_logement uuid, p_canal text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; v_copro uuid;
begin
  u := ps__user(p_session);
  select copro_id into v_copro from ps_logements where id = p_logement;
  if v_copro is null or not ps__copro_visible(v_copro, u) then raise exception 'INTROUVABLE'; end if;
  update ps_logements set rdv_invite_le = now(), rdv_invite_canal = case when p_canal in ('email', 'sms', 'qr') then p_canal else 'autre' end where id = p_logement;
  return jsonb_build_object('ok', true);
end $$;

-- Campagne envoyée et feuille affichée (étape de la barre d'avancement).
create or replace function public.ps_syndic_campagne_envoyee(p_session text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  update ps_copros set campagne = campagne || jsonb_build_object('envoyee_le', now()), maj_le = now() where id = p_copro;
  perform ps__log(p_copro, coalesce(nullif(u.nom, ''), u.email), 'campagne_envoyee');
  return jsonb_build_object('ok', true);
end $$;

-- Rattacher un rendez-vous de locataire à un appartement (numéro non reconnu), ou l'annuler.
create or replace function public.ps__rdv_rattacher(p_rdv uuid, p_logement uuid, p_par text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r ps_rdv;
begin
  select * into r from ps_rdv where id = p_rdv;
  if r.id is null or not exists (select 1 from ps_logements l where l.id = p_logement and l.copro_id = r.copro_id) then raise exception 'INTROUVABLE'; end if;
  update ps_rdv set statut = 'remplace' where logement_id = p_logement and statut = 'confirme' and id <> p_rdv;
  update ps_rdv set logement_id = p_logement where id = p_rdv;
  perform ps__log(r.copro_id, p_par, 'rdv_rattache', jsonb_build_object('rdv', p_rdv, 'logement', p_logement));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ps_syndic_rdv_rattacher(p_session text, p_rdv uuid, p_logement uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; v_copro uuid;
begin
  u := ps__user(p_session);
  select copro_id into v_copro from ps_rdv where id = p_rdv;
  if v_copro is null or not ps__copro_visible(v_copro, u) then raise exception 'INTROUVABLE'; end if;
  return ps__rdv_rattacher(p_rdv, p_logement, coalesce(nullif(u.nom, ''), u.email));
end $$;

create or replace function public.ps_admin_rdv_rattacher(p_admin text, p_rdv uuid, p_logement uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return ps__rdv_rattacher(p_rdv, p_logement, 'Harmonie');
end $$;

create or replace function public.ps_syndic_rdv_annuler(p_session text, p_rdv uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; v_copro uuid;
begin
  u := ps__user(p_session);
  select copro_id into v_copro from ps_rdv where id = p_rdv;
  if v_copro is null or not ps__copro_visible(v_copro, u) then raise exception 'INTROUVABLE'; end if;
  update ps_rdv set statut = 'annule' where id = p_rdv;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ps_admin_rdv_annuler(p_admin text, p_rdv uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  update ps_rdv set statut = 'annule' where id = p_rdv;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- Page publique de rendez-vous ----------
-- p_jeton : lien personnel d'un appartement (propriétaire occupant) ou jeton de la feuille d'affichage (locataires).
create or replace function public.ps_rdv_lire(p_jeton text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l ps_logements; c ps_copros;
begin
  if coalesce(p_jeton, '') !~ '^[0-9a-f]{32}$' then raise exception 'LIEN_INVALIDE'; end if;
  select * into l from ps_logements where jeton = p_jeton;
  if l.id is not null then select * into c from ps_copros where id = l.copro_id;
  else select * into c from ps_copros where campagne->>'jeton_public' = p_jeton; end if;
  if c.id is null then raise exception 'LIEN_INVALIDE'; end if;
  return jsonb_build_object(
    'mode', case when l.id is null then 'affiche' else 'lien' end,
    'copro', jsonb_build_object('nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'travaux', c.travaux),
    'syndic', (select jsonb_build_object('nom', s.nom) from ps_syndics s where s.id = c.syndic_id),
    'message', coalesce(c.campagne->>'message', ''), 'jours', coalesce(c.campagne->'jours', '[]'::jsonb), 'duree', c.campagne->'duree',
    'creneaux', ps__creneaux(c),
    'logement', case when l.id is null then null else jsonb_build_object('numero', l.numero, 'lot', l.lot,
      'contact', (select jsonb_build_object('nom', k.nom, 'prenom', k.prenom, 'telephone', k.telephone, 'email', k.email, 'qualite', k.qualite)
                  from ps_commandes k where k.logement_id = l.id and k.statut = 'signe' order by k.signe_le desc limit 1)) end,
    'rdv', case when l.id is null then null else (select ps__rdv_json(r) from ps_rdv r where r.logement_id = l.id and r.statut = 'confirme' order by r.cree_le desc limit 1) end);
end $$;

-- Réserver : p = { debut, nom, prenom, telephone, email, numero_appt }
create or replace function public.ps_rdv_reserver(p_jeton text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l ps_logements; c ps_copros; v_debut timestamptz; e jsonb; v_lg uuid; v_mode text; r ps_rdv; v_num text; v_ancien uuid;
begin
  if coalesce(p_jeton, '') !~ '^[0-9a-f]{32}$' then raise exception 'LIEN_INVALIDE'; end if;
  select * into l from ps_logements where jeton = p_jeton;
  if l.id is not null then select * into c from ps_copros where id = l.copro_id; v_mode := 'lien';
  else select * into c from ps_copros where campagne->>'jeton_public' = p_jeton; v_mode := 'affiche'; end if;
  if c.id is null then raise exception 'LIEN_INVALIDE'; end if;
  if coalesce(trim(p->>'nom'), '') = '' or coalesce(trim(p->>'prenom'), '') = '' then raise exception 'NOM_OBLIGATOIRE'; end if;
  v_num := left(trim(coalesce(p->>'numero_appt', '')), 30);
  if v_mode = 'affiche' then
    if coalesce(trim(p->>'telephone'), '') = '' then raise exception 'TELEPHONE_OBLIGATOIRE'; end if;
    if v_num = '' then raise exception 'APPARTEMENT_OBLIGATOIRE'; end if;
    -- Rattachement automatique par le numéro de l'étiquette blanche.
    select id into v_lg from ps_logements where copro_id = c.id and type = 'logement'
      and lower(regexp_replace(numero, '\s+', '', 'g')) = lower(regexp_replace(v_num, '\s+', '', 'g')) limit 1;
  else
    v_lg := l.id; v_num := coalesce(nullif(v_num, ''), l.numero);
  end if;
  v_debut := (p->>'debut')::timestamptz;
  select x into e from jsonb_array_elements(ps__creneaux(c)) x where (x->>'debut')::timestamptz = v_debut limit 1;
  if e is null then raise exception 'CRENEAU_INDISPONIBLE'; end if;
  select id into v_ancien from ps_rdv where v_lg is not null and logement_id = v_lg and statut = 'confirme' and debut = v_debut limit 1;
  if (e->>'places')::int <= 0 and v_ancien is null then raise exception 'CRENEAU_COMPLET'; end if;
  if v_lg is not null then update ps_rdv set statut = 'remplace' where logement_id = v_lg and statut = 'confirme'; end if;
  insert into ps_rdv (copro_id, logement_id, debut, fin, nom, prenom, telephone, email, numero_appt, qualite, source, ip)
  values (c.id, v_lg, v_debut, (e->>'fin')::timestamptz, left(trim(p->>'nom'), 80), left(trim(p->>'prenom'), 80),
    left(trim(coalesce(p->>'telephone', '')), 30), left(lower(trim(coalesce(p->>'email', ''))), 120), v_num,
    case when v_mode = 'lien' then 'occupant' else 'locataire' end, v_mode, ps__ip())
  returning * into r;
  perform ps__log(c.id, trim(p->>'prenom') || ' ' || trim(p->>'nom'), 'rdv_pris', jsonb_build_object('appartement', v_num, 'debut', v_debut, 'rattache', v_lg is not null));
  return ps__rdv_json(r) || jsonb_build_object('rattache', v_lg is not null);
end $$;

revoke execute on function public.ps__creneaux(public.ps_copros) from public, anon, authenticated;
revoke execute on function public.ps__rdv_json(public.ps_rdv) from public, anon, authenticated;
revoke execute on function public.ps__avancement(public.ps_copros) from public, anon, authenticated;
revoke execute on function public.ps__campagne_suivi(uuid) from public, anon, authenticated;
revoke execute on function public.ps__rdv_rattacher(uuid, uuid, text) from public, anon, authenticated;
revoke execute on function public.ps_admin_jalon(text, uuid, text, boolean, text) from public, anon, authenticated;
grant execute on function public.ps_admin_jalon(text, uuid, text, boolean, text) to anon, authenticated;
revoke execute on function public.ps_admin_campagne(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_admin_campagne(text, uuid) to anon, authenticated;
revoke execute on function public.ps_admin_campagne_planifier(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.ps_admin_campagne_planifier(text, uuid, jsonb) to anon, authenticated;
revoke execute on function public.ps_syndic_campagne(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_syndic_campagne(text, uuid) to anon, authenticated;
revoke execute on function public.ps_syndic_campagne_invite(text, uuid, text) from public, anon, authenticated;
grant execute on function public.ps_syndic_campagne_invite(text, uuid, text) to anon, authenticated;
revoke execute on function public.ps_syndic_campagne_envoyee(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_syndic_campagne_envoyee(text, uuid) to anon, authenticated;
revoke execute on function public.ps_syndic_rdv_rattacher(text, uuid, uuid) from public, anon, authenticated;
grant execute on function public.ps_syndic_rdv_rattacher(text, uuid, uuid) to anon, authenticated;
revoke execute on function public.ps_admin_rdv_rattacher(text, uuid, uuid) from public, anon, authenticated;
grant execute on function public.ps_admin_rdv_rattacher(text, uuid, uuid) to anon, authenticated;
revoke execute on function public.ps_syndic_rdv_annuler(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_syndic_rdv_annuler(text, uuid) to anon, authenticated;
revoke execute on function public.ps_admin_rdv_annuler(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_admin_rdv_annuler(text, uuid) to anon, authenticated;
revoke execute on function public.ps_rdv_lire(text) from public, anon, authenticated;
grant execute on function public.ps_rdv_lire(text) to anon, authenticated;
revoke execute on function public.ps_rdv_reserver(text, jsonb) from public, anon, authenticated;
grant execute on function public.ps_rdv_reserver(text, jsonb) to anon, authenticated;
