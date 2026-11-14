-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 13 : avancement des chantiers dans les listes
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 12.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Les listes de chantiers (portail admin et espace syndic) reçoivent ce qu'il faut pour dessiner
-- la frise d'avancement : travaux, recensement (étiquettes, fichier), sondage, nombre de bons signés.
-- =====================================================================================

create or replace function public.ps__avancement(c public.ps_copros) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('travaux', c.travaux, 'recensement', c.recensement, 'sondage', c.sondage,
    'nb_logements_saisis', (select count(*) from ps_logements l where l.copro_id = c.id and l.type = 'logement'),
    'nb_commandes', (select count(distinct k.logement_id) from ps_commandes k where k.copro_id = c.id and k.statut = 'signe'));
$$;

create or replace function public.ps_admin_etat(p_admin text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return jsonb_build_object(
    'syndics', coalesce((select jsonb_agg(ps__syndic_public(s) || jsonb_build_object(
        'users', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'nom', u.nom, 'email', u.email, 'tel', u.tel, 'actif', u.actif,
            'statut', case when not u.actif then 'desactive' when u.mdp_hash is not null then 'actif' else 'invite' end,
            'invitation', case when u.mdp_hash is null and u.invitation_expire > now() then u.invitation end,
            'invitation_expire', u.invitation_expire, 'active_le', u.active_le, 'derniere_connexion', u.derniere_connexion) order by u.nom)
          from ps_users u where u.syndic_id = s.id), '[]'::jsonb)) order by s.nom) from ps_syndics s), '[]'::jsonb),
    'copros', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville,
        'reference', c.reference, 'type', c.type, 'etat', c.etat, 'syndic_id', c.syndic_id, 'gestionnaire_id', c.gestionnaire_id, 'chantier_id', c.chantier_id, 'notes', c.notes,
        'cree_le', c.cree_le, 'compteurs', ps__compteurs(c.id)) || ps__avancement(c) order by c.cree_le desc) from ps_copros c), '[]'::jsonb));
end $$;

create or replace function public.ps_syndic_etat(p_session text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  return jsonb_build_object(
    'user', jsonb_build_object('id', u.id, 'nom', u.nom, 'email', u.email, 'tel', u.tel),
    'syndic', (select ps__syndic_public(s) from ps_syndics s where s.id = u.syndic_id),
    'copros', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville,
        'reference', c.reference, 'type', c.type, 'etat', c.etat, 'compteurs', ps__compteurs(c.id)) || ps__avancement(c) order by c.nom)
      from ps_copros c where c.syndic_id = u.syndic_id and (c.gestionnaire_id is null or c.gestionnaire_id = u.id)), '[]'::jsonb));
end $$;

revoke execute on function public.ps__avancement(public.ps_copros) from public, anon, authenticated;
revoke execute on function public.ps_admin_etat(text) from public, anon, authenticated;
grant execute on function public.ps_admin_etat(text) to anon, authenticated;
revoke execute on function public.ps_syndic_etat(text) from public, anon, authenticated;
grant execute on function public.ps_syndic_etat(text) to anon, authenticated;
