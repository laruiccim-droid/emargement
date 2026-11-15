-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 34 : noms du recensement dans le suivi des badges
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 33.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Émargement des badges (syndic), bloc Badges (admin), remises : le nom affiché est celui que le
-- propriétaire a donné en signant le recensement (prénom nom), et le n° d'appartement qu'il a indiqué
-- quand le fichier du syndic n'en a pas. Une fiche d'appartement modifiée à la main reste prioritaire.
-- =====================================================================================

create or replace function public.ps__badges_suivi(p_copro uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'suivi', c.badges_suivi, 'campagne', jsonb_build_object('jours', c.campagne->'jours'),
    'copro', jsonb_build_object('id', c.id, 'nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference,
      'travaux', c.travaux, 'marque_vigik', c.marque_vigik, 'vigik', c.vigik),
    'syndic', (select jsonb_build_object('nom', s.nom) from ps_syndics s where s.id = c.syndic_id),
    'compteurs', ps__compteurs(c.id),
    'logements', coalesce((select jsonb_agg(jsonb_build_object('id', l.id,
        -- N° d'appartement et nom donnés par le propriétaire au recensement (une fiche modifiée à la main prime).
        'numero', coalesce(nullif(l.numero, ''), nullif(trim(k.numero_appt), ''), ''), 'lot', l.lot,
        'nom', case when l.coord_maj_le is null and coalesce(trim(k.nom), '') <> '' then trim(concat_ws(' ', nullif(trim(k.prenom), ''), trim(k.nom))) else l.nom end,
        'nom_fichier', l.nom, 'emails', l.emails, 'telephone', l.telephone,
        'attendus', coalesce(ps__badges_attendus(l.id), 0), 'locataire', l.badges_locataire, 'supp', l.badges_supp,
        'remis', coalesce((select sum(jsonb_array_length(r.badges)) from ps_remises r where r.logement_id = l.id and r.statut = 'signe'), 0),
        'en_attente', coalesce((select sum(jsonb_array_length(r.badges)) from ps_remises r where r.logement_id = l.id and r.statut = 'attente'), 0),
        'qualite', k.qualite,
        'rdv', (select r.debut from ps_rdv r where r.logement_id = l.id and r.statut = 'confirme' order by r.cree_le desc limit 1))
      order by l.ordre) from ps_logements l
      left join lateral (select x.* from ps_commandes x where x.logement_id = l.id and x.statut = 'signe' order by x.signe_le desc limit 1) k on true
      where l.copro_id = c.id and l.type = 'logement'), '[]'::jsonb),
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

revoke execute on function public.ps__badges_suivi(uuid) from public, anon, authenticated;
