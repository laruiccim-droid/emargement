-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 22 : circuit des badges d'un chantier complet
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 21.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
--  1. Matériel reçu → fiche de programmation Vigik (appartements, badges commandés, stock, intervenants, droits).
--  2. Harmonie programme les badges dans son logiciel, importe le listing et fait signer la livraison au syndic.
--  3. Le syndic prévient les propriétaires, puis remet les badges appartement par appartement (émargement signé).
--     Remise partielle possible : le reste est réservé au locataire (remis le jour de l'installation).
--  4. Correspondance badges / appartements pour les lier dans le logiciel (J-2 avant l'intervention, ou quand tout est remis).
-- badges_suivi = { programmes_le, prevenus_le, correspondance_le }
-- =====================================================================================

alter table public.ps_remises add column if not exists logement_id uuid references public.ps_logements(id) on delete set null;
alter table public.ps_logements add column if not exists badges_locataire integer not null default 0;
alter table public.ps_copros add column if not exists badges_suivi jsonb not null default '{}'::jsonb;

-- Badges commandés par un appartement (bon de commande signé).
create or replace function public.ps__badges_attendus(p_logement uuid) returns integer
language sql stable security definer set search_path = public as $$
  select coalesce((select sum((x->>'qte')::int) from jsonb_array_elements(k.lignes) x where x->>'type' = 'badge'), 0)::int
  from ps_commandes k where k.logement_id = p_logement and k.statut = 'signe' order by k.signe_le desc limit 1;
$$;

-- Suivi des badges par appartement, hors logements, et correspondance badge → appartement.
create or replace function public.ps__badges_suivi(p_copro uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'suivi', c.badges_suivi, 'campagne', jsonb_build_object('jours', c.campagne->'jours'),
    'copro', jsonb_build_object('id', c.id, 'nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference,
      'travaux', c.travaux, 'marque_vigik', c.marque_vigik, 'vigik', c.vigik),
    'syndic', (select jsonb_build_object('nom', s.nom) from ps_syndics s where s.id = c.syndic_id),
    'compteurs', ps__compteurs(c.id),
    'logements', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'numero', l.numero, 'lot', l.lot, 'nom', l.nom, 'emails', l.emails, 'telephone', l.telephone,
        'attendus', coalesce(ps__badges_attendus(l.id), 0), 'locataire', l.badges_locataire,
        'remis', coalesce((select sum(jsonb_array_length(r.badges)) from ps_remises r where r.logement_id = l.id and r.statut = 'signe'), 0),
        'en_attente', coalesce((select sum(jsonb_array_length(r.badges)) from ps_remises r where r.logement_id = l.id and r.statut = 'attente'), 0),
        'qualite', (select k.qualite from ps_commandes k where k.logement_id = l.id and k.statut = 'signe' order by k.signe_le desc limit 1),
        'rdv', (select r.debut from ps_rdv r where r.logement_id = l.id and r.statut = 'confirme' order by r.cree_le desc limit 1))
      order by l.ordre) from ps_logements l where l.copro_id = c.id and l.type = 'logement'), '[]'::jsonb),
    'hors', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'type', l.type, 'nom', l.nom, 'badges', l.badges) order by l.ordre)
      from ps_logements l where l.copro_id = c.id and l.type <> 'logement'), '[]'::jsonb),
    'correspondance', coalesce((select jsonb_agg(jsonb_build_object('numero', b.numero, 'statut', b.statut, 'droit', b.droit,
        'appartement', (select coalesce(nullif(l.numero, ''), 'lot ' || l.lot) from ps_remises r join ps_logements l on l.id = r.logement_id where r.id = b.remise_id),
        'beneficiaire', (select r.proprietaire from ps_remises r where r.id = b.remise_id)) order by b.numero)
      from ps_badges b where b.copro_id = c.id), '[]'::jsonb))
  from ps_copros c where c.id = p_copro;
$$;

