-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 39 : étape « feuille d'information affichée dans la résidence »
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 38.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- La campagne d'information se fait en deux temps : envoi des liens de rendez-vous par e-mail
-- (campagne.envoyee_le, posé automatiquement par « Tout envoyer par e-mail »), puis affichage de la
-- feuille dans la résidence (campagne.affichee_le, nouveau jalon « affichage »).
-- Chantiers dont la campagne est déjà notée envoyée : considérés comme affichés (ancien bouton unique).
-- =====================================================================================

create or replace function public.ps_admin_jalon(p_admin text, p_copro uuid, p_jalon text, p_fait boolean, p_info text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  if p_jalon = 'etiquettes' then
    update ps_copros set recensement = case when p_fait then recensement || jsonb_build_object('etiquettes_le', now(), 'etiquettes_par', 'Harmonie')
      else recensement - 'etiquettes_le' - 'etiquettes_par' end, maj_le = now() where id = p_copro;
  elsif p_jalon = 'campagne' then
    update ps_copros set campagne = case when p_fait then campagne || jsonb_build_object('envoyee_le', now()) else campagne - 'envoyee_le' end, maj_le = now() where id = p_copro;
  elsif p_jalon = 'affichage' then
    update ps_copros set campagne = case when p_fait then campagne || jsonb_build_object('affichee_le', now()) else campagne - 'affichee_le' end, maj_le = now() where id = p_copro;
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

update public.ps_copros set campagne = campagne || jsonb_build_object('affichee_le', campagne->>'envoyee_le')
where campagne ? 'envoyee_le' and not campagne ? 'affichee_le';

revoke execute on function public.ps_admin_jalon(text, uuid, text, boolean, text) from public, anon, authenticated;
grant execute on function public.ps_admin_jalon(text, uuid, text, boolean, text) to anon, authenticated;
