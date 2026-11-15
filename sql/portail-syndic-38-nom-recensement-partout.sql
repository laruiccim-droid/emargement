-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 38 : le nom donné au recensement devient le nom de l'appartement
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 37.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Quand un propriétaire signe le recensement, son « prénom nom » remplace le nom du fichier du syndic
-- sur l'appartement : toutes les vues (campagne d'information, listes, fiches, e-mails, PDF) affichent
-- donc le bon nom. Le nom d'origine du fichier est gardé dans « nom_fichier ».
-- Une fiche modifiée à la main (changement de propriétaire) n'est jamais écrasée.
-- Rattrapage à la fin : les appartements déjà signés sont mis à jour.
-- =====================================================================================

alter table public.ps_logements add column if not exists nom_fichier text;
update public.ps_logements set nom_fichier = nom where nom_fichier is null;

create or replace function public.ps__commande_nom() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.statut = 'signe' and new.logement_id is not null and coalesce(trim(new.nom), '') <> '' then
    update ps_logements set nom = left(trim(concat_ws(' ', nullif(trim(new.prenom), ''), trim(new.nom))), 120), maj_le = now()
    where id = new.logement_id and coord_maj_le is null;
  end if;
  return new;
exception when others then
  raise warning 'Nom du recensement non reporté : %', sqlerrm;
  return new;
end $$;

drop trigger if exists ps_commandes_nom on public.ps_commandes;
create trigger ps_commandes_nom after insert or update of statut on public.ps_commandes
  for each row execute function public.ps__commande_nom();

revoke execute on function public.ps__commande_nom() from public, anon, authenticated;

-- Rattrapage : dernier recensement signé de chaque appartement.
update public.ps_logements l set nom = left(trim(concat_ws(' ', nullif(trim(k.prenom), ''), trim(k.nom))), 120), maj_le = now()
from (select distinct on (logement_id) logement_id, prenom, nom from public.ps_commandes
      where statut = 'signe' and logement_id is not null and coalesce(trim(nom), '') <> '' order by logement_id, signe_le desc) k
where l.id = k.logement_id and l.coord_maj_le is null;
