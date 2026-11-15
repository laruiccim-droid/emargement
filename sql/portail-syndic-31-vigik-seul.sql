-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 31 : parcours « Vigik seul »
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 30.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
--  1. Le syndic commande un nombre total de badges.
--  2. Harmonie programme les badges et dépose le listing : l'espace du gestionnaire se débloque.
--  3. Fichier des copropriétaires (sans étiquettes) puis recensement : nombre de badges par appartement.
--  4. Harmonie attribue les badges dans son logiciel et valide : le syndic peut distribuer.
--  5. Remises signées à l'agence ; feu vert d'installation à 80 % (Harmonie peut lancer librement).
--  6. Installation des centrales, mise en service, puis facture.
-- badges_suivi = { commande_nb, commande_le, commande_par, attribues_le, installation_le, service_le, … }
-- =====================================================================================

-- Gestionnaire : commande du nombre total de badges.
create or replace function public.ps_syndic_badges_commander(p_session text, p_copro uuid, p_nb integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  if coalesce(p_nb, 0) < 1 or p_nb > 5000 then raise exception 'INTROUVABLE'; end if;
  update ps_copros set badges_suivi = badges_suivi || jsonb_build_object('commande_nb', p_nb, 'commande_le', now(), 'commande_par', coalesce(nullif(u.nom, ''), u.email)), maj_le = now()
  where id = p_copro;
  perform ps__log(p_copro, coalesce(nullif(u.nom, ''), u.email), 'badges_commandes', jsonb_build_object('nb', p_nb));
  return jsonb_build_object('ok', true);
end $$;

-- Harmonie : jalons des badges (programmés, liés, attribués, installation lancée, mise en service).
create or replace function public.ps_admin_badges_jalon(p_admin text, p_copro uuid, p_jalon text, p_fait boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  if p_jalon not in ('programmes', 'correspondance', 'attribues', 'installation', 'service') then raise exception 'INTROUVABLE'; end if;
  update ps_copros set badges_suivi = case when p_fait then badges_suivi || jsonb_build_object(p_jalon || '_le', now()) else badges_suivi - (p_jalon || '_le') end,
    etat = case when p_fait and p_jalon = 'installation' and etat not in ('attente_facturation', 'facture', 'termine') then 'installation'
                when p_fait and p_jalon = 'service' and etat not in ('facture', 'termine') then 'attente_facturation' else etat end,
    maj_le = now() where id = p_copro;
  perform ps__log(p_copro, 'Harmonie', 'badges_' || p_jalon, jsonb_build_object('fait', p_fait));
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
  -- Vigik seul : pas d'étiquettes, mais le listing des badges doit être déposé par Harmonie avant le fichier.
  if (select travaux from ps_copros where id = p_copro) = 'vigik' then
    if not exists (select 1 from ps_badges where copro_id = p_copro) then raise exception 'BADGES_A_DEPOSER'; end if;
  elsif coalesce(v_rec->>'etiquettes_le', '') = '' then raise exception 'ETIQUETTES_A_VALIDER'; end if;
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

revoke execute on function public.ps_syndic_badges_commander(text, uuid, integer) from public, anon, authenticated;
grant execute on function public.ps_syndic_badges_commander(text, uuid, integer) to anon, authenticated;
revoke execute on function public.ps_admin_badges_jalon(text, uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.ps_admin_badges_jalon(text, uuid, text, boolean) to anon, authenticated;
revoke execute on function public.ps_syndic_recensement_enregistrer(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.ps_syndic_recensement_enregistrer(text, uuid, jsonb) to anon, authenticated;
