-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 44 : « Vigik seul », accès du syndic ouvert par le bon de livraison
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 43.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
--  1. Harmonie dépose le listing des badges : le syndic voit « listing déposé, en attente de livraison ».
--  2. Harmonie déclare les badges livrés à l'agence (badges_suivi.livre_le).
--  3. Le bon de livraison est signé : sur le téléphone d'Harmonie, ou à distance par le gestionnaire
--     dans son espace syndic. La signature ouvre l'accès du syndic au chantier (badges_suivi.livraison_signee_le).
--  4. Harmonie peut aussi débloquer l'accès sans attendre la signature (badges_suivi.acces_le).
-- Tant que l'accès n'est pas ouvert, le fichier des copropriétaires est refusé (ACCES_BLOQUE).
-- Chantiers Vigik seul déjà commencés : accès laissé ouvert.
-- =====================================================================================

create or replace function public.ps__acces_syndic(p_copro uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select c.travaux <> 'vigik' or c.badges_suivi ? 'acces_le' or c.badges_suivi ? 'livraison_signee_le'
                   from ps_copros c where c.id = p_copro), false);
$$;

-- Bon de livraison signé (à la création, par Harmonie ou à distance par le gestionnaire) : accès ouvert.
create or replace function public.ps__livraison_signee() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.signature, '') <> '' and (tg_op = 'INSERT' or coalesce(old.signature, '') = '') then
    update ps_copros set badges_suivi = badges_suivi
        || jsonb_build_object('livraison_signee_le', now(), 'livraison_signataire', coalesce(new.signataire, ''))
        || case when badges_suivi ? 'livre_le' then '{}'::jsonb else jsonb_build_object('livre_le', now()) end,
      maj_le = now()
    where id = new.copro_id;
  end if;
  return new;
end $$;
drop trigger if exists ps_livraisons_signee on public.ps_livraisons;
create trigger ps_livraisons_signee after insert or update of signature on public.ps_livraisons
  for each row execute function public.ps__livraison_signee();

create or replace function public.ps_admin_badges_jalon(p_admin text, p_copro uuid, p_jalon text, p_fait boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  if p_jalon not in ('programmes', 'correspondance', 'attribues', 'installation', 'service', 'livre', 'acces') then raise exception 'INTROUVABLE'; end if;
  update ps_copros set badges_suivi = case when p_fait then badges_suivi || jsonb_build_object(p_jalon || '_le', now()) else badges_suivi - (p_jalon || '_le') end,
    etat = case when p_fait and p_jalon = 'installation' and etat not in ('attente_facturation', 'facture', 'termine') then 'installation'
                when p_fait and p_jalon = 'service' and etat not in ('facture', 'termine') then 'attente_facturation' else etat end,
    maj_le = now() where id = p_copro;
  perform ps__log(p_copro, 'Harmonie', 'badges_' || p_jalon, jsonb_build_object('fait', p_fait));
  return jsonb_build_object('ok', true);
end $$;

-- Harmonie : faire signer le bon d'une livraison déjà enregistrée (sur son appareil).
create or replace function public.ps_admin_livraison_signer(p_admin text, p_livraison uuid, p_signataire text, p_signature text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_copro uuid;
begin
  perform ps__admin(p_admin);
  if coalesce(trim(p_signataire), '') = '' then raise exception 'NOM_OBLIGATOIRE'; end if;
  if coalesce(p_signature, '') !~ '^data:image/png;base64,' or length(p_signature) > 800000 then raise exception 'SIGNATURE_INVALIDE'; end if;
  update ps_livraisons set signataire = left(trim(p_signataire), 120), signature = p_signature, signe_le = now()
  where id = p_livraison and coalesce(signature, '') = '' returning copro_id into v_copro;
  if v_copro is null then raise exception 'INTROUVABLE'; end if;
  perform ps__log(v_copro, 'Harmonie', 'livraison_signee', jsonb_build_object('livraison', p_livraison, 'signataire', trim(p_signataire)));
  return jsonb_build_object('ok', true);
end $$;

-- Gestionnaire : état de la livraison des badges de son chantier (dernière livraison).
create or replace function public.ps_syndic_livraison(p_session text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  return coalesce((select jsonb_build_object('id', l.id, 'nb', jsonb_array_length(l.badges), 'premier', l.badges->>0, 'dernier', l.badges->>(jsonb_array_length(l.badges) - 1),
      'cree_le', l.cree_le, 'signe_le', l.signe_le, 'signataire', l.signataire)
    from ps_livraisons l where l.copro_id = p_copro order by (coalesce(l.signature, '') = '') desc, l.cree_le desc limit 1), '{}'::jsonb);
end $$;

-- Gestionnaire : signer à distance le bon de livraison (ouvre l'accès au chantier).
create or replace function public.ps_syndic_livraison_signer(p_session text, p_copro uuid, p_signataire text, p_signature text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; v_liv uuid;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  if coalesce(trim(p_signataire), '') = '' then raise exception 'NOM_OBLIGATOIRE'; end if;
  if coalesce(p_signature, '') !~ '^data:image/png;base64,' or length(p_signature) > 800000 then raise exception 'SIGNATURE_INVALIDE'; end if;
  select id into v_liv from ps_livraisons where copro_id = p_copro and coalesce(signature, '') = '' order by cree_le desc limit 1;
  if v_liv is null then raise exception 'INTROUVABLE'; end if;
  update ps_livraisons set signataire = left(trim(p_signataire), 120), signature = p_signature, signe_le = now() where id = v_liv;
  perform ps__log(p_copro, coalesce(nullif(u.nom, ''), u.email), 'livraison_signee', jsonb_build_object('livraison', v_liv, 'signataire', trim(p_signataire)));
  perform ps__notifier_harmonie(p_copro, '', 'bon de livraison signé',
    trim(p_signataire) || ' a signé à distance le bon de livraison des badges : son accès au chantier est ouvert.' || E'\n\n'
    || 'Pour information : le gestionnaire peut maintenant compléter le fichier des copropriétaires.');
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

-- Chantiers Vigik seul déjà commencés (fichier saisi ou badges livrés) : accès laissé ouvert.
update public.ps_copros c set badges_suivi = badges_suivi || jsonb_build_object('acces_le', now())
where c.travaux = 'vigik' and not c.badges_suivi ? 'acces_le'
  and (exists (select 1 from public.ps_logements l where l.copro_id = c.id) or exists (select 1 from public.ps_livraisons v where v.copro_id = c.id));

revoke execute on function public.ps__acces_syndic(uuid) from public, anon, authenticated;
revoke execute on function public.ps__livraison_signee() from public, anon, authenticated;
revoke execute on function public.ps_admin_badges_jalon(text, uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.ps_admin_badges_jalon(text, uuid, text, boolean) to anon, authenticated;
revoke execute on function public.ps_admin_livraison_signer(text, uuid, text, text) from public, anon, authenticated;
grant execute on function public.ps_admin_livraison_signer(text, uuid, text, text) to anon, authenticated;
revoke execute on function public.ps_syndic_livraison(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_syndic_livraison(text, uuid) to anon, authenticated;
revoke execute on function public.ps_syndic_livraison_signer(text, uuid, text, text) from public, anon, authenticated;
grant execute on function public.ps_syndic_livraison_signer(text, uuid, text, text) to anon, authenticated;
revoke execute on function public.ps_syndic_recensement_enregistrer(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.ps_syndic_recensement_enregistrer(text, uuid, jsonb) to anon, authenticated;
