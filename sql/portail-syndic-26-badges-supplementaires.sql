-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 26 : badges supplémentaires
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 25.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Un propriétaire ou un locataire demande un ou plusieurs badges en plus : depuis la fiche de
-- l'appartement, on les lui attribue sur le stock du syndic. Ils s'ajoutent aux badges à remettre
-- de l'appartement (la remise se fait comme d'habitude, avec signature) et sont listés pour la facturation.
-- =====================================================================================

alter table public.ps_logements add column if not exists badges_supp integer not null default 0;
alter table public.ps_logements add column if not exists badges_supp_hist jsonb not null default '[]'::jsonb;

-- Badges attendus par un appartement : bon de commande + badges supplémentaires.
create or replace function public.ps__badges_attendus(p_logement uuid) returns integer
language sql stable security definer set search_path = public as $$
  select (coalesce((select sum((x->>'qte')::int) from ps_commandes k, jsonb_array_elements(k.lignes) x
      where k.id = (select k2.id from ps_commandes k2 where k2.logement_id = p_logement and k2.statut = 'signe' order by k2.signe_le desc limit 1)
        and x->>'type' = 'badge'), 0)
    + coalesce((select l.badges_supp from ps_logements l where l.id = p_logement), 0))::int;
$$;

create or replace function public.ps__badges_supp(p_logement uuid, p_nb integer, p_pour text, p_motif text, p_par text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l ps_logements;
begin
  select * into l from ps_logements where id = p_logement and type = 'logement';
  if l.id is null then raise exception 'INTROUVABLE'; end if;
  if coalesce(p_nb, 0) < 1 or p_nb > 20 then raise exception 'INTROUVABLE'; end if;
  update ps_logements set badges_supp = badges_supp + p_nb,
    badges_supp_hist = badges_supp_hist || jsonb_build_array(jsonb_build_object('nb', p_nb, 'pour', case when p_pour = 'locataire' then 'locataire' else 'proprietaire' end,
      'motif', left(coalesce(p_motif, ''), 300), 'le', now(), 'par', p_par)), maj_le = now()
  where id = p_logement;
  -- Pris sur le stock du syndic.
  update ps_logements set badges = greatest(0, badges - p_nb), maj_le = now() where copro_id = l.copro_id and type = 'stock';
  perform ps__log(l.copro_id, p_par, 'badges_supplementaires', jsonb_build_object('logement', l.numero, 'lot', l.lot, 'nb', p_nb, 'pour', p_pour));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ps_syndic_badges_supp(p_session text, p_logement uuid, p_nb integer, p_pour text, p_motif text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; v_copro uuid;
begin
  u := ps__user(p_session);
  select copro_id into v_copro from ps_logements where id = p_logement;
  if v_copro is null or not ps__copro_visible(v_copro, u) then raise exception 'INTROUVABLE'; end if;
  return ps__badges_supp(p_logement, p_nb, p_pour, p_motif, coalesce(nullif(u.nom, ''), u.email));
end $$;

create or replace function public.ps_admin_badges_supp(p_admin text, p_logement uuid, p_nb integer, p_pour text, p_motif text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return ps__badges_supp(p_logement, p_nb, p_pour, p_motif, 'Harmonie');
end $$;

create or replace function public.ps__appartements(p_copro uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'copro', jsonb_build_object('id', c.id, 'nom', c.nom, 'marque_interphone', c.marque_interphone, 'marque_vigik', c.marque_vigik, 'travaux', c.travaux),
    'logements', coalesce((select jsonb_agg(jsonb_build_object(
        'id', l.id, 'numero', l.numero, 'lot', l.lot, 'nom', l.nom, 'telephone', l.telephone, 'emails', l.emails,
        'badges_locataire', l.badges_locataire, 'emarge', l.emarge, 'badges_supp', l.badges_supp, 'badges_supp_hist', l.badges_supp_hist,
        'commande', (select ps__commande_json(k) from ps_commandes k where k.logement_id = l.id and k.statut = 'signe' order by k.signe_le desc limit 1),
        'rdv', (select ps__rdv_json(r) from ps_rdv r where r.logement_id = l.id and r.statut = 'confirme' order by r.cree_le desc limit 1),
        'remises', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'numero', r.numero, 'statut', r.statut, 'badges', r.badges,
            'proprietaire', r.proprietaire, 'qualite', r.qualite, 'mode', r.mode_signature, 'signe_le', r.signe_le, 'cree_le', r.cree_le) order by r.cree_le)
          from ps_remises r where r.logement_id = l.id and r.statut <> 'annule'), '[]'::jsonb))
      order by l.ordre) from ps_logements l where l.copro_id = c.id and l.type = 'logement'), '[]'::jsonb))
  from ps_copros c where c.id = p_copro;
