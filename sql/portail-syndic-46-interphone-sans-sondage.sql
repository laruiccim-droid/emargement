-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 46 : « Sans sondage préalable » pour l'interphone
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 45.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Le syndic a fait son propre sondage : dans le fichier des copropriétaires, il indique pour chaque
-- appartement le poste choisi, la plaque de propreté et (Interphone + Vigik) le nombre de badges.
-- À la validation du fichier, un bon de commande est établi pour chaque appartement (par = 'gestionnaire',
-- sans signature) : commande du matériel, campagne, émargement et badges suivent ensuite comme avec sondage.
-- Le chantier est un chantier « complet » marqué recensement.sans_sondage = true.
-- =====================================================================================

alter table public.ps_logements add column if not exists poste_ref text not null default '';
alter table public.ps_logements add column if not exists plaque boolean not null default false;

create or replace function public.ps__logements(p_copro uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'type', l.type, 'numero', l.numero, 'lot', l.lot, 'nom', l.nom,
    'telephone', l.telephone, 'emails', l.emails, 'badges', l.badges, 'poste_ref', l.poste_ref, 'plaque', l.plaque) order by l.type <> 'logement', l.ordre), '[]'::jsonb)
  from ps_logements l where l.copro_id = p_copro;
$$;

-- Ligne de bon de commande d'après un article du catalogue (prix du chantier compris).
create or replace function public.ps__ligne_commande(a jsonb, p_qte integer) returns jsonb
language sql immutable as $$
  select jsonb_build_object('ref', a->>'ref', 'nom', a->>'nom', 'type', a->>'type', 'marque', a->>'marque', 'qte', p_qte,
    'prix_ht', (a->>'prix_ht')::numeric, 'tva', (a->>'tva')::numeric,
    'total_ht', round((a->>'prix_ht')::numeric * p_qte, 2),
    'total_ttc', round(round((a->>'prix_ht')::numeric * p_qte, 2) * (1 + (a->>'tva')::numeric / 100), 2));
$$;

-- Bons de commande établis d'après le fichier du syndic (remplacent les précédents bons « fichier »).
create or replace function public.ps__commandes_depuis_fichier(p_copro uuid) returns void
language plpgsql security definer set search_path = public as $$
declare c ps_copros; l ps_logements; arts jsonb; a jsonb; v_lignes jsonb; v_num int := 0; v_pref text;
begin
  select * into c from ps_copros where id = p_copro;
  arts := ps__articles_sondage(c);
  v_pref := 'BC-' || coalesce(nullif(regexp_replace(coalesce(c.reference, ''), '[^A-Za-z0-9]', '', 'g'), ''), upper(left(replace(c.id::text, '-', ''), 6))) || '-F';
  delete from ps_commandes where copro_id = p_copro and par = 'gestionnaire';
  for l in select * from ps_logements where copro_id = p_copro and type = 'logement' order by ordre loop
    v_lignes := '[]';
    if coalesce(l.poste_ref, '') <> '' then
      a := null; select e into a from jsonb_array_elements(arts) e where e->>'ref' = l.poste_ref limit 1;
      if a is not null then v_lignes := v_lignes || jsonb_build_array(ps__ligne_commande(a, 1)); end if;
    end if;
    if l.plaque then
      a := null; select e into a from jsonb_array_elements(arts) e where e->>'type' = 'plaque' limit 1;
      if a is not null then v_lignes := v_lignes || jsonb_build_array(ps__ligne_commande(a, 1)); end if;
    end if;
    if c.travaux = 'interphone_vigik' and coalesce(l.badges, 0) > 0 then
      a := null; select e into a from jsonb_array_elements(arts) e where e->>'type' = 'badge' limit 1;
      if a is not null then v_lignes := v_lignes || jsonb_build_array(ps__ligne_commande(a, l.badges)); end if;
    end if;
    if jsonb_array_length(v_lignes) = 0 then continue; end if;
    v_num := v_num + 1;
    update ps_commandes set statut = 'remplace' where logement_id = l.id and statut = 'signe';
    insert into ps_commandes (copro_id, logement_id, numero, statut, lignes, total_ht, total_ttc, nom, telephone, email, numero_appt, qualite, signature, par, navigateur)
    values (p_copro, l.id, v_pref || lpad(v_num::text, 3, '0'), 'signe', v_lignes,
      (select coalesce(sum((x->>'total_ht')::numeric), 0) from jsonb_array_elements(v_lignes) x),
      (select coalesce(sum((x->>'total_ttc')::numeric), 0) from jsonb_array_elements(v_lignes) x),
      left(coalesce(l.nom, ''), 80), coalesce(l.telephone, ''), coalesce(l.emails->>0, ''), coalesce(l.numero, ''), 'occupant', '', 'gestionnaire',
      'Fichier du syndic (sans sondage préalable)');
  end loop;
  -- Recensement considéré comme fait (par le syndic) : la suite du chantier peut démarrer.
  update ps_copros set sondage = sondage || jsonb_build_object('ouvert_le', coalesce(sondage->>'ouvert_le', now()::text), 'clos_le', now(), 'sans_sondage', true), maj_le = now()
  where id = p_copro;
end $$;

