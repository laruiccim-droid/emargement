-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 10 : devis rattaché au chantier
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 9.
-- Ne touche pas à la table « emargements ».
--
-- Le PDF du devis est déposé à la création (ou modification) du chantier dans le portail admin.
-- Il reste disponible pour la suite : prix du sondage des copropriétaires, bons de commande, facturation.
-- devis = { url, nom, taille, depose_le }   ({} : aucun devis)
-- =====================================================================================

alter table public.ps_copros add column if not exists devis jsonb not null default '{}'::jsonb;

-- Enregistrement d'un chantier : version du script n° 8, avec le devis.
create or replace function public.ps_admin_copro_enregistrer(p_admin text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_ancien uuid;
  v_travaux text := case when p->>'travaux' in ('interphone', 'interphone_vigik', 'vigik') then p->>'travaux' else 'interphone' end;
  v_vigik jsonb := case when jsonb_typeof(p->'vigik') = 'object' then p->'vigik' else '{"portes": [], "autorisations": []}'::jsonb end;
  v_devis jsonb := case when jsonb_typeof(p->'devis') = 'object' and coalesce(p->'devis'->>'url', '') like 'https://%' then
      jsonb_build_object('url', p->'devis'->>'url', 'nom', left(coalesce(p->'devis'->>'nom', 'devis.pdf'), 200),
        'taille', coalesce(nullif(p->'devis'->>'taille', '')::bigint, 0), 'depose_le', coalesce(p->'devis'->>'depose_le', now()::text))
    else '{}'::jsonb end;
  v_mi text; v_mv text;
begin
  perform ps__admin(p_admin);
  if coalesce(trim(p->>'nom'), '') = '' then raise exception 'NOM_OBLIGATOIRE'; end if;
  v_mi := case when v_travaux = 'vigik' then '' else coalesce(trim(p->>'marque_interphone'), '') end;
  v_mv := case when v_travaux = 'interphone' then '' else coalesce(trim(p->>'marque_vigik'), '') end;
  if v_id is null then
    insert into ps_copros (syndic_id, nom, adresse, cp, ville, reference, type, etat, chantier_id, notes, travaux, vigik, marque_interphone, marque_vigik, devis)
    values (nullif(p->>'syndic_id','')::uuid, trim(p->>'nom'), coalesce(p->>'adresse',''), coalesce(p->>'cp',''), coalesce(p->>'ville',''),
      coalesce(p->>'reference',''), coalesce(nullif(p->>'type',''),'badges'), coalesce(nullif(p->>'etat',''),'commence'), coalesce(p->>'chantier_id',''), coalesce(p->>'notes',''),
      v_travaux, v_vigik, v_mi, v_mv, v_devis)
    returning id into v_id;
    perform ps__log(v_id, 'Harmonie', 'copro_creee', p);
  else
    select syndic_id into v_ancien from ps_copros where id = v_id;
    update ps_copros set syndic_id = nullif(p->>'syndic_id','')::uuid,
      gestionnaire_id = case when syndic_id is distinct from nullif(p->>'syndic_id','')::uuid then null else gestionnaire_id end,
      nom = trim(p->>'nom'), adresse = coalesce(p->>'adresse',''), cp = coalesce(p->>'cp',''),
      ville = coalesce(p->>'ville',''), reference = coalesce(p->>'reference',''), type = coalesce(nullif(p->>'type',''),'badges'),
      etat = coalesce(nullif(p->>'etat',''),'commence'), chantier_id = coalesce(p->>'chantier_id',''), notes = coalesce(p->>'notes',''),
      travaux = v_travaux, vigik = v_vigik, marque_interphone = v_mi, marque_vigik = v_mv, devis = v_devis, maj_le = now()
    where id = v_id;
    if v_ancien is distinct from nullif(p->>'syndic_id','')::uuid then
      perform ps__log(v_id, 'Harmonie', 'syndic_change', jsonb_build_object('avant', v_ancien, 'apres', p->>'syndic_id'));
    end if;
  end if;
  return jsonb_build_object('id', v_id);
end $$;
