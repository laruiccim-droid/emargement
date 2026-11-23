-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 50 : interventions dans l'espace syndic + e-mails d'avancement
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 49.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- 1. Interventions (dépannages) visibles par le syndic, alimentées automatiquement :
--    • rendez-vous de l'agenda Google (envoyés par l'app métier) → « Planifiée » ;
--    • timer lancé dans l'app métier → « Intervention en cours » ;
--    • bon validé → « Intervention terminée » (bon disponible), ou « Nouvelle intervention nécessaire »
--      si « intervention à suivre » est coché, jusqu'au dernier bon de suite.
--    Le cabinet est reconnu par l'e-mail du demandeur (gestionnaire), le domaine de son adresse,
--    ou les mots de reconnaissance du syndic (« S/C SAVOIE IMMO LAC »…). Les bons « S/C » non
--    reconnus vont dans la file « À attribuer » du portail admin.
-- 2. E-mails d'avancement aux gestionnaires (interventions et chantiers), activables ou non
--    pour chaque gestionnaire (portail admin, ou lui-même dans ses Paramètres).
-- 3. Reprise des bons validés des 60 derniers jours (sans envoyer d'e-mail).
-- =====================================================================================

alter table public.ps_users   add column if not exists mail_avancement boolean not null default true;
alter table public.ps_syndics add column if not exists reconnaissance text not null default '';
alter table public.ps_syndics add column if not exists format_bon text not null default 'sansprix';

create table if not exists public.ps_interventions (
  id uuid primary key default gen_random_uuid(),
  syndic_id uuid references public.ps_syndics(id) on delete set null,
  gestionnaire_id uuid references public.ps_users(id) on delete set null,
  a_attribuer boolean not null default false,
  ignoree boolean not null default false,
  titre text not null default '',
  client text not null default '',
  adresse text not null default '',
  reference text not null default '',
  demandeur text not null default '',
  passages jsonb not null default '[]',
  statut text not null default '',
  notifie jsonb not null default '{}',
  cree_le timestamptz not null default now(),
  maj_le timestamptz not null default now()
);
create index if not exists ps_interventions_passages on public.ps_interventions using gin (passages jsonb_path_ops);
create index if not exists ps_interventions_syndic on public.ps_interventions (syndic_id);
alter table public.ps_interventions enable row level security;
revoke all on public.ps_interventions from anon, authenticated;

-- ---------- Outils ----------
create or replace function public.ps__norm(t text) returns text
language sql immutable set search_path = public as $$
  select regexp_replace(lower(translate(coalesce(t, ''), 'ÀÂÄÉÈÊËÎÏÔÖÙÛÜÇàâäéèêëîïôöùûüç', 'AAAEEEEIIOOUUUCaaaeeeeiioouuuc')), '[^a-z0-9]', '', 'g');
$$;

create or replace function public.ps__domaine_generique(d text) returns boolean
language sql immutable set search_path = public as $$
  select d is null or d = '' or d ~ '^(gmail|googlemail|hotmail|outlook|live|msn|yahoo|ymail|icloud|me|aol|orange|wanadoo|free|sfr|neuf|laposte|bbox|numericable|gmx|protonmail|proton)\.'
      or d like '%harmonie-electricite.com';
$$;

-- Date en français : « mardi 25 novembre à 14 h 00 » (heure de Paris).
create or replace function public.ps__date_fr(t timestamptz, avec_heure boolean default true) returns text
language sql stable set search_path = public as $$
  select (array['dimanche','lundi','mardi','mercredi','jeudi','vendredi','samedi'])[extract(dow from t at time zone 'Europe/Paris')::int + 1]
    || ' ' || extract(day from t at time zone 'Europe/Paris')::int
    || ' ' || (array['janvier','février','mars','avril','mai','juin','juillet','août','septembre','octobre','novembre','décembre'])[extract(month from t at time zone 'Europe/Paris')::int]
    || case when avec_heure then ' à ' || to_char(t at time zone 'Europe/Paris', 'HH24" h "MI') else '' end;
$$;

-- Envoi d'un e-mail (service Gmail d'Harmonie). Ne bloque jamais l'action en cours.
create or replace function public.ps__email(p_to text, p_objet text, p_texte text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_jeton text;
begin
  if coalesce(p_to, '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return; end if;
  select payload->>'refresh_token' into v_jeton from notes where id = 'he_gcal_refresh';
  if coalesce(v_jeton, '') = '' then return; end if;
  perform net.http_post(
    url := 'https://send-email-harmonie.harmonie-electricite.workers.dev',
    body := jsonb_build_object('refresh_token', v_jeton, 'to', p_to, 'subject', p_objet, 'bodyText', p_texte),
    headers := '{"Content-Type": "application/json"}'::jsonb);
exception when others then
  raise warning 'E-mail non envoyé à % : %', p_to, sqlerrm;
end $$;

-- E-mail d'avancement aux gestionnaires concernés (ceux qui l'ont activé).
-- p_gest renseigné : ce gestionnaire seulement ; sinon tous les gestionnaires actifs du cabinet.
create or replace function public.ps__email_gestionnaires(p_syndic uuid, p_gest uuid, p_objet text, p_texte text) returns int
language plpgsql security definer set search_path = public as $$
declare u ps_users; n int := 0;
begin
  if coalesce(current_setting('ps.silence', true), '') = '1' or p_syndic is null then return 0; end if;
  for u in select * from ps_users where syndic_id = p_syndic and actif and mail_avancement and (p_gest is null or id = p_gest) loop
    perform ps__email(u.email, p_objet,
      'Bonjour' || coalesce(' ' || nullif(trim(u.nom), ''), '') || ',' || E'\n\n' || p_texte
      || E'\n\nSuivi en ligne : https://www.harmonie-electricite.com/espace-syndics (« Espace syndics »)'
      || E'\n\nCordialement,\nHarmonie Électricité'
      || E'\n\n—\nVous ne souhaitez plus recevoir ces e-mails d''avancement ? Désactivez-les dans les Paramètres de votre espace syndic.');
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------- Reconnaissance du cabinet ----------
-- Renvoie {syndic, gestionnaire} (vide si inconnu) à partir d'un texte (e-mails, « S/C … », nom de résidence…).
create or replace function public.ps__interv_reconnaitre(p_texte text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_mail text; v_dom text; v_id uuid; v_gest uuid; s ps_syndics; k text; v_norm text := ps__norm(p_texte);
  v_mails text[] := array(select distinct m[1] from regexp_matches(lower(coalesce(p_texte, '')), '([a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,})', 'g') m);
begin
  -- 1. Adresse exacte d'un gestionnaire. S'il n'a pas encore activé son espace personnel,
  --    la demande va au cabinet (« Toutes les demandes »), sans gestionnaire attitré.
  foreach v_mail in array v_mails loop
    select case when mdp_hash is not null and actif then id end, syndic_id into v_gest, v_id from ps_users where lower(email) = v_mail limit 1;
    if v_id is not null then return jsonb_strip_nulls(jsonb_build_object('syndic', v_id, 'gestionnaire', v_gest)); end if;
  end loop;
  -- 2. Domaine de l'adresse (gestionnaires, e-mail de l'agence, mots de reconnaissance)
  foreach v_mail in array v_mails loop
    v_dom := split_part(v_mail, '@', 2);
    if ps__domaine_generique(v_dom) then continue; end if;
    select syndic_id into v_id from ps_users where lower(email) like '%@' || v_dom limit 1;
    if v_id is null then
      select id into v_id from ps_syndics where lower(email) like '%@' || v_dom
        or ps__norm(v_dom) = any (select ps__norm(x) from unnest(string_to_array(reconnaissance, ',')) x) limit 1;
    end if;
    if v_id is not null then return jsonb_build_object('syndic', v_id); end if;
  end loop;
  -- 3. Nom du cabinet ou mots de reconnaissance présents dans le texte
  for s in select * from ps_syndics order by length(nom) desc loop
    foreach k in array (string_to_array(s.reconnaissance, ',') || s.nom) loop
      k := ps__norm(k);
      if length(k) >= 4 and position(k in v_norm) > 0 then return jsonb_build_object('syndic', s.id); end if;
    end loop;
  end loop;
  return '{}'::jsonb;
end $$;

-- ---------- État d'une intervention ----------
-- planifiee → en_cours → (suite → suite_planifiee → suite_en_cours)… → terminee
create or replace function public.ps__interv_statut(p jsonb) returns text
language plpgsql immutable set search_path = public as $$
declare x jsonb; v_bons int := 0; v_ouvert jsonb; v_suite boolean := false;
begin
  for x in select e from jsonb_array_elements(coalesce(p, '[]')) e order by coalesce(e->>'prevu', e->>'debut_le', '') loop
    if x->>'bon_valide_le' is not null then
      v_bons := v_bons + 1;
      if coalesce((x->>'suite_requise')::boolean, false) and not coalesce((x->>'suite_close')::boolean, false) then v_suite := true; end if;
    elsif v_ouvert is null then v_ouvert := x;
    end if;
  end loop;
  if v_ouvert is not null then
    return case when v_bons > 0 then case when v_ouvert->>'debut_le' is not null then 'suite_en_cours' else 'suite_planifiee' end
                else case when v_ouvert->>'debut_le' is not null then 'en_cours' else 'planifiee' end end;
  end if;
  return case when v_suite then 'suite' else 'terminee' end;
end $$;

-- Recalcule l'état ; envoie l'e-mail d'avancement si l'état change (une fois par étape).
create or replace function public.ps__interv_maj(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare i ps_interventions; v_st text; v_cle text; v_prevu timestamptz; v_lieu text; v_texte text; v_objet text;
begin
  select * into i from ps_interventions where id = p_id;
  if i.id is null then return; end if;
  if jsonb_array_length(i.passages) = 0 then delete from ps_interventions where id = p_id; return; end if;
  v_st := ps__interv_statut(i.passages);
  if v_st is not distinct from i.statut then update ps_interventions set maj_le = now() where id = p_id; return; end if;
  v_cle := v_st || ':' || jsonb_array_length(i.passages);
  update ps_interventions set statut = v_st, maj_le = now(), notifie = notifie || jsonb_build_object(v_cle, now()) where id = p_id;
  if i.notifie ? v_cle or i.syndic_id is null or i.ignoree or v_st in ('en_cours', 'suite_en_cours') then return; end if;

  select (e->>'prevu')::timestamptz into v_prevu from jsonb_array_elements(i.passages) e
    where e->>'bon_valide_le' is null order by e->>'prevu' limit 1;
  v_lieu := concat_ws(' — ', nullif(i.titre, ''), nullif(i.adresse, ''))
    || coalesce(E'\nVotre référence : ' || nullif(i.reference, ''), '');
  if v_st in ('planifiee', 'suite_planifiee') then
    v_objet := case when v_st = 'planifiee' then 'Intervention planifiée' else 'Nouvelle intervention planifiée' end;
    v_texte := case when v_st = 'planifiee' then 'Votre demande d''intervention est planifiée' else 'La nouvelle intervention nécessaire est planifiée' end
      || coalesce(' le ' || ps__date_fr(v_prevu), '') || ' (date prévisionnelle, susceptible d''évoluer).' || E'\n\n' || v_lieu;
  elsif v_st = 'suite' then
    v_objet := 'Nouvelle intervention nécessaire';
    v_texte := 'Notre technicien est intervenu : une nouvelle intervention est nécessaire pour terminer. Nous la planifions et vous tiendrons informé.'
      || E'\n\n' || v_lieu || E'\n\nLe bon d''intervention est disponible dans votre espace syndic.';
  else
    v_objet := 'Intervention terminée';
    v_texte := 'L''intervention est terminée.' || E'\n\n' || v_lieu || E'\n\nLe bon d''intervention est disponible dans votre espace syndic.';
  end if;
  perform ps__email_gestionnaires(i.syndic_id, i.gestionnaire_id, v_objet || ' — ' || coalesce(nullif(i.titre, ''), nullif(i.adresse, ''), 'Harmonie Électricité'), v_texte);
end $$;

-- Remplace (ou ajoute) le passage repéré par l'événement ou le bon.
create or replace function public.ps__interv_passage(p_id uuid, p_event text, p_bon text, p_maj jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v_trouve boolean := false; v_res jsonb := '[]'; x jsonb;
begin
  for x in select e from ps_interventions i, jsonb_array_elements(i.passages) e where i.id = p_id loop
    if not v_trouve and ((p_bon is not null and x->>'bon' = p_bon) or (p_event is not null and x->>'event' = p_event)) then
      x := x || p_maj; v_trouve := true;
    end if;
    v_res := v_res || jsonb_build_array(x);
  end loop;
  if not v_trouve then v_res := v_res || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('event', p_event, 'bon', p_bon)) || p_maj); end if;
  update ps_interventions set passages = v_res where id = p_id;
end $$;

-- Intervention d'un rendez-vous de l'agenda (création si le cabinet est reconnu). Renvoie son id ou null.
create or replace function public.ps__interv_evenement(e jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_ev text := e->>'id'; i ps_interventions; a jsonb; v_prevu timestamptz; v_texte text; v_rue text;
begin
  if v_ev is null or coalesce(e->>'status', '') = 'cancelled' then return null; end if;
  begin v_prevu := coalesce(e->'start'->>'dateTime', e->'start'->>'date')::timestamptz; exception when others then v_prevu := null; end;
  select * into i from ps_interventions where passages @> jsonb_build_array(jsonb_build_object('event', v_ev)) limit 1;
  if i.id is null then
    v_texte := concat_ws(' ', e->>'summary', e->>'location', e->>'description');
    a := ps__interv_reconnaitre(v_texte);
    if a->>'syndic' is null then return null; end if;
    -- Suite d'une intervention qui l'attend (même cabinet, même rue) ?
    select * into i from ps_interventions x where x.syndic_id = (a->>'syndic')::uuid and x.statut = 'suite' and not x.ignoree
      and length(ps__norm(split_part(x.adresse, ',', 1))) >= 6 and position(ps__norm(split_part(x.adresse, ',', 1)) in ps__norm(v_texte)) > 0
      order by x.maj_le desc limit 1;
    if i.id is null then
      insert into ps_interventions (syndic_id, gestionnaire_id, titre, adresse, demandeur)
      values ((a->>'syndic')::uuid, (a->>'gestionnaire')::uuid, left(coalesce(e->>'summary', ''), 200), left(coalesce(e->>'location', ''), 200),
        coalesce((regexp_match(lower(coalesce(e->>'description', '')), '([a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,})'))[1], ''))
      returning * into i;
    end if;
  end if;
  perform ps__interv_passage(i.id, v_ev, null, jsonb_strip_nulls(jsonb_build_object('prevu', v_prevu, 'titre', left(coalesce(e->>'summary', ''), 200))));
  return i.id;
end $$;

-- Intervention d'un bon de l'app métier (table devis, type « bon »).
create or replace function public.ps__interv_depuis_bon(p_bon text, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v_ev text := nullif(p->>'eventId', ''); v_lie text := nullif(p->>'bonLieId', ''); i ps_interventions; ip ps_interventions;
  a jsonb; v_valide boolean := p->>'statut' = 'valide'; v_maj jsonb; v_mail text := lower(coalesce(p->>'email', ''));
begin
  if p->>'type' is distinct from 'bon' then return; end if;
  select * into i from ps_interventions where passages @> jsonb_build_array(jsonb_build_object('bon', p_bon)) limit 1;
  if i.id is null and v_ev is not null then select * into i from ps_interventions where passages @> jsonb_build_array(jsonb_build_object('event', v_ev)) limit 1; end if;
  if v_lie is not null then select * into ip from ps_interventions where passages @> jsonb_build_array(jsonb_build_object('bon', v_lie)) limit 1; end if;
  -- Bon de suite : ses passages rejoignent l'intervention d'origine.
  if ip.id is not null and i.id is not null and ip.id <> i.id then
    update ps_interventions set passages = passages || i.passages where id = ip.id;
    delete from ps_interventions where id = i.id;
    select * into i from ps_interventions where id = ip.id;
  elsif i.id is null and ip.id is not null then i := ip;
  end if;
  if i.id is null then
    if not v_valide and p->>'statut' is distinct from 'en_cours' then return; end if;
    a := ps__interv_reconnaitre(concat_ws(' ', v_mail, p->>'adresseFacturation', p->>'client', p->>'motif'));
    if a->>'syndic' is null and not (coalesce(p->>'adresseFacturation', '') ~* '^\s*(s/c|c/o|chez)\M'
        or (v_mail like '%@%' and not ps__domaine_generique(split_part(v_mail, '@', 2)))) then return; end if;
    insert into ps_interventions (syndic_id, gestionnaire_id, a_attribuer, titre, client, adresse, reference, demandeur)
    values ((a->>'syndic')::uuid, (a->>'gestionnaire')::uuid, a->>'syndic' is null,
      left(split_part(coalesce(p->>'motif', ''), E'\n', 1), 200), left(coalesce(p->>'client', ''), 200), left(coalesce(p->>'adresse', ''), 200),
      left(coalesce(p->>'reference', ''), 80), v_mail)
    returning * into i;
  end if;
  update ps_interventions set
    client = case when client = '' then left(coalesce(p->>'client', ''), 200) else client end,
    adresse = case when coalesce(p->>'adresse', '') <> '' then left(p->>'adresse', 200) else adresse end,
    reference = case when coalesce(p->>'reference', '') <> '' then left(p->>'reference', 80) else reference end,
    titre = case when titre = '' then left(split_part(coalesce(p->>'motif', ''), E'\n', 1), 200) else titre end,
    demandeur = case when demandeur = '' then v_mail else demandeur end
  where id = i.id;
  v_maj := jsonb_build_object('bon', p_bon, 'numero', coalesce(p->>'numero', p_bon), 'date_bon', p->>'date', 'heure_debut', p->>'heureDebut',
    'heure_fin', p->>'heureFin', 'duree', p->>'duree',
    'suite_requise', coalesce((p->>'suiviRequis')::boolean, false), 'suite_close', coalesce((p->>'suiviClos')::boolean, false),
    'bon_valide_le', case when v_valide then coalesce((select e->>'bon_valide_le' from jsonb_array_elements(i.passages) e where e->>'bon' = p_bon limit 1), now()::text) end);
  if v_ev is not null then v_maj := v_maj || jsonb_build_object('event', v_ev); end if;
  -- Bon commencé : l'intervention a eu lieu (même sans timer).
  if not exists (select 1 from jsonb_array_elements(i.passages) e where (e->>'bon' = p_bon or e->>'event' = v_ev) and e->>'debut_le' is not null) then
    v_maj := v_maj || jsonb_build_object('debut_le', now());
  end if;
  perform ps__interv_passage(i.id, v_ev, p_bon, v_maj);
  -- bon_valide_le à null (bon remis en pause) : on retire la clé.
  if not v_valide then
    update ps_interventions set passages = (select jsonb_agg(case when e->>'bon' = p_bon then e - 'bon_valide_le' else e end) from jsonb_array_elements(passages) e) where id = i.id;
  end if;
  perform ps__interv_maj(i.id);
end $$;

-- ---------- Déclencheurs (app métier) ----------
-- Bons : à chaque enregistrement.
create or replace function public.ps__interv_trigger_bon() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.payload->>'type' = 'bon' then perform ps__interv_depuis_bon(new.id, new.payload); end if;
  return new;
exception when others then
  raise warning 'Suivi d''intervention (bon %) : %', new.id, sqlerrm;
  return new;
end $$;
drop trigger if exists ps_interventions_bon on public.devis;
create trigger ps_interventions_bon after insert or update on public.devis
  for each row execute function public.ps__interv_trigger_bon();

-- Timer lancé dans l'app métier (ligne notes « he_timer_sync ») : intervention en cours.
create or replace function public.ps__interv_trigger_timer() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_ev text; v_id uuid;
begin
  if new.id <> 'he_timer_sync' or new.payload is null or new.payload->>'eventId' is null then return new; end if;
  v_ev := new.payload->>'eventId';
  select id into v_id from ps_interventions where passages @> jsonb_build_array(jsonb_build_object('event', v_ev)) limit 1;
  if v_id is null and new.payload ? 'eventData' then v_id := ps__interv_evenement(new.payload->'eventData'); end if;
  if v_id is null then return new; end if;
  update ps_interventions set passages = (select jsonb_agg(case when e->>'event' = v_ev and e->>'debut_le' is null then e || jsonb_build_object('debut_le', now()) else e end)
    from jsonb_array_elements(passages) e) where id = v_id;
  perform ps__interv_maj(v_id);
  return new;
exception when others then
  raise warning 'Suivi d''intervention (timer) : %', sqlerrm;
  return new;
end $$;
drop trigger if exists ps_interventions_timer on public.notes;
create trigger ps_interventions_timer after insert or update on public.notes
  for each row execute function public.ps__interv_trigger_timer();

-- Agenda : l'app métier envoie les rendez-vous d'une période (code d'accès de l'app obligatoire).
-- Les rendez-vous disparus de l'agenda (annulés) sans bon ni timer sont retirés.
create or replace function public.ps_app_planning(p_debut timestamptz, p_fin timestamptz, p_events jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e jsonb; v_ids text[] := '{}'; n int := 0; r record;
begin
  if not em__ok() then raise exception 'CODE_APP'; end if;
  for e in select x from jsonb_array_elements(coalesce(p_events, '[]')) x loop
    if coalesce(e->>'status', '') <> 'cancelled' then v_ids := v_ids || (e->>'id'); end if;
    if ps__interv_evenement(e) is not null then n := n + 1; end if;
  end loop;
  for r in select i.id from ps_interventions i where exists (select 1 from jsonb_array_elements(i.passages) x
      where x->>'bon' is null and x->>'debut_le' is null and (x->>'prevu')::timestamptz >= p_debut and (x->>'prevu')::timestamptz < p_fin
        and not (x->>'event' = any (v_ids))) loop
    update ps_interventions set passages = coalesce((select jsonb_agg(x) from jsonb_array_elements(passages) x
      where not (x->>'bon' is null and x->>'debut_le' is null and (x->>'prevu')::timestamptz >= p_debut and (x->>'prevu')::timestamptz < p_fin
        and not (x->>'event' = any (v_ids)))), '[]') where id = r.id;
    perform ps__interv_maj(r.id);
  end loop;
  return jsonb_build_object('ok', true, 'interventions', n);
end $$;

-- ---------- Espace syndic ----------
create or replace function public.ps__interv_json(i ps_interventions, p_admin boolean default false) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', i.id, 'titre', i.titre, 'client', i.client, 'adresse', i.adresse, 'reference', i.reference, 'statut', i.statut,
    'cree_le', i.cree_le, 'maj_le', i.maj_le, 'gestionnaire_id', i.gestionnaire_id,
    'passages', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('prevu', e->>'prevu', 'debut_le', e->>'debut_le', 'bon', case when e->>'bon_valide_le' is not null then e->>'bon' end,
        'numero', e->>'numero', 'date_bon', e->>'date_bon', 'heure_debut', e->>'heure_debut', 'heure_fin', e->>'heure_fin', 'duree', e->>'duree',
        'bon_valide_le', e->>'bon_valide_le', 'suite_requise', e->'suite_requise'))
      || case when p_admin then jsonb_strip_nulls(jsonb_build_object('bon_brouillon', case when e->>'bon_valide_le' is null then e->>'bon' end, 'event', e->>'event', 'titre_rdv', e->>'titre')) else '{}'::jsonb end
      order by coalesce(e->>'prevu', e->>'debut_le', '')) from jsonb_array_elements(i.passages) e), '[]'::jsonb))
  || case when p_admin then jsonb_build_object('syndic_id', i.syndic_id, 'a_attribuer', i.a_attribuer, 'ignoree', i.ignoree, 'demandeur', i.demandeur) else '{}'::jsonb end;
