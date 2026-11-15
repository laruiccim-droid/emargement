-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 30 : suppression d'un syndic
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 29.
-- Peut être relancé sans risque.
--
-- Réservé à Harmonie (portail admin). Supprime le cabinet et ses gestionnaires (et leurs sessions).
--  • Sans chantier rattaché : suppression directe.
--  • Avec des chantiers : refus, sauf si Harmonie demande explicitement de supprimer aussi les chantiers
--    (et tout ce qui en dépend, y compris le chantier correspondant dans l'app d'émargement).
-- =====================================================================================

create or replace function public.ps_admin_syndic_supprimer(p_admin text, p_syndic uuid, p_avec_chantiers boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nb int;
begin
  perform ps__admin(p_admin);
  if not exists (select 1 from ps_syndics where id = p_syndic) then raise exception 'INTROUVABLE'; end if;
  select count(*) into v_nb from ps_copros where syndic_id = p_syndic;
  if v_nb > 0 and not coalesce(p_avec_chantiers, false) then raise exception 'SYNDIC_A_DES_CHANTIERS'; end if;
  if v_nb > 0 then
    delete from emargements where id in (select chantier_id from ps_copros where syndic_id = p_syndic and coalesce(chantier_id, '') <> '');
    delete from ps_copros where syndic_id = p_syndic;
  end if;
  delete from ps_users where syndic_id = p_syndic;
  delete from ps_syndics where id = p_syndic;
  return jsonb_build_object('ok', true, 'chantiers_supprimes', v_nb);
end $$;

revoke execute on function public.ps_admin_syndic_supprimer(text, uuid, boolean) from public, anon, authenticated;
grant execute on function public.ps_admin_syndic_supprimer(text, uuid, boolean) to anon, authenticated;
