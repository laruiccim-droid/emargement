-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 49 : e-mail à Harmonie quand un gestionnaire active son espace
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 48.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Dès qu'un gestionnaire choisit son mot de passe (lien d'invitation), un e-mail part vers
-- contact@harmonie-electricite.com : nom, adresse, cabinet et chantiers du cabinet (avec ceux encore
-- bloqués en attente de la signature du bon de livraison).
-- =====================================================================================

-- Envoi simple d'un e-mail d'information à Harmonie (même service Gmail que les autres alertes).
create or replace function public.ps__email_harmonie(p_objet text, p_texte text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_jeton text;
begin
  select payload->>'refresh_token' into v_jeton from notes where id = 'he_gcal_refresh';
  if coalesce(v_jeton, '') = '' then return; end if;
  perform net.http_post(
    url := 'https://send-email-harmonie.harmonie-electricite.workers.dev',
    body := jsonb_build_object('refresh_token', v_jeton, 'to', 'contact@harmonie-electricite.com', 'subject', p_objet,
      'bodyText', p_texte || E'\n\nPortail admin : https://laruiccim-droid.github.io/emargement/portail-admin.html' || E'\n\n— Message automatique du portail syndic Harmonie Électricité'),
    headers := '{"Content-Type": "application/json"}'::jsonb);
exception when others then
  raise warning 'E-mail à Harmonie non envoyé : %', sqlerrm;
end $$;

create or replace function public.ps__notif_activation() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_syndic text; v_chantiers text;
begin
  if new.active_le is not null and old.active_le is null then
    select nom into v_syndic from ps_syndics where id = new.syndic_id;
    select string_agg('• ' || c.nom
        || case when (c.type = 'badges' or c.travaux = 'vigik') and not c.badges_suivi ? 'livraison_signee_le' and not c.badges_suivi ? 'acces_le'
             then case when c.badges_suivi ? 'livre_le' then ' — bloqué : bon de livraison à signer' else ' — bloqué : badges pas encore livrés' end else '' end,
        E'\n' order by c.nom)
      into v_chantiers
    from ps_copros c where c.syndic_id = new.syndic_id and (c.gestionnaire_id is null or c.gestionnaire_id = new.id);
    perform ps__email_harmonie('Espace syndic activé — ' || coalesce(nullif(new.nom, ''), new.email),
      coalesce(nullif(new.nom, ''), new.email) || ' (' || coalesce(v_syndic, 'cabinet inconnu') || ', ' || new.email || ') a activé son espace syndic.'
      || E'\n\n' || coalesce('Chantiers accessibles :' || E'\n' || v_chantiers, 'Aucun chantier rattaché pour le moment.'));
  end if;
  return new;
exception when others then
  raise warning 'Alerte d''activation non envoyée : %', sqlerrm;
  return new;
end $$;

drop trigger if exists ps_users_activation on public.ps_users;
create trigger ps_users_activation after update of active_le on public.ps_users
  for each row execute function public.ps__notif_activation();

revoke execute on function public.ps__email_harmonie(text, text) from public, anon, authenticated;
revoke execute on function public.ps__notif_activation() from public, anon, authenticated;