$$;

create or replace function public.ps_syndic_interventions(p_session text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  return jsonb_build_object(
    'mail_avancement', (select mail_avancement from ps_users where id = u.id),
    'moi', u.id,
    'gestionnaires', coalesce((select jsonb_object_agg(x.id, coalesce(nullif(x.nom, ''), x.email)) from ps_users x where x.syndic_id = u.syndic_id), '{}'::jsonb),
    -- Tout le cabinet : « Mes demandes » = celles du gestionnaire ; « Toutes les demandes » = toutes,
    -- dont celles sans gestionnaire attitré (demandeur sans espace personnel).
    'interventions', coalesce((select jsonb_agg(ps__interv_json(i) order by (i.statut = 'terminee'), i.maj_le desc) from ps_interventions i
      where i.syndic_id = u.syndic_id and not i.ignoree), '[]'::jsonb));
end $$;

-- Bon d'intervention validé, pour le PDF du syndic (prix selon le format choisi pour le cabinet).
create or replace function public.ps__bon_public(p jsonb, p_format text) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('numero', coalesce(p->>'numero', p->>'id'), 'date', p->>'date', 'heure_debut', p->>'heureDebut', 'heure_fin', p->>'heureFin',
    'duree', p->>'duree', 'client', p->>'client', 'adresse', p->>'adresse', 'adresse_facturation', p->>'adresseFacturation', 'reference', p->>'reference',
    'motif', p->>'motif', 'rapport', p->>'rapport', 'suite_requise', coalesce((p->>'suiviRequis')::boolean, false), 'format', p_format,
    'show_heures', coalesce((p->>'showHeures')::boolean, true),
    'lignes', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('nom', l->>'nom', 'ref', l->>'ref', 'qty', l->'qty', 'unite', l->>'unite',
        'pu', case when p_format = 'detail' then l->'pu' end))) from jsonb_array_elements(coalesce(p->'lignes', '[]')) l), '[]'::jsonb),
    'total_ht', case when p_format <> 'sansprix' then p->'totalHT' end, 'total_tva', case when p_format <> 'sansprix' then p->'totalTVA' end,
    'total_ttc', case when p_format <> 'sansprix' then p->'totalTTC' end, 'tva', case when p_format <> 'sansprix' then p->'tvaRate' end,
    'photos', coalesce((select jsonb_agg(jsonb_build_object('url', ph->>'url', 'legende', coalesce(ph->>'caption', ph->>'legende', ''))) from jsonb_array_elements(coalesce(p->'photos', '[]')) ph where ph->>'url' like 'https://%'), '[]'::jsonb),
    'sig_client', case when coalesce((p->>'sigClientOk')::boolean, false) then p->>'sigClientData' end,
    'sig_intervenant', case when coalesce((p->>'sigIntervenantOk')::boolean, false) then p->>'sigIntervenantData' end);
