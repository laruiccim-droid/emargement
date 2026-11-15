-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 25 : fiche complète de chaque appartement
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 24.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Pour l'onglet « Appartements » (espace syndic et portail admin) : par appartement, le propriétaire
-- et le locataire, le bon de commande (modèle, plaque, badges), les badges remis (propriétaire /
-- locataire), le rendez-vous, l'émargement et tous les documents signés.
-- =====================================================================================

create or replace function public.ps__appartements(p_copro uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'copro', jsonb_build_object('id', c.id, 'nom', c.nom, 'marque_interphone', c.marque_interphone, 'marque_vigik', c.marque_vigik, 'travaux', c.travaux),
    'logements', coalesce((select jsonb_agg(jsonb_build_object(
        'id', l.id, 'numero', l.numero, 'lot', l.lot, 'nom', l.nom, 'telephone', l.telephone, 'emails', l.emails,
        'badges_locataire', l.badges_locataire, 'emarge', l.emarge,
        'commande', (select ps__commande_json(k) from ps_commandes k where k.logement_id = l.id and k.statut = 'signe' order by k.signe_le desc limit 1),
        'rdv', (select ps__rdv_json(r) from ps_rdv r where r.logement_id = l.id and r.statut = 'confirme' order by r.cree_le desc limit 1),
        'remises', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'numero', r.numero, 'statut', r.statut, 'badges', r.badges,
            'proprietaire', r.proprietaire, 'qualite', r.qualite, 'mode', r.mode_signature, 'signe_le', r.signe_le, 'cree_le', r.cree_le) order by r.cree_le)
          from ps_remises r where r.logement_id = l.id and r.statut <> 'annule'), '[]'::jsonb))
      order by l.ordre) from ps_logements l where l.copro_id = c.id and l.type = 'logement'), '[]'::jsonb))
  from ps_copros c where c.id = p_copro;
$$;

create or replace function public.ps_syndic_appartements(p_session text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  return ps__appartements(p_copro);
end $$;

create or replace function public.ps_admin_appartements(p_admin text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return ps__appartements(p_copro);
end $$;

revoke execute on function public.ps__appartements(uuid) from public, anon, authenticated;
revoke execute on function public.ps_syndic_appartements(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_syndic_appartements(text, uuid) to anon, authenticated;
revoke execute on function public.ps_admin_appartements(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_admin_appartements(text, uuid) to anon, authenticated;