create or replace function public.ps_syndic_badges(p_session text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  return ps__badges_suivi(p_copro);
end $$;

create or replace function public.ps_admin_badges(p_admin text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return ps__badges_suivi(p_copro);
end $$;

-- Gestionnaire : rattacher une remise à un appartement ; reste réservé au locataire.
create or replace function public.ps_syndic_remise_lier(p_session text, p_remise uuid, p_logement uuid, p_reste integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; r ps_remises;
begin
  u := ps__user(p_session);
  select * into r from ps_remises where id = p_remise;
  if r.id is null or not ps__copro_visible(r.copro_id, u) then raise exception 'INTROUVABLE'; end if;
  if not exists (select 1 from ps_logements where id = p_logement and copro_id = r.copro_id) then raise exception 'INTROUVABLE'; end if;
  update ps_remises set logement_id = p_logement where id = p_remise;
  update ps_logements set badges_locataire = least(greatest(coalesce(p_reste, 0), 0), 50), maj_le = now() where id = p_logement;
  return jsonb_build_object('ok', true);
end $$;

-- Gestionnaire : propriétaires prévenus (« passez à l'agence récupérer vos badges »).
create or replace function public.ps_syndic_badges_prevenus(p_session text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  update ps_copros set badges_suivi = badges_suivi || jsonb_build_object('prevenus_le', now()), maj_le = now() where id = p_copro;
  perform ps__log(p_copro, coalesce(nullif(u.nom, ''), u.email), 'badges_prevenus');
  return jsonb_build_object('ok', true);
end $$;

-- Harmonie : badges programmés dans le logiciel / liés aux appartements dans le logiciel.
create or replace function public.ps_admin_badges_jalon(p_admin text, p_copro uuid, p_jalon text, p_fait boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  if p_jalon not in ('programmes', 'correspondance') then raise exception 'INTROUVABLE'; end if;
  update ps_copros set badges_suivi = case when p_fait then badges_suivi || jsonb_build_object(p_jalon || '_le', now()) else badges_suivi - (p_jalon || '_le') end,
    maj_le = now() where id = p_copro;
  perform ps__log(p_copro, 'Harmonie', 'badges_' || p_jalon, jsonb_build_object('fait', p_fait));
  return jsonb_build_object('ok', true);
end $$;

-- Avancement : badges attendus / récupérés par appartement (stock et intervenants exclus).
create or replace function public.ps__avancement(c public.ps_copros) returns jsonb
language sql stable security definer set search_path = public as $$
  with b as (select l.id, coalesce(ps__badges_attendus(l.id), 0) as att, l.badges_locataire as loc,
      coalesce((select sum(jsonb_array_length(r.badges)) from ps_remises r where r.logement_id = l.id and r.statut = 'signe'), 0) as rem
    from ps_logements l where l.copro_id = c.id and l.type = 'logement')
  select jsonb_build_object('travaux', c.travaux, 'recensement', c.recensement, 'sondage', c.sondage, 'campagne', c.campagne - 'jeton_public',
    'fourniture', c.fourniture, 'facture', c.facture, 'transfert_demande', c.transfert_demande, 'badges_suivi', c.badges_suivi,
    'nb_logements_saisis', (select count(*) from ps_logements l where l.copro_id = c.id and l.type = 'logement'),
    'nb_invites', (select count(*) from ps_logements l where l.copro_id = c.id and l.type = 'logement' and l.invite_le is not null),
    'nb_commandes', (select count(distinct k.logement_id) from ps_commandes k where k.copro_id = c.id and k.statut = 'signe'),
    'nb_rdv', (select count(distinct r.logement_id) from ps_rdv r where r.copro_id = c.id and r.statut = 'confirme' and r.logement_id is not null),
    'nb_rdv_a_rattacher', (select count(*) from ps_rdv r where r.copro_id = c.id and r.statut = 'confirme' and r.logement_id is null),
    'nb_emarges', (select count(*) from ps_logements l where l.copro_id = c.id and l.type = 'logement' and l.emarge->>'statut' = 'signe'),
    'nb_badges_attendus', (select count(*) from b where att > 0),
    'nb_badges_ok', (select count(*) from b where att > 0 and rem + loc >= att));
$$;

revoke execute on function public.ps__badges_attendus(uuid) from public, anon, authenticated;
revoke execute on function public.ps__badges_suivi(uuid) from public, anon, authenticated;
revoke execute on function public.ps__avancement(public.ps_copros) from public, anon, authenticated;
revoke execute on function public.ps_syndic_badges(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_syndic_badges(text, uuid) to anon, authenticated;
revoke execute on function public.ps_admin_badges(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_admin_badges(text, uuid) to anon, authenticated;
revoke execute on function public.ps_syndic_remise_lier(text, uuid, uuid, integer) from public, anon, authenticated;
grant execute on function public.ps_syndic_remise_lier(text, uuid, uuid, integer) to anon, authenticated;
revoke execute on function public.ps_syndic_badges_prevenus(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_syndic_badges_prevenus(text, uuid) to anon, authenticated;
revoke execute on function public.ps_admin_badges_jalon(text, uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.ps_admin_badges_jalon(text, uuid, text, boolean) to anon, authenticated;