$$;

create or replace function public.ps_syndic_bon(p_session text, p_bon text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; v_format text; p jsonb;
begin
  u := ps__user(p_session);
  if not exists (select 1 from ps_interventions i where i.syndic_id = u.syndic_id and not i.ignoree
      and i.passages @> jsonb_build_array(jsonb_build_object('bon', p_bon))) then raise exception 'INTROUVABLE'; end if;
  select payload into p from devis where id = p_bon and payload->>'statut' = 'valide';
  if p is null then raise exception 'INTROUVABLE'; end if;
  select coalesce(nullif(format_bon, ''), 'sansprix') into v_format from ps_syndics where id = u.syndic_id;
  return ps__bon_public(p, v_format);
end $$;

-- Le gestionnaire active ou coupe ses e-mails d'avancement.
create or replace function public.ps_syndic_mail_avancement(p_session text, p_actif boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  update ps_users set mail_avancement = coalesce(p_actif, true) where id = u.id;
  return jsonb_build_object('ok', true, 'mail_avancement', coalesce(p_actif, true));
end $$;

-- ---------- Portail admin ----------
create or replace function public.ps_admin_interventions(p_admin text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return jsonb_build_object(
    'interventions', coalesce((select jsonb_agg(ps__interv_json(i, true) order by i.a_attribuer desc, i.maj_le desc) from ps_interventions i), '[]'::jsonb),
    'syndics', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'nom', s.nom, 'reconnaissance', s.reconnaissance, 'format_bon', s.format_bon,
        'users', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'nom', u.nom, 'email', u.email, 'actif', u.actif, 'mail_avancement', u.mail_avancement) order by u.nom)
          from ps_users u where u.syndic_id = s.id), '[]'::jsonb)) order by s.nom) from ps_syndics s), '[]'::jsonb));
