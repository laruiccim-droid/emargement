-- =====================================================================================
-- SÉCURITÉ n° 9 : la table « emargements » n'est plus ouverte à tous
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 8.
--
-- Jusqu'ici, n'importe qui possédant la clé publique (visible dans toutes les pages) pouvait lire,
-- modifier ou effacer les chantiers, les listings et les signatures. Désormais :
--   • l'app d'émargement, les relevés, le portail admin et le robot BatiConnect envoient un
--     « code d'accès de l'app » (en-tête x-harmonie-cle), choisi par vous et vérifié ici ;
--   • la page de signature à distance (signer.html) passe par deux fonctions qui n'ouvrent
--     QUE la demande correspondant au lien reçu (jeton de 32 caractères), et ne peuvent que la signer.
-- Le code est choisi dans l'app, au premier lancement, avec le mot de passe administrateur du portail.
-- Aucune donnée n'est modifiée ni supprimée.
-- =====================================================================================

-- Le code n'est jamais stocké en clair : « sel:empreinte sha256 » dans ps_config (table fermée).
create or replace function public.em__ok() returns boolean
language plpgsql stable security definer set search_path = public as $$
declare k text; v text;
begin
  k := nullif(current_setting('request.headers', true), '')::json->>'x-harmonie-cle';
  if k is null or k = '' then return false; end if;
  select valeur into v from ps_config where cle = 'app_cle';
  if v is null then return false; end if;
  return encode(extensions.digest(split_part(v, ':', 1) || k, 'sha256'), 'hex') = split_part(v, ':', 2);
end $$;

-- État du code pour l'app : défini ? celui envoyé est-il le bon ?
create or replace function public.em_cle_etat() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('definie', exists (select 1 from ps_config where cle = 'app_cle'), 'valide', em__ok());
$$;

-- Choisir ou changer le code : réservé à l'administrateur (mot de passe du portail admin).
create or replace function public.em_cle_definir(p_admin text, p_cle text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s text := encode(extensions.gen_random_bytes(16), 'hex');
begin
  perform ps__admin(p_admin);
  if length(coalesce(p_cle, '')) < 8 then raise exception 'CODE_TROP_COURT'; end if;
  insert into ps_config (cle, valeur) values ('app_cle', s || ':' || encode(extensions.digest(s || p_cle, 'sha256'), 'hex'))
  on conflict (cle) do update set valeur = excluded.valeur;
  return jsonb_build_object('ok', true);
end $$;

-- Signature à distance : lire la demande du lien, et la signer (une seule fois).
create or replace function public.em_sig_lire(p_jeton text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce(p_jeton, '') !~ '^[0-9a-f]{32}$' then return null; end if;
  return (select payload from emargements where id = 'SIG_' || p_jeton);
end $$;

create or replace function public.em_sig_signer(p_jeton text, p_signataire text, p_signature text, p_navigateur text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(p_jeton, '') !~ '^[0-9a-f]{32}$' then raise exception 'DEMANDE_INTROUVABLE'; end if;
  if coalesce(trim(p_signataire), '') = '' then raise exception 'NOM_OBLIGATOIRE'; end if;
  if coalesce(p_signature, '') !~ '^data:image/png;base64,' or length(p_signature) > 800000 then raise exception 'SIGNATURE_INVALIDE'; end if;
  update emargements set payload = payload || jsonb_build_object('statut', 'signe', 'signature', p_signature,
      'signataire', left(trim(p_signataire), 120), 'signeLe', (extract(epoch from now()) * 1000)::bigint, 'navigateur', left(coalesce(p_navigateur, ''), 300))
  where id = 'SIG_' || p_jeton and coalesce(payload->>'statut', '') <> 'signe';
  if not found then
    if exists (select 1 from emargements where id = 'SIG_' || p_jeton) then raise exception 'DEJA_SIGNE'; end if;
    raise exception 'DEMANDE_INTROUVABLE';
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- Droits d'exécution (em__ok doit rester exécutable : la règle d'accès l'appelle).
revoke execute on function public.em__ok() from public;
grant execute on function public.em__ok() to anon, authenticated;
revoke execute on function public.em_cle_etat() from public;
grant execute on function public.em_cle_etat() to anon, authenticated;
revoke execute on function public.em_cle_definir(text, text) from public;
grant execute on function public.em_cle_definir(text, text) to anon, authenticated;
revoke execute on function public.em_sig_lire(text) from public;
grant execute on function public.em_sig_lire(text) to anon, authenticated;
revoke execute on function public.em_sig_signer(text, text, text, text) from public;
grant execute on function public.em_sig_signer(text, text, text, text) to anon, authenticated;

-- La règle « tout le monde peut tout faire » est remplacée par « seulement avec le bon code ».
do $$ declare p record;
begin
  for p in select policyname from pg_policies where schemaname = 'public' and tablename = 'emargements' loop
    execute format('drop policy %I on public.emargements', p.policyname);
  end loop;
end $$;
create policy "Acces avec le code de l'app" on public.emargements for all to anon, authenticated
  using ((select public.em__ok())) with check ((select public.em__ok()));
