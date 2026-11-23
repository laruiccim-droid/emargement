-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 54 : e-mails d'avancement réservés aux comptes activés
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 53.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Un gestionnaire créé dans le portail mais qui n'a pas encore choisi son mot de passe (lien
-- d'invitation) ne reçoit aucun e-mail d'avancement. Ils commencent dès l'activation de son compte.
-- =====================================================================================

create or replace function public.ps__email_gestionnaires(p_syndic uuid, p_gest uuid, p_objet text, p_texte text, p_etape text) returns int
language plpgsql security definer set search_path = public as $$
declare u ps_users; n int := 0;
begin
  if coalesce(current_setting('ps.silence', true), '') = '1' or p_syndic is null then return 0; end if;
  for u in select * from ps_users where syndic_id = p_syndic and actif and mdp_hash is not null and mail_avancement
      and (p_gest is null or id = p_gest)
      and coalesce((mail_etapes->>p_etape)::boolean, ps__mail_etape_defaut(p_etape)) loop
    perform ps__email(u.email, p_objet,
      'Bonjour' || coalesce(' ' || nullif(trim(u.nom), ''), '') || ',' || E'\n\n' || p_texte
      || E'\n\nSuivi en ligne : https://www.harmonie-electricite.com/espace-syndics (« Espace syndics »)'
      || E'\n\nCordialement,\nHarmonie Électricité'
      || E'\n\n—\nVous ne souhaitez plus recevoir ces e-mails d''avancement ? Désactivez-les dans les Paramètres de votre espace syndic.');
    n := n + 1;
  end loop;
  return n;
end $$;

revoke execute on function public.ps__email_gestionnaires(uuid, uuid, text, text, text) from public, anon, authenticated;
