-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 18 : demande de transfert d'un chantier entre gestionnaires
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 17.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
--  • Vers un autre syndic : seul Harmonie transfère (portail admin, inchangé).
--  • Vers un autre gestionnaire du même syndic : Harmonie transfère directement ; le gestionnaire,
--    lui, fait une demande que Harmonie valide (ou refuse) dans le portail admin.
-- transfert_demande = { vers, vers_nom, par, par_nom, motif, demande_le }   ({} : aucune demande)
-- =====================================================================================

alter table public.ps_copros add column if not exists transfert_demande jsonb not null default '{}'::jsonb;

-- Gestionnaire : collègues du même cabinet (pour choisir à qui transférer).
create or replace function public.ps_syndic_collegues(p_session text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  return coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'nom', coalesce(nullif(x.nom, ''), x.email)) order by x.nom)
    from ps_users x where x.syndic_id = u.syndic_id and x.actif and x.id <> u.id), '[]'::jsonb);
end $$;

-- Gestionnaire : demander le transfert d'un chantier à un collègue du même cabinet.
create or replace function public.ps_syndic_transfert_demander(p_session text, p_copro uuid, p_vers uuid, p_motif text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; v ps_users;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  select * into v from ps_users where id = p_vers;
  if v.id is null or v.syndic_id is distinct from u.syndic_id or not v.actif then raise exception 'GESTIONNAIRE_AUTRE_SYNDIC'; end if;
  update ps_copros set transfert_demande = jsonb_build_object('vers', v.id, 'vers_nom', coalesce(nullif(v.nom, ''), v.email),
      'par', u.id, 'par_nom', coalesce(nullif(u.nom, ''), u.email), 'motif', left(coalesce(p_motif, ''), 500), 'demande_le', now()), maj_le = now()
  where id = p_copro;
  perform ps__log(p_copro, coalesce(nullif(u.nom, ''), u.email), 'transfert_demande', jsonb_build_object('vers', v.id, 'vers_nom', coalesce(nullif(v.nom, ''), v.email)));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ps_syndic_transfert_annuler(p_session text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  update ps_copros set transfert_demande = '{}'::jsonb, maj_le = now() where id = p_copro;
  return jsonb_build_object('ok', true);
end $$;

-- Harmonie : valider ou refuser la demande.
create or replace function public.ps_admin_transfert_decider(p_admin text, p_copro uuid, p_accepter boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c ps_copros; v_vers uuid;
begin
  perform ps__admin(p_admin);
  select * into c from ps_copros where id = p_copro for update;
  if c.id is null or coalesce(c.transfert_demande->>'vers', '') = '' then raise exception 'INTROUVABLE'; end if;
  v_vers := (c.transfert_demande->>'vers')::uuid;
  if p_accepter then
    if not exists (select 1 from ps_users where id = v_vers and syndic_id = c.syndic_id) then raise exception 'GESTIONNAIRE_AUTRE_SYNDIC'; end if;
    update ps_copros set gestionnaire_id = v_vers, transfert_demande = '{}'::jsonb, maj_le = now() where id = p_copro;
  else
    update ps_copros set transfert_demande = '{}'::jsonb, maj_le = now() where id = p_copro;
  end if;
  perform ps__log(p_copro, 'Harmonie', case when p_accepter then 'transfert_valide' else 'transfert_refuse' end, c.transfert_demande);
  return jsonb_build_object('ok', true);
end $$;

-- Transfert direct par Harmonie (script n° 3) : efface aussi une demande en attente.
create or replace function public.ps_admin_copro_transferer(p_admin text, p_copro uuid, p_syndic uuid, p_gestionnaire uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c ps_copros; v_nom_s text; v_nom_g text;
begin
  perform ps__admin(p_admin);
  select * into c from ps_copros where id = p_copro for update;
  if c.id is null then raise exception 'INTROUVABLE'; end if;
  if p_syndic is null or not exists (select 1 from ps_syndics where id = p_syndic) then raise exception 'INTROUVABLE'; end if;
  if p_gestionnaire is not null and not exists (select 1 from ps_users where id = p_gestionnaire and syndic_id = p_syndic) then
    raise exception 'GESTIONNAIRE_AUTRE_SYNDIC';
  end if;
  update ps_copros set syndic_id = p_syndic, gestionnaire_id = p_gestionnaire, transfert_demande = '{}'::jsonb, maj_le = now() where id = p_copro;
  select nom into v_nom_s from ps_syndics where id = p_syndic;
  select coalesce(nullif(nom, ''), email) into v_nom_g from ps_users where id = p_gestionnaire;
  perform ps__log(p_copro, 'Harmonie', 'transfert', jsonb_build_object(
    'syndic_avant', c.syndic_id, 'gestionnaire_avant', c.gestionnaire_id,
    'syndic', p_syndic, 'syndic_nom', v_nom_s, 'gestionnaire', p_gestionnaire, 'gestionnaire_nom', coalesce(v_nom_g, 'tout le cabinet')));
  return jsonb_build_object('ok', true);
end $$;

-- Listes : la demande de transfert en attente accompagne chaque chantier.
create or replace function public.ps__avancement(c public.ps_copros) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('travaux', c.travaux, 'recensement', c.recensement, 'sondage', c.sondage, 'campagne', c.campagne - 'jeton_public',
    'fourniture', c.fourniture, 'facture', c.facture, 'transfert_demande', c.transfert_demande,
    'nb_logements_saisis', (select count(*) from ps_logements l where l.copro_id = c.id and l.type = 'logement'),
    'nb_invites', (select count(*) from ps_logements l where l.copro_id = c.id and l.type = 'logement' and l.invite_le is not null),
    'nb_commandes', (select count(distinct k.logement_id) from ps_commandes k where k.copro_id = c.id and k.statut = 'signe'),
    'nb_rdv', (select count(distinct r.logement_id) from ps_rdv r where r.copro_id = c.id and r.statut = 'confirme' and r.logement_id is not null),
    'nb_rdv_a_rattacher', (select count(*) from ps_rdv r where r.copro_id = c.id and r.statut = 'confirme' and r.logement_id is null),
    'nb_emarges', (select count(*) from ps_logements l where l.copro_id = c.id and l.type = 'logement' and l.emarge->>'statut' = 'signe'));
$$;

revoke execute on function public.ps__avancement(public.ps_copros) from public, anon, authenticated;
revoke execute on function public.ps_syndic_collegues(text) from public, anon, authenticated;
grant execute on function public.ps_syndic_collegues(text) to anon, authenticated;
revoke execute on function public.ps_syndic_transfert_demander(text, uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.ps_syndic_transfert_demander(text, uuid, uuid, text) to anon, authenticated;
revoke execute on function public.ps_syndic_transfert_annuler(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_syndic_transfert_annuler(text, uuid) to anon, authenticated;
revoke execute on function public.ps_admin_transfert_decider(text, uuid, boolean) from public, anon, authenticated;
grant execute on function public.ps_admin_transfert_decider(text, uuid, boolean) to anon, authenticated;
revoke execute on function public.ps_admin_copro_transferer(text, uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.ps_admin_copro_transferer(text, uuid, uuid, uuid) to anon, authenticated;
