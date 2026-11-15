-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 32 : prix du recensement repris du devis du chantier
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 31.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Le portail admin lit les lignes de prix du devis déposé sur le chantier, les rapproche des articles
-- du catalogue et les garde dans devis.extrait.prix = { "<réf. catalogue>": <prix HT>, … }.
-- Les articles proposés au recensement (page des copropriétaires, liste du gestionnaire, bons de commande signés)
-- prennent ce prix ; tout le reste (photo, description, brochure, notice, TVA) reste celui du catalogue.
-- Sans prix pour un article : prix du catalogue.
-- =====================================================================================

create or replace function public.ps__articles_sondage(c public.ps_copros) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(
    case when jsonb_typeof(c.devis->'extrait'->'prix'->a.ref) = 'number' and (c.devis->'extrait'->'prix'->>a.ref)::numeric > 0
      then (to_jsonb(a) - 'cree_le' - 'maj_le' - 'actif')
           || jsonb_build_object('prix_ht', round((c.devis->'extrait'->'prix'->>a.ref)::numeric, 2), 'prix_catalogue', a.prix_ht, 'prix_devis', true)
      else to_jsonb(a) - 'cree_le' - 'maj_le' - 'actif' end
    order by a.ordre, a.prix_ht), '[]'::jsonb)
  from ps_catalogue a
  where a.actif and (
    (c.travaux <> 'vigik' and a.marque = c.marque_interphone and a.type in ('combine', 'moniteur', 'plaque'))
    or (c.travaux <> 'interphone' and a.type = 'badge' and a.id = (
      select b.id from ps_catalogue b where b.actif and b.type = 'badge'
      order by (b.marque = c.marque_vigik) desc, (b.marque = c.marque_interphone) desc, b.prix_ht limit 1)));
$$;

revoke execute on function public.ps__articles_sondage(public.ps_copros) from public, anon, authenticated;
