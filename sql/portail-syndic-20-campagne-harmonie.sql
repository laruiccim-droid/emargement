-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 20 : la campagne d'information est envoyée par Harmonie
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 19.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Harmonie envoie à chaque propriétaire occupant son lien de rendez-vous depuis le portail admin ;
-- l'envoi est noté sur l'appartement. Le gestionnaire suit les rendez-vous dans son espace, sans envoyer.
-- =====================================================================================

create or replace function public.ps_admin_campagne_invite(p_admin text, p_logement uuid, p_canal text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  update ps_logements set rdv_invite_le = now(), rdv_invite_canal = case when p_canal in ('email', 'sms', 'qr') then p_canal else 'autre' end where id = p_logement;
  return jsonb_build_object('ok', true);
end $$;

-- Le gestionnaire ne note plus lui-même l'envoi de la campagne.
revoke execute on function public.ps_syndic_campagne_envoyee(text, uuid) from public, anon, authenticated;
revoke execute on function public.ps_syndic_campagne_invite(text, uuid, text) from public, anon, authenticated;

revoke execute on function public.ps_admin_campagne_invite(text, uuid, text) from public, anon, authenticated;
grant execute on function public.ps_admin_campagne_invite(text, uuid, text) to anon, authenticated;
