-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 52 : choix des étapes envoyées par e-mail, gestionnaire par gestionnaire
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 51.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- « E-mails d'avancement » reste l'interrupteur général du gestionnaire. En plus, chaque étape peut
-- être cochée ou non pour lui (portail admin → Syndics → « Étapes envoyées »).
-- Étapes (clé → envoyée par défaut) :
--   Interventions : i_planifiee (oui), i_en_cours (non), i_suite (oui), i_suite_planifiee (oui),
--                   i_suite_en_cours (non), i_terminee (oui)
--   Chantiers     : c_livres, c_commande, c_installation, c_reserves, c_attente_facturation, c_termine (oui)
-- =====================================================================================

alter table public.ps_users add column if not exists mail_etapes jsonb not null default '{}';

create or replace function public.ps__mail_etape_defaut(p_etape text) returns boolean
language sql immutable set search_path = public as $$
  select coalesce(p_etape, '') not in ('i_en_cours', 'i_suite_en_cours');
$$;

-- Envoi aux gestionnaires concernés qui ont activé les e-mails ET cette étape.
create or replace function public.ps__email_gestionnaires(p_syndic uuid, p_gest uuid, p_objet text, p_texte text, p_etape text) returns int
language plpgsql security definer set search_path = public as $$
declare u ps_users; n int := 0;
begin
  if coalesce(current_setting('ps.silence', true), '') = '1' or p_syndic is null then return 0; end if;
  for u in select * from ps_users where syndic_id = p_syndic and actif and mail_avancement and (p_gest is null or id = p_gest)
      and coalesce((mail_etapes->>p_etape)::boolean, ps__mail_etape_defaut(p_etape)) loop
    perform ps__email(u.email, p_objet,
      'Bonjour' || coalesce(' ' || nullif(trim(u.nom), ''), '') || ',' || E'\n\n' || p_texte
      || E'\n\nSuivi en ligne : https://www.harmonie-electricite.com/espace-syndics (« Espace syndics »)'
      || E'\n\nCordialement,\nHarmonie Électricité'
      || E'\n\n—\nVous ne souhaitez plus recevoir ces e-mails d''avancement ? Désactivez-les dans les Paramètres de votre espace syndic.');
    n := n + 1;
  end loop;
  return n;
end $$;

-- Interventions : e-mail selon l'étape atteinte (en cours inclus, si l'étape est cochée).
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
  if i.notifie ? v_cle or i.syndic_id is null or i.ignoree then return; end if;

  select (e->>'prevu')::timestamptz into v_prevu from jsonb_array_elements(i.passages) e
    where e->>'bon_valide_le' is null order by e->>'prevu' limit 1;
  v_lieu := concat_ws(' — ', nullif(i.titre, ''), nullif(i.adresse, ''))
    || coalesce(E'\nVotre référence : ' || nullif(i.reference, ''), '');
  if v_st in ('planifiee', 'suite_planifiee') then
    v_objet := case when v_st = 'planifiee' then 'Intervention planifiée' else 'Nouvelle intervention planifiée' end;
    v_texte := case when v_st = 'planifiee' then 'Votre demande d''intervention est planifiée' else 'La nouvelle intervention nécessaire est planifiée' end
      || coalesce(' le ' || ps__date_fr(v_prevu), '') || ' (date prévisionnelle, susceptible d''évoluer).' || E'\n\n' || v_lieu;
  elsif v_st in ('en_cours', 'suite_en_cours') then
    v_objet := 'Intervention en cours';
    v_texte := 'Notre technicien est sur place : l''intervention a commencé.' || E'\n\n' || v_lieu;
  elsif v_st = 'suite' then
    v_objet := 'Nouvelle intervention nécessaire';
    v_texte := 'Notre technicien est intervenu : une nouvelle intervention est nécessaire pour terminer. Nous la planifions et vous tiendrons informé.'
      || E'\n\n' || v_lieu || E'\n\nLe bon d''intervention est disponible dans votre espace syndic.';
  else
    v_objet := 'Intervention terminée';
    v_texte := 'L''intervention est terminée.' || E'\n\n' || v_lieu || E'\n\nLe bon d''intervention est disponible dans votre espace syndic.';
  end if;
  perform ps__email_gestionnaires(i.syndic_id, i.gestionnaire_id, v_objet || ' — ' || coalesce(nullif(i.titre, ''), nullif(i.adresse, ''), 'Harmonie Électricité'), v_texte, 'i_' || v_st);
end $$;

-- Chantiers : e-mail aux étapes menées par Harmonie, selon les étapes cochées.
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
    || ' avance : ' || v_lib || '.', 'c_' || new.etat);
  return new;
exception when others then
  raise warning 'E-mail d''avancement du chantier : %', sqlerrm;
  return new;
end $$;

-- L'ancienne version (sans étape) n'est plus utilisée.
drop function if exists public.ps__email_gestionnaires(uuid, uuid, text, text);

-- Portail admin : interventions et réglages (format et étapes de chaque gestionnaire).
create or replace function public.ps_admin_interventions(p_admin text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return jsonb_build_object(
    'interventions', coalesce((select jsonb_agg(ps__interv_json(i, true) order by i.a_attribuer desc, i.maj_le desc) from ps_interventions i), '[]'::jsonb),
    'syndics', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'nom', s.nom, 'reconnaissance', s.reconnaissance, 'format_bon', s.format_bon,
        'users', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'nom', u.nom, 'email', u.email, 'actif', u.actif,
            'mail_avancement', u.mail_avancement, 'format_bon', u.format_bon, 'mail_etapes', u.mail_etapes) order by u.nom)
          from ps_users u where u.syndic_id = s.id), '[]'::jsonb)) order by s.nom) from ps_syndics s), '[]'::jsonb));
end $$;

-- Portail admin : étapes envoyées à un gestionnaire ({ "i_planifiee": true, "c_commande": false, … }).
create or replace function public.ps_admin_user_mail_etapes(p_admin text, p_user uuid, p_etapes jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  update ps_users set mail_etapes = coalesce((select jsonb_object_agg(k, v) from jsonb_each(coalesce(p_etapes, '{}')) e(k, v)
      where k ~ '^[ic]_[a-z_]{3,30}$' and jsonb_typeof(v) = 'boolean'), '{}'::jsonb)
  where id = p_user;
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function public.ps__mail_etape_defaut(text) from public, anon, authenticated;
revoke execute on function public.ps__email_gestionnaires(uuid, uuid, text, text, text) from public, anon, authenticated;
revoke execute on function public.ps__interv_maj(uuid) from public, anon, authenticated;
revoke execute on function public.ps__notif_etat_gestionnaire() from public, anon, authenticated;
revoke execute on function public.ps_admin_interventions(text) from public, anon, authenticated;
grant execute on function public.ps_admin_interventions(text) to anon, authenticated;
revoke execute on function public.ps_admin_user_mail_etapes(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.ps_admin_user_mail_etapes(text, uuid, jsonb) to anon, authenticated;