end $$;

create or replace function public.ps_admin_bon(p_admin text, p_bon text, p_format text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p jsonb;
begin
  perform ps__admin(p_admin);
  select payload into p from devis where id = p_bon;
  if p is null then raise exception 'INTROUVABLE'; end if;
  return ps__bon_public(p, case when p_format in ('detail', 'semi', 'sansprix') then p_format else 'sansprix' end);
end $$;

-- Attribuer (ou transférer) une intervention à un cabinet ; le domaine du demandeur est retenu pour la suite.
create or replace function public.ps_admin_intervention_attribuer(p_admin text, p_id uuid, p_syndic uuid, p_gestionnaire uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare i ps_interventions; v_dom text;
begin
  perform ps__admin(p_admin);
  if p_gestionnaire is not null and not exists (select 1 from ps_users where id = p_gestionnaire and syndic_id = p_syndic) then raise exception 'GESTIONNAIRE_AUTRE_SYNDIC'; end if;
  update ps_interventions set syndic_id = p_syndic, gestionnaire_id = p_gestionnaire, a_attribuer = false, ignoree = false, maj_le = now()
  where id = p_id returning * into i;
  if i.id is null then raise exception 'INTROUVABLE'; end if;
  v_dom := split_part(i.demandeur, '@', 2);
  if p_syndic is not null and v_dom <> '' and not ps__domaine_generique(v_dom)
     and not exists (select 1 from ps_syndics s where s.id = p_syndic and (lower(s.email) like '%@' || v_dom
       or ps__norm(v_dom) = any (select ps__norm(x) from unnest(string_to_array(s.reconnaissance, ',')) x)))
     and not exists (select 1 from ps_users u where u.syndic_id = p_syndic and lower(u.email) like '%@' || v_dom) then
    update ps_syndics set reconnaissance = trim(both ', ' from reconnaissance || ', ' || v_dom) where id = p_syndic;
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ps_admin_intervention_ignorer(p_admin text, p_id uuid, p_ignorer boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  update ps_interventions set ignoree = coalesce(p_ignorer, true), a_attribuer = case when coalesce(p_ignorer, true) then false else a_attribuer end, maj_le = now() where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ps_admin_syndic_interventions(p_admin text, p_syndic uuid, p_reconnaissance text, p_format_bon text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  update ps_syndics set reconnaissance = left(coalesce(p_reconnaissance, ''), 1000),
    format_bon = case when p_format_bon in ('detail', 'semi', 'sansprix') then p_format_bon else format_bon end where id = p_syndic;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ps_admin_user_mail_avancement(p_admin text, p_user uuid, p_actif boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  update ps_users set mail_avancement = coalesce(p_actif, true) where id = p_user;
  return jsonb_build_object('ok', true);
end $$;

-- Quand un gestionnaire active son espace, ses demandes déposées dans « Toutes les demandes » lui reviennent.
create or replace function public.ps__interv_activation() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.mdp_hash is not null and old.mdp_hash is null then
    update ps_interventions set gestionnaire_id = new.id
    where syndic_id = new.syndic_id and gestionnaire_id is null and lower(demandeur) = lower(new.email);
  end if;
  return new;
exception when others then
  raise warning 'Rattachement des demandes : %', sqlerrm;
  return new;
end $$;
drop trigger if exists ps_users_interv_activation on public.ps_users;
create trigger ps_users_interv_activation after update of mdp_hash on public.ps_users
  for each row execute function public.ps__interv_activation();

-- ---------- E-mail d'avancement des chantiers (étapes menées par Harmonie) ----------
create or replace function public.ps__notif_etat_gestionnaire() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_lib text;
begin
  if new.etat is not distinct from old.etat or new.syndic_id is null then return new; end if;
  v_lib := case new.etat
    when 'livres' then 'les badges ont été livrés à votre cabinet'
    when 'commande' then 'le matériel est commandé'
    when 'installation' then 'l''installation est en cours'
    when 'reserves' then 'des réserves sont à lever'
    when 'attente_facturation' then 'l''installation est terminée'
    when 'termine' then 'le chantier est terminé' end;
  if v_lib is null then return new; end if;
  insert into ps_notifications (copro_id, cle, objet) values (new.id, 'gestionnaire_etat_' || new.etat, v_lib) on conflict do nothing;
  if not found then return new; end if;
  perform ps__email_gestionnaires(new.syndic_id, new.gestionnaire_id, 'Avancement du chantier — ' || new.nom,
    'Le chantier de la résidence ' || new.nom || coalesce(' (' || nullif(concat_ws(' ', nullif(new.adresse, ''), nullif(new.cp, ''), nullif(new.ville, '')), '') || ')', '')
    || ' avance : ' || v_lib || '.');
  return new;
exception when others then
  raise warning 'E-mail d''avancement du chantier : %', sqlerrm;
  return new;
end $$;
drop trigger if exists ps_copros_etat_gestionnaire on public.ps_copros;
create trigger ps_copros_etat_gestionnaire after update of etat on public.ps_copros
  for each row execute function public.ps__notif_etat_gestionnaire();

-- ---------- Droits ----------
do $$
declare f text;
begin
  foreach f in array array['ps__norm(text)', 'ps__domaine_generique(text)', 'ps__date_fr(timestamptz, boolean)', 'ps__email(text, text, text)',
    'ps__email_gestionnaires(uuid, uuid, text, text)', 'ps__interv_reconnaitre(text)', 'ps__interv_statut(jsonb)', 'ps__interv_maj(uuid)',
    'ps__interv_passage(uuid, text, text, jsonb)', 'ps__interv_evenement(jsonb)', 'ps__interv_depuis_bon(text, jsonb)', 'ps__interv_trigger_bon()',
    'ps__interv_trigger_timer()', 'ps__interv_json(ps_interventions, boolean)', 'ps__bon_public(jsonb, text)', 'ps__notif_etat_gestionnaire()', 'ps__interv_activation()'] loop
    execute 'revoke execute on function public.' || f || ' from public, anon, authenticated';
  end loop;
  foreach f in array array['ps_app_planning(timestamptz, timestamptz, jsonb)', 'ps_syndic_interventions(text)', 'ps_syndic_bon(text, text)',
    'ps_syndic_mail_avancement(text, boolean)', 'ps_admin_interventions(text)', 'ps_admin_bon(text, text, text)',
    'ps_admin_intervention_attribuer(text, uuid, uuid, uuid)', 'ps_admin_intervention_ignorer(text, uuid, boolean)',
    'ps_admin_syndic_interventions(text, uuid, text, text)', 'ps_admin_user_mail_avancement(text, uuid, boolean)'] loop
    execute 'revoke execute on function public.' || f || ' from public, anon, authenticated';
    execute 'grant execute on function public.' || f || ' to anon, authenticated';
  end loop;
end $$;

-- ---------- Reprise : bons validés des 60 derniers jours (aucun e-mail) ----------
do $$
declare r record;
begin
  perform set_config('ps.silence', '1', true);
  for r in select id, payload from devis where payload->>'type' = 'bon' and payload->>'statut' = 'valide'
      and payload->>'createdAt' ~ '^[0-9]{10,15}$'
      and (payload->>'createdAt')::bigint > (extract(epoch from now() - interval '60 days') * 1000)::bigint
      order by (payload->>'createdAt')::bigint loop
    begin perform ps__interv_depuis_bon(r.id, r.payload); exception when others then raise warning 'Reprise bon % : %', r.id, sqlerrm; end;
  end loop;
  perform set_config('ps.silence', '', true);
end $$;

select count(*) filter (where syndic_id is not null) as interventions_attribuees,
       count(*) filter (where a_attribuer) as a_attribuer
from public.ps_interventions;
