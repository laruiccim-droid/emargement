-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 53 : « Relancer la reconnaissance » des interventions à attribuer
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 52.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque. N'envoie aucun e-mail.
--
-- Après avoir créé des cabinets, des gestionnaires ou des mots de reconnaissance, le bouton du
-- portail admin relit les bons des interventions « À attribuer » (e-mail du demandeur, « S/C … »,
-- client, motif) et rattache celles qui sont reconnues.
-- Il donne aussi leur gestionnaire aux interventions d'un cabinet restées sans gestionnaire attitré,
-- quand le demandeur a désormais un espace activé.
-- =====================================================================================

create or replace function public.ps_admin_interventions_reconnaitre(p_admin text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare i ps_interventions; v_texte text; a jsonb; n_ok int := 0; n_reste int := 0; n_gest int := 0;
begin
  perform ps__admin(p_admin);
  for i in select * from ps_interventions where a_attribuer and not ignoree loop
    select concat_ws(' ', i.demandeur, i.titre, i.client,
        string_agg(concat_ws(' ', d.payload->>'email', d.payload->>'adresseFacturation', d.payload->>'client', d.payload->>'motif'), ' '),
        (select string_agg(e->>'titre', ' ') from jsonb_array_elements(i.passages) e))
      into v_texte
    from jsonb_array_elements(i.passages) e join devis d on d.id = e->>'bon';
    a := ps__interv_reconnaitre(v_texte);
    if a->>'syndic' is not null then
      update ps_interventions set syndic_id = (a->>'syndic')::uuid, gestionnaire_id = (a->>'gestionnaire')::uuid, a_attribuer = false, maj_le = now()
      where id = i.id;
      n_ok := n_ok + 1;
    else
      n_reste := n_reste + 1;
    end if;
  end loop;
  -- Demandeur qui a maintenant un espace activé dans le bon cabinet : l'intervention lui revient.
  update ps_interventions x set gestionnaire_id = u.id
  from ps_users u
  where x.gestionnaire_id is null and x.syndic_id is not null and u.syndic_id = x.syndic_id
    and u.actif and u.mdp_hash is not null and lower(u.email) = lower(x.demandeur) and x.demandeur <> '';
  get diagnostics n_gest = row_count;
  return jsonb_build_object('reconnues', n_ok, 'restantes', n_reste, 'gestionnaires', n_gest);
end $$;

revoke execute on function public.ps_admin_interventions_reconnaitre(text) from public, anon, authenticated;
grant execute on function public.ps_admin_interventions_reconnaitre(text) to anon, authenticated;
