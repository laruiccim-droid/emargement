-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 11 : recensement des logements par le gestionnaire
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 10.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Chantier « complet » : le gestionnaire pose les étiquettes de numérotation, puis saisit
-- (ou importe) les appartements : n° d'étiquette, n° de lot, propriétaire, téléphone, e-mails.
-- Si le chantier comprend du Vigik : badges du stock syndic et des intervenants (ménage, ascenseur…).
-- Ces logements serviront ensuite au sondage des copropriétaires.
-- =====================================================================================

create table if not exists public.ps_logements (
  id uuid primary key default gen_random_uuid(),
  copro_id uuid not null references public.ps_copros(id) on delete cascade,
  type text not null default 'logement',      -- logement | intervenant | stock
  numero text not null default '',            -- n° de l'étiquette blanche (appartement)
  lot text not null default '',
  nom text not null default '',               -- propriétaire, ou société intervenante
  telephone text not null default '',
  emails jsonb not null default '[]',
  badges integer not null default 0,          -- intervenants et stock : nombre de badges
  ordre integer not null default 0,
  cree_le timestamptz not null default now(),
  maj_le timestamptz not null default now()
);
create index if not exists ps_logements_copro on public.ps_logements (copro_id, ordre);
alter table public.ps_logements enable row level security;
revoke all on public.ps_logements from anon, authenticated;

-- État du recensement : { etape: 'etiquettes' | 'saisie' | 'pret', nb_logements, etiquettes_le, enregistre_le, par }
alter table public.ps_copros add column if not exists recensement jsonb not null default '{}'::jsonb;

create or replace function public.ps__logements(p_copro uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'type', l.type, 'numero', l.numero, 'lot', l.lot, 'nom', l.nom,
    'telephone', l.telephone, 'emails', l.emails, 'badges', l.badges) order by l.type <> 'logement', l.ordre), '[]'::jsonb)
  from ps_logements l where l.copro_id = p_copro;
$$;

