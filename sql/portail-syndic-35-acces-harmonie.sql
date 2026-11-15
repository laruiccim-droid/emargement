-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 35 : Harmonie agit dans l'espace syndic
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 34.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Depuis le portail admin, Harmonie ouvre l'espace syndic d'un chantier et peut y faire tout ce que
-- fait le gestionnaire (remises de badges, fichier, recensement…). La session est ouverte au nom du
-- gestionnaire du chantier (sinon d'un gestionnaire du cabinet), mais tout ce qui est fait est
-- enregistré au nom de « Harmonie Électricité » (journal, bons de remise). Session limitée à 8 h.
-- =====================================================================================

alter table public.ps_sessions add column if not exists par_harmonie boolean not null default false;

create or replace function public.ps__user(p_session text) returns public.ps_users
language plpgsql security definer set search_path = public, extensions as $$
declare u ps_users; s ps_sessions;
begin
  select * into s from ps_sessions where jeton = p_session and expire_le > now() and cree_le > now() - interval '30 days';
  if s.jeton is null then raise exception 'SESSION_INVALIDE'; end if;
  select * into u from ps_users where id = s.user_id and actif;
  if u.id is null then raise exception 'SESSION_INVALIDE'; end if;
  if s.expire_le < now() + interval '7 hours 50 minutes' and not s.par_harmonie then
    update ps_sessions set expire_le = now() + interval '8 hours' where jeton = p_session;
  end if;
  -- Session ouverte par Harmonie : les actions sont enregistrées à son nom.
  if s.par_harmonie then u.nom := 'Harmonie Électricité'; end if;
  return u;
end $$;

-- Harmonie : ouvrir l'espace syndic d'un chantier.
create or replace function public.ps_admin_session_syndic(p_admin text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare c ps_copros; u ps_users; v_session text := ps__jeton() || ps__jeton();
begin
  perform ps__admin(p_admin);
  select * into c from ps_copros where id = p_copro;
  if c.id is null then raise exception 'INTROUVABLE'; end if;
  if c.syndic_id is null then raise exception 'AUCUN_GESTIONNAIRE'; end if;
  select * into u from ps_users where id = c.gestionnaire_id and actif and syndic_id = c.syndic_id;
  if u.id is null then
    select * into u from ps_users where syndic_id = c.syndic_id and actif order by (mdp_hash is null), cree_le limit 1;
  end if;
  if u.id is null then raise exception 'AUCUN_GESTIONNAIRE'; end if;
  delete from ps_sessions where expire_le < now();
  insert into ps_sessions (jeton, user_id, expire_le, par_harmonie) values (v_session, u.id, now() + interval '8 hours', true);
  perform ps__log(p_copro, 'Harmonie', 'acces_espace_syndic', jsonb_build_object('gestionnaire', coalesce(nullif(u.nom, ''), u.email)));
  return jsonb_build_object('session', v_session, 'gestionnaire', coalesce(nullif(u.nom, ''), u.email));
end $$;

revoke execute on function public.ps__user(text) from public, anon, authenticated;
revoke execute on function public.ps_admin_session_syndic(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_admin_session_syndic(text, uuid) to anon, authenticated;
