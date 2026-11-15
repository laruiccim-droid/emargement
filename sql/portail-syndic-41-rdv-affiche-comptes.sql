-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 41 : rendez-vous pris via l'affiche comptés dans l'avancement
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 40.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
--  • Les rendez-vous des locataires pris via la feuille d'affichage comptent tout de suite
--    (un par numéro d'appartement), même avant leur rattachement à un propriétaire.
--  • Au rattachement, l'appartement reçoit le numéro indiqué par le locataire s'il n'en avait pas :
--    les rendez-vous suivants pour ce numéro se rattachent alors automatiquement.
-- =====================================================================================

create or replace function public.ps__avancement(c public.ps_copros) returns jsonb
language sql stable security definer set search_path = public as $$
  with b as (select l.id, coalesce(ps__badges_attendus(l.id), 0) as att, l.badges_locataire as loc,
      coalesce((select sum(jsonb_array_length(r.badges)) from ps_remises r where r.logement_id = l.id and r.statut = 'signe'), 0) as rem
    from ps_logements l where l.copro_id = c.id and l.type = 'logement')
  select jsonb_build_object('travaux', c.travaux, 'recensement', c.recensement, 'sondage', c.sondage, 'campagne', c.campagne - 'jeton_public',
    'fourniture', c.fourniture, 'facture', c.facture, 'transfert_demande', c.transfert_demande, 'badges_suivi', c.badges_suivi,
    'nb_logements_saisis', (select count(*) from ps_logements l where l.copro_id = c.id and l.type = 'logement'),
    'nb_invites', (select count(*) from ps_logements l where l.copro_id = c.id and l.type = 'logement' and l.invite_le is not null),
    'nb_commandes', (select count(distinct k.logement_id) from ps_commandes k where k.copro_id = c.id and k.statut = 'signe'),
    -- Rendez-vous : appartements rattachés + rendez-vous pris via l'affiche pas encore rattachés (un par numéro d'appartement).
    'nb_rdv', (select count(distinct r.logement_id) from ps_rdv r where r.copro_id = c.id and r.statut = 'confirme' and r.logement_id is not null)
      + (select count(distinct lower(regexp_replace(coalesce(r.numero_appt, ''), '\s+', '', 'g'))) from ps_rdv r
         where r.copro_id = c.id and r.statut = 'confirme' and r.logement_id is null and coalesce(trim(r.numero_appt), '') <> ''),
    'nb_rdv_a_rattacher', (select count(*) from ps_rdv r where r.copro_id = c.id and r.statut = 'confirme' and r.logement_id is null),
    'nb_emarges', (select count(*) from ps_logements l where l.copro_id = c.id and l.type = 'logement' and l.emarge->>'statut' = 'signe'),
    'nb_badges_attendus', (select count(*) from b where att > 0),
    'nb_badges_ok', (select count(*) from b where att > 0 and rem + loc >= att));
$$;

create or replace function public.ps__rdv_rattacher(p_rdv uuid, p_logement uuid, p_par text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r ps_rdv;
begin
  select * into r from ps_rdv where id = p_rdv;
  if r.id is null or not exists (select 1 from ps_logements l where l.id = p_logement and l.copro_id = r.copro_id) then raise exception 'INTROUVABLE'; end if;
  update ps_rdv set statut = 'remplace' where logement_id = p_logement and statut = 'confirme' and id <> p_rdv;
  update ps_rdv set logement_id = p_logement where id = p_rdv;
  -- L'appartement prend le numéro indiqué par le locataire s'il n'en avait pas (rattachements suivants automatiques).
  update ps_logements set numero = left(trim(r.numero_appt), 30), maj_le = now()
  where id = p_logement and coalesce(trim(numero), '') = '' and coalesce(trim(r.numero_appt), '') <> '';
  perform ps__log(r.copro_id, p_par, 'rdv_rattache', jsonb_build_object('rdv', p_rdv, 'logement', p_logement));
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function public.ps__avancement(public.ps_copros) from public, anon, authenticated;
revoke execute on function public.ps__rdv_rattacher(uuid, uuid, text) from public, anon, authenticated;
