-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 40 : un seul rendez-vous par appartement depuis l'affiche
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 39.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Prise de rendez-vous par le QR code de la feuille d'affichage : si l'appartement indiqué a déjà un
-- rendez-vous confirmé (pris par le propriétaire avec son lien ou par une autre personne via l'affiche),
-- la réservation est refusée (RDV_DEJA_PRIS) et la date du rendez-vous existant est renvoyée.
-- Le lien personnel du propriétaire permet toujours de changer de créneau.
-- =====================================================================================

create or replace function public.ps_rdv_reserver(p_jeton text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l ps_logements; c ps_copros; v_debut timestamptz; e jsonb; v_lg uuid; v_mode text; r ps_rdv; v_num text; v_ancien uuid; v_deja timestamptz;
begin
  if coalesce(p_jeton, '') !~ '^[0-9a-f]{32}$' then raise exception 'LIEN_INVALIDE'; end if;
  select * into l from ps_logements where jeton = p_jeton;
  if l.id is not null then select * into c from ps_copros where id = l.copro_id; v_mode := 'lien';
  else select * into c from ps_copros where campagne->>'jeton_public' = p_jeton; v_mode := 'affiche'; end if;
  if c.id is null then raise exception 'LIEN_INVALIDE'; end if;
  if coalesce(trim(p->>'nom'), '') = '' or coalesce(trim(p->>'prenom'), '') = '' then raise exception 'NOM_OBLIGATOIRE'; end if;
  v_num := left(trim(coalesce(p->>'numero_appt', '')), 30);
  if v_mode = 'affiche' then
    if coalesce(trim(p->>'telephone'), '') = '' then raise exception 'TELEPHONE_OBLIGATOIRE'; end if;
    if v_num = '' then raise exception 'APPARTEMENT_OBLIGATOIRE'; end if;
    -- Rattachement automatique par le numéro de l'étiquette blanche.
    select id into v_lg from ps_logements where copro_id = c.id and type = 'logement'
      and lower(regexp_replace(numero, '\s+', '', 'g')) = lower(regexp_replace(v_num, '\s+', '', 'g')) limit 1;
    -- Un seul rendez-vous par appartement depuis l'affiche : numéro déjà réservé → refus, avec la date du rendez-vous existant.
    select r.debut into v_deja from ps_rdv r
    where r.copro_id = c.id and r.statut = 'confirme'
      and ((v_lg is not null and r.logement_id = v_lg)
        or lower(regexp_replace(coalesce(r.numero_appt, ''), '\s+', '', 'g')) = lower(regexp_replace(v_num, '\s+', '', 'g')))
    order by r.cree_le desc limit 1;
    if v_deja is not null then
      raise exception 'RDV_DEJA_PRIS' using detail = to_char(v_deja at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
    end if;
  else
    v_lg := l.id; v_num := coalesce(nullif(v_num, ''), l.numero);
  end if;
  v_debut := (p->>'debut')::timestamptz;
  select x into e from jsonb_array_elements(ps__creneaux(c)) x where (x->>'debut')::timestamptz = v_debut limit 1;
  if e is null then raise exception 'CRENEAU_INDISPONIBLE'; end if;
  select id into v_ancien from ps_rdv where v_lg is not null and logement_id = v_lg and statut = 'confirme' and debut = v_debut limit 1;
  if (e->>'places')::int <= 0 and v_ancien is null then raise exception 'CRENEAU_COMPLET'; end if;
  if v_lg is not null then update ps_rdv set statut = 'remplace' where logement_id = v_lg and statut = 'confirme'; end if;
  insert into ps_rdv (copro_id, logement_id, debut, fin, nom, prenom, telephone, email, numero_appt, qualite, source, ip)
  values (c.id, v_lg, v_debut, (e->>'fin')::timestamptz, left(trim(p->>'nom'), 80), left(trim(p->>'prenom'), 80),
    left(trim(coalesce(p->>'telephone', '')), 30), left(lower(trim(coalesce(p->>'email', ''))), 120), v_num,
    case when v_mode = 'lien' then 'occupant' else 'locataire' end, v_mode, ps__ip())
  returning * into r;
  perform ps__log(c.id, trim(p->>'prenom') || ' ' || trim(p->>'nom'), 'rdv_pris', jsonb_build_object('appartement', v_num, 'debut', v_debut, 'rattache', v_lg is not null));
  return ps__rdv_json(r) || jsonb_build_object('rattache', v_lg is not null);
end $$;

revoke execute on function public.ps_rdv_reserver(text, jsonb) from public, anon, authenticated;
grant execute on function public.ps_rdv_reserver(text, jsonb) to anon, authenticated;
