-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 28 : propriétaire et locataire modifiables dans la fiche appartement
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 27.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Changement de propriétaire ou de locataire : la fiche de l'appartement est corrigée (gestionnaire ou
-- Harmonie) ; le nom affiché sur l'interphone suit. Harmonie reporte ensuite les changements dans le
-- chantier de l'app d'émargement, qui régénère la fiche interphone et la codification.
-- =====================================================================================

alter table public.ps_logements add column if not exists nom_affiche text not null default '';
alter table public.ps_logements add column if not exists locataire jsonb not null default '{}'::jsonb;
alter table public.ps_logements add column if not exists coord_maj_le timestamptz;

-- p = { nom, telephone, emails[], nom_affiche, locataire: { nom, prenom, telephone, email } }
create or replace function public.ps__appartement_maj(p_logement uuid, p jsonb, p_par text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l ps_logements; v_emails jsonb; v_loc jsonb;
begin
  select * into l from ps_logements where id = p_logement and type = 'logement';
  if l.id is null then raise exception 'INTROUVABLE'; end if;
  if coalesce(trim(p->>'nom'), '') = '' then raise exception 'NOM_OBLIGATOIRE'; end if;
  select coalesce(jsonb_agg(distinct lower(trim(e))), '[]'::jsonb) into v_emails
    from jsonb_array_elements_text(case when jsonb_typeof(p->'emails') = 'array' then p->'emails' else '[]'::jsonb end) e
    where trim(e) ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$';
  v_loc := case when jsonb_typeof(p->'locataire') = 'object' and coalesce(trim(p->'locataire'->>'nom'), '') <> '' then jsonb_build_object(
      'nom', left(trim(p->'locataire'->>'nom'), 80), 'prenom', left(coalesce(trim(p->'locataire'->>'prenom'), ''), 80),
      'telephone', left(coalesce(trim(p->'locataire'->>'telephone'), ''), 30), 'email', left(lower(coalesce(trim(p->'locataire'->>'email'), '')), 120))
    else '{}'::jsonb end;
  update ps_logements set nom = left(trim(p->>'nom'), 120), telephone = left(coalesce(trim(p->>'telephone'), ''), 30), emails = v_emails,
    nom_affiche = left(upper(coalesce(trim(p->>'nom_affiche'), '')), 60), locataire = v_loc, coord_maj_le = now(), maj_le = now()
  where id = p_logement;
  perform ps__log(l.copro_id, p_par, 'appartement_modifie', jsonb_build_object('logement', l.numero, 'lot', l.lot,
    'avant', jsonb_build_object('nom', l.nom, 'locataire', l.locataire, 'nom_affiche', l.nom_affiche), 'apres', p - 'emails'));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ps_syndic_appartement_maj(p_session text, p_logement uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; v_copro uuid;
begin
  u := ps__user(p_session);
  select copro_id into v_copro from ps_logements where id = p_logement;
  if v_copro is null or not ps__copro_visible(v_copro, u) then raise exception 'INTROUVABLE'; end if;
  return ps__appartement_maj(p_logement, p, coalesce(nullif(u.nom, ''), u.email));
end $$;

create or replace function public.ps_admin_appartement_maj(p_admin text, p_logement uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return ps__appartement_maj(p_logement, p, 'Harmonie');
end $$;

create or replace function public.ps__appartements(p_copro uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'copro', jsonb_build_object('id', c.id, 'nom', c.nom, 'marque_interphone', c.marque_interphone, 'marque_vigik', c.marque_vigik, 'travaux', c.travaux),
    'logements', coalesce((select jsonb_agg(jsonb_build_object(
        'id', l.id, 'numero', l.numero, 'lot', l.lot, 'nom', l.nom, 'telephone', l.telephone, 'emails', l.emails,
        'badges_locataire', l.badges_locataire, 'emarge', l.emarge, 'badges_supp', l.badges_supp, 'badges_supp_hist', l.badges_supp_hist, 'invite_le', l.invite_le, 'nom_affiche', l.nom_affiche, 'locataire', l.locataire, 'coord_maj_le', l.coord_maj_le, 'attendus', coalesce(ps__badges_attendus(l.id), 0),
        'commande', (select ps__commande_json(k) from ps_commandes k where k.logement_id = l.id and k.statut = 'signe' order by k.signe_le desc limit 1),
        'rdv', (select ps__rdv_json(r) from ps_rdv r where r.logement_id = l.id and r.statut = 'confirme' order by r.cree_le desc limit 1),
        'remises', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'numero', r.numero, 'statut', r.statut, 'badges', r.badges,
            'proprietaire', r.proprietaire, 'qualite', r.qualite, 'mode', r.mode_signature, 'signe_le', r.signe_le, 'cree_le', r.cree_le) order by r.cree_le)
          from ps_remises r where r.logement_id = l.id and r.statut <> 'annule'), '[]'::jsonb))
      order by l.ordre) from ps_logements l where l.copro_id = c.id and l.type = 'logement'), '[]'::jsonb))
  from ps_copros c where c.id = p_copro;
$$;

create or replace function public.ps_admin_preparation_app(p_admin text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return (select jsonb_build_object(
    'copro', jsonb_build_object('id', c.id, 'nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference, 'travaux', c.travaux,
      'marque_interphone', c.marque_interphone, 'marque_vigik', c.marque_vigik, 'chantier_id', c.chantier_id, 'campagne', c.campagne - 'jeton_public', 'vigik', c.vigik),
    'syndic', (select jsonb_build_object('nom', s.nom, 'email', s.email) from ps_syndics s where s.id = c.syndic_id),
    'logements', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'type', l.type, 'numero', l.numero, 'lot', l.lot, 'nom', l.nom,
        'telephone', l.telephone, 'emails', l.emails, 'badges', l.badges, 'nom_affiche', l.nom_affiche, 'locataire', l.locataire, 'coord_maj_le', l.coord_maj_le,
        'commande', (select ps__commande_json(k) from ps_commandes k where k.logement_id = l.id and k.statut = 'signe' order by k.signe_le desc limit 1),
        'rdv', (select ps__rdv_json(r) from ps_rdv r where r.logement_id = l.id and r.statut = 'confirme' order by r.cree_le desc limit 1))
      order by l.type <> 'logement', l.ordre) from ps_logements l where l.copro_id = c.id), '[]'::jsonb))
  from ps_copros c where c.id = p_copro);
end $$;

revoke execute on function public.ps__appartement_maj(uuid, jsonb, text) from public, anon, authenticated;
revoke execute on function public.ps__appartements(uuid) from public, anon, authenticated;
revoke execute on function public.ps_syndic_appartement_maj(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.ps_syndic_appartement_maj(text, uuid, jsonb) to anon, authenticated;
revoke execute on function public.ps_admin_appartement_maj(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.ps_admin_appartement_maj(text, uuid, jsonb) to anon, authenticated;
revoke execute on function public.ps_admin_preparation_app(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_admin_preparation_app(text, uuid) to anon, authenticated;
