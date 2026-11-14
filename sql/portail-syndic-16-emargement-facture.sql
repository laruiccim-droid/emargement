-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 16 : émargement par appartement et facturation
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 15.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
--  • Le portail admin crée le chantier dans l'app d'émargement à partir du recensement, des bons de
--    commande et des rendez-vous, puis relit l'émargement : chaque appartement reçoit son statut
--    (signé, absent), le numéro et le PDF de son bon d'intervention.
--  • Tous les appartements émargés → « Installation terminée, en attente de facturation ».
--  • Dépôt de la facture → « Facturé, chantier terminé ».
-- emarge = { statut: 'signe' | 'absent', signe_le, absent_le, bon, bon_url, signataire }
-- facture = { url, nom, taille, depose_le }
-- =====================================================================================

alter table public.ps_logements add column if not exists emarge jsonb not null default '{}'::jsonb;
alter table public.ps_copros add column if not exists facture jsonb not null default '{}'::jsonb;

create or replace function public.ps__avancement(c public.ps_copros) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('travaux', c.travaux, 'recensement', c.recensement, 'sondage', c.sondage, 'campagne', c.campagne - 'jeton_public',
    'fourniture', c.fourniture, 'facture', c.facture,
    'nb_logements_saisis', (select count(*) from ps_logements l where l.copro_id = c.id and l.type = 'logement'),
    'nb_invites', (select count(*) from ps_logements l where l.copro_id = c.id and l.type = 'logement' and l.invite_le is not null),
    'nb_commandes', (select count(distinct k.logement_id) from ps_commandes k where k.copro_id = c.id and k.statut = 'signe'),
    'nb_rdv', (select count(distinct r.logement_id) from ps_rdv r where r.copro_id = c.id and r.statut = 'confirme' and r.logement_id is not null),
    'nb_rdv_a_rattacher', (select count(*) from ps_rdv r where r.copro_id = c.id and r.statut = 'confirme' and r.logement_id is null),
    'nb_emarges', (select count(*) from ps_logements l where l.copro_id = c.id and l.type = 'logement' and l.emarge->>'statut' = 'signe'));
$$;

-- Harmonie : préparation du chantier de l'app d'émargement (tout ce qu'il faut, en une lecture).
create or replace function public.ps_admin_preparation_app(p_admin text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return (select jsonb_build_object(
    'copro', jsonb_build_object('id', c.id, 'nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference, 'travaux', c.travaux,
      'marque_interphone', c.marque_interphone, 'marque_vigik', c.marque_vigik, 'chantier_id', c.chantier_id, 'campagne', c.campagne - 'jeton_public', 'vigik', c.vigik),
    'syndic', (select jsonb_build_object('nom', s.nom, 'email', s.email) from ps_syndics s where s.id = c.syndic_id),
    'logements', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'type', l.type, 'numero', l.numero, 'lot', l.lot, 'nom', l.nom,
        'telephone', l.telephone, 'emails', l.emails, 'badges', l.badges,
        'commande', (select ps__commande_json(k) from ps_commandes k where k.logement_id = l.id and k.statut = 'signe' order by k.signe_le desc limit 1),
        'rdv', (select ps__rdv_json(r) from ps_rdv r where r.logement_id = l.id and r.statut = 'confirme' order by r.cree_le desc limit 1))
      order by l.type <> 'logement', l.ordre) from ps_logements l where l.copro_id = c.id), '[]'::jsonb))
  from ps_copros c where c.id = p_copro);
end $$;

