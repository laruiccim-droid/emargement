-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 4 : supprimer un chantier
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 3.
-- Ajout pur : une fonction de plus, rien d'existant n'est modifié ; ne touche pas à « emargements ».
--
-- Supprime définitivement le chantier et, par cascade, ses livraisons, son stock de badges,
-- ses remises (signées ou non) et son historique. Réservé à l'administrateur.
-- =====================================================================================

create or replace function public.ps_admin_copro_supprimer(p_admin text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nom text;
begin
  perform ps__admin(p_admin);
  delete from ps_copros where id = p_copro returning nom into v_nom;
  if v_nom is null then raise exception 'INTROUVABLE'; end if;
  return jsonb_build_object('ok', true, 'nom', v_nom);
end $$;

revoke execute on function public.ps_admin_copro_supprimer(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_admin_copro_supprimer(text, uuid) to anon, authenticated;
