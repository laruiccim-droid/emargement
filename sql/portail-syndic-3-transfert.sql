-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 3 : transfert d'un chantier
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 et 2.
-- Ne touche pas à la table « emargements ».
--
--  • Un chantier peut avoir un gestionnaire en charge (ps_copros.gestionnaire_id) :
--      - renseigné  → seul ce gestionnaire voit le chantier dans son espace ;
--      - vide       → tous les gestionnaires du cabinet le voient (comme avant).
--  • ps_admin_copro_transferer : vers un autre gestionnaire du même cabinet ou vers un autre syndic.
--  • Chaque remise garde le syndic qui l'a émise (ps_remises.syndic_id) : après un transfert, les bons
--    déjà signés conservent l'en-tête, le tampon et la signature de leur syndic d'origine.
-- =====================================================================================

alter table public.ps_copros  add column if not exists gestionnaire_id uuid references public.ps_users(id) on delete set null;
alter table public.ps_remises add column if not exists syndic_id uuid references public.ps_syndics(id) on delete set null;
update public.ps_remises r set syndic_id = c.syndic_id from public.ps_copros c where c.id = r.copro_id and r.syndic_id is null;

-- Le gestionnaire voit-il ce chantier ? (même cabinet, et chantier non attribué ou attribué à lui)
create or replace function public.ps__copro_visible(p_copro uuid, u public.ps_users) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from ps_copros c where c.id = p_copro and c.syndic_id = u.syndic_id
                  and (c.gestionnaire_id is null or c.gestionnaire_id = u.id));
$$;

-- ---------- Administrateur ----------
create or replace function public.ps_admin_copro_transferer(p_admin text, p_copro uuid, p_syndic uuid, p_gestionnaire uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c ps_copros; v_nom_s text; v_nom_g text;
begin
  perform ps__admin(p_admin);
  select * into c from ps_copros where id = p_copro for update;
  if c.id is null then raise exception 'INTROUVABLE'; end if;
  if p_syndic is null or not exists (select 1 from ps_syndics where id = p_syndic) then raise exception 'INTROUVABLE'; end if;
  if p_gestionnaire is not null and not exists (select 1 from ps_users where id = p_gestionnaire and syndic_id = p_syndic) then
    raise exception 'GESTIONNAIRE_AUTRE_SYNDIC';
  end if;
  update ps_copros set syndic_id = p_syndic, gestionnaire_id = p_gestionnaire, maj_le = now() where id = p_copro;
  select nom into v_nom_s from ps_syndics where id = p_syndic;
  select coalesce(nullif(nom, ''), email) into v_nom_g from ps_users where id = p_gestionnaire;
  perform ps__log(p_copro, 'Harmonie', 'transfert', jsonb_build_object(
    'syndic_avant', c.syndic_id, 'gestionnaire_avant', c.gestionnaire_id,
    'syndic', p_syndic, 'syndic_nom', v_nom_s, 'gestionnaire', p_gestionnaire, 'gestionnaire_nom', coalesce(v_nom_g, 'tout le cabinet')));
  return jsonb_build_object('ok', true);
end $$;

-- État général : ajoute le gestionnaire en charge de chaque chantier.
create or replace function public.ps_admin_etat(p_admin text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return jsonb_build_object(
    'syndics', coalesce((select jsonb_agg(ps__syndic_public(s) || jsonb_build_object(
        'users', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'nom', u.nom, 'email', u.email, 'tel', u.tel, 'actif', u.actif,
            'statut', case when not u.actif then 'desactive' when u.mdp_hash is not null then 'actif' else 'invite' end,
            'invitation', case when u.mdp_hash is null and u.invitation_expire > now() then u.invitation end,
            'invitation_expire', u.invitation_expire, 'active_le', u.active_le, 'derniere_connexion', u.derniere_connexion) order by u.nom)
          from ps_users u where u.syndic_id = s.id), '[]'::jsonb)) order by s.nom) from ps_syndics s), '[]'::jsonb),
    'copros', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville,
        'reference', c.reference, 'type', c.type, 'etat', c.etat, 'syndic_id', c.syndic_id, 'gestionnaire_id', c.gestionnaire_id,
        'chantier_id', c.chantier_id, 'notes', c.notes, 'cree_le', c.cree_le, 'compteurs', ps__compteurs(c.id)) order by c.cree_le desc) from ps_copros c), '[]'::jsonb));
