-- =====================================================================================
-- PORTAIL SYNDIC — complément n° 47 : bon de livraison des badges signé à distance (QR code ou lien)
-- À exécuter une seule fois dans Supabase → SQL Editor → Run, après les scripts 1 à 46.
-- Ne touche pas à la table « emargements ». Peut être relancé sans risque.
--
-- Chaque bon de livraison reçoit un jeton : la page signer-badges.html?l=<jeton> (QR code à scanner, ou lien
-- envoyé par e-mail) permet au gestionnaire de relire le bon et de le signer sur son téléphone, sans se connecter.
-- La signature ouvre son accès au chantier (déclencheur du script 44) et Harmonie est prévenue par e-mail.
-- =====================================================================================

alter table public.ps_livraisons add column if not exists jeton text;
create unique index if not exists ps_livraisons_jeton on public.ps_livraisons (jeton) where jeton is not null;

create or replace function public.ps__livraison_jeton(p_livraison uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v text;
begin
  select jeton into v from ps_livraisons where id = p_livraison;
  if v is null then
    v := replace(gen_random_uuid()::text, '-', '');
    update ps_livraisons set jeton = v where id = p_livraison;
  end if;
  return v;
end $$;

-- Harmonie : jeton du bon à faire signer.
create or replace function public.ps_admin_livraison_jeton(p_admin text, p_livraison uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ps__admin(p_admin);
  if not exists (select 1 from ps_livraisons where id = p_livraison) then raise exception 'INTROUVABLE'; end if;
  return jsonb_build_object('jeton', ps__livraison_jeton(p_livraison));
end $$;

-- Gestionnaire : jeton du dernier bon non signé de son chantier (pour signer sur son téléphone).
create or replace function public.ps_syndic_livraison_jeton(p_session text, p_copro uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u ps_users; v_liv uuid;
begin
  u := ps__user(p_session);
  if not ps__copro_visible(p_copro, u) then raise exception 'INTROUVABLE'; end if;
  select id into v_liv from ps_livraisons where copro_id = p_copro and coalesce(signature, '') = '' order by cree_le desc limit 1;
  if v_liv is null then raise exception 'INTROUVABLE'; end if;
  return jsonb_build_object('jeton', ps__livraison_jeton(v_liv));
end $$;

-- Page publique : relire le bon de livraison.
create or replace function public.ps_livraison_lire(p_jeton text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l ps_livraisons; c ps_copros;
begin
  if coalesce(p_jeton, '') !~ '^[0-9a-f]{32}$' then raise exception 'LIEN_INVALIDE'; end if;
  select * into l from ps_livraisons where jeton = p_jeton;
  if l.id is null then raise exception 'LIEN_INVALIDE'; end if;
  select * into c from ps_copros where id = l.copro_id;
  return jsonb_build_object(
    'copro', jsonb_build_object('nom', c.nom, 'adresse', c.adresse, 'cp', c.cp, 'ville', c.ville, 'reference', c.reference),
    'syndic', (select jsonb_build_object('nom', s.nom, 'tel', s.tel) from ps_syndics s where s.id = c.syndic_id),
    'gestionnaire', (select coalesce(nullif(u.nom, ''), u.email) from ps_users u where u.id = c.gestionnaire_id),
    'badges', l.badges, 'commentaire', l.commentaire, 'cree_le', l.cree_le, 'signe_le', l.signe_le, 'signataire', l.signataire);
end $$;

-- Page publique : signer le bon de livraison (ouvre l'accès du syndic au chantier).
create or replace function public.ps_livraison_signer(p_jeton text, p_nom text, p_signature text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l ps_livraisons;
begin
  if coalesce(p_jeton, '') !~ '^[0-9a-f]{32}$' then raise exception 'LIEN_INVALIDE'; end if;
  if coalesce(trim(p_nom), '') = '' then raise exception 'NOM_OBLIGATOIRE'; end if;
  if coalesce(p_signature, '') !~ '^data:image/png;base64,' or length(p_signature) > 800000 then raise exception 'SIGNATURE_INVALIDE'; end if;
  select * into l from ps_livraisons where jeton = p_jeton;
  if l.id is null then raise exception 'LIEN_INVALIDE'; end if;
  if coalesce(l.signature, '') <> '' then raise exception 'DEJA_SIGNE'; end if;
  update ps_livraisons set signataire = left(trim(p_nom), 120), signature = p_signature, signe_le = now() where id = l.id;
  perform ps__log(l.copro_id, trim(p_nom), 'livraison_signee', jsonb_build_object('livraison', l.id, 'distance', true));
  perform ps__notifier_harmonie(l.copro_id, '', 'bon de livraison signé',
    trim(p_nom) || ' a signé à distance le bon de livraison des badges (' || jsonb_array_length(l.badges) || ' badges) : l’accès du syndic au chantier est ouvert.');
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function public.ps__livraison_jeton(uuid) from public, anon, authenticated;
revoke execute on function public.ps_admin_livraison_jeton(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_admin_livraison_jeton(text, uuid) to anon, authenticated;
revoke execute on function public.ps_syndic_livraison_jeton(text, uuid) from public, anon, authenticated;
grant execute on function public.ps_syndic_livraison_jeton(text, uuid) to anon, authenticated;
revoke execute on function public.ps_livraison_lire(text) from public, anon, authenticated;
grant execute on function public.ps_livraison_lire(text) to anon, authenticated;
revoke execute on function public.ps_livraison_signer(text, text, text) from public, anon, authenticated;
grant execute on function public.ps_livraison_signer(text, text, text) to anon, authenticated;
