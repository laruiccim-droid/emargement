-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 45 : accès par le bon de livraison aussi pour les chantiers « badges seuls »
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 44.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Chantiers « badges seuls » et « Vigik seul » : l'import du listing n'est plus une livraison.
-- Harmonie déclare ensuite les badges livrés à l'agence, puis le bon de livraison est signé (sur place ou à
-- distance par le gestionnaire) : c'est cette signature qui ouvre l'accès du syndic (ou un déblocage par Harmonie).
-- Chantiers « badges seuls » déjà en cours (remises faites ou bon déjà signé) : accès laissé ouvert.
-- =====================================================================================

create or replace function public.ps__acces_syndic(p_copro uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select (c.type <> 'badges' and c.travaux <> 'vigik') or c.badges_suivi ? 'acces_le' or c.badges_suivi ? 'livraison_signee_le'
                   from ps_copros c where c.id = p_copro), false);
$$;

update public.ps_copros c set badges_suivi = badges_suivi || jsonb_build_object('acces_le', now())
where c.type = 'badges' and not c.badges_suivi ? 'acces_le' and not c.badges_suivi ? 'livraison_signee_le'
  and (exists (select 1 from public.ps_remises r where r.copro_id = c.id)
    or exists (select 1 from public.ps_livraisons v where v.copro_id = c.id and coalesce(v.signature, '') <> ''));

revoke execute on function public.ps__acces_syndic(uuid) from public, anon, authenticated;
