-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 21 : retours du test du parcours
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 20.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
--  • Le recensement ne peut commencer qu'après la validation des étiquettes par Harmonie.
--  • Catalogue : une brochure (PDF) par article, montrée aux copropriétaires à la place de la notice.
--  • Recensement rempli sur ordinateur : les choix sont gardés (brouillon) et la signature se fait
--    sur le téléphone, en scannant le QR code affiché.
-- =====================================================================================

alter table public.ps_catalogue add column if not exists brochure text not null default '';
alter table public.ps_logements add column if not exists brouillon jsonb;

-- Copropriétaire : garder ses choix pour signer ensuite sur son téléphone.
create or replace function public.ps_sondage_brouillon(p_jeton text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(p_jeton, '') !~ '^[0-9a-f]{32}$' then raise exception 'LIEN_INVALIDE'; end if;
  if length(coalesce(p::text, '')) > 20000 then raise exception 'LIEN_INVALIDE'; end if;
  update ps_logements set brouillon = p || jsonb_build_object('le', now()) where jeton = p_jeton;
  if not found then raise exception 'LIEN_INVALIDE'; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ps_syndic_recensement_enregistrer(p_session text, p_copro uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; v_rec jsonb; v_garder uuid[] := '{}'; x jsonb; v_id uuid; v_i int := 0; v_type text; v_emails jsonb;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  select recensement into v_rec from ps_copros where id = p_copro;
  -- Le recensement ne commence qu'une fois la pose des étiquettes validée par Harmonie.
  if coalesce(v_rec->>'etiquettes_le', '') = '' then raise exception 'ETIQUETTES_A_VALIDER'; end if;
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
          badges = least(greatest(coalesce(nullif(x->>'badges', '')::int, 0), 0), 500), ordre = v_i, maj_le = now()
        where id = (x->>'id')::uuid and copro_id = p_copro returning id into v_id;
      end if;
      if v_id is null then
        insert into ps_logements (copro_id, type, numero, lot, nom, telephone, emails, badges, ordre)
        values (p_copro, v_type, left(coalesce(trim(x->>'numero'), ''), 30), left(coalesce(trim(x->>'lot'), ''), 30), left(coalesce(trim(x->>'nom'), ''), 120),
          left(coalesce(trim(x->>'telephone'), ''), 30), v_emails, least(greatest(coalesce(nullif(x->>'badges', '')::int, 0), 0), 500), v_i)
        returning id into v_id;
      end if;
      v_garder := v_garder || v_id;
    end loop;
    delete from ps_logements where copro_id = p_copro and not (id = any(v_garder));
  end if;
  perform ps__log(p_copro, coalesce(nullif(u.nom, ''), u.email), 'recensement', jsonb_build_object('etape', v_rec->>'etape', 'logements', v_i));
  return jsonb_build_object('recensement', v_rec, 'logements', ps__logements(p_copro));
end $$;

create or replace function public.ps_sondage_lire(p_jeton text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l ps_logements; c ps_copros;
begin
  if coalesce(p_jeton, '') !~ '^[0-9a-f]{32}$' then raise exception 'LIEN_INVALIDE'; end if;
  select * into l from ps_logements where jeton = p_jeton;
  if l.id is null then raise exception 'LIEN_INVALIDE'; end if;
  select * into c from ps_copros where id = l.copro_id;
  return jsonb_build_object(
    'copro', jsonb_build_object('nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'travaux', c.travaux,
      'marque_interphone', c.marque_interphone, 'marque_vigik', c.marque_vigik),
    'syndic', (select jsonb_build_object('nom', s.nom) from ps_syndics s where s.id = c.syndic_id),
    'texte', coalesce(c.sondage->>'texte', ''), 'ouvert', c.sondage ? 'ouvert_le' and not (c.sondage ? 'clos_le'),
    'logement', jsonb_build_object('numero', l.numero, 'lot', l.lot, 'nom', l.nom, 'telephone', l.telephone, 'emails', l.emails),
    'brouillon', l.brouillon,
    'articles', ps__articles_sondage(c),
    'commande', (select ps__commande_json(k) from ps_commandes k where k.logement_id = l.id and k.statut = 'signe' order by k.signe_le desc limit 1));
end $$;

create or replace function public.ps_sondage_signer(p_jeton text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l ps_logements; c ps_copros; x jsonb; a jsonb; v_lignes jsonb := '[]'; v_qte int; v_ht numeric := 0; v_ttc numeric := 0;
  v_lht numeric; v_lttc numeric; v_postes int := 0; k ps_commandes; v_num int;
begin
  if coalesce(p_jeton, '') !~ '^[0-9a-f]{32}$' then raise exception 'LIEN_INVALIDE'; end if;
  select * into l from ps_logements where jeton = p_jeton;
  if l.id is null then raise exception 'LIEN_INVALIDE'; end if;
  select * into c from ps_copros where id = l.copro_id;
  if not (c.sondage ? 'ouvert_le') or c.sondage ? 'clos_le' then raise exception 'SONDAGE_CLOS'; end if;
  if coalesce(trim(p->>'nom'), '') = '' or coalesce(trim(p->>'prenom'), '') = '' or coalesce(trim(p->>'telephone'), '') = '' then raise exception 'NOM_OBLIGATOIRE'; end if;
  if coalesce(p->>'qualite', '') not in ('occupant', 'bailleur') then raise exception 'QUALITE_OBLIGATOIRE'; end if;
  if p->>'qualite' = 'occupant' and coalesce(trim(p->>'numero_appt'), '') = '' then raise exception 'APPARTEMENT_OBLIGATOIRE'; end if;
  if coalesce(p->>'signature', '') !~ '^data:image/png;base64,' or length(p->>'signature') > 800000 then raise exception 'SIGNATURE_INVALIDE'; end if;

  for x in select * from jsonb_array_elements(case when jsonb_typeof(p->'lignes') = 'array' then p->'lignes' else '[]'::jsonb end) loop
    v_qte := least(greatest(coalesce(nullif(x->>'qte', '')::int, 0), 0), 20);
    if v_qte = 0 then continue; end if;
    a := null;
    select e into a from jsonb_array_elements(ps__articles_sondage(c)) e where e->>'ref' = x->>'ref' limit 1;
    if a is null then raise exception 'ARTICLE_INCONNU'; end if;
    v_lht := round((a->>'prix_ht')::numeric * v_qte, 2);
    v_lttc := round(v_lht * (1 + (a->>'tva')::numeric / 100), 2);
    v_ht := v_ht + v_lht; v_ttc := v_ttc + v_lttc;
    if a->>'type' in ('combine', 'moniteur') then v_postes := v_postes + v_qte; end if;
    v_lignes := v_lignes || jsonb_build_array(jsonb_build_object('ref', a->>'ref', 'nom', a->>'nom', 'type', a->>'type', 'marque', a->>'marque', 'qte', v_qte,
      'prix_ht', (a->>'prix_ht')::numeric, 'tva', (a->>'tva')::numeric, 'total_ht', v_lht, 'total_ttc', v_lttc));
  end loop;
  if c.travaux <> 'vigik' and v_postes = 0 then raise exception 'POSTE_OBLIGATOIRE'; end if;

  update ps_commandes set statut = 'remplace' where logement_id = l.id and statut = 'signe';
  select count(*) + 1 into v_num from ps_commandes where copro_id = c.id;
  insert into ps_commandes (copro_id, logement_id, numero, lignes, total_ht, total_ttc, nom, prenom, telephone, email, numero_appt, qualite, signature, ip, navigateur)
  values (c.id, l.id, 'BC-' || coalesce(nullif(regexp_replace(c.reference, '[^A-Za-z0-9]', '', 'g'), ''), upper(left(replace(c.id::text, '-', ''), 6))) || '-' || lpad(v_num::text, 3, '0'),
    v_lignes, v_ht, v_ttc, left(trim(p->>'nom'), 80), left(trim(p->>'prenom'), 80), left(trim(p->>'telephone'), 30), left(lower(trim(coalesce(p->>'email', ''))), 120),
    left(trim(coalesce(p->>'numero_appt', '')), 30), p->>'qualite', p->>'signature', ps__ip(), left(coalesce(p->>'navigateur', ''), 300))
  returning * into k;
  -- Le numéro d'appartement (étiquette blanche) est connu par la réponse du copropriétaire.
  if coalesce(trim(p->>'numero_appt'), '') <> '' then
    update ps_logements set numero = left(trim(p->>'numero_appt'), 30), maj_le = now() where id = l.id;
  end if;
  update ps_logements set brouillon = null where id = l.id;
  perform ps__log(c.id, trim(p->>'prenom') || ' ' || trim(p->>'nom'), 'commande_signee', jsonb_build_object('logement', l.numero, 'numero', k.numero, 'total_ttc', v_ttc));
  return ps__commande_json(k, true) || jsonb_build_object('copro', jsonb_build_object('nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference),
    'logement', jsonb_build_object('numero', coalesce(nullif(trim(p->>'numero_appt'), ''), l.numero), 'lot', l.lot));
end $$;

create or replace function public.ps_admin_catalogue_enregistrer(p_admin text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := nullif(p->>'id', '')::uuid;
begin
  perform ps__admin(p_admin);
  if coalesce(trim(p->>'nom'), '') = '' or coalesce(trim(p->>'marque'), '') = '' then raise exception 'NOM_OBLIGATOIRE'; end if;
  if v_id is null then
    insert into ps_catalogue (marque, ref, type, nom, argument, points, prix_ht, tva, photo, notice, brochure, ordre, actif)
    values (trim(p->>'marque'), coalesce(trim(p->>'ref'), ''), coalesce(nullif(p->>'type', ''), 'combine'), trim(p->>'nom'), coalesce(p->>'argument', ''),
      coalesce(p->'points', '[]'), coalesce(nullif(p->>'prix_ht', '')::numeric, 0), coalesce(nullif(p->>'tva', '')::numeric, 10),
      coalesce(p->>'photo', ''), coalesce(p->>'notice', ''), coalesce(p->>'brochure', ''), coalesce(nullif(p->>'ordre', '')::int, 0), coalesce((p->>'actif')::boolean, true))
    returning id into v_id;
  else
    update ps_catalogue set marque = trim(p->>'marque'), ref = coalesce(trim(p->>'ref'), ''), type = coalesce(nullif(p->>'type', ''), 'combine'),
      nom = trim(p->>'nom'), argument = coalesce(p->>'argument', ''), points = coalesce(p->'points', '[]'),
      prix_ht = coalesce(nullif(p->>'prix_ht', '')::numeric, 0), tva = coalesce(nullif(p->>'tva', '')::numeric, 10),
      photo = coalesce(p->>'photo', ''), notice = coalesce(p->>'notice', ''), brochure = coalesce(p->>'brochure', ''), ordre = coalesce(nullif(p->>'ordre', '')::int, 0),
      actif = coalesce((p->>'actif')::boolean, true), maj_le = now()
    where id = v_id;
  end if;
  return jsonb_build_object('id', v_id);
exception when unique_violation then raise exception 'REFERENCE_EXISTANTE';
end $$;

revoke execute on function public.ps_sondage_brouillon(text, jsonb) from public, anon, authenticated;
grant execute on function public.ps_sondage_brouillon(text, jsonb) to anon, authenticated;
revoke execute on function public.ps_syndic_recensement_enregistrer(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.ps_syndic_recensement_enregistrer(text, uuid, jsonb) to anon, authenticated;
revoke execute on function public.ps_sondage_lire(text) from public, anon, authenticated;
grant execute on function public.ps_sondage_lire(text) to anon, authenticated;
revoke execute on function public.ps_sondage_signer(text, jsonb) from public, anon, authenticated;
grant execute on function public.ps_sondage_signer(text, jsonb) to anon, authenticated;
revoke execute on function public.ps_admin_catalogue_enregistrer(text, jsonb) from public, anon, authenticated;
grant execute on function public.ps_admin_catalogue_enregistrer(text, jsonb) to anon, authenticated;
