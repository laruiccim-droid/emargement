-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 29 : connexion renforcée (accès depuis le site internet)
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 28.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
--  • Blocage après 5 mots de passe faux en 15 minutes (par adresse e-mail et par adresse IP).
--  • Session fermée après 8 heures sans activité (et au plus 30 jours), au lieu de 90 jours fixes.
--  • Mot de passe d'au moins 10 caractères, avec au moins une lettre et un chiffre.
--  • Mot de passe administrateur faux : réponse ralentie et blocage temporaire en cas d'acharnement.
-- =====================================================================================

create table if not exists public.ps_tentatives (
  id bigserial primary key,
  cle text not null,           -- 'email:…' ou 'ip:…' ou 'admin:…'
  le timestamptz not null default now()
);
create index if not exists ps_tentatives_cle on public.ps_tentatives (cle, le);
alter table public.ps_tentatives enable row level security;
revoke all on public.ps_tentatives from anon, authenticated;

create or replace function public.ps__bloque(p_cles text[]) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from ps_tentatives t where t.cle = any(p_cles) and t.le > now() - interval '15 minutes'
                 group by t.cle having count(*) >= 5);
$$;

create or replace function public.ps__mdp_ok(p_mdp text) returns void
language plpgsql immutable as $$
begin
  if length(coalesce(p_mdp, '')) < 10 or p_mdp !~ '[A-Za-zÀ-ÿ]' or p_mdp !~ '[0-9]' then raise exception 'MDP_FAIBLE'; end if;
end $$;

-- Connexion : la réponse d'échec n'est plus une erreur, pour que la tentative soit bien enregistrée.
create or replace function public.ps_connexion(p_email text, p_mdp text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u ps_users; v_session text := ps__jeton() || ps__jeton(); v_cles text[];
begin
  v_cles := array['email:' || lower(trim(coalesce(p_email, ''))), 'ip:' || ps__ip()];
  if ps__bloque(v_cles) then return jsonb_build_object('erreur', 'TROP_DE_TENTATIVES'); end if;
  select * into u from ps_users where lower(email) = lower(trim(p_email)) and actif;
  if u.id is null or u.mdp_hash is null or extensions.crypt(coalesce(p_mdp, ''), u.mdp_hash) <> u.mdp_hash then
    insert into ps_tentatives (cle) select unnest(v_cles);
    perform pg_sleep(0.8);
    return jsonb_build_object('erreur', 'IDENTIFIANTS_INCORRECTS');
  end if;
  delete from ps_tentatives where cle = any(v_cles) or le < now() - interval '1 day';
  update ps_users set derniere_connexion = now() where id = u.id;
  delete from ps_sessions where expire_le < now();
  insert into ps_sessions (jeton, user_id, expire_le) values (v_session, u.id, now() + interval '8 hours');
  return jsonb_build_object('session', v_session);
end $$;

-- Session glissante : 8 h sans activité, 30 jours au plus.
create or replace function public.ps__user(p_session text) returns public.ps_users
language plpgsql security definer set search_path = public, extensions as $$
declare u ps_users; s ps_sessions;
begin
  select * into s from ps_sessions where jeton = p_session and expire_le > now() and cree_le > now() - interval '30 days';
  if s.jeton is null then raise exception 'SESSION_INVALIDE'; end if;
  select * into u from ps_users where id = s.user_id and actif;
  if u.id is null then raise exception 'SESSION_INVALIDE'; end if;
  if s.expire_le < now() + interval '7 hours 50 minutes' then
    update ps_sessions set expire_le = now() + interval '8 hours' where jeton = p_session;
  end if;
  return u;
end $$;

create or replace function public.ps_activer(p_invitation text, p_mdp text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u ps_users; v_session text := ps__jeton() || ps__jeton();
begin
  select * into u from ps_users where invitation = p_invitation and invitation_expire > now() and actif;
  if u.id is null then raise exception 'INVITATION_INVALIDE'; end if;
  perform ps__mdp_ok(p_mdp);
  update ps_users set mdp_hash = extensions.crypt(p_mdp, extensions.gen_salt('bf', 10)), invitation = null, invitation_expire = null,
    active_le = coalesce(active_le, now()), derniere_connexion = now() where id = u.id;
  delete from ps_sessions where user_id = u.id;
  insert into ps_sessions (jeton, user_id, expire_le) values (v_session, u.id, now() + interval '8 hours');
  return jsonb_build_object('session', v_session);
end $$;

create or replace function public.ps_syndic_mdp(p_session text, p_ancien text, p_nouveau text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u ps_users;
begin
  u := ps__user(p_session);
  if extensions.crypt(coalesce(p_ancien, ''), u.mdp_hash) <> u.mdp_hash then raise exception 'IDENTIFIANTS_INCORRECTS'; end if;
  perform ps__mdp_ok(p_nouveau);
  update ps_users set mdp_hash = extensions.crypt(p_nouveau, extensions.gen_salt('bf', 10)) where id = u.id;
  delete from ps_sessions where user_id = u.id and jeton <> p_session;
  return jsonb_build_object('ok', true);
end $$;

-- Administrateur : bloqué 15 minutes après 5 échecs depuis la même adresse IP ; chaque échec est ralenti.
create or replace function public.ps_admin_ouvrir(p_admin text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare h text; v_cle text := 'admin:' || ps__ip();
begin
  if ps__bloque(array[v_cle]) then return jsonb_build_object('erreur', 'TROP_DE_TENTATIVES'); end if;
  select valeur into h from ps_config where cle = 'admin_hash';
  if h is null then return jsonb_build_object('erreur', 'ADMIN_NON_DEFINI'); end if;
  if p_admin is null or extensions.crypt(p_admin, h) <> h then
    insert into ps_tentatives (cle) values (v_cle); perform pg_sleep(0.8);
    return jsonb_build_object('erreur', 'ADMIN_REFUSE');
  end if;
  delete from ps_tentatives where cle = v_cle;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ps__admin(p_admin text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  if ps__bloque(array['admin:' || ps__ip()]) then raise exception 'TROP_DE_TENTATIVES'; end if;
  select valeur into h from ps_config where cle = 'admin_hash';
  if h is null then raise exception 'ADMIN_NON_DEFINI'; end if;
  if p_admin is null or extensions.crypt(p_admin, h) <> h then perform pg_sleep(0.8); raise exception 'ADMIN_REFUSE'; end if;
end $$;

-- Les sessions existantes passent à la nouvelle règle (8 h sans activité).
update public.ps_sessions set expire_le = least(expire_le, now() + interval '8 hours');

revoke execute on function public.ps__bloque(text[]) from public, anon, authenticated;
revoke execute on function public.ps__mdp_ok(text) from public, anon, authenticated;
revoke execute on function public.ps__user(text) from public, anon, authenticated;
revoke execute on function public.ps__admin(text) from public, anon, authenticated;
revoke execute on function public.ps_connexion(text, text) from public, anon, authenticated;
grant execute on function public.ps_connexion(text, text) to anon, authenticated;
revoke execute on function public.ps_activer(text, text) from public, anon, authenticated;
grant execute on function public.ps_activer(text, text) to anon, authenticated;
revoke execute on function public.ps_syndic_mdp(text, text, text) from public, anon, authenticated;
grant execute on function public.ps_syndic_mdp(text, text, text) to anon, authenticated;
revoke execute on function public.ps_admin_ouvrir(text) from public, anon, authenticated;
grant execute on function public.ps_admin_ouvrir(text) to anon, authenticated;