-- Gestionnaire : lire le recensement d'un chantier.
create or replace function public.ps_syndic_recensement(p_session text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  return (select jsonb_build_object(
    'copro', jsonb_build_object('id', c.id, 'nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'type', c.type, 'travaux', c.travaux,
      'marque_interphone', c.marque_interphone, 'marque_vigik', c.marque_vigik,
      'appartements_devis', coalesce(nullif(c.devis->'extrait'->>'appartements', '')::int, 0)),
    'recensement', c.recensement, 'logements', ps__logements(c.id))
  from ps_copros c where c.id = p_copro);
end $$;

-- Gestionnaire : enregistrer le recensement (étape, étiquettes posées, logements, intervenants, stock).
-- p = { etape, nb_logements, etiquettes: true|false, logements: [{id?, type, numero, lot, nom, telephone, emails[], badges}] }
create or replace function public.ps_syndic_recensement_enregistrer(p_session text, p_copro uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; v_rec jsonb; v_garder uuid[] := '{}'; x jsonb; v_id uuid; v_i int := 0; v_type text; v_emails jsonb;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  select recensement into v_rec from ps_copros where id = p_copro;
  v_rec := v_rec || jsonb_build_object(
    'etape', case when p->>'etape' in ('etiquettes', 'saisie', 'pret') then p->>'etape' else coalesce(v_rec->>'etape', 'etiquettes') end,
    'nb_logements', least(greatest(coalesce(nullif(p->>'nb_logements', '')::int, (v_rec->>'nb_logements')::int, 0), 0), 2000),
    'enregistre_le', now(), 'par', coalesce(nullif(u.nom, ''), u.email));
  if (p->>'etiquettes')::boolean is true and coalesce(v_rec->>'etiquettes_le', '') = '' then v_rec := v_rec || jsonb_build_object('etiquettes_le', now()); end if;
  if (p->>'etiquettes')::boolean is false then v_rec := v_rec - 'etiquettes_le'; end if;
  update ps_copros set recensement = v_rec, maj_le = now() where id = p_copro;

  if jsonb_typeof(p->'logements') = 'array' then
    if jsonb_array_length(p->'logements') > 2000 then raise exception 'TROP_DE_LOGEMENTS'; end if;
    for x in select * from jsonb_array_elements(p->'logements') loop
      v_i := v_i + 1;
      v_type := case when x->>'type' in ('logement', 'intervenant', 'stock') then x->>'type' else 'logement' end;
      select coalesce(jsonb_agg(distinct lower(trim(e))), '[]'::jsonb) into v_emails
        from jsonb_array_elements_text(case when jsonb_typeof(x->'emails') = 'array' then x->'emails' else '[]'::jsonb end) e
        where trim(e) ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$';
      v_id := null;
      if coalesce(x->>'id', '') ~ '^[0-9a-f-]{36}$' then
        update ps_logements set type = v_type, numero = left(coalesce(trim(x->>'numero'), ''), 30), lot = left(coalesce(trim(x->>'lot'), ''), 30),
          nom = left(coalesce(trim(x->>'nom'), ''), 120), telephone = left(coalesce(trim(x->>'telephone'), ''), 30), emails = v_emails,
          badges = least(greatest(coalesce(nullif(x->>'badges', '')::int, 0), 0), 500), ordre = v_i, maj_le = now()
        where id = (x->>'id')::uuid and copro_id = p_copro returning id into v_id;
      end if;
      if v_id is null then
        insert into ps_logements (copro_id, type, numero, lot, nom, telephone, emails, badges, ordre)
        values (p_copro, v_type, left(coalesce(trim(x->>'numero'), ''), 30), left(coalesce(trim(x->>'lot'), ''), 30), left(coalesce(trim(x->>'nom'), ''), 120),
          left(coalesce(trim(x->>'telephone'), ''), 30), v_emails, least(greatest(coalesce(nullif(x->>'badges', '')::int, 0), 0), 500), v_i)
        returning id into v_id;
      end if;
      v_garder := v_garder || v_id;
    end loop;
    delete from ps_logements where copro_id = p_copro and not (id = any(v_garder));
  end if;
  perform ps__log(p_copro, coalesce(nullif(u.nom, ''), u.email), 'recensement', jsonb_build_object('etape', v_rec->>'etape', 'logements', v_i));
  return jsonb_build_object('recensement', v_rec, 'logements', ps__logements(p_copro));
end $$;

-- Administrateur : voir le recensement d'un chantier.
create or replace function public.ps_admin_recensement(p_admin text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return (select jsonb_build_object('recensement', c.recensement, 'logements', ps__logements(c.id)) from ps_copros c where c.id = p_copro);
end $$;

-- Gestionnaire : la fiche du chantier indique aussi le type, les marques et l'état du recensement.
create or replace function public.ps_syndic_copro(p_session text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  return (select jsonb_build_object(
    'copro', jsonb_build_object('id', c.id, 'nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference, 'type', c.type, 'etat', c.etat,
      'travaux', c.travaux, 'vigik', c.vigik, 'marque_interphone', c.marque_interphone, 'marque_vigik', c.marque_vigik, 'recensement', c.recensement,
      'nb_logements_saisis', (select count(*) from ps_logements l where l.copro_id = c.id and l.type = 'logement')),
    'compteurs', ps__compteurs(c.id),
    'badges', coalesce((select jsonb_agg(jsonb_build_object('numero', b.numero, 'statut', b.statut, 'droit', b.droit, 'remise_id', b.remise_id) order by b.numero)
                from ps_badges b where b.copro_id = c.id), '[]'::jsonb),
    'remises', coalesce((select jsonb_agg(ps__remise_resume(r) order by r.cree_le desc) from ps_remises r where r.copro_id = c.id), '[]'::jsonb))
  from ps_copros c where c.id = p_copro);
end $$;

revoke execute on function public.ps__logements(uuid) from public, anon, authenticated;
revoke execute on function public.ps_syndic_recensement(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_syndic_recensement(text, uuid) to anon, authenticated;
revoke execute on function public.ps_syndic_recensement_enregistrer(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.ps_syndic_recensement_enregistrer(text, uuid, jsonb) to anon, authenticated;
revoke execute on function public.ps_admin_recensement(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_admin_recensement(text, uuid) to anon, authenticated;
revoke execute on function public.ps_syndic_copro(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_syndic_copro(text, uuid) to anon, authenticated;
