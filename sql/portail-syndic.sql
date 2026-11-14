-- =====================================================================================
-- PORTAIL SYNDIC — à exécuter une seule fois dans Supabase → SQL Editor → Run
-- Ajout pur : ne modifie PAS la table « emargements » ni rien d'existant.
--
-- Sécurité : les tables ps_* sont FERMÉES aux visiteurs (RLS activée, aucune règle d'accès).
-- On n'y accède que par les fonctions ps_* ci-dessous, qui vérifient à chaque appel :
--   • le mot de passe administrateur (toi, Harmonie Électricité),
--   • ou la session d'un gestionnaire de syndic (il ne voit que les copros de SON cabinet),
--   • ou le lien de signature d'une remise (le résident ne voit que SA remise).
-- =====================================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- Tables ----------
create table if not exists public.ps_config (
  cle text primary key,
  valeur text not null
);

create table if not exists public.ps_syndics (
  id uuid primary key default gen_random_uuid(),
  nom text not null,
  adresse text default '', cp text default '', ville text default '',
  tel text default '', email text default '', siret text default '',
  tampon text default '',          -- image PNG (data URL)
  signature text default '',       -- image PNG (data URL)
  signataire text default '',      -- nom sous la signature
  cree_le timestamptz not null default now(),
  maj_le timestamptz not null default now()
);

create table if not exists public.ps_users (
  id uuid primary key default gen_random_uuid(),
  syndic_id uuid not null references public.ps_syndics(id) on delete cascade,
  nom text not null default '',
  email text not null,
  tel text default '',
  mdp_hash text,
  invitation text unique,
  invitation_expire timestamptz,
  actif boolean not null default true,
  cree_le timestamptz not null default now(),
  active_le timestamptz,
  derniere_connexion timestamptz
);
create unique index if not exists ps_users_email on public.ps_users (lower(email));

create table if not exists public.ps_sessions (
  jeton text primary key,
  user_id uuid not null references public.ps_users(id) on delete cascade,
  cree_le timestamptz not null default now(),
  expire_le timestamptz not null default now() + interval '90 days'
);

create table if not exists public.ps_copros (
  id uuid primary key default gen_random_uuid(),
  syndic_id uuid references public.ps_syndics(id) on delete set null,
  nom text not null,
  adresse text default '', cp text default '', ville text default '',
  reference text default '',
  type text not null default 'badges',     -- 'badges' (badges seuls) | 'complet'
  etat text not null default 'commence',   -- voir ps_etats ci-dessous
  chantier_id text default '',             -- lien éventuel vers un chantier CH_… de l'app d'émargement
  notes text default '',
  compteur_bons integer not null default 0,
  cree_le timestamptz not null default now(),
  maj_le timestamptz not null default now()
);

create table if not exists public.ps_livraisons (
  id uuid primary key default gen_random_uuid(),
  copro_id uuid not null references public.ps_copros(id) on delete cascade,
  badges jsonb not null default '[]',
  commentaire text default '',
  signataire text default '', signature text default '', signe_le timestamptz,
  cree_le timestamptz not null default now()
);

create table if not exists public.ps_remises (
  id uuid primary key default gen_random_uuid(),
  copro_id uuid not null references public.ps_copros(id) on delete cascade,
  numero text not null,
  jeton text unique not null,
  statut text not null default 'attente',  -- 'attente' | 'signe' | 'annule'
  badges jsonb not null default '[]',
  lot text default '', batiment text default '',
  proprietaire text default '', qualite text default 'proprietaire', -- 'proprietaire' | 'locataire' | 'autre'
  email text default '', tel text default '',
  commentaire text default '',
  photos jsonb not null default '[]',      -- images JPEG compressées (data URL)
  agent_id uuid references public.ps_users(id) on delete set null,
  agent_nom text default '',
  mode_signature text default '',          -- 'ecran' | 'distance'
  signataire text default '', signature text default '', signe_le timestamptz,
  navigateur text default '', ip text default '',
  annule_le timestamptz, annule_motif text default '',
  controle_acces boolean not null default false,  -- coché par Harmonie quand c'est créé dans le logiciel
  controle_le timestamptz,
  cree_le timestamptz not null default now()
);

create table if not exists public.ps_badges (
  copro_id uuid not null references public.ps_copros(id) on delete cascade,
  numero text not null,
  livraison_id uuid references public.ps_livraisons(id) on delete set null,
  statut text not null default 'stock',    -- 'stock' | 'reserve' | 'remis' | 'perdu' | 'desactive'
  remise_id uuid references public.ps_remises(id) on delete set null,
  maj_le timestamptz not null default now(),
  primary key (copro_id, numero)
);

create table if not exists public.ps_historique (
  id bigserial primary key,
  copro_id uuid references public.ps_copros(id) on delete cascade,
  acteur text not null default '',
  action text not null,
  details jsonb not null default '{}',
  le timestamptz not null default now()
);

-- Fermeture : RLS sans aucune règle = aucun accès direct depuis l'API publique.
alter table public.ps_config     enable row level security;
alter table public.ps_syndics    enable row level security;
alter table public.ps_users      enable row level security;
alter table public.ps_sessions   enable row level security;
alter table public.ps_copros     enable row level security;
alter table public.ps_livraisons enable row level security;
alter table public.ps_remises    enable row level security;
alter table public.ps_badges     enable row level security;
alter table public.ps_historique enable row level security;
revoke all on public.ps_config, public.ps_syndics, public.ps_users, public.ps_sessions, public.ps_copros,
  public.ps_livraisons, public.ps_remises, public.ps_badges, public.ps_historique from anon, authenticated;

-- ---------- Outils internes ----------
create or replace function public.ps__jeton() returns text
language sql volatile set search_path = public, extensions as $$
  select encode(extensions.gen_random_bytes(16), 'hex');
$$;

create or replace function public.ps__admin(p_admin text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  select valeur into h from ps_config where cle = 'admin_hash';
  if h is null then raise exception 'ADMIN_NON_DEFINI'; end if;
  if p_admin is null or extensions.crypt(p_admin, h) <> h then raise exception 'ADMIN_REFUSE'; end if;
end $$;

create or replace function public.ps__user(p_session text) returns public.ps_users
language plpgsql security definer set search_path = public, extensions as $$
declare u ps_users;
begin
  select us.* into u from ps_sessions s join ps_users us on us.id = s.user_id
   where s.jeton = p_session and s.expire_le > now() and us.actif;
  if u.id is null then raise exception 'SESSION_INVALIDE'; end if;
  return u;
end $$;

create or replace function public.ps__ip() returns text
language sql stable as $$
  select coalesce(split_part(nullif(current_setting('request.headers', true), '')::json->>'x-forwarded-for', ',', 1), '');
$$;

create or replace function public.ps__compteurs(p_copro uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'livres', count(*),
    'stock', count(*) filter (where statut = 'stock'),
    'reserves', count(*) filter (where statut = 'reserve'),
    'remis', count(*) filter (where statut = 'remis'),
    'perdus', count(*) filter (where statut in ('perdu','desactive')),
    'remises', (select count(*) from ps_remises r where r.copro_id = p_copro and r.statut = 'signe'),
    'attente', (select count(*) from ps_remises r where r.copro_id = p_copro and r.statut = 'attente'),
    'a_creer', (select count(*) from ps_remises r where r.copro_id = p_copro and r.statut = 'signe' and not r.controle_acces))
  from ps_badges b where b.copro_id = p_copro;
$$;

create or replace function public.ps__log(p_copro uuid, p_acteur text, p_action text, p_details jsonb default '{}') returns void
language sql security definer set search_path = public as $$
  insert into ps_historique (copro_id, acteur, action, details) values (p_copro, coalesce(p_acteur, ''), p_action, coalesce(p_details, '{}'));
$$;

-- Remise sans les images lourdes (listes)
create or replace function public.ps__remise_resume(r public.ps_remises) returns jsonb
language sql stable as $$
  select jsonb_build_object('id', r.id, 'numero', r.numero, 'statut', r.statut, 'badges', r.badges, 'lot', r.lot, 'batiment', r.batiment,
    'proprietaire', r.proprietaire, 'qualite', r.qualite, 'email', r.email, 'tel', r.tel, 'commentaire', r.commentaire,
    'nb_photos', jsonb_array_length(r.photos), 'agent_nom', r.agent_nom, 'mode_signature', r.mode_signature, 'signataire', r.signataire,
    'signe_le', r.signe_le, 'annule_le', r.annule_le, 'annule_motif', r.annule_motif, 'controle_acces', r.controle_acces,
    'controle_le', r.controle_le, 'jeton', case when r.statut = 'attente' then r.jeton end, 'cree_le', r.cree_le);
$$;

create or replace function public.ps__syndic_public(s public.ps_syndics) returns jsonb
language sql stable as $$
  select jsonb_build_object('id', s.id, 'nom', s.nom, 'adresse', s.adresse, 'cp', s.cp, 'ville', s.ville, 'tel', s.tel, 'email', s.email,
    'siret', s.siret, 'tampon', s.tampon, 'signature', s.signature, 'signataire', s.signataire);
$$;

-- =====================================================================================
-- ADMINISTRATEUR (Harmonie Électricité)
-- =====================================================================================

-- Premier lancement : crée le mot de passe administrateur (refusé s'il existe déjà).
create or replace function public.ps_admin_initialiser(p_mdp text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  if exists (select 1 from ps_config where cle = 'admin_hash') then raise exception 'ADMIN_DEJA_DEFINI'; end if;
  if length(coalesce(p_mdp, '')) < 8 then raise exception 'MDP_TROP_COURT'; end if;
  insert into ps_config values ('admin_hash', extensions.crypt(p_mdp, extensions.gen_salt('bf', 10)));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ps_admin_statut() returns jsonb
language sql security definer set search_path = public as $$
  select jsonb_build_object('initialise', exists (select 1 from ps_config where cle = 'admin_hash'));
$$;

create or replace function public.ps_admin_changer_mdp(p_admin text, p_nouveau text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform ps__admin(p_admin);
  if length(coalesce(p_nouveau, '')) < 8 then raise exception 'MDP_TROP_COURT'; end if;
  update ps_config set valeur = extensions.crypt(p_nouveau, extensions.gen_salt('bf', 10)) where cle = 'admin_hash';
  return jsonb_build_object('ok', true);
end $$;

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
        'reference', c.reference, 'type', c.type, 'etat', c.etat, 'syndic_id', c.syndic_id, 'chantier_id', c.chantier_id, 'notes', c.notes,
        'cree_le', c.cree_le, 'compteurs', ps__compteurs(c.id)) order by c.cree_le desc) from ps_copros c), '[]'::jsonb));
