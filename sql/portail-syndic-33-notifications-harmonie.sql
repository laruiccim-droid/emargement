-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 33 : e-mail à Harmonie quand c'est à elle de jouer
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 32.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
-- À la fin du script, un e-mail de test part vers contact@harmonie-electricite.com.
--
-- L'e-mail part du serveur (extension pg_net → service d'envoi Gmail d'Harmonie), quel que soit
-- l'appareil du gestionnaire ou du copropriétaire. Un échec d'envoi ne bloque jamais leur action.
--
-- Moments où c'est au tour d'Harmonie (tous types de chantier) :
--  • Vigik seul : le syndic a commandé les badges → les programmer et déposer le listing ;
--  • recensement terminé (tous les copropriétaires ont signé, ou le gestionnaire l'a clos)
--      → interphone : commander le matériel ; Vigik seul : attribuer les badges ;
--  • demande de transfert d'un gestionnaire → la valider ;
--  • Vigik seul : 80 % des appartements ont leurs badges → l'installation peut être lancée ;
--  • Vigik seul : tous les appartements ont leurs badges (installation pas encore lancée) ;
--  • plus aucun badge en stock chez le syndic → prévoir une livraison.
-- =====================================================================================

create extension if not exists pg_net with schema extensions;

-- Envois déjà faits (évite les doublons pour les seuils : 80 %, 100 %, stock vide…).
create table if not exists public.ps_notifications (
  id bigserial primary key,
  copro_id uuid references public.ps_copros(id) on delete cascade,
  cle text not null,
  objet text not null default '',
  le timestamptz not null default now()
);
create unique index if not exists ps_notifications_cle on public.ps_notifications (copro_id, cle);
alter table public.ps_notifications enable row level security;
revoke all on public.ps_notifications from anon, authenticated;

-- Envoi : p_cle non vide = une seule fois par chantier.
create or replace function public.ps__notifier_harmonie(p_copro uuid, p_cle text, p_objet text, p_texte text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_jeton text; c ps_copros; v_syndic text; v_corps text;
begin
  if coalesce(p_cle, '') <> '' then
    insert into ps_notifications (copro_id, cle, objet) values (p_copro, p_cle, p_objet) on conflict do nothing;
    if not found then return; end if;
  end if;
  select payload->>'refresh_token' into v_jeton from notes where id = 'he_gcal_refresh';
  if coalesce(v_jeton, '') = '' then return; end if;
  select * into c from ps_copros where id = p_copro;
  select s.nom into v_syndic from ps_syndics s where s.id = c.syndic_id;
  v_corps := p_texte || E'\n\n'
    || coalesce('Chantier : ' || c.nom || coalesce(nullif(' — ' || concat_ws(' ', nullif(c.adresse, ''), nullif(c.cp, ''), nullif(c.ville, '')), ' — '), '') || E'\n', '')
    || coalesce('Syndic : ' || v_syndic || E'\n', '')
    || coalesce('Référence : ' || nullif(c.reference, '') || E'\n', '')
    || E'\nPortail admin : https://laruiccim-droid.github.io/emargement/portail-admin.html'
    || E'\n\n— Message automatique du portail syndic Harmonie Électricité';
  perform net.http_post(
    url := 'https://send-email-harmonie.harmonie-electricite.workers.dev',
    body := jsonb_build_object('refresh_token', v_jeton, 'to', 'contact@harmonie-electricite.com',
      'subject', 'À vous de jouer — ' || coalesce(c.nom, 'Portail syndic') || ' : ' || p_objet, 'bodyText', v_corps),
    headers := '{"Content-Type": "application/json"}'::jsonb);
exception when others then
  raise warning 'Notification Harmonie non envoyée : %', sqlerrm;  -- ne bloque jamais l'action du syndic
end $$;

-- Recensement terminé : prochaine étape d'Harmonie selon les travaux.
create or replace function public.ps__notif_recensement_fini(c ps_copros, p_pourquoi text) returns void
language plpgsql security definer set search_path = public as $$
declare a jsonb := ps__avancement(c);
begin
  perform ps__notifier_harmonie(c.id, 'recensement_fini', 'recensement terminé',
    p_pourquoi || ' (' || coalesce(a->>'nb_commandes', '0') || ' réponse(s) signée(s) sur ' || coalesce(a->>'nb_logements_saisis', '0') || ' appartements).' || E'\n\n'
    || case when c.travaux = 'vigik'
         then 'À vous : récupérer le « Listing des réponses » dans le portail, attribuer les badges dans votre logiciel, puis cliquer « Attributions faites : prévenir le syndic ».'
         else 'À vous : commander le matériel au fournisseur (bouton « Commander le matériel » dans le portail), puis indiquer « Matériel reçu ».' end);
end $$;

-- Événements du journal (actions du syndic et des copropriétaires).
create or replace function public.ps__notif_journal() returns trigger
language plpgsql security definer set search_path = public as $$
declare c ps_copros; a jsonb;
begin
  if new.copro_id is null then return new; end if;
  select * into c from ps_copros where id = new.copro_id;
  if c.id is null then return new; end if;

  if new.action = 'badges_commandes' then
    perform ps__notifier_harmonie(c.id, '', 'badges commandés',
      new.acteur || ' a commandé ' || coalesce(new.details->>'nb', '?') || ' badges.' || E'\n\n'
      || 'À vous : programmer les badges, exporter le listing puis le glisser au-dessus de la barre de progression du chantier dans le portail (cela ouvre l’espace du gestionnaire pour le recensement).');

  elsif new.action = 'sondage_clos' then
    perform ps__notif_recensement_fini(c, new.acteur || ' a clos le recensement des copropriétaires');

  elsif new.action = 'commande_signee' then
    a := ps__avancement(c);
    if coalesce((a->>'nb_logements_saisis')::int, 0) > 0 and (a->>'nb_commandes')::int >= (a->>'nb_logements_saisis')::int then
      perform ps__notif_recensement_fini(c, 'Tous les copropriétaires ont répondu au recensement');
    end if;

  elsif new.action = 'transfert_demande' then
    perform ps__notifier_harmonie(c.id, '', 'transfert à valider',
      new.acteur || ' demande à transférer ce chantier à ' || coalesce(new.details->>'vers_nom', 'un autre gestionnaire') || '.' || E'\n\n'
      || 'À vous : valider ou refuser la demande dans le portail.');
  end if;
  return new;
exception when others then
  raise warning 'Notification Harmonie (journal) : %', sqlerrm;
  return new;
end $$;

drop trigger if exists ps_historique_notif on public.ps_historique;
create trigger ps_historique_notif after insert on public.ps_historique
  for each row execute function public.ps__notif_journal();

-- Remises de badges : seuils de distribution et stock épuisé.
create or replace function public.ps__notif_remises() returns trigger
language plpgsql security definer set search_path = public as $$
declare c ps_copros; a jsonb; v_att int; v_ok int; v_liv int;
begin
  select * into c from ps_copros where id = new.copro_id;
  if c.id is null then return new; end if;
  a := ps__avancement(c);
  v_att := coalesce((a->>'nb_badges_attendus')::int, 0); v_ok := coalesce((a->>'nb_badges_ok')::int, 0);
  if v_att > 0 and c.travaux = 'vigik' and v_ok * 100 >= v_att * 80 and v_ok < v_att and coalesce(c.badges_suivi->>'installation_le', '') = '' then
    perform ps__notifier_harmonie(c.id, 'badges_80', '80 % des badges distribués',
      v_ok || ' appartements sur ' || v_att || ' ont récupéré leurs badges.' || E'\n\n'
      || 'À vous : vous pouvez lancer l’installation des centrales Vigik (bouton « Lancer l’installation »).');
  end if;
  if v_att > 0 and v_ok >= v_att and c.travaux = 'vigik' and coalesce(c.badges_suivi->>'installation_le', '') = '' then
    perform ps__notifier_harmonie(c.id, 'badges_100', 'tous les badges distribués',
      'Les ' || v_att || ' appartements ont récupéré leurs badges.' || E'\n\n'
      || 'À vous : lancer l’installation des centrales Vigik (bouton « Lancer l’installation »).');
  end if;
  -- Plus aucun badge en stock (clé liée au nombre de livraisons : nouvelle alerte après une nouvelle livraison).
  if exists (select 1 from ps_badges where copro_id = c.id) and not exists (select 1 from ps_badges where copro_id = c.id and statut = 'stock') then
    select count(*) into v_liv from ps_livraisons where copro_id = c.id;
    perform ps__notifier_harmonie(c.id, 'stock_vide_' || v_liv, 'plus de badges en stock',
      'Tous les badges livrés au syndic ont été remis : il n’en reste plus en stock.' || E'\n\n'
      || 'À vous : prévoir une nouvelle livraison de badges si le chantier en a encore besoin.');
  end if;
  return new;
exception when others then
  raise warning 'Notification Harmonie (remises) : %', sqlerrm;
  return new;
end $$;

drop trigger if exists ps_remises_notif on public.ps_remises;
create trigger ps_remises_notif after insert or update of statut, logement_id on public.ps_remises
  for each row execute function public.ps__notif_remises();

revoke execute on function public.ps__notifier_harmonie(uuid, text, text, text) from public, anon, authenticated;
revoke execute on function public.ps__notif_recensement_fini(public.ps_copros, text) from public, anon, authenticated;
revoke execute on function public.ps__notif_journal() from public, anon, authenticated;
revoke execute on function public.ps__notif_remises() from public, anon, authenticated;

-- E-mail de test (vérifiez la boîte contact@harmonie-electricite.com dans la minute).
do $$
declare v_jeton text;
begin
  select payload->>'refresh_token' into v_jeton from public.notes where id = 'he_gcal_refresh';
  if coalesce(v_jeton, '') = '' then raise notice 'Autorisation Google introuvable : aucun e-mail ne pourra partir.'; return; end if;
  perform net.http_post(url := 'https://send-email-harmonie.harmonie-electricite.workers.dev',
    body := jsonb_build_object('refresh_token', v_jeton, 'to', 'contact@harmonie-electricite.com',
      'subject', 'Portail syndic : alertes « À vous de jouer » activées',
      'bodyText', 'Ce message confirme que le portail syndic peut vous prévenir par e-mail quand c''est à vous de jouer sur un chantier (badges commandés, recensement terminé, transfert à valider, badges distribués, stock épuisé).'
        || E'\n\n— Message automatique du portail syndic Harmonie Électricité'),
    headers := '{"Content-Type": "application/json"}'::jsonb);
end $$;
