-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 6 : droit d'accès Vigik de chaque badge remis
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 5.
-- Ne touche pas à la table « emargements ».
--
--  ps_remises.acces : { "N° de badge": "Nom du droit d'accès", … }  (choisi par le syndic à la remise)
--  ps_badges.droit  : droit d'accès du badge remis (vide en stock)
-- Les droits proposés sont ceux du chantier (ps_copros.vigik, script n° 5).
-- =====================================================================================

alter table public.ps_remises add column if not exists acces jsonb not null default '{}'::jsonb;
alter table public.ps_badges  add column if not exists droit text not null default '';

-- Résumé d'une remise (listes) : avec les droits d'accès.
create or replace function public.ps__remise_resume(r public.ps_remises) returns jsonb
language sql stable as $$
  select jsonb_build_object('id', r.id, 'numero', r.numero, 'statut', r.statut, 'badges', r.badges, 'acces', r.acces, 'lot', r.lot, 'batiment', r.batiment,
    'proprietaire', r.proprietaire, 'qualite', r.qualite, 'email', r.email, 'tel', r.tel, 'commentaire', r.commentaire,
    'nb_photos', jsonb_array_length(r.photos), 'agent_nom', r.agent_nom, 'mode_signature', r.mode_signature, 'signataire', r.signataire,
    'signe_le', r.signe_le, 'annule_le', r.annule_le, 'annule_motif', r.annule_motif, 'controle_acces', r.controle_acces,
    'controle_le', r.controle_le, 'jeton', case when r.statut = 'attente' then r.jeton end, 'cree_le', r.cree_le);
$$;

-- Administrateur : détail d'un chantier (badges avec leur droit d'accès).
create or replace function public.ps_admin_copro_detail(p_admin text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return (select jsonb_build_object(
    'copro', to_jsonb(c) - 'compteur_bons',
    'syndic', (select ps__syndic_public(s) from ps_syndics s where s.id = c.syndic_id),
    'gestionnaire', (select jsonb_build_object('id', u.id, 'nom', u.nom, 'email', u.email) from ps_users u where u.id = c.gestionnaire_id),
    'compteurs', ps__compteurs(c.id),
    'badges', coalesce((select jsonb_agg(jsonb_build_object('numero', b.numero, 'statut', b.statut, 'droit', b.droit, 'remise_id', b.remise_id, 'livraison_id', b.livraison_id) order by b.numero)
                from ps_badges b where b.copro_id = c.id), '[]'::jsonb),
    'livraisons', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'badges', l.badges, 'commentaire', l.commentaire, 'signataire', l.signataire,
                'signature', l.signature, 'signe_le', l.signe_le, 'cree_le', l.cree_le) order by l.cree_le desc) from ps_livraisons l where l.copro_id = c.id), '[]'::jsonb),
    'remises', coalesce((select jsonb_agg(ps__remise_resume(r) order by r.cree_le desc) from ps_remises r where r.copro_id = c.id), '[]'::jsonb))
  from ps_copros c where c.id = p_copro);
end $$;

