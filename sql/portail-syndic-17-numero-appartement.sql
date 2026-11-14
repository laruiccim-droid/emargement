-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 17 : numéro d'appartement donné par le copropriétaire
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 16.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Le syndic ne connaît pas les numéros d'appartement : il recense par n° de lot. Le numéro
-- (étiquette blanche sur la porte) est enregistré sur l'appartement quand le copropriétaire
-- signe son bon de commande dans le sondage. Il sert ensuite au rattachement des locataires,
-- aux rendez-vous et à l'émargement.
-- =====================================================================================

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
  perform ps__log(c.id, trim(p->>'prenom') || ' ' || trim(p->>'nom'), 'commande_signee', jsonb_build_object('logement', l.numero, 'numero', k.numero, 'total_ttc', v_ttc));
  return ps__commande_json(k, true) || jsonb_build_object('copro', jsonb_build_object('nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference),
    'logement', jsonb_build_object('numero', coalesce(nullif(trim(p->>'numero_appt'), ''), l.numero), 'lot', l.lot));
end $$;

revoke execute on function public.ps_sondage_signer(text, jsonb) from public, anon, authenticated;
grant execute on function public.ps_sondage_signer(text, jsonb) to anon, authenticated;
