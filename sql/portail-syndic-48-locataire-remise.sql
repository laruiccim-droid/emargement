-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 48 : le locataire qui reçoit des badges est enregistré sur l'appartement
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 47.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Remise de badges à un locataire (qualité « locataire ») rattachée à un appartement : son nom, son téléphone
-- et son e-mail deviennent le locataire de l'appartement (fiche appartement, admin et syndic).
-- La dernière remise à un locataire l'emporte (changement de locataire). Rattrapage des remises existantes.
-- =====================================================================================

create or replace function public.ps__remise_locataire() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.qualite = 'locataire' and new.logement_id is not null and coalesce(trim(new.proprietaire), '') <> '' and coalesce(new.statut, '') <> 'annule' then
    update ps_logements set locataire = jsonb_build_object('nom', left(trim(new.proprietaire), 80), 'prenom', '',
        'telephone', left(coalesce(trim(new.tel), ''), 30), 'email', left(lower(coalesce(trim(new.email), '')), 120)), maj_le = now()
    where id = new.logement_id and type = 'logement';
  end if;
  return new;
exception when others then
  raise warning 'Locataire non reporté sur l''appartement : %', sqlerrm;
  return new;
end $$;

drop trigger if exists ps_remises_locataire on public.ps_remises;
create trigger ps_remises_locataire after insert or update of logement_id, qualite, proprietaire, tel, email on public.ps_remises
  for each row execute function public.ps__remise_locataire();

revoke execute on function public.ps__remise_locataire() from public, anon, authenticated;

-- Rattrapage : dernière remise à un locataire de chaque appartement, si aucun locataire n'est connu.
update public.ps_logements l set locataire = jsonb_build_object('nom', left(trim(r.proprietaire), 80), 'prenom', '',
    'telephone', left(coalesce(trim(r.tel), ''), 30), 'email', left(lower(coalesce(trim(r.email), '')), 120)), maj_le = now()
from (select distinct on (logement_id) logement_id, proprietaire, tel, email from public.ps_remises
      where qualite = 'locataire' and logement_id is not null and statut <> 'annule' and coalesce(trim(proprietaire), '') <> ''
      order by logement_id, cree_le desc) r
where l.id = r.logement_id and coalesce(l.locataire->>'nom', '') = '';
