-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 42 : e-mail « rapprochement terminé, chantier prêt »
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 41.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Dès que le rapprochement locataires / propriétaires est terminé (feuille affichée, tous les
-- appartements ont un rendez-vous, plus aucun locataire à rattacher), un e-mail part vers
-- contact@harmonie-electricite.com (une seule fois par chantier) avec la date d'intervention.
-- Les autres alertes des scripts 33 et 37 sont reprises à l'identique.
-- =====================================================================================

create or replace function public.ps__notif_journal() returns trigger
language plpgsql security definer set search_path = public as $$
declare c ps_copros; a jsonb;
begin
  if new.copro_id is null then return new; end if;
  select * into c from ps_copros where id = new.copro_id;
  if c.id is null then return new; end if;

  if new.action = 'badges_commandes' then
    perform ps__notifier_harmonie(c.id, '', 'badges commandés',
      new.acteur || ' a commandé ' || coalesce(new.details->>'nb', '?') || ' badges.' || E'\n\n'
      || 'À vous : programmer les badges, exporter le listing puis le glisser au-dessus de la barre de progression du chantier dans le portail (cela ouvre l’espace du gestionnaire pour le recensement).');

  elsif new.action = 'sondage_clos' then
    perform ps__notif_recensement_fini(c, new.acteur || ' a clos le recensement des copropriétaires');

  elsif new.action = 'commande_signee' then
    a := ps__avancement(c);
    if coalesce((a->>'nb_logements_saisis')::int, 0) > 0 and (a->>'nb_commandes')::int >= (a->>'nb_logements_saisis')::int then
      perform ps__notif_recensement_fini(c, 'Tous les copropriétaires ont répondu au recensement');
    end if;

  elsif new.action = 'transfert_demande' then
    perform ps__notifier_harmonie(c.id, '', 'transfert à valider',
      new.acteur || ' demande à transférer ce chantier à ' || coalesce(new.details->>'vers_nom', 'un autre gestionnaire') || '.' || E'\n\n'
      || 'À vous : valider ou refuser la demande dans le portail.');

  -- Rapprochement terminé : affichage fait, tous les appartements ont un rendez-vous, plus aucun locataire à rattacher.
  elsif new.action in ('rdv_pris', 'rdv_rattache') and c.type = 'complet' and c.campagne ? 'affichee_le' then
    a := ps__avancement(c);
    if coalesce((a->>'nb_logements_saisis')::int, 0) > 0 and (a->>'nb_rdv')::int >= (a->>'nb_logements_saisis')::int
       and coalesce((a->>'nb_rdv_a_rattacher')::int, 0) = 0 then
      perform ps__notifier_harmonie(c.id, 'rapprochement_fini', 'rapprochement terminé, chantier prêt',
        'Tous les appartements ont leur rendez-vous et chaque locataire est rattaché à son propriétaire ('
        || (a->>'nb_rdv') || ' / ' || (a->>'nb_logements_saisis') || ').' || E'
'
        || coalesce('Intervention prévue : ' || (select string_agg(distinct to_char((x->>'date')::date, 'DD/MM/YYYY'), ', ')
             from jsonb_array_elements(coalesce(c.campagne->'jours', '[]'::jsonb)) x) || '.' || E'
', '') || E'
'
        || case when coalesce(c.chantier_id, '') = ''
             then 'À vous : ouvrez le portail admin, le chantier d’émargement se crée automatiquement dans l’app (logements, rendez-vous, badges, boutons d’appel).'
             else 'À vous : le chantier d’émargement existe déjà dans l’app ; mettez-le à jour depuis la fiche du chantier (bloc Émargement) pour reprendre les derniers rendez-vous.' end);
    end if;

  -- Fiche d'appartement modifiée par le gestionnaire (changement de propriétaire, de locataire ou de nom affiché).
  elsif new.action = 'appartement_modifie' and new.acteur not in ('Harmonie', 'Harmonie Électricité') then
    perform ps__notifier_harmonie(c.id, '', 'fiche appartement modifiée',
      new.acteur || ' a modifié la fiche de l’appartement '
      || coalesce(nullif(new.details->>'logement', ''), nullif('lot ' || coalesce(new.details->>'lot', ''), 'lot '), '(sans numéro)') || '.' || E'

'
      || 'Propriétaire : ' || coalesce(nullif(new.details->'avant'->>'nom', ''), '—') || ' → ' || coalesce(nullif(new.details->'apres'->>'nom', ''), '—') || E'
'
      || 'Nom affiché sur l’interphone : ' || coalesce(nullif(new.details->'avant'->>'nom_affiche', ''), '—') || ' → ' || coalesce(nullif(upper(new.details->'apres'->>'nom_affiche'), ''), '—') || E'
'
      || 'Locataire : ' || coalesce(nullif(trim(concat_ws(' ', new.details->'avant'->'locataire'->>'prenom', new.details->'avant'->'locataire'->>'nom')), ''), '—')
      || ' → ' || coalesce(nullif(trim(concat_ws(' ', new.details->'apres'->'locataire'->>'prenom', new.details->'apres'->'locataire'->>'nom')), ''), '—') || E'

'
      || case when c.travaux = 'vigik'
           then 'À vous : mettre à jour le nom du badge dans votre logiciel de gestion Vigik.'
           else 'À vous : reporter le changement dans le chantier de l’app d’émargement (fiche interphone, codification des boutons)'
             || case when c.travaux = 'interphone_vigik' then ' et dans votre logiciel de gestion Vigik.' else '.' end end);
  end if;
  return new;
exception when others then
  raise warning 'Notification Harmonie (journal) : %', sqlerrm;
  return new;
end $$;

revoke execute on function public.ps__notif_journal() from public, anon, authenticated;