-- Gestionnaire : chantier avec ses travaux et ses droits d'accès Vigik.
create or replace function public.ps_syndic_copro(p_session text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  return (select jsonb_build_object(
    'copro', jsonb_build_object('id', c.id, 'nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference, 'type', c.type, 'etat', c.etat,
      'travaux', c.travaux, 'vigik', c.vigik),
    'compteurs', ps__compteurs(c.id),
    'badges', coalesce((select jsonb_agg(jsonb_build_object('numero', b.numero, 'statut', b.statut, 'droit', b.droit, 'remise_id', b.remise_id) order by b.numero)
                from ps_badges b where b.copro_id = c.id), '[]'::jsonb),
    'remises', coalesce((select jsonb_agg(ps__remise_resume(r) order by r.cree_le desc) from ps_remises r where r.copro_id = c.id), '[]'::jsonb))
  from ps_copros c where c.id = p_copro);
end $$;

-- Création d'une remise : enregistre le droit d'accès de chaque badge (p.acces).
create or replace function public.ps_syndic_remise_creer(p_session text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; v_copro uuid := (p->>'copro_id')::uuid; v_badges jsonb; v_n int; v_id uuid; v_jeton text := ps__jeton();
  v_signe boolean := coalesce(p->>'signature', '') <> ''; v_compteur int; v_nb_ok int; v_acces jsonb := '{}'::jsonb; v_num text;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(v_copro, u) then raise exception 'INTROUVABLE'; end if;
  select coalesce(jsonb_agg(distinct upper(trim(x))), '[]') into v_badges from jsonb_array_elements_text(coalesce(p->'badges','[]')) x where trim(x) <> '';
  v_n := jsonb_array_length(v_badges);
  if v_n = 0 then raise exception 'AUCUN_BADGE'; end if;
  if coalesce(trim(p->>'proprietaire'), '') = '' then raise exception 'NOM_OBLIGATOIRE'; end if;
  -- droits d'accès : seulement pour les badges de la remise, noms nettoyés
  if jsonb_typeof(p->'acces') = 'object' then
    for v_num in select jsonb_array_elements_text(v_badges) loop
      if coalesce(trim(p->'acces'->>v_num), '') <> '' then v_acces := v_acces || jsonb_build_object(v_num, left(trim(p->'acces'->>v_num), 120)); end if;
    end loop;
  end if;
  perform 1 from ps_badges where copro_id = v_copro and numero in (select jsonb_array_elements_text(v_badges)) for update;
  select count(*) into v_nb_ok from ps_badges where copro_id = v_copro and statut = 'stock' and numero in (select jsonb_array_elements_text(v_badges));
  if v_nb_ok <> v_n then raise exception 'BADGE_INDISPONIBLE'; end if;
  update ps_copros set compteur_bons = compteur_bons + 1 where id = v_copro returning compteur_bons into v_compteur;
  insert into ps_remises (copro_id, syndic_id, numero, jeton, statut, badges, acces, lot, batiment, proprietaire, qualite, email, tel, commentaire, photos,
    agent_id, agent_nom, mode_signature, signataire, signature, signe_le, navigateur, ip)
  values (v_copro, u.syndic_id, 'RB-' || to_char(now(), 'YYYY') || '-' || lpad(v_compteur::text, 3, '0'), v_jeton,
    case when v_signe then 'signe' else 'attente' end, v_badges, v_acces,
    coalesce(p->>'lot',''), coalesce(p->>'batiment',''), trim(p->>'proprietaire'), coalesce(nullif(p->>'qualite',''),'proprietaire'),
    coalesce(p->>'email',''), coalesce(p->>'tel',''), coalesce(p->>'commentaire',''), coalesce(p->'photos','[]'),
    u.id, u.nom, case when v_signe then 'ecran' else '' end,
    case when v_signe then coalesce(nullif(trim(p->>'signataire'),''), trim(p->>'proprietaire')) else '' end,
    coalesce(p->>'signature',''), case when v_signe then now() end,
    case when v_signe then coalesce(p->>'navigateur','') else '' end, case when v_signe then ps__ip() else '' end)
  returning id into v_id;
  update ps_badges set statut = case when v_signe then 'remis' else 'reserve' end, remise_id = v_id, droit = coalesce(v_acces->>numero, ''), maj_le = now()
   where copro_id = v_copro and numero in (select jsonb_array_elements_text(v_badges));
  update ps_copros set etat = case when etat in ('commence','livres') then 'distribution' else etat end, maj_le = now() where id = v_copro;
  perform ps__log(v_copro, u.nom, 'remise_creee', jsonb_build_object('remise', v_id, 'badges', v_badges, 'acces', v_acces, 'signe', v_signe));
  return jsonb_build_object('id', v_id, 'jeton', v_jeton, 'statut', case when v_signe then 'signe' else 'attente' end);
end $$;

-- Annulation : les badges reviennent en stock, sans droit d'accès.
create or replace function public.ps_syndic_remise_annuler(p_session text, p_remise uuid, p_motif text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; r ps_remises;
begin
  u := ps__user(p_session);
  select rr.* into r from ps_remises rr where rr.id = p_remise and ps__copro_visible(rr.copro_id, u) for update;
  if r.id is null then raise exception 'INTROUVABLE'; end if;
  if r.statut = 'annule' then return jsonb_build_object('ok', true); end if;
  if coalesce(trim(p_motif), '') = '' then raise exception 'MOTIF_OBLIGATOIRE'; end if;
  update ps_remises set statut = 'annule', annule_le = now(), annule_motif = trim(p_motif) where id = r.id;
  update ps_badges set statut = 'stock', remise_id = null, droit = '', maj_le = now() where remise_id = r.id and statut in ('reserve','remis');
  perform ps__log(r.copro_id, u.nom, 'remise_annulee', jsonb_build_object('remise', r.id, 'motif', p_motif));
  return jsonb_build_object('ok', true);
end $$;

-- Résident : la page de signature montre aussi le droit d'accès de chaque badge.
create or replace function public.ps_remise_lire(p_jeton text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if p_jeton !~ '^[0-9a-f]{32}$' then raise exception 'LIEN_INVALIDE'; end if;
  return (select jsonb_build_object('numero', r.numero, 'statut', r.statut, 'badges', r.badges, 'acces', r.acces, 'lot', r.lot, 'batiment', r.batiment,
      'proprietaire', r.proprietaire, 'qualite', r.qualite, 'commentaire', r.commentaire, 'signe_le', r.signe_le, 'cree_le', r.cree_le,
      'copro', jsonb_build_object('nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville),
      'syndic', (select jsonb_build_object('nom', s.nom, 'tel', s.tel, 'email', s.email) from ps_syndics s where s.id = coalesce(r.syndic_id, c.syndic_id)))
    from ps_remises r join ps_copros c on c.id = r.copro_id where r.jeton = p_jeton);
end $$;
