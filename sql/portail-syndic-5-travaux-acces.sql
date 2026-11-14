-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 5 : type de travaux, portes et droits d'accès Vigik d'un chantier
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 4.
-- Ne touche pas à la table « emargements ».
--
--  ps_copros.travaux : 'interphone' | 'interphone_vigik' | 'vigik'
--  ps_copros.vigik   : { "portes": ["Porte d’entrée", "Porte de garage"],
--                        "autorisations": [ { "nom": "…", "portes": [0, 1] }, … ] }
-- =====================================================================================

alter table public.ps_copros add column if not exists travaux text not null default 'interphone';
alter table public.ps_copros add column if not exists vigik jsonb not null default '{"portes": [], "autorisations": []}'::jsonb;

-- Enregistrement d'un chantier : reprend la version du script n° 3 (gestionnaire retiré si le syndic change)
-- et enregistre en plus le type de travaux et les accès Vigik.
create or replace function public.ps_admin_copro_enregistrer(p_admin text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_ancien uuid;
  v_travaux text := case when p->>'travaux' in ('interphone', 'interphone_vigik', 'vigik') then p->>'travaux' else 'interphone' end;
  v_vigik jsonb := case when jsonb_typeof(p->'vigik') = 'object' then p->'vigik' else '{"portes": [], "autorisations": []}'::jsonb end;
begin
  perform ps__admin(p_admin);
  if coalesce(trim(p->>'nom'), '') = '' then raise exception 'NOM_OBLIGATOIRE'; end if;
  if v_id is null then
    insert into ps_copros (syndic_id, nom, adresse, cp, ville, reference, type, etat, chantier_id, notes, travaux, vigik)
    values (nullif(p->>'syndic_id','')::uuid, trim(p->>'nom'), coalesce(p->>'adresse',''), coalesce(p->>'cp',''), coalesce(p->>'ville',''),
      coalesce(p->>'reference',''), coalesce(nullif(p->>'type',''),'badges'), coalesce(nullif(p->>'etat',''),'commence'), coalesce(p->>'chantier_id',''), coalesce(p->>'notes',''),
      v_travaux, v_vigik)
    returning id into v_id;
    perform ps__log(v_id, 'Harmonie', 'copro_creee', p);
  else
    select syndic_id into v_ancien from ps_copros where id = v_id;
    update ps_copros set syndic_id = nullif(p->>'syndic_id','')::uuid,
      gestionnaire_id = case when syndic_id is distinct from nullif(p->>'syndic_id','')::uuid then null else gestionnaire_id end,
      nom = trim(p->>'nom'), adresse = coalesce(p->>'adresse',''), cp = coalesce(p->>'cp',''),
      ville = coalesce(p->>'ville',''), reference = coalesce(p->>'reference',''), type = coalesce(nullif(p->>'type',''),'badges'),
      etat = coalesce(nullif(p->>'etat',''),'commence'), chantier_id = coalesce(p->>'chantier_id',''), notes = coalesce(p->>'notes',''),
      travaux = v_travaux, vigik = v_vigik, maj_le = now()
    where id = v_id;
    if v_ancien is distinct from nullif(p->>'syndic_id','')::uuid then
      perform ps__log(v_id, 'Harmonie', 'syndic_change', jsonb_build_object('avant', v_ancien, 'apres', p->>'syndic_id'));
    end if;
  end if;
  return jsonb_build_object('id', v_id);
end $$;