$$;

-- Suivi des badges : avec les badges supplémentaires (facturation).
create or replace function public.ps__badges_suivi(p_copro uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'suivi', c.badges_suivi, 'campagne', jsonb_build_object('jours', c.campagne->'jours'),
    'copro', jsonb_build_object('id', c.id, 'nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference,
      'travaux', c.travaux, 'marque_vigik', c.marque_vigik, 'vigik', c.vigik),
    'syndic', (select jsonb_build_object('nom', s.nom) from ps_syndics s where s.id = c.syndic_id),
    'compteurs', ps__compteurs(c.id),
    'logements', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'numero', l.numero, 'lot', l.lot, 'nom', l.nom, 'emails', l.emails, 'telephone', l.telephone,
        'attendus', coalesce(ps__badges_attendus(l.id), 0), 'locataire', l.badges_locataire, 'supp', l.badges_supp,
        'remis', coalesce((select sum(jsonb_array_length(r.badges)) from ps_remises r where r.logement_id = l.id and r.statut = 'signe'), 0),
        'en_attente', coalesce((select sum(jsonb_array_length(r.badges)) from ps_remises r where r.logement_id = l.id and r.statut = 'attente'), 0),
        'qualite', (select k.qualite from ps_commandes k where k.logement_id = l.id and k.statut = 'signe' order by k.signe_le desc limit 1),
        'rdv', (select r.debut from ps_rdv r where r.logement_id = l.id and r.statut = 'confirme' order by r.cree_le desc limit 1))
      order by l.ordre) from ps_logements l where l.copro_id = c.id and l.type = 'logement'), '[]'::jsonb),
    'hors', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'type', l.type, 'nom', l.nom, 'badges', l.badges,
        'remis', coalesce((select sum(jsonb_array_length(r.badges)) from ps_remises r where r.logement_id = l.id and r.statut = 'signe'), 0),
        'en_attente', coalesce((select sum(jsonb_array_length(r.badges)) from ps_remises r where r.logement_id = l.id and r.statut = 'attente'), 0)) order by l.ordre)
      from ps_logements l where l.copro_id = c.id and l.type <> 'logement'), '[]'::jsonb),
    'correspondance', coalesce((select jsonb_agg(jsonb_build_object('numero', b.numero, 'statut', b.statut, 'droit', b.droit,
        'appartement', (select case when l.type <> 'logement' then l.nom else coalesce(nullif(l.numero, ''), nullif('lot ' || l.lot, 'lot '), l.nom) end
                        from ps_remises r join ps_logements l on l.id = r.logement_id where r.id = b.remise_id),
        'beneficiaire', (select r.proprietaire from ps_remises r where r.id = b.remise_id)) order by b.numero)
      from ps_badges b where b.copro_id = c.id), '[]'::jsonb))
  from ps_copros c where c.id = p_copro;
$$;

revoke execute on function public.ps__badges_attendus(uuid) from public, anon, authenticated;
revoke execute on function public.ps__badges_suivi(uuid) from public, anon, authenticated;
revoke execute on function public.ps__badges_supp(uuid, integer, text, text, text) from public, anon, authenticated;
revoke execute on function public.ps__appartements(uuid) from public, anon, authenticated;
revoke execute on function public.ps_syndic_badges_supp(text, uuid, integer, text, text) from public, anon, authenticated;
grant execute on function public.ps_syndic_badges_supp(text, uuid, integer, text, text) to anon, authenticated;
revoke execute on function public.ps_admin_badges_supp(text, uuid, integer, text, text) from public, anon, authenticated;
grant execute on function public.ps_admin_badges_supp(text, uuid, integer, text, text) to anon, authenticated;
