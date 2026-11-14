-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 2 : supprimer une livraison de badges (mauvais fichier importé)
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après sql/portail-syndic.sql.
-- Ajout pur : une fonction de plus, rien d'existant n'est modifié.
--
-- Les badges de la livraison encore « en stock » sont retirés. Ceux déjà réservés ou remis à un
-- résident sont gardés (la livraison reste alors avec ces seuls badges) : une remise signée n'est
-- jamais effacée.
-- =====================================================================================

create or replace function public.ps_admin_livraison_supprimer(p_admin text, p_livraison uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_copro uuid; v_retires int; v_gardes jsonb;
begin
  perform ps__admin(p_admin);
  select copro_id into v_copro from ps_livraisons where id = p_livraison for update;
  if v_copro is null then raise exception 'INTROUVABLE'; end if;
  select coalesce(jsonb_agg(numero order by numero), '[]'::jsonb) into v_gardes
    from ps_badges where livraison_id = p_livraison and statut <> 'stock';
  delete from ps_badges where livraison_id = p_livraison and statut = 'stock';
  get diagnostics v_retires = row_count;
  if jsonb_array_length(v_gardes) = 0 then
    delete from ps_livraisons where id = p_livraison;
  else
    update ps_livraisons set badges = v_gardes,
      commentaire = trim(coalesce(commentaire, '') || ' (badges non remis supprimés le ' || to_char(now(), 'DD/MM/YYYY') || ')')
    where id = p_livraison;
  end if;
  perform ps__log(v_copro, 'Harmonie', 'livraison_supprimee', jsonb_build_object('livraison', p_livraison, 'retires', v_retires, 'gardes', v_gardes));
  return jsonb_build_object('retires', v_retires, 'gardes', v_gardes);
end $$;

revoke execute on function public.ps_admin_livraison_supprimer(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_admin_livraison_supprimer(text, uuid) to anon, authenticated;
