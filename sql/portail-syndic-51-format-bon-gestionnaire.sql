-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 51 : format du bon d'intervention choisi par gestionnaire
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 50.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Chaque cabinet a un format par défaut (sans prix, semi-détaillé, détaillé). Chaque gestionnaire
-- peut avoir son propre format ; vide = format du cabinet.
-- Le format appliqué dans l'espace d'un gestionnaire est le sien s'il en a un, sinon celui du cabinet.
-- =====================================================================================

alter table public.ps_users add column if not exists format_bon text;

-- Bon d'intervention dans l'espace syndic : format du gestionnaire connecté, sinon du cabinet.
create or replace function public.ps_syndic_bon(p_session text, p_bon text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; v_format text; p jsonb;
begin
  u := ps__user(p_session);
  if not exists (select 1 from ps_interventions i where i.syndic_id = u.syndic_id and not i.ignoree
      and i.passages @> jsonb_build_array(jsonb_build_object('bon', p_bon))) then raise exception 'INTROUVABLE'; end if;
  select payload into p from devis where id = p_bon and payload->>'statut' = 'valide';
  if p is null then raise exception 'INTROUVABLE'; end if;
  select coalesce(nullif(x.format_bon, ''), nullif(s.format_bon, ''), 'sansprix') into v_format
  from ps_users x join ps_syndics s on s.id = x.syndic_id where x.id = u.id;
  return ps__bon_public(p, coalesce(v_format, 'sansprix'));
end $$;

-- Portail admin : liste des interventions et réglages (avec le format de chaque gestionnaire).
create or replace function public.ps_admin_interventions(p_admin text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  return jsonb_build_object(
    'interventions', coalesce((select jsonb_agg(ps__interv_json(i, true) order by i.a_attribuer desc, i.maj_le desc) from ps_interventions i), '[]'::jsonb),
    'syndics', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'nom', s.nom, 'reconnaissance', s.reconnaissance, 'format_bon', s.format_bon,
        'users', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'nom', u.nom, 'email', u.email, 'actif', u.actif,
            'mail_avancement', u.mail_avancement, 'format_bon', u.format_bon) order by u.nom)
          from ps_users u where u.syndic_id = s.id), '[]'::jsonb)) order by s.nom) from ps_syndics s), '[]'::jsonb));
end $$;

-- Portail admin : format d'un gestionnaire ('' = format du cabinet).
create or replace function public.ps_admin_user_format_bon(p_admin text, p_user uuid, p_format text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  update ps_users set format_bon = case when p_format in ('detail', 'semi', 'sansprix') then p_format end where id = p_user;
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function public.ps_syndic_bon(text, text) from public, anon, authenticated;
grant execute on function public.ps_syndic_bon(text, text) to anon, authenticated;
revoke execute on function public.ps_admin_interventions(text) from public, anon, authenticated;
grant execute on function public.ps_admin_interventions(text) to anon, authenticated;
revoke execute on function public.ps_admin_user_format_bon(text, uuid, text) from public, anon, authenticated;
grant execute on function public.ps_admin_user_format_bon(text, uuid, text) to anon, authenticated;