end $$;

create or replace function public.ps_admin_syndic_enregistrer(p_admin text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := nullif(p->>'id', '')::uuid;
begin
  perform ps__admin(p_admin);
  if coalesce(trim(p->>'nom'), '') = '' then raise exception 'NOM_OBLIGATOIRE'; end if;
  if v_id is null then
    insert into ps_syndics (nom, adresse, cp, ville, tel, email, siret)
    values (trim(p->>'nom'), coalesce(p->>'adresse',''), coalesce(p->>'cp',''), coalesce(p->>'ville',''), coalesce(p->>'tel',''), coalesce(p->>'email',''), coalesce(p->>'siret',''))
    returning id into v_id;
  else
    update ps_syndics set nom = trim(p->>'nom'), adresse = coalesce(p->>'adresse',''), cp = coalesce(p->>'cp',''), ville = coalesce(p->>'ville',''),
      tel = coalesce(p->>'tel',''), email = coalesce(p->>'email',''), siret = coalesce(p->>'siret',''), maj_le = now() where id = v_id;
  end if;
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.ps_admin_user_enregistrer(p_admin text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_email text := lower(trim(coalesce(p->>'email', '')));
begin
  perform ps__admin(p_admin);
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'EMAIL_INVALIDE'; end if;
  if exists (select 1 from ps_users where lower(email) = v_email and id is distinct from v_id) then raise exception 'EMAIL_DEJA_UTILISE'; end if;
  if v_id is null then
    insert into ps_users (syndic_id, nom, email, tel) values ((p->>'syndic_id')::uuid, coalesce(trim(p->>'nom'),''), v_email, coalesce(p->>'tel',''))
    returning id into v_id;
  else
    update ps_users set nom = coalesce(trim(p->>'nom'),''), email = v_email, tel = coalesce(p->>'tel','') where id = v_id;
  end if;
  return jsonb_build_object('id', v_id);
end $$;

-- Crée (ou recrée) le lien d'invitation d'un gestionnaire, valable 14 jours.
create or replace function public.ps_admin_user_inviter(p_admin text, p_user uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_jeton text := ps__jeton();
begin
  perform ps__admin(p_admin);
  update ps_users set invitation = v_jeton, invitation_expire = now() + interval '14 days', actif = true where id = p_user;
  if not found then raise exception 'INTROUVABLE'; end if;
  return jsonb_build_object('invitation', v_jeton);
end $$;

create or replace function public.ps_admin_user_actif(p_admin text, p_user uuid, p_actif boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  update ps_users set actif = p_actif where id = p_user;
  if not p_actif then delete from ps_sessions where user_id = p_user; end if;
  return jsonb_build_object('ok', true);
end $$;

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
    update ps_copros set syndic_id = nullif(p->>'syndic_id','')::uuid, nom = trim(p->>'nom'), adresse = coalesce(p->>'adresse',''), cp = coalesce(p->>'cp',''),
      ville = coalesce(p->>'ville',''), reference = coalesce(p->>'reference',''), type = coalesce(nullif(p->>'type',''),'badges'),
      etat = coalesce(nullif(p->>'etat',''),'commence'), chantier_id = coalesce(p->>'chantier_id',''), notes = coalesce(p->>'notes',''), maj_le = now()
    where id = v_id;
    if v_ancien is distinct from nullif(p->>'syndic_id','')::uuid then
      perform ps__log(v_id, 'Harmonie', 'syndic_change', jsonb_build_object('avant', v_ancien, 'apres', p->>'syndic_id'));
    end if;
  end if;
  return jsonb_build_object('id', v_id);
end $$;

-- Livraison de badges au syndic : ajoute au stock les n° absents de cette copro.
-- Retourne les n° ajoutés, ceux déjà présents dans la copro, et ceux connus dans une autre copro (ajoutés quand même, pour info).
create or replace function public.ps_admin_livrer(p_admin text, p_copro uuid, p_badges jsonb, p_commentaire text default '',
  p_signataire text default '', p_signature text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_liv uuid; v_num text; v_ajoutes jsonb := '[]'; v_deja jsonb := '[]'; v_ailleurs jsonb := '[]'; v_autre text;
begin
  perform ps__admin(p_admin);
  if not exists (select 1 from ps_copros where id = p_copro) then raise exception 'INTROUVABLE'; end if;
  insert into ps_livraisons (copro_id, commentaire, signataire, signature, signe_le)
  values (p_copro, coalesce(p_commentaire,''), coalesce(p_signataire,''), coalesce(p_signature,''), case when coalesce(p_signature,'') <> '' then now() end)
  returning id into v_liv;
  for v_num in select distinct upper(trim(x)) from jsonb_array_elements_text(p_badges) x where trim(x) <> '' loop
    if exists (select 1 from ps_badges where copro_id = p_copro and numero = v_num) then
      v_deja := v_deja || to_jsonb(v_num);
    else
      select c.nom into v_autre from ps_badges b join ps_copros c on c.id = b.copro_id where b.numero = v_num and b.copro_id <> p_copro limit 1;
      if v_autre is not null then v_ailleurs := v_ailleurs || jsonb_build_object('numero', v_num, 'copro', v_autre); end if;
      insert into ps_badges (copro_id, numero, livraison_id) values (p_copro, v_num, v_liv);
      v_ajoutes := v_ajoutes || to_jsonb(v_num);
    end if;
  end loop;
  if jsonb_array_length(v_ajoutes) = 0 then
    delete from ps_livraisons where id = v_liv; v_liv := null;
  else
    update ps_livraisons set badges = v_ajoutes where id = v_liv;
    update ps_copros set etat = case when etat = 'commence' and type = 'badges' then 'livres' else etat end, maj_le = now() where id = p_copro;
    perform ps__log(p_copro, 'Harmonie', 'livraison', jsonb_build_object('livraison', v_liv, 'nombre', jsonb_array_length(v_ajoutes)));
  end if;
  return jsonb_build_object('livraison', v_liv, 'ajoutes', v_ajoutes, 'deja', v_deja, 'ailleurs', v_ailleurs);
end $$;

-- Retire du stock un badge pas encore remis (erreur de saisie).
create or replace function public.ps_admin_badge_retirer(p_admin text, p_copro uuid, p_numero text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  delete from ps_badges where copro_id = p_copro and numero = p_numero and statut = 'stock';
  if not found then raise exception 'BADGE_NON_RETIRABLE'; end if;
  perform ps__log(p_copro, 'Harmonie', 'badge_retire', jsonb_build_object('numero', p_numero));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ps_admin_copro_detail(p_admin text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return (select jsonb_build_object(
    'copro', to_jsonb(c) - 'compteur_bons',
    'syndic', (select ps__syndic_public(s) from ps_syndics s where s.id = c.syndic_id),
    'compteurs', ps__compteurs(c.id),
    'badges', coalesce((select jsonb_agg(jsonb_build_object('numero', b.numero, 'statut', b.statut, 'remise_id', b.remise_id, 'livraison_id', b.livraison_id) order by b.numero)
                from ps_badges b where b.copro_id = c.id), '[]'::jsonb),
    'livraisons', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'badges', l.badges, 'commentaire', l.commentaire, 'signataire', l.signataire,
                'signature', l.signature, 'signe_le', l.signe_le, 'cree_le', l.cree_le) order by l.cree_le desc) from ps_livraisons l where l.copro_id = c.id), '[]'::jsonb),
    'remises', coalesce((select jsonb_agg(ps__remise_resume(r) order by r.cree_le desc) from ps_remises r where r.copro_id = c.id), '[]'::jsonb))
  from ps_copros c where c.id = p_copro);
end $$;

-- Remise complète (avec signatures et photos) pour refaire le PDF.
create or replace function public.ps_admin_remise(p_admin text, p_remise uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return (select to_jsonb(r) - 'jeton' || jsonb_build_object(
      'copro', jsonb_build_object('nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference),
      'syndic', (select ps__syndic_public(s) from ps_syndics s where s.id = c.syndic_id))
    from ps_remises r join ps_copros c on c.id = r.copro_id where r.id = p_remise);
end $$;

create or replace function public.ps_admin_controle(p_admin text, p_remise uuid, p_fait boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  update ps_remises set controle_acces = p_fait, controle_le = case when p_fait then now() end where id = p_remise;
  return jsonb_build_object('ok', true);
end $$;

-- =====================================================================================
-- GESTIONNAIRE DE SYNDIC
-- =====================================================================================

create or replace function public.ps_invitation_lire(p_invitation text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  select u.nom, u.email, s.nom as syndic into r from ps_users u join ps_syndics s on s.id = u.syndic_id
   where u.invitation = p_invitation and u.invitation_expire > now() and u.actif;
  if r is null then raise exception 'INVITATION_INVALIDE'; end if;
  return jsonb_build_object('nom', r.nom, 'email', r.email, 'syndic', r.syndic);
end $$;

-- Le gestionnaire choisit son mot de passe depuis le lien d'invitation : renvoie une session.
create or replace function public.ps_activer(p_invitation text, p_mdp text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u ps_users; v_session text := ps__jeton() || ps__jeton();
begin
  select * into u from ps_users where invitation = p_invitation and invitation_expire > now() and actif;
  if u.id is null then raise exception 'INVITATION_INVALIDE'; end if;
  if length(coalesce(p_mdp, '')) < 8 then raise exception 'MDP_TROP_COURT'; end if;
  update ps_users set mdp_hash = extensions.crypt(p_mdp, extensions.gen_salt('bf', 10)), invitation = null, invitation_expire = null,
    active_le = coalesce(active_le, now()), derniere_connexion = now() where id = u.id;
  insert into ps_sessions (jeton, user_id) values (v_session, u.id);
  return jsonb_build_object('session', v_session);
end $$;

create or replace function public.ps_connexion(p_email text, p_mdp text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u ps_users; v_session text := ps__jeton() || ps__jeton();
begin
  select * into u from ps_users where lower(email) = lower(trim(p_email)) and actif;
  if u.id is null or u.mdp_hash is null or extensions.crypt(coalesce(p_mdp,''), u.mdp_hash) <> u.mdp_hash then
    perform pg_sleep(0.5);
    raise exception 'IDENTIFIANTS_INCORRECTS';
  end if;
  update ps_users set derniere_connexion = now() where id = u.id;
  delete from ps_sessions where expire_le < now();
  insert into ps_sessions (jeton, user_id) values (v_session, u.id);
  return jsonb_build_object('session', v_session);
end $$;

create or replace function public.ps_deconnexion(p_session text) returns jsonb
language sql security definer set search_path = public as $$
  delete from ps_sessions where jeton = p_session returning jsonb_build_object('ok', true);
$$;

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
      from ps_copros c where c.syndic_id = u.syndic_id), '[]'::jsonb));
end $$;

-- Premier démarrage / paramètres : coordonnées, tampon, signature du cabinet.
create or replace function public.ps_syndic_profil(p_session text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  update ps_syndics set
    nom = coalesce(nullif(trim(p->>'nom'), ''), nom),
    adresse = coalesce(p->>'adresse', adresse), cp = coalesce(p->>'cp', cp), ville = coalesce(p->>'ville', ville),
    tel = coalesce(p->>'tel', tel), email = coalesce(p->>'email', email), siret = coalesce(p->>'siret', siret),
    tampon = coalesce(p->>'tampon', tampon), signature = coalesce(p->>'signature', signature), signataire = coalesce(p->>'signataire', signataire),
    maj_le = now()
  where id = u.syndic_id;
  if p ? 'user_nom' or p ? 'user_tel' then
    update ps_users set nom = coalesce(nullif(trim(p->>'user_nom'), ''), nom), tel = coalesce(p->>'user_tel', tel) where id = u.id;
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ps_syndic_mdp(p_session text, p_ancien text, p_nouveau text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  if extensions.crypt(coalesce(p_ancien,''), u.mdp_hash) <> u.mdp_hash then raise exception 'IDENTIFIANTS_INCORRECTS'; end if;
  if length(coalesce(p_nouveau, '')) < 8 then raise exception 'MDP_TROP_COURT'; end if;
  update ps_users set mdp_hash = extensions.crypt(p_nouveau, extensions.gen_salt('bf', 10)) where id = u.id;
  delete from ps_sessions where user_id = u.id and jeton <> p_session;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ps_syndic_copro(p_session text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  if not exists (select 1 from ps_copros where id = p_copro and syndic_id = u.syndic_id) then raise exception 'INTROUVABLE'; end if;
  return (select jsonb_build_object(
    'copro', jsonb_build_object('id', c.id, 'nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference, 'type', c.type, 'etat', c.etat),
    'compteurs', ps__compteurs(c.id),
    'badges', coalesce((select jsonb_agg(jsonb_build_object('numero', b.numero, 'statut', b.statut, 'remise_id', b.remise_id) order by b.numero)
                from ps_badges b where b.copro_id = c.id), '[]'::jsonb),
    'remises', coalesce((select jsonb_agg(ps__remise_resume(r) order by r.cree_le desc) from ps_remises r where r.copro_id = c.id), '[]'::jsonb))
  from ps_copros c where c.id = p_copro);
end $$;

-- Crée une remise. Si p contient une signature, la remise est signée tout de suite (signature sur l'écran de l'agence).
-- Sinon elle est « en attente » : les badges sont réservés et le jeton sert au lien / QR code de signature.
create or replace function public.ps_syndic_remise_creer(p_session text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; v_copro uuid := (p->>'copro_id')::uuid; v_badges jsonb; v_n int; v_num text; v_id uuid; v_jeton text := ps__jeton();
  v_signe boolean := coalesce(p->>'signature', '') <> ''; v_compteur int; v_nb_ok int;
begin
  u := ps__user(p_session);
  if not exists (select 1 from ps_copros where id = v_copro and syndic_id = u.syndic_id) then raise exception 'INTROUVABLE'; end if;
  select coalesce(jsonb_agg(distinct upper(trim(x))), '[]') into v_badges from jsonb_array_elements_text(coalesce(p->'badges','[]')) x where trim(x) <> '';
  v_n := jsonb_array_length(v_badges);
  if v_n = 0 then raise exception 'AUCUN_BADGE'; end if;
  if coalesce(trim(p->>'proprietaire'), '') = '' then raise exception 'NOM_OBLIGATOIRE'; end if;
  -- verrou sur les badges concernés, tous doivent être en stock dans cette copro
  perform 1 from ps_badges where copro_id = v_copro and numero in (select jsonb_array_elements_text(v_badges)) for update;
  select count(*) into v_nb_ok from ps_badges where copro_id = v_copro and statut = 'stock' and numero in (select jsonb_array_elements_text(v_badges));
  if v_nb_ok <> v_n then raise exception 'BADGE_INDISPONIBLE'; end if;
  update ps_copros set compteur_bons = compteur_bons + 1 where id = v_copro returning compteur_bons into v_compteur;
  insert into ps_remises (copro_id, numero, jeton, statut, badges, lot, batiment, proprietaire, qualite, email, tel, commentaire, photos,
    agent_id, agent_nom, mode_signature, signataire, signature, signe_le, navigateur, ip)
  values (v_copro, 'RB-' || to_char(now(), 'YYYY') || '-' || lpad(v_compteur::text, 3, '0'), v_jeton,
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

-- Remise complète (images comprises) : pour le PDF, et pour savoir si la signature à distance est arrivée.
create or replace function public.ps_syndic_remise(p_session text, p_remise uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  return (select to_jsonb(r) - 'ip' || jsonb_build_object(
      'jeton', case when r.statut = 'attente' then r.jeton end,
      'copro', jsonb_build_object('nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference),
      'syndic', (select ps__syndic_public(s) from ps_syndics s where s.id = c.syndic_id))
    from ps_remises r join ps_copros c on c.id = r.copro_id where r.id = p_remise and c.syndic_id = u.syndic_id);
end $$;

-- Statut seul (léger) pour l'attente de signature à distance.
create or replace function public.ps_syndic_remise_statut(p_session text, p_remise uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  return (select jsonb_build_object('statut', r.statut, 'signe_le', r.signe_le)
    from ps_remises r join ps_copros c on c.id = r.copro_id where r.id = p_remise and c.syndic_id = u.syndic_id);
end $$;

-- Annulation (rien n'est effacé) : les badges reviennent en stock.
create or replace function public.ps_syndic_remise_annuler(p_session text, p_remise uuid, p_motif text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; r ps_remises;
begin
  u := ps__user(p_session);
  select rr.* into r from ps_remises rr join ps_copros c on c.id = rr.copro_id where rr.id = p_remise and c.syndic_id = u.syndic_id for update;
  if r.id is null then raise exception 'INTROUVABLE'; end if;
  if r.statut = 'annule' then return jsonb_build_object('ok', true); end if;
  if coalesce(trim(p_motif), '') = '' then raise exception 'MOTIF_OBLIGATOIRE'; end if;
  update ps_remises set statut = 'annule', annule_le = now(), annule_motif = trim(p_motif) where id = r.id;
  update ps_badges set statut = 'stock', remise_id = null, maj_le = now() where remise_id = r.id and statut in ('reserve','remis');
  perform ps__log(r.copro_id, u.nom, 'remise_annulee', jsonb_build_object('remise', r.id, 'motif', p_motif));
  return jsonb_build_object('ok', true);
end $$;

-- =====================================================================================
-- RÉSIDENT (page publique signer-badges.html?t=…)
-- =====================================================================================

create or replace function public.ps_remise_lire(p_jeton text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if p_jeton !~ '^[0-9a-f]{32}$' then raise exception 'LIEN_INVALIDE'; end if;
  return (select jsonb_build_object('numero', r.numero, 'statut', r.statut, 'badges', r.badges, 'lot', r.lot, 'batiment', r.batiment,
      'proprietaire', r.proprietaire, 'qualite', r.qualite, 'commentaire', r.commentaire, 'signe_le', r.signe_le, 'cree_le', r.cree_le,
      'copro', jsonb_build_object('nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville),
      'syndic', (select jsonb_build_object('nom', s.nom, 'tel', s.tel, 'email', s.email) from ps_syndics s where s.id = c.syndic_id))
    from ps_remises r join ps_copros c on c.id = r.copro_id where r.jeton = p_jeton);
end $$;

create or replace function public.ps_remise_signer(p_jeton text, p_nom text, p_signature text, p_navigateur text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare r ps_remises;
begin
  if p_jeton !~ '^[0-9a-f]{32}$' then raise exception 'LIEN_INVALIDE'; end if;
  select * into r from ps_remises where jeton = p_jeton for update;
  if r.id is null then raise exception 'LIEN_INVALIDE'; end if;
  if r.statut = 'signe' then return jsonb_build_object('statut', 'signe', 'signe_le', r.signe_le); end if;
  if r.statut <> 'attente' then raise exception 'REMISE_ANNULEE'; end if;
  if coalesce(trim(p_nom), '') = '' or coalesce(p_signature, '') !~ '^data:image/png;base64,' then raise exception 'SIGNATURE_INCOMPLETE'; end if;
  update ps_remises set statut = 'signe', signataire = trim(p_nom), signature = p_signature, signe_le = now(), mode_signature = 'distance',
    navigateur = left(coalesce(p_navigateur, ''), 300), ip = ps__ip() where id = r.id;
  update ps_badges set statut = 'remis', maj_le = now() where remise_id = r.id and statut = 'reserve';
  perform ps__log(r.copro_id, trim(p_nom), 'remise_signee', jsonb_build_object('remise', r.id, 'mode', 'distance'));
  return jsonb_build_object('statut', 'signe', 'signe_le', now());
end $$;

-- ---------- Droits d'exécution (uniquement les fonctions ps_* ; rien d'autre n'est touché) ----------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'ps\_%' loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
    if f.proname not like 'ps\_\_%' then
      execute format('grant execute on function %s to anon, authenticated', f.sig);
    end if;
  end loop;
end $$;