-- Harmonie : chantier avec ou sans sondage préalable (pour l'interphone, le type reste « complet »).
create or replace function public.ps_admin_sans_sondage(p_admin text, p_copro uuid, p_sans boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  update ps_copros set recensement = case when p_sans then recensement || '{"sans_sondage": true}'::jsonb else recensement - 'sans_sondage' end, maj_le = now()
  where id = p_copro;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ps_syndic_recensement_enregistrer(p_session text, p_copro uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; v_rec jsonb; v_garder uuid[] := '{}'; x jsonb; v_id uuid; v_i int := 0; v_type text; v_emails jsonb;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  -- Vigik seul : accès ouvert par la signature du bon de livraison des badges (ou débloqué par Harmonie).
  if not ps__acces_syndic(p_copro) then raise exception 'ACCES_BLOQUE'; end if;
  select recensement into v_rec from ps_copros where id = p_copro;
  -- Le recensement ne commence qu'une fois la pose des étiquettes validée par Harmonie.
  -- Vigik seul : pas d'étiquettes, mais le listing des badges doit être déposé par Harmonie avant le fichier.
  -- Vigik seul : fichier ouvert dès la création du chantier (ni étiquettes, ni badges à attendre).
  if (select travaux from ps_copros where id = p_copro) <> 'vigik' and coalesce(v_rec->>'etiquettes_le', '') = '' then raise exception 'ETIQUETTES_A_VALIDER'; end if;
  v_rec := v_rec || jsonb_build_object(
    'etape', case when p->>'etape' in ('etiquettes', 'saisie', 'pret') then p->>'etape' else coalesce(v_rec->>'etape', 'saisie') end,
    'nb_logements', least(greatest(coalesce(nullif(p->>'nb_logements', '')::int, (v_rec->>'nb_logements')::int, 0), 0), 2000),
    'enregistre_le', now(), 'par', coalesce(nullif(u.nom, ''), u.email));
  update ps_copros set recensement = v_rec, maj_le = now() where id = p_copro;

  if jsonb_typeof(p->'logements') = 'array' then
    if jsonb_array_length(p->'logements') > 2000 then raise exception 'TROP_DE_LOGEMENTS'; end if;
    for x in select * from jsonb_array_elements(p->'logements') loop
      v_i := v_i + 1;
      v_type := case when x->>'type' in ('logement', 'intervenant', 'stock') then x->>'type' else 'logement' end;
      select coalesce(jsonb_agg(distinct lower(trim(e))), '[]'::jsonb) into v_emails
        from jsonb_array_elements_text(case when jsonb_typeof(x->'emails') = 'array' then x->'emails' else '[]'::jsonb end) e
        where trim(e) ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$';
      v_id := null;
      if coalesce(x->>'id', '') ~ '^[0-9a-f-]{36}$' then
        update ps_logements set type = v_type, numero = left(coalesce(trim(x->>'numero'), ''), 30), lot = left(coalesce(trim(x->>'lot'), ''), 30),
          nom = left(coalesce(trim(x->>'nom'), ''), 120), telephone = left(coalesce(trim(x->>'telephone'), ''), 30), emails = v_emails,
          badges = least(greatest(coalesce(nullif(x->>'badges', '')::int, 0), 0), 500),
          poste_ref = left(coalesce(trim(x->>'poste_ref'), ''), 60), plaque = coalesce((x->>'plaque')::boolean, false), ordre = v_i, maj_le = now()
        where id = (x->>'id')::uuid and copro_id = p_copro returning id into v_id;
      end if;
      if v_id is null then
        insert into ps_logements (copro_id, type, numero, lot, nom, telephone, emails, badges, poste_ref, plaque, ordre)
        values (p_copro, v_type, left(coalesce(trim(x->>'numero'), ''), 30), left(coalesce(trim(x->>'lot'), ''), 30), left(coalesce(trim(x->>'nom'), ''), 120),
          left(coalesce(trim(x->>'telephone'), ''), 30), v_emails, least(greatest(coalesce(nullif(x->>'badges', '')::int, 0), 0), 500),
          left(coalesce(trim(x->>'poste_ref'), ''), 60), coalesce((x->>'plaque')::boolean, false), v_i)
        returning id into v_id;
      end if;
      v_garder := v_garder || v_id;
    end loop;
    delete from ps_logements where copro_id = p_copro and not (id = any(v_garder));
  end if;
  -- Sans sondage préalable (interphone) : fichier validé → bons de commande établis d'après les choix du syndic.
  if v_rec->>'etape' = 'pret' and coalesce((v_rec->>'sans_sondage')::boolean, false)
     and (select travaux from ps_copros where id = p_copro) <> 'vigik' then
    perform ps__commandes_depuis_fichier(p_copro);
  end if;
  perform ps__log(p_copro, coalesce(nullif(u.nom, ''), u.email), 'recensement', jsonb_build_object('etape', v_rec->>'etape', 'logements', v_i));
  return jsonb_build_object('recensement', v_rec, 'logements', ps__logements(p_copro));
end $$;

revoke execute on function public.ps__logements(uuid) from public, anon, authenticated;
revoke execute on function public.ps__ligne_commande(jsonb, integer) from public, anon, authenticated;
revoke execute on function public.ps__commandes_depuis_fichier(uuid) from public, anon, authenticated;
revoke execute on function public.ps_admin_sans_sondage(text, uuid, boolean) from public, anon, authenticated;
grant execute on function public.ps_admin_sans_sondage(text, uuid, boolean) to anon, authenticated;
revoke execute on function public.ps_syndic_recensement_enregistrer(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.ps_syndic_recensement_enregistrer(text, uuid, jsonb) to anon, authenticated;
