-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 19 : suppression d'un gestionnaire
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 18.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Supprime l'accès d'un gestionnaire (réservé à Harmonie). Ce qui reste :
--   • ses chantiers repassent à « tous les gestionnaires du cabinet » ;
--   • les remises de badges qu'il a faites gardent son nom (agent_nom) et leurs signatures ;
--   • ses sessions sont fermées ; une demande de transfert qui le concerne est effacée.
-- =====================================================================================

create or replace function public.ps_admin_user_supprimer(p_admin text, p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v ps_users;
begin
  perform ps__admin(p_admin);
  select * into v from ps_users where id = p_user;
  if v.id is null then raise exception 'INTROUVABLE'; end if;
  update ps_remises set agent_nom = coalesce(nullif(agent_nom, ''), nullif(v.nom, ''), v.email) where agent_id = p_user;
  update ps_copros set transfert_demande = '{}'::jsonb
    where transfert_demande->>'vers' = p_user::text or transfert_demande->>'par' = p_user::text;
  delete from ps_users where id = p_user;
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function public.ps_admin_user_supprimer(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_admin_user_supprimer(text, uuid) to anon, authenticated;
