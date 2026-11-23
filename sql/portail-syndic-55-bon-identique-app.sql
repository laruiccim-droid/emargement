-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 55 : bon d'intervention identique à celui de l'app métier
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 54.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- L'espace syndic et le portail admin dessinent désormais le bon avec le générateur de l'app
-- métier (même mise en page). Le serveur leur fournit le bon complet, avec la chaîne des
-- interventions précédentes (rapport, détail, photos), sans les notes internes.
-- Format « sans prix » : les prix sont retirés avant l'envoi (ils ne quittent pas le serveur).
-- =====================================================================================

create or replace function public.ps__bon_complet(p jsonb, p_format text, p_niveau int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb := coalesce(p, '{}'::jsonb) - 'notesInternes' - 'sessions'; v_lie jsonb;
begin
  -- Bon précédent (« intervention à suivre ») : version complète lue dans la base, sinon la copie du bon.
  if p_niveau < 10 then
    if coalesce(r->>'bonLieId', '') <> '' then
      select d.payload || jsonb_build_object('id', d.id) into v_lie from devis d where d.id = r->>'bonLieId';
    end if;
    if v_lie is null and jsonb_typeof(r->'bonLieData') = 'object' then v_lie := r->'bonLieData'; end if;
    if v_lie is not null then r := r || jsonb_build_object('bonLieData', ps__bon_complet(v_lie, p_format, p_niveau + 1)); end if;
  else
    r := r - 'bonLieData';
  end if;
  if p_format = 'sansprix' then
    r := (r || jsonb_build_object('lignes', coalesce((select jsonb_agg(l || '{"pu": 0}'::jsonb) from jsonb_array_elements(
           case when jsonb_typeof(r->'lignes') = 'array' then r->'lignes' else '[]'::jsonb end) l), '[]'::jsonb)))
         - 'totalHT' - 'totalTVA' - 'totalTTC';
  end if;
  return r || jsonb_build_object('pdfMode', p_format);
end $$;

-- Espace syndic : { format, bon } — format du gestionnaire connecté, sinon du cabinet.
create or replace function public.ps_syndic_bon(p_session text, p_bon text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; v_format text; p jsonb;
begin
  u := ps__user(p_session);
  if not exists (select 1 from ps_interventions i where i.syndic_id = u.syndic_id and not i.ignoree
      and i.passages @> jsonb_build_array(jsonb_build_object('bon', p_bon))) then raise exception 'INTROUVABLE'; end if;
  select payload || jsonb_build_object('id', id) into p from devis where id = p_bon and payload->>'statut' = 'valide';
  if p is null then raise exception 'INTROUVABLE'; end if;
  select coalesce(nullif(x.format_bon, ''), nullif(s.format_bon, ''), 'sansprix') into v_format
  from ps_users x join ps_syndics s on s.id = x.syndic_id where x.id = u.id;
  v_format := coalesce(v_format, 'sansprix');
  return jsonb_build_object('format', v_format, 'bon', ps__bon_complet(p, v_format));
end $$;

-- Portail admin : { format, bon } dans le format demandé.
create or replace function public.ps_admin_bon(p_admin text, p_bon text, p_format text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p jsonb; v_format text := case when p_format in ('detail', 'semi', 'sansprix') then p_format else 'sansprix' end;
begin
  perform ps__admin(p_admin);
  select payload || jsonb_build_object('id', id) into p from devis where id = p_bon;
  if p is null then raise exception 'INTROUVABLE'; end if;
  return jsonb_build_object('format', v_format, 'bon', ps__bon_complet(p, v_format));
end $$;

revoke execute on function public.ps__bon_complet(jsonb, text, int) from public, anon, authenticated;
revoke execute on function public.ps_syndic_bon(text, text) from public, anon, authenticated;
grant execute on function public.ps_syndic_bon(text, text) to anon, authenticated;
revoke execute on function public.ps_admin_bon(text, text, text) from public, anon, authenticated;
grant execute on function public.ps_admin_bon(text, text, text) to anon, authenticated;
