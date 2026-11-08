// Outils communs à l'accueil (index.html) et aux relevés (releves.html) :
// Supabase, clients de l'app métier, envoi Gmail. L'émargement (emargement.html) garde ses propres outils.
'use strict';

const SUPA_URL = 'https://bqzebkobyfktemnwfwbt.supabase.co';
const SUPA_KEY = 'sb_publishable_vh62KxFcG1NuLcnya6WpMg_oFRtY-2v';
const SB = { apikey: SUPA_KEY, Authorization: 'Bearer ' + SUPA_KEY };
const TABLE = 'emargements';
const ENVOI_GMAIL_URL = 'https://send-email-harmonie.harmonie-electricite.workers.dev';

const sansAccent = s => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
const triFr = (a, b) => String(a || '').localeCompare(String(b || ''), 'fr', { sensitivity: 'base', numeric: true });
const villeDe = a => { const m = String(a || '').match(/\d{5}\s*-?\s*([^,]+)$/); return (m ? m[1] : String(a || '').split(',').pop()).trim(); };
const aujourdhuiIso = () => new Date().toLocaleDateString('sv-SE');

// ---------- Clients de l'app métier (table « clients ») ----------
// Même clé de cache que l'émargement : la liste reste disponible sans réseau.
const CLE_CLIENTS = 'he.emargement.clients';
const CLE_CLIENTS_A_ENVOYER = 'he.clients.aEnvoyer';
const versClient = (id, p) => ({ id, name: p.name || '', email: p.email || '', phone: p.phone || '', address: p.address || '',
  addressChantier: p.addressChantier || '', residences: p.residences || null, type: p.type || '' });
function clientsEnCache() { try { return JSON.parse(localStorage.getItem(CLE_CLIENTS)) || []; } catch { return []; } }
function clientsAEnvoyer() { try { return JSON.parse(localStorage.getItem(CLE_CLIENTS_A_ENVOYER)) || []; } catch { return []; } }
async function chargerClients() {
  await envoyerClientsEnAttente();
  let liste = null;
  try {
    // Par pages de 1000 : la table dépasse déjà 900 clients.
    const tous = [];
    for (let debut = 0; debut < 20000; debut += 1000) {
      const r = await fetch(`${SUPA_URL}/rest/v1/clients?select=id,payload&order=id`, { headers: { ...SB, Range: `${debut}-${debut + 999}` } });
      if (!r.ok) throw new Error(r.status);
      const page = await r.json(); tous.push(...page);
      if (page.length < 1000) break;
    }
    liste = tous.map(x => versClient(x.id, x.payload || {}));
    try { localStorage.setItem(CLE_CLIENTS, JSON.stringify(liste)); } catch {}
  } catch { liste = clientsEnCache(); }
  // Clients créés hors ligne, pas encore partis
  for (const c of clientsAEnvoyer()) if (!liste.some(x => x.id === c.id)) liste.push(versClient(c.id, c.payload));
  return liste.filter(c => c.name.trim() && c.type !== 'PROSPECT');
}
// Nouveau client, au même format que ceux créés à la main dans l'app métier (id C_<horodatage>).
async function creerClient({ nom, adresse, tel, email }) {
  const t = Date.now(), id = 'C_' + t;
  const payload = { id, name: nom.trim(), email: (email || '').trim(), phone: (tel || '').trim(), address: (adresse || '').trim() || ' ',
    addressChantier: (adresse || '').trim() || ' ', createdAt: t };
  const file = clientsAEnvoyer(); file.push({ id, payload });
  try { localStorage.setItem(CLE_CLIENTS_A_ENVOYER, JSON.stringify(file)); } catch {}
  const cache = clientsEnCache(); cache.push(versClient(id, payload));
  try { localStorage.setItem(CLE_CLIENTS, JSON.stringify(cache)); } catch {}
  await envoyerClientsEnAttente();
  return versClient(id, payload);
}
async function envoyerClientsEnAttente() {
  const file = clientsAEnvoyer(); if (!file.length) return;
  const restent = [];
  for (const c of file) {
    try {
      const r = await fetch(`${SUPA_URL}/rest/v1/clients`, { method: 'POST',
        headers: { ...SB, 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates,return=minimal' }, body: JSON.stringify(c) });
      if (!r.ok) restent.push(c);
    } catch { restent.push(c); }
  }
  try { localStorage.setItem(CLE_CLIENTS_A_ENVOYER, JSON.stringify(restent)); } catch {}
}
// Le client est le plus souvent la copropriété : « Le saint François SC CHAMBÉRY SYNDIC »
// donne la résidence « Le saint François » et le syndic « CHAMBÉRY SYNDIC ».
function residenceDuClient(c) {
  let nom = String(c?.name || '').trim(), syndic = '';
  const m = nom.match(/^(.*?)\s+(?:SC|S\/C|SDC)\s+(.+)$/i);
  if (m && m[1].trim()) { nom = m[1].trim(); syndic = m[2].trim(); }
  nom = nom.replace(/^\d+\s*-\s*/, '').replace(/^(?:SDC|Sdc|sdc)\s+/, '').trim();
  const adresse = String(c?.addressChantier || '').trim() || String(c?.address || '').trim();
  return { nom, syndic, adresse };
}

// ---------- Envoi Gmail (service Harmonie), comme dans l'émargement ----------
async function getGoogleRefreshToken() {
  try { const local = localStorage.getItem('gcal_refresh_token'); if (local) return local; } catch {}
  try {
    const r = await fetch(SUPA_URL + '/rest/v1/notes?id=eq.he_gcal_refresh&select=payload', { headers: SB });
    const rt = r.ok && (await r.json())[0]?.payload?.refresh_token;
    if (rt) { try { localStorage.setItem('gcal_refresh_token', rt); } catch {} return rt; }
  } catch {}
  return null;
}
// Renvoie '' si l'e-mail est parti, sinon la raison de l'échec.
async function envoiGmail(dest, objet, texte, blob, nom) {
  const b64 = await new Promise(ok => { const r = new FileReader(); r.onload = () => ok(r.result.split(',')[1]); r.readAsDataURL(blob); });
  const essai = async jeton => {
    const rep = await fetch(ENVOI_GMAIL_URL, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refresh_token: jeton, to: dest, subject: objet, bodyText: texte, pdfBase64: b64, pdfFilename: nom }) }).catch(() => null);
    if (!rep) return 'pas de connexion au service d’envoi';
    const res = await rep.json().catch(() => null);
    if (res && res.success) return '';
    const e = res?.error;
    return String(e?.error?.message || e?.error_description || e?.message || (typeof e === 'string' ? e : '') || res?.message || 'erreur ' + rep.status).slice(0, 140);
  };
  const jeton = await getGoogleRefreshToken();
  if (!jeton) return 'autorisation Google introuvable';
  let erreur = await essai(jeton);
  if (erreur) {
    try { localStorage.removeItem('gcal_refresh_token'); } catch {}
    const frais = await getGoogleRefreshToken();
    if (frais && frais !== jeton) erreur = await essai(frais);
  }
  return erreur;
}

// Lien Google Agenda pré-rempli (rappel de la prochaine relève), sans autorisation à donner.
function lienAgenda({ titre, date, details, lieu }) {
  const d = date.replace(/-/g, ''), fin = new Date(date + 'T12:00'); fin.setDate(fin.getDate() + 1);
  const p = new URLSearchParams({ action: 'TEMPLATE', text: titre, dates: `${d}/${fin.toLocaleDateString('sv-SE').replace(/-/g, '')}`, details: details || '', location: lieu || '' });
  return 'https://calendar.google.com/calendar/render?' + p.toString();
}
