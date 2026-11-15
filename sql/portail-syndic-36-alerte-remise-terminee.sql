-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 36 : e-mail « remise des badges terminée »
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 35.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Quel que soit le type de chantier : quand tous les appartements ont leurs badges (remis au
-- propriétaire, ou laissés pour le locataire à la demande du bailleur), un e-mail part vers
-- contact@harmonie-electricite.com (une seule fois par chantier). Il indique combien de badges
-- restent à remettre aux locataires le jour de l'installation.
-- Les autres alertes du script 33 (80 %, stock épuisé) sont gardées.
-- =====================================================================================

-- Contrôle commun aux remises et aux badges réservés aux locataires.
create or replace function public.ps__notif_badges_copro(p_copro uuid) returns void
language plpgsql security definer set search_path = public as $$
declare c ps_copros; a jsonb; v_att int; v_ok int; v_liv int; v_loc int;
begin
  select * into c from ps_copros where id = p_copro;
  if c.id is null then return; end if;
  a := ps__avancement(c);
  v_att := coalesce((a->>'nb_badges_attendus')::int, 0); v_ok := coalesce((a->>'nb_badges_ok')::int, 0);

  -- Vigik seul : feu vert à 80 % pour l'installation.
  if v_att > 0 and c.travaux = 'vigik' and v_ok * 100 >= v_att * 80 and v_ok < v_att and coalesce(c.badges_suivi->>'installation_le', '') = '' then
    perform ps__notifier_harmonie(c.id, 'badges_80', '80 % des badges distribués',
      v_ok || ' appartements sur ' || v_att || ' ont récupéré leurs badges.' || E'\n\n'
      || 'À vous : vous pouvez lancer l’installation des centrales Vigik (bouton « Lancer l’installation »).');
  end if;

  -- Remise terminée : tous les appartements servis.
  if v_att > 0 and v_ok >= v_att then
    select coalesce(sum(badges_locataire), 0), count(*) filter (where badges_locataire > 0) into v_loc, v_liv
      from ps_logements where copro_id = c.id and type = 'logement';
    perform ps__notifier_harmonie(c.id, 'badges_100', 'remise des badges terminée',
      'Le syndic a terminé la remise des badges : les ' || v_att || ' appartements ont été servis.'
      || case when v_loc > 0 then E'\n' || v_loc || ' badge(s) restent à remettre aux locataires le jour de l’installation (' || v_liv || ' appartement(s) en location).' else '' end
      || E'\n\n'
      || case when c.travaux = 'vigik' and coalesce(c.badges_suivi->>'installation_le', '') = ''
           then 'À vous : lancer l’installation des centrales Vigik (bouton « Lancer l’installation »).'
           else 'Pour information : la distribution des badges est terminée.' end);
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

create or replace function public.ps__notif_remises() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform ps__notif_badges_copro(new.copro_id);
  return new;
end $$;

-- Badges laissés au locataire : enregistrés juste après le rattachement de la remise à l'appartement.
create or replace function public.ps__notif_logements() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.type = 'logement' and new.badges_locataire is distinct from old.badges_locataire then perform ps__notif_badges_copro(new.copro_id); end if;
  return new;
end $$;

drop trigger if exists ps_logements_notif on public.ps_logements;
create trigger ps_logements_notif after update of badges_locataire on public.ps_logements
  for each row execute function public.ps__notif_logements();

revoke execute on function public.ps__notif_badges_copro(uuid) from public, anon, authenticated;
revoke execute on function public.ps__notif_remises() from public, anon, authenticated;
revoke execute on function public.ps__notif_logements() from public, anon, authenticated;

-- Rattrapage : chantiers en cours dont la remise est déjà terminée (e-mail envoyé maintenant, une seule fois).
do $$
declare r record;
begin
  for r in select id from public.ps_copros where etat not in ('facture', 'termine') loop
    perform public.ps__notif_badges_copro(r.id);
  end loop;
end $$;
