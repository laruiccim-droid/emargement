-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 43 : nouveau parcours « Vigik seul »
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 42.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
--  1. Le fichier des copropriétaires s'ouvre dès la création du chantier (plus de commande ni de listing à attendre).
--  2. Badges attendus par appartement : ceux du recensement signé, sinon le nombre fixé par le syndic dans
--     le fichier (+ badges supplémentaires).
--  3. E-mails à Harmonie : remise des badges à 25, 50, 75 et 100 % ; stock syndic sous 10 badges ; stock épuisé.
-- =====================================================================================

create or replace function public.ps__badges_attendus(p_logement uuid) returns integer
language sql stable security definer set search_path = public as $$
  with k as (select k2.id from ps_commandes k2 where k2.logement_id = p_logement and k2.statut = 'signe' order by k2.signe_le desc limit 1)
  select (case when exists (select 1 from k)
      then coalesce((select sum((x->>'qte')::int) from ps_commandes kk, jsonb_array_elements(kk.lignes) x where kk.id = (select id from k) and x->>'type' = 'badge'), 0)
      else coalesce((select l.badges from ps_logements l where l.id = p_logement and (select travaux from ps_copros where id = l.copro_id) = 'vigik'), 0) end
    + coalesce((select l.badges_supp from ps_logements l where l.id = p_logement), 0))::int;
$$;

create or replace function public.ps_syndic_recensement_enregistrer(p_session text, p_copro uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; v_rec jsonb; v_garder uuid[] := '{}'; x jsonb; v_id uuid; v_i int := 0; v_type text; v_emails jsonb;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
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

create or replace function public.ps__notif_badges_copro(p_copro uuid) returns void
language plpgsql security definer set search_path = public as $$
declare c ps_copros; a jsonb; v_att int; v_ok int; v_liv int; v_loc int; v_pc int; v_stock int;
begin
  select * into c from ps_copros where id = p_copro;
  if c.id is null then return; end if;
  a := ps__avancement(c);
  v_att := coalesce((a->>'nb_badges_attendus')::int, 0); v_ok := coalesce((a->>'nb_badges_ok')::int, 0);

  -- Vigik seul : avancement de la remise des badges à 25, 50 et 75 % des appartements.
  if v_att > 0 and c.travaux = 'vigik' and v_ok < v_att then
    for v_pc in select unnest(array[75, 50, 25]) loop
      if v_ok * 100 >= v_att * v_pc then
        perform ps__notifier_harmonie(c.id, 'badges_' || v_pc, 'remise des badges à ' || v_pc || ' %',
          'Avancement de la remise des badges à l’agence : ' || v_ok || ' appartements sur ' || v_att || ' ont récupéré leurs badges.' || E'\n\n'
          || 'Pour information : le compte rendu (badges, appartements, droits d’accès) est disponible à tout moment dans le portail, bloc Badges.');
        exit;
      end if;
    end loop;
  end if;

  -- Remise terminée : tous les appartements servis.
  if v_att > 0 and v_ok >= v_att then
    select coalesce(sum(badges_locataire), 0), count(*) filter (where badges_locataire > 0) into v_loc, v_liv
      from ps_logements where copro_id = c.id and type = 'logement';
    perform ps__notifier_harmonie(c.id, 'badges_100', 'remise des badges terminée',
      'Le syndic a terminé la remise des badges : les ' || v_att || ' appartements ont été servis.'
      || case when v_loc > 0 then E'\n' || v_loc || ' badge(s) restent à remettre aux locataires le jour de l’installation (' || v_liv || ' appartement(s) en location).' else '' end
      || E'\n\n'
      || case when c.travaux = 'vigik' and coalesce(c.badges_suivi->>'service_le', '') = ''
           then 'À vous : installer les centrales Vigik, puis cliquer « Installation des centrales terminée » (le syndic est prévenu).'
           else 'Pour information : la distribution des badges est terminée.' end
      || case when c.travaux = 'vigik' then E'\n\nLe compte rendu des remises (badges, appartements, droits d’accès) est disponible dans le portail, bloc Badges.' else '' end);
  end if;

  -- Stock syndic presque épuisé : moins de 10 badges disponibles (nouvelle alerte après une nouvelle livraison).
  select count(*) into v_stock from ps_badges where copro_id = c.id and statut = 'stock';
  if v_stock > 0 and v_stock < 10 then
    select count(*) into v_liv from ps_livraisons where copro_id = c.id;
    perform ps__notifier_harmonie(c.id, 'stock_bas_' || v_liv, 'stock de badges presque épuisé',
      'Il ne reste plus que ' || v_stock || ' badge(s) disponible(s) dans le stock du syndic.' || E'\n\n'
      || 'À vous : prévoir une nouvelle livraison de badges si le chantier en a encore besoin.');
  end if;
  -- Plus aucun badge en stock (nouvelle alerte après une nouvelle livraison).
  if exists (select 1 from ps_badges where copro_id = c.id) and not exists (select 1 from ps_badges where copro_id = c.id and statut = 'stock') then
    select count(*) into v_liv from ps_livraisons where copro_id = c.id;
    perform ps__notifier_harmonie(c.id, 'stock_vide_' || v_liv, 'plus de badges en stock',
      'Tous les badges livrés au syndic ont été remis : il n’en reste plus en stock.' || E'\n\n'
      || 'À vous : prévoir une nouvelle livraison de badges si le chantier en a encore besoin.');
  end if;
exception when others then
  raise warning 'Notification Harmonie (badges) : %', sqlerrm;
end $$;

create or replace function public.ps__notif_recensement_fini(c ps_copros, p_pourquoi text) returns void
language plpgsql security definer set search_path = public as $$
declare a jsonb := ps__avancement(c);
begin
  -- Vigik seul : le recensement sert seulement à fixer le nombre de badges, rien à faire pour Harmonie.
  if c.travaux = 'vigik' then return; end if;
  perform ps__notifier_harmonie(c.id, 'recensement_fini', 'recensement terminé',
    p_pourquoi || ' (' || coalesce(a->>'nb_commandes', '0') || ' réponse(s) signée(s) sur ' || coalesce(a->>'nb_logements_saisis', '0') || ' appartements).' || E'\n\n'
    || case when c.travaux = 'vigik'
         then 'À vous : récupérer le « Listing des réponses » dans le portail, attribuer les badges dans votre logiciel, puis cliquer « Attributions faites : prévenir le syndic ».'
         else 'À vous : commander le matériel au fournisseur (bouton « Commander le matériel » dans le portail), puis indiquer « Matériel reçu ».' end);
end $$;

revoke execute on function public.ps__badges_attendus(uuid) from public, anon, authenticated;
revoke execute on function public.ps__notif_badges_copro(uuid) from public, anon, authenticated;
revoke execute on function public.ps__notif_recensement_fini(public.ps_copros, text) from public, anon, authenticated;
revoke execute on function public.ps_syndic_recensement_enregistrer(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.ps_syndic_recensement_enregistrer(text, uuid, jsonb) to anon, authenticated;