end $$;

-- Modification d'un chantier : si le syndic change par le formulaire, le gestionnaire en charge est retiré.
create or replace function public.ps_admin_copro_enregistrer(p_admin text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_ancien uuid;
begin
  perform ps__admin(p_admin);
  if coalesce(trim(p->>'nom'), '') = '' then raise exception 'NOM_OBLIGATOIRE'; end if;
  if v_id is null then
    insert into ps_copros (syndic_id, nom, adresse, cp, ville, reference, type, etat, chantier_id, notes)
    values (nullif(p->>'syndic_id','')::uuid, trim(p->>'nom'), coalesce(p->>'adresse',''), coalesce(p->>'cp',''), coalesce(p->>'ville',''),
      coalesce(p->>'reference',''), coalesce(nullif(p->>'type',''),'badges'), coalesce(nullif(p->>'etat',''),'commence'), coalesce(p->>'chantier_id',''), coalesce(p->>'notes',''))
    returning id into v_id;
    perform ps__log(v_id, 'Harmonie', 'copro_creee', p);
  else
    select syndic_id into v_ancien from ps_copros where id = v_id;
    update ps_copros set syndic_id = nullif(p->>'syndic_id','')::uuid,
      gestionnaire_id = case when syndic_id is distinct from nullif(p->>'syndic_id','')::uuid then null else gestionnaire_id end,
      nom = trim(p->>'nom'), adresse = coalesce(p->>'adresse',''), cp = coalesce(p->>'cp',''),
      ville = coalesce(p->>'ville',''), reference = coalesce(p->>'reference',''), type = coalesce(nullif(p->>'type',''),'badges'),
      etat = coalesce(nullif(p->>'etat',''),'commence'), chantier_id = coalesce(p->>'chantier_id',''), notes = coalesce(p->>'notes',''), maj_le = now()
    where id = v_id;
    if v_ancien is distinct from nullif(p->>'syndic_id','')::uuid then
      perform ps__log(v_id, 'Harmonie', 'syndic_change', jsonb_build_object('avant', v_ancien, 'apres', p->>'syndic_id'));
    end if;
  end if;
  return jsonb_build_object('id', v_id);
end $$;

-- Détail d'un chantier : gestionnaire en charge en plus.
create or replace function public.ps_admin_copro_detail(p_admin text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return (select jsonb_build_object(
    'copro', to_jsonb(c) - 'compteur_bons',
    'syndic', (select ps__syndic_public(s) from ps_syndics s where s.id = c.syndic_id),
    'gestionnaire', (select jsonb_build_object('id', u.id, 'nom', u.nom, 'email', u.email) from ps_users u where u.id = c.gestionnaire_id),
    'compteurs', ps__compteurs(c.id),
    'badges', coalesce((select jsonb_agg(jsonb_build_object('numero', b.numero, 'statut', b.statut, 'remise_id', b.remise_id, 'livraison_id', b.livraison_id) order by b.numero)
                from ps_badges b where b.copro_id = c.id), '[]'::jsonb),
    'livraisons', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'badges', l.badges, 'commentaire', l.commentaire, 'signataire', l.signataire,
                'signature', l.signature, 'signe_le', l.signe_le, 'cree_le', l.cree_le) order by l.cree_le desc) from ps_livraisons l where l.copro_id = c.id), '[]'::jsonb),
    'remises', coalesce((select jsonb_agg(ps__remise_resume(r) order by r.cree_le desc) from ps_remises r where r.copro_id = c.id), '[]'::jsonb))
  from ps_copros c where c.id = p_copro);
end $$;

