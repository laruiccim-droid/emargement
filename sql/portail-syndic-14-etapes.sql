-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 14 : étapes du chantier revues
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 13.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
--  • La pose des étiquettes de numérotation est validée par Harmonie (portail admin), plus par le gestionnaire.
--  • « Sondage envoyé » : chaque appartement est noté invité quand le gestionnaire lui envoie son lien
--    (e-mail, SMS ou QR code).
--  • Campagne d'information (date d'intervention + feuille d'affichage) : jalon validé par Harmonie
--    en attendant le module dédié.
-- =====================================================================================

alter table public.ps_logements add column if not exists invite_le timestamptz;
alter table public.ps_logements add column if not exists invite_canal text not null default '';
alter table public.ps_copros add column if not exists campagne jsonb not null default '{}'::jsonb;   -- { envoyee_le }

-- Données d'avancement communes aux listes et aux fiches.
create or replace function public.ps__avancement(c public.ps_copros) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('travaux', c.travaux, 'recensement', c.recensement, 'sondage', c.sondage, 'campagne', c.campagne,
    'nb_logements_saisis', (select count(*) from ps_logements l where l.copro_id = c.id and l.type = 'logement'),
    'nb_invites', (select count(*) from ps_logements l where l.copro_id = c.id and l.type = 'logement' and l.invite_le is not null),
    'nb_commandes', (select count(distinct k.logement_id) from ps_commandes k where k.copro_id = c.id and k.statut = 'signe'));
$$;

-- Harmonie : valider (ou annuler) un jalon du chantier.  p_jalon = 'etiquettes' | 'campagne'
create or replace function public.ps_admin_jalon(p_admin text, p_copro uuid, p_jalon text, p_fait boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  if p_jalon = 'etiquettes' then
    update ps_copros set recensement = case when p_fait then recensement || jsonb_build_object('etiquettes_le', now(), 'etiquettes_par', 'Harmonie')
      else recensement - 'etiquettes_le' - 'etiquettes_par' end, maj_le = now() where id = p_copro;
  elsif p_jalon = 'campagne' then
    update ps_copros set campagne = case when p_fait then campagne || jsonb_build_object('envoyee_le', now()) else campagne - 'envoyee_le' end, maj_le = now()
    where id = p_copro;
  else raise exception 'INTROUVABLE';
  end if;
  perform ps__log(p_copro, 'Harmonie', 'jalon_' || p_jalon, jsonb_build_object('fait', p_fait));
  return jsonb_build_object('ok', true);
end $$;

-- Gestionnaire : noter qu'un copropriétaire a reçu son lien (e-mail, sms, qr).
create or replace function public.ps_syndic_sondage_invite(p_session text, p_logement uuid, p_canal text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; v_copro uuid;
begin
  u := ps__user(p_session);
  select copro_id into v_copro from ps_logements where id = p_logement;
  if v_copro is null or not ps__copro_visible(v_copro, u) then raise exception 'INTROUVABLE'; end if;
  update ps_logements set invite_le = now(), invite_canal = case when p_canal in ('email', 'sms', 'qr') then p_canal else 'autre' end where id = p_logement;
  return jsonb_build_object('ok', true, 'invite_le', now());
end $$;

-- Recensement par le gestionnaire : version du script n° 11 sans la case « étiquettes » (validée par Harmonie).
create or replace function public.ps_syndic_recensement_enregistrer(p_session text, p_copro uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; v_rec jsonb; v_garder uuid[] := '{}'; x jsonb; v_id uuid; v_i int := 0; v_type text; v_emails jsonb;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  select recensement into v_rec from ps_copros where id = p_copro;
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

-- Suivi du sondage : avec la date d'envoi du lien à chaque appartement.
create or replace function public.ps__sondage_suivi(p_copro uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'sondage', c.sondage, 'articles', ps__articles_sondage(c),
    'copro', jsonb_build_object('id', c.id, 'nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference,
      'travaux', c.travaux, 'marque_interphone', c.marque_interphone, 'marque_vigik', c.marque_vigik, 'recensement', c.recensement),
    'logements', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'numero', l.numero, 'lot', l.lot, 'nom', l.nom, 'telephone', l.telephone,
        'emails', l.emails, 'jeton', l.jeton, 'invite_le', l.invite_le, 'invite_canal', l.invite_canal,
        'commande', (select ps__commande_json(k) from ps_commandes k where k.logement_id = l.id and k.statut = 'signe' order by k.signe_le desc limit 1))
      order by l.ordre) from ps_logements l where l.copro_id = c.id and l.type = 'logement'), '[]'::jsonb))
  from ps_copros c where c.id = p_copro;
$$;

-- Fiche du chantier (gestionnaire) : avec les données d'avancement.
create or replace function public.ps_syndic_copro(p_session text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  return (select jsonb_build_object(
    'copro', jsonb_build_object('id', c.id, 'nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference, 'type', c.type, 'etat', c.etat,
      'vigik', c.vigik, 'marque_interphone', c.marque_interphone, 'marque_vigik', c.marque_vigik) || ps__avancement(c),
    'compteurs', ps__compteurs(c.id),
    'badges', coalesce((select jsonb_agg(jsonb_build_object('numero', b.numero, 'statut', b.statut, 'droit', b.droit, 'remise_id', b.remise_id) order by b.numero)
                from ps_badges b where b.copro_id = c.id), '[]'::jsonb),
    'remises', coalesce((select jsonb_agg(ps__remise_resume(r) order by r.cree_le desc) from ps_remises r where r.copro_id = c.id), '[]'::jsonb))
  from ps_copros c where c.id = p_copro);
end $$;

revoke execute on function public.ps__avancement(public.ps_copros) from public, anon, authenticated;
revoke execute on function public.ps__sondage_suivi(uuid) from public, anon, authenticated;
revoke execute on function public.ps_admin_jalon(text, uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.ps_admin_jalon(text, uuid, text, boolean) to anon, authenticated;
revoke execute on function public.ps_syndic_sondage_invite(text, uuid, text) from public, anon, authenticated;
grant execute on function public.ps_syndic_sondage_invite(text, uuid, text) to anon, authenticated;
revoke execute on function public.ps_syndic_recensement_enregistrer(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.ps_syndic_recensement_enregistrer(text, uuid, jsonb) to anon, authenticated;
revoke execute on function public.ps_syndic_copro(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_syndic_copro(text, uuid) to anon, authenticated;
