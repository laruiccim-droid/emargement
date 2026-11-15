-- =====================================================================================
-- NETTOYAGE DES DONNÉES DE TEST — à exécuter dans Supabase → SQL Editor → Run
-- Supprime tout ce qui concerne les syndics dont le nom commence par « TEST » (ex. TEST Cabinet),
-- les chantiers de ces syndics (ex. Le Comte de Boigne) et les chantiers dont le nom commence par « TEST » :
--   appartements, recensements signés, bons de commande, rendez-vous, badges, livraisons, remises,
--   historique, gestionnaires de test et leurs sessions, ainsi que le chantier correspondant
--   dans l'app d'émargement (table « emargements »).
-- Les autres syndics et chantiers (ex. Cabinet Pautrat) ne sont PAS touchés.
-- Les fichiers déposés (devis, bons PDF, factures, photos) restent dans le stockage : à retirer à la main
-- dans Supabase → Storage → bon-photos si besoin.
-- =====================================================================================

-- 1. Aperçu de ce qui va être supprimé (affiché en résultat)
select 'syndic' as quoi, s.nom as nom from ps_syndics s where s.nom ilike 'TEST%'
union all
select 'gestionnaire', coalesce(nullif(u.nom, ''), u.email) from ps_users u join ps_syndics s on s.id = u.syndic_id where s.nom ilike 'TEST%'
union all
select 'chantier', c.nom || coalesce(' (app : ' || nullif(c.chantier_id, '') || ')', '') from ps_copros c
  where c.nom ilike 'TEST%' or c.syndic_id in (select id from ps_syndics where nom ilike 'TEST%');

-- 2. Suppression
begin;

-- Chantiers de l'app d'émargement reliés aux chantiers de test (et leurs demandes de signature à distance)
delete from emargements where id in (
  select c.chantier_id from ps_copros c
  where coalesce(c.chantier_id, '') <> '' and (c.nom ilike 'TEST%' or c.syndic_id in (select id from ps_syndics where nom ilike 'TEST%')));

-- Chantiers du portail (tout ce qui en dépend part avec eux)
delete from ps_copros where nom ilike 'TEST%' or syndic_id in (select id from ps_syndics where nom ilike 'TEST%');

-- Gestionnaires de test (et leurs sessions), puis les syndics de test
delete from ps_users where syndic_id in (select id from ps_syndics where nom ilike 'TEST%');
delete from ps_syndics where nom ilike 'TEST%';

-- Essais de connexion enregistrés pendant les tests
do $$ begin if to_regclass('public.ps_tentatives') is not null then delete from ps_tentatives; end if; end $$;

commit;