-- Remise complète : en-tête du syndic qui l'a émise.
create or replace function public.ps_admin_remise(p_admin text, p_remise uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return (select to_jsonb(r) - 'jeton' || jsonb_build_object(
      'copro', jsonb_build_object('nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference),
      'syndic', (select ps__syndic_public(s) from ps_syndics s where s.id = coalesce(r.syndic_id, c.syndic_id)))
    from ps_remises r join ps_copros c on c.id = r.copro_id where r.id = p_remise);
end $$;

-- ---------- Gestionnaire : ne voit que les chantiers non attribués de son cabinet et les siens ----------
create or replace function public.ps_syndic_etat(p_session text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  return jsonb_build_object(
    'user', jsonb_build_object('id', u.id, 'nom', u.nom, 'email', u.email, 'tel', u.tel),
    'syndic', (select ps__syndic_public(s) from ps_syndics s where s.id = u.syndic_id),
    'copros', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville,
        'reference', c.reference, 'type', c.type, 'etat', c.etat, 'compteurs', ps__compteurs(c.id)) order by c.nom)
      from ps_copros c where c.syndic_id = u.syndic_id and (c.gestionnaire_id is null or c.gestionnaire_id = u.id)), '[]'::jsonb));
end $$;

create or replace function public.ps_syndic_copro(p_session text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  return (select jsonb_build_object(
    'copro', jsonb_build_object('id', c.id, 'nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference, 'type', c.type, 'etat', c.etat),
    'compteurs', ps__compteurs(c.id),
    'badges', coalesce((select jsonb_agg(jsonb_build_object('numero', b.numero, 'statut', b.statut, 'remise_id', b.remise_id) order by b.numero)
                from ps_badges b where b.copro_id = c.id), '[]'::jsonb),
    'remises', coalesce((select jsonb_agg(ps__remise_resume(r) order by r.cree_le desc) from ps_remises r where r.copro_id = c.id), '[]'::jsonb))
  from ps_copros c where c.id = p_copro);
end $$;

create or replace function public.ps_syndic_remise_creer(p_session text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; v_copro uuid := (p->>'copro_id')::uuid; v_badges jsonb; v_n int; v_id uuid; v_jeton text := ps__jeton();
  v_signe boolean := coalesce(p->>'signature', '') <> ''; v_compteur int; v_nb_ok int;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(v_copro, u) then raise exception 'INTROUVABLE'; end if;
  select coalesce(jsonb_agg(distinct upper(trim(x))), '[]') into v_badges from jsonb_array_elements_text(coalesce(p->'badges','[]')) x where trim(x) <> '';
  v_n := jsonb_array_length(v_badges);
  if v_n = 0 then raise exception 'AUCUN_BADGE'; end if;
  if coalesce(trim(p->>'proprietaire'), '') = '' then raise exception 'NOM_OBLIGATOIRE'; end if;
  perform 1 from ps_badges where copro_id = v_copro and numero in (select jsonb_array_elements_text(v_badges)) for update;
  select count(*) into v_nb_ok from ps_badges where copro_id = v_copro and statut = 'stock' and numero in (select jsonb_array_elements_text(v_badges));
  if v_nb_ok <> v_n then raise exception 'BADGE_INDISPONIBLE'; end if;
  update ps_copros set compteur_bons = compteur_bons + 1 where id = v_copro returning compteur_bons into v_compteur;
  insert into ps_remises (copro_id, syndic_id, numero, jeton, statut, badges, lot, batiment, proprietaire, qualite, email, tel, commentaire, photos,
    agent_id, agent_nom, mode_signature, signataire, signature, signe_le, navigateur, ip)
  values (v_copro, u.syndic_id, 'RB-' || to_char(now(), 'YYYY') || '-' || lpad(v_compteur::text, 3, '0'), v_jeton,
    case when v_signe then 'signe' else 'attente' end, v_badges,
    coalesce(p->>'lot',''), coalesce(p->>'batiment',''), trim(p->>'proprietaire'), coalesce(nullif(p->>'qualite',''),'proprietaire'),
    coalesce(p->>'email',''), coalesce(p->>'tel',''), coalesce(p->>'commentaire',''), coalesce(p->'photos','[]'),
    u.id, u.nom, case when v_signe then 'ecran' else '' end,
    case when v_signe then coalesce(nullif(trim(p->>'signataire'),''), trim(p->>'proprietaire')) else '' end,
    coalesce(p->>'signature',''), case when v_signe then now() end,
    case when v_signe then coalesce(p->>'navigateur','') else '' end, case when v_signe then ps__ip() else '' end)
  returning id into v_id;
  update ps_badges set statut = case when v_signe then 'remis' else 'reserve' end, remise_id = v_id, maj_le = now()
   where copro_id = v_copro and numero in (select jsonb_array_elements_text(v_badges));
  update ps_copros set etat = case when etat in ('commence','livres') then 'distribution' else etat end, maj_le = now() where id = v_copro;
  perform ps__log(v_copro, u.nom, 'remise_creee', jsonb_build_object('remise', v_id, 'badges', v_badges, 'signe', v_signe));
  return jsonb_build_object('id', v_id, 'jeton', v_jeton, 'statut', case when v_signe then 'signe' else 'attente' end);
end $$;

create or replace function public.ps_syndic_remise(p_session text, p_remise uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  return (select to_jsonb(r) - 'ip' || jsonb_build_object(
      'jeton', case when r.statut = 'attente' then r.jeton end,
      'copro', jsonb_build_object('nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference),
      'syndic', (select ps__syndic_public(s) from ps_syndics s where s.id = coalesce(r.syndic_id, c.syndic_id)))
    from ps_remises r join ps_copros c on c.id = r.copro_id where r.id = p_remise and ps__copro_visible(c.id, u));
end $$;

create or replace function public.ps_syndic_remise_statut(p_session text, p_remise uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  return (select jsonb_build_object('statut', r.statut, 'signe_le', r.signe_le)
    from ps_remises r where r.id = p_remise and ps__copro_visible(r.copro_id, u));
end $$;

create or replace function public.ps_syndic_remise_annuler(p_session text, p_remise uuid, p_motif text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; r ps_remises;
begin
  u := ps__user(p_session);
  select rr.* into r from ps_remises rr where rr.id = p_remise and ps__copro_visible(rr.copro_id, u) for update;
  if r.id is null then raise exception 'INTROUVABLE'; end if;
  if r.statut = 'annule' then return jsonb_build_object('ok', true); end if;
  if coalesce(trim(p_motif), '') = '' then raise exception 'MOTIF_OBLIGATOIRE'; end if;
  update ps_remises set statut = 'annule', annule_le = now(), annule_motif = trim(p_motif) where id = r.id;
  update ps_badges set statut = 'stock', remise_id = null, maj_le = now() where remise_id = r.id and statut in ('reserve','remis');
  perform ps__log(r.copro_id, u.nom, 'remise_annulee', jsonb_build_object('remise', r.id, 'motif', p_motif));
  return jsonb_build_object('ok', true);
end $$;

-- ---------- Résident : contact du syndic qui a émis la remise ----------
create or replace function public.ps_remise_lire(p_jeton text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if p_jeton !~ '^[0-9a-f]{32}$' then raise exception 'LIEN_INVALIDE'; end if;
  return (select jsonb_build_object('numero', r.numero, 'statut', r.statut, 'badges', r.badges, 'lot', r.lot, 'batiment', r.batiment,
      'proprietaire', r.proprietaire, 'qualite', r.qualite, 'commentaire', r.commentaire, 'signe_le', r.signe_le, 'cree_le', r.cree_le,
      'copro', jsonb_build_object('nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville),
      'syndic', (select jsonb_build_object('nom', s.nom, 'tel', s.tel, 'email', s.email) from ps_syndics s where s.id = coalesce(r.syndic_id, c.syndic_id)))
    from ps_remises r join ps_copros c on c.id = r.copro_id where r.jeton = p_jeton);
end $$;

-- ---------- Droits ----------
revoke execute on function public.ps__copro_visible(uuid, public.ps_users) from public, anon, authenticated;
revoke execute on function public.ps_admin_copro_transferer(text, uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.ps_admin_copro_transferer(text, uuid, uuid, uuid) to anon, authenticated;
