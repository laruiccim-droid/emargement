-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 23 : badges remis au locataire le jour de l'installation
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 22.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Dans l'app d'émargement, le technicien choisit les badges laissés au locataire parmi les badges
-- restant à distribuer. À la relecture de l'émargement, ces badges passent « remis » sur l'appartement
-- (remise signée « installation »), et la correspondance badges / appartements est complète.
-- =====================================================================================

create or replace function public.ps_admin_emargement_maj(p_admin text, p_copro uuid, p_items jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare x jsonb; v_n int; v_s int; v_etat text; v_b jsonb; v_r uuid;
begin
  perform ps__admin(p_admin);
  for x in select * from jsonb_array_elements(case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) loop
    if coalesce(x->>'logement_id', '') !~ '^[0-9a-f-]{36}$' then continue; end if;
    update ps_logements set emarge = case when x->>'statut' in ('signe', 'absent') then jsonb_strip_nulls(jsonb_build_object(
        'statut', x->>'statut', 'signe_le', x->'signe_le', 'absent_le', x->'absent_le', 'bon', left(coalesce(x->>'bon', ''), 40),
        'bon_url', case when coalesce(x->>'bon_url', '') like 'https://%' then x->>'bon_url' end, 'signataire', left(coalesce(x->>'signataire', ''), 120)))
      else '{}'::jsonb end, maj_le = now()
    where id = (x->>'logement_id')::uuid and copro_id = p_copro;
    -- Badges laissés au locataire le jour de l'installation (choisis dans l'app parmi les badges restants).
    if x->>'statut' = 'signe' and jsonb_typeof(x->'badges') = 'array' and jsonb_array_length(x->'badges') > 0 then
      select coalesce(jsonb_agg(b.numero), '[]'::jsonb) into v_b from ps_badges b
        where b.copro_id = p_copro and b.statut = 'stock' and b.numero in (select upper(trim(e)) from jsonb_array_elements_text(x->'badges') e);
      if jsonb_array_length(v_b) > 0 then
        insert into ps_remises (copro_id, numero, jeton, statut, badges, proprietaire, qualite, logement_id, mode_signature, signataire, signe_le, agent_nom, commentaire)
        values (p_copro, 'INST-' || coalesce(nullif(x->>'bon', ''), to_char(now(), 'YYYYMMDDHH24MISS')), ps__jeton(), 'signe', v_b,
          left(coalesce(x->>'signataire', ''), 120), 'locataire', (x->>'logement_id')::uuid, 'installation', left(coalesce(x->>'signataire', ''), 120),
          coalesce(nullif(x->>'signe_le', '')::timestamptz, now()), 'Harmonie Électricité', 'Badges remis au locataire le jour de l''installation')
        returning id into v_r;
        update ps_badges set statut = 'remis', remise_id = v_r, maj_le = now()
          where copro_id = p_copro and numero in (select jsonb_array_elements_text(v_b));
        update ps_logements set badges_locataire = greatest(0, badges_locataire - jsonb_array_length(v_b)) where id = (x->>'logement_id')::uuid;
      end if;
    end if;
  end loop;
  select count(*), count(*) filter (where emarge->>'statut' = 'signe') into v_n, v_s from ps_logements where copro_id = p_copro and type = 'logement';
  select etat into v_etat from ps_copros where id = p_copro;
  -- Tous les appartements émargés : installation terminée, en attente de facturation.
  if v_n > 0 and v_s >= v_n and v_etat not in ('attente_facturation', 'facture', 'termine') then
    update ps_copros set etat = 'attente_facturation', maj_le = now() where id = p_copro;
    perform ps__log(p_copro, 'Harmonie', 'installation_terminee', jsonb_build_object('emarges', v_s));
  elsif v_s > 0 and v_etat in ('commence', 'livres', 'distribution', 'recensement', 'recensement_termine', 'commande') then
    update ps_copros set etat = 'installation', maj_le = now() where id = p_copro;
  end if;
  return jsonb_build_object('logements', v_n, 'emarges', v_s);
end $$;

revoke execute on function public.ps_admin_emargement_maj(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.ps_admin_emargement_maj(text, uuid, jsonb) to anon, authenticated;