-- Harmonie : relier le chantier de l'app (CH_…) au chantier du portail.
create or replace function public.ps_admin_lier_app(p_admin text, p_copro uuid, p_chantier text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  update ps_copros set chantier_id = left(coalesce(p_chantier, ''), 80), maj_le = now() where id = p_copro;
  return jsonb_build_object('ok', true);
end $$;

-- Harmonie : report de l'émargement de l'app dans les appartements.
-- p_items = [{ logement_id, statut, signe_le, absent_le, bon, bon_url, signataire }]
create or replace function public.ps_admin_emargement_maj(p_admin text, p_copro uuid, p_items jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare x jsonb; v_n int; v_s int; v_etat text;
begin
  perform ps__admin(p_admin);
  for x in select * from jsonb_array_elements(case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) loop
    if coalesce(x->>'logement_id', '') !~ '^[0-9a-f-]{36}$' then continue; end if;
    update ps_logements set emarge = case when x->>'statut' in ('signe', 'absent') then jsonb_strip_nulls(jsonb_build_object(
        'statut', x->>'statut', 'signe_le', x->'signe_le', 'absent_le', x->'absent_le', 'bon', left(coalesce(x->>'bon', ''), 40),
        'bon_url', case when coalesce(x->>'bon_url', '') like 'https://%' then x->>'bon_url' end, 'signataire', left(coalesce(x->>'signataire', ''), 120)))
      else '{}'::jsonb end, maj_le = now()
    where id = (x->>'logement_id')::uuid and copro_id = p_copro;
  end loop;
  select count(*), count(*) filter (where emarge->>'statut' = 'signe') into v_n, v_s from ps_logements where copro_id = p_copro and type = 'logement';
  select etat into v_etat from ps_copros where id = p_copro;
  -- Tous les appartements émargés : installation terminée, en attente de facturation.
  if v_n > 0 and v_s >= v_n and v_etat not in ('attente_facturation', 'facture', 'termine') then
    update ps_copros set etat = 'attente_facturation', maj_le = now() where id = p_copro;
    perform ps__log(p_copro, 'Harmonie', 'installation_terminee', jsonb_build_object('emarges', v_s));
  elsif v_s > 0 and v_etat in ('commence', 'livres', 'distribution', 'recensement', 'recensement_termine', 'commande') then
    update ps_copros set etat = 'installation', maj_le = now() where id = p_copro;
  end if;
  return jsonb_build_object('logements', v_n, 'emarges', v_s);
end $$;

-- Harmonie : dépôt (ou retrait) de la facture. p = { url, nom, taille }  ({} : retrait)
create or replace function public.ps_admin_facture(p_admin text, p_copro uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  if coalesce(p->>'url', '') like 'https://%' then
    update ps_copros set facture = jsonb_build_object('url', p->>'url', 'nom', left(coalesce(p->>'nom', 'facture.pdf'), 200),
      'taille', coalesce(nullif(p->>'taille', '')::bigint, 0), 'depose_le', now()), etat = 'facture', maj_le = now() where id = p_copro;
    perform ps__log(p_copro, 'Harmonie', 'facture_deposee', jsonb_build_object('nom', p->>'nom'));
  else
    update ps_copros set facture = '{}'::jsonb, etat = case when etat = 'facture' then 'attente_facturation' else etat end, maj_le = now() where id = p_copro;
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- Suivi de la campagne : avec l'émargement de chaque appartement (bon signé).
create or replace function public.ps__campagne_suivi(p_copro uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'campagne', c.campagne, 'creneaux', ps__creneaux(c), 'facture', c.facture, 'etat', c.etat,
    'copro', jsonb_build_object('id', c.id, 'nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference, 'travaux', c.travaux,
      'marque_interphone', c.marque_interphone, 'marque_vigik', c.marque_vigik),
    'syndic', (select jsonb_build_object('nom', s.nom, 'tel', s.tel, 'email', s.email) from ps_syndics s where s.id = c.syndic_id),
    'logements', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'numero', l.numero, 'lot', l.lot, 'nom', l.nom, 'telephone', l.telephone,
        'emails', l.emails, 'jeton', l.jeton, 'rdv_invite_le', l.rdv_invite_le, 'rdv_invite_canal', l.rdv_invite_canal, 'emarge', l.emarge,
        'commande', (select jsonb_build_object('qualite', k.qualite, 'nom', k.nom, 'prenom', k.prenom, 'telephone', k.telephone, 'email', k.email)
                     from ps_commandes k where k.logement_id = l.id and k.statut = 'signe' order by k.signe_le desc limit 1),
        'rdv', (select ps__rdv_json(r) from ps_rdv r where r.logement_id = l.id and r.statut = 'confirme' order by r.cree_le desc limit 1))
      order by l.ordre) from ps_logements l where l.copro_id = c.id and l.type = 'logement'), '[]'::jsonb),
    'a_rattacher', coalesce((select jsonb_agg(ps__rdv_json(r) order by r.debut) from ps_rdv r where r.copro_id = c.id and r.statut = 'confirme' and r.logement_id is null), '[]'::jsonb),
    'rdv', coalesce((select jsonb_agg(ps__rdv_json(r) || jsonb_build_object('logement', (select l.numero from ps_logements l where l.id = r.logement_id)) order by r.debut)
      from ps_rdv r where r.copro_id = c.id and r.statut = 'confirme'), '[]'::jsonb))
  from ps_copros c where c.id = p_copro;
$$;

revoke execute on function public.ps__avancement(public.ps_copros) from public, anon, authenticated;
revoke execute on function public.ps__campagne_suivi(uuid) from public, anon, authenticated;
revoke execute on function public.ps_admin_preparation_app(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_admin_preparation_app(text, uuid) to anon, authenticated;
revoke execute on function public.ps_admin_lier_app(text, uuid, text) from public, anon, authenticated;
grant execute on function public.ps_admin_lier_app(text, uuid, text) to anon, authenticated;
revoke execute on function public.ps_admin_emargement_maj(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.ps_admin_emargement_maj(text, uuid, jsonb) to anon, authenticated;
revoke execute on function public.ps_admin_facture(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.ps_admin_facture(text, uuid, jsonb) to anon, authenticated;
