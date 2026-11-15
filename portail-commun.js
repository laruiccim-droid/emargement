// Portail syndic Harmonie Électricité — outils communs (portail-admin.html, syndic.html, signer-badges.html).
// Toutes les données passent par les fonctions ps_* de Supabase (tables fermées, voir sql/portail-syndic.sql).
'use strict';
const PS = (() => {
  const SUPA_URL = window.PS_SUPA_URL || 'https://bqzebkobyfktemnwfwbt.supabase.co';
  const SUPA_KEY = 'sb_publishable_vh62KxFcG1NuLcnya6WpMg_oFRtY-2v';
  const ENTREPRISE = { nom: 'Harmonie Électricité', adresse: '225 chemin des Bochets, 73170 Yenne', tel: '06 31 13 47 01', email: 'contact@harmonie-electricite.com', web: 'www.harmonie-electricite.com' };

  const ERREURS = {
    ADMIN_REFUSE: 'Mot de passe administrateur incorrect.',
    ADMIN_NON_DEFINI: 'Le mot de passe administrateur n’est pas encore créé.',
    ADMIN_DEJA_DEFINI: 'Le mot de passe administrateur existe déjà.',
    MDP_TROP_COURT: 'Le mot de passe doit faire au moins 8 caractères.',
    SESSION_INVALIDE: 'Votre session a expiré : reconnectez-vous.',
    IDENTIFIANTS_INCORRECTS: 'Adresse e-mail ou mot de passe incorrect.',
    INVITATION_INVALIDE: 'Ce lien d’invitation n’est plus valable. Demandez un nouveau lien à Harmonie Électricité.',
    EMAIL_INVALIDE: 'Adresse e-mail invalide.',
    EMAIL_DEJA_UTILISE: 'Cette adresse e-mail est déjà utilisée par un autre accès.',
    NOM_OBLIGATOIRE: 'Le nom est obligatoire.',
    AUCUN_BADGE: 'Sélectionnez au moins un badge.',
    BADGE_INDISPONIBLE: 'Un des badges choisis n’est plus disponible (déjà remis ou réservé). Actualisez la liste.',
    BADGE_NON_RETIRABLE: 'Ce badge a déjà été remis : il ne peut pas être retiré du stock.',
    MOTIF_OBLIGATOIRE: 'Indiquez le motif de l’annulation.',
    INTROUVABLE: 'Élément introuvable.',
    LIEN_INVALIDE: 'Ce lien n’est pas valide.',
    REMISE_ANNULEE: 'Cette remise a été annulée.',
    SIGNATURE_INCOMPLETE: 'Indiquez votre nom et signez dans le cadre.',
    GESTIONNAIRE_AUTRE_SYNDIC: 'Ce gestionnaire n’appartient pas au syndic choisi.',
    RECENSEMENT_A_VALIDER: 'Validez d’abord le recensement des logements.',
    SONDAGE_CLOS: 'Le sondage est clos : contactez votre syndic pour modifier votre choix.',
    QUALITE_OBLIGATOIRE: 'Indiquez si vous habitez le logement ou si vous le louez.',
    APPARTEMENT_OBLIGATOIRE: 'Indiquez le numéro de votre appartement (étiquette blanche sur la porte).',
    POSTE_OBLIGATOIRE: 'Choisissez au moins un poste.',
    ARTICLE_INCONNU: 'Un article choisi n’est plus proposé : rechargez la page.',
    SIGNATURE_INVALIDE: 'Signez dans le cadre prévu.',
    TELEPHONE_OBLIGATOIRE: 'Indiquez votre numéro de téléphone.',
    ETIQUETTES_A_VALIDER: 'Le recensement commence quand Harmonie Électricité a validé la pose des étiquettes de numérotation.',
    CRENEAU_INDISPONIBLE: 'Ce créneau n’est plus proposé : choisissez-en un autre.',
    CRENEAU_COMPLET: 'Ce créneau vient d’être pris : choisissez-en un autre.',
  };

  async function rpc(fonction, args = {}) {
    let r;
    try {
      r = await fetch(`${SUPA_URL}/rest/v1/rpc/${fonction}`, {
        method: 'POST',
        headers: { apikey: SUPA_KEY, Authorization: 'Bearer ' + SUPA_KEY, 'Content-Type': 'application/json' },
        body: JSON.stringify(args),
      });
    } catch { throw new Error('Pas de connexion internet. Réessayez dans un instant.'); }
    const txt = await r.text();
    let data = null; try { data = txt ? JSON.parse(txt) : null; } catch {}
    if (!r.ok) {
      const code = (data && data.message) || '';
      const absente = r.status === 404 && fonction !== 'ps_admin_statut';
      const e = new Error(ERREURS[code] || (absente ? `Fonction ${fonction} absente de Supabase : exécutez le dernier script du dossier sql/ (SQL Editor).`
        : r.status === 404 ? 'Le portail n’est pas encore installé dans Supabase (script sql/portail-syndic.sql).' : 'Erreur : ' + (code || r.status)));
      e.code = code; throw e;
    }
    return data;
  }

  const $ = id => document.getElementById(id);
  const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const horodatage = ts => ts ? new Date(ts).toLocaleString('fr-FR', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '';
  const dateCourte = ts => ts ? new Date(ts).toLocaleDateString('fr-FR') : '';
  const estTel = () => /iPhone|iPad|iPod|Android/i.test(navigator.userAgent);
  const estIOS = /iPhone|iPad|iPod/i.test(navigator.userAgent);
  const lienSms = (tel, texte) => `sms:${String(tel || '').replace(/[^\d+]/g, '')}${estIOS ? '&' : '?'}body=${encodeURIComponent(texte)}`;

  function toast(txt, ms = 3200) {
    let t = $('toast');
    if (!t) { t = document.createElement('div'); t.id = 'toast'; t.className = 'toast'; t.setAttribute('role', 'status'); document.body.append(t); }
    t.textContent = txt; t.hidden = false; clearTimeout(toast.t); toast.t = setTimeout(() => { t.hidden = true; }, ms);
  }

  async function copier(txt) {
    try { await navigator.clipboard.writeText(txt); toast('Copié.'); }
    catch { prompt('Copiez ce texte :', txt); }
  }

  function chargerScript(src) {
    return new Promise((ok, ko) => {
      if (document.querySelector(`script[src="${src}"]`)) return ok();
      const s = document.createElement('script'); s.src = src; s.onload = ok; s.onerror = () => ko(new Error('Chargement impossible : ' + src)); document.head.append(s);
    });
  }
  const jsPdf = async () => { if (!window.jspdf) await chargerScript('https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js'); return window.jspdf.jsPDF; };

  // ---------- Pad de signature (même tracé que l'app d'émargement) ----------
  function pad(canvas) {
    const ctx = canvas.getContext('2d');
    let actif = false, dernier = null, vide = true, image = '';
    const pos = e => { const r = canvas.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
    function taille() {
      const r = canvas.getBoundingClientRect(); if (!r.width) return;
      const dpr = window.devicePixelRatio || 1;
      canvas.width = Math.round(r.width * dpr); canvas.height = Math.round(r.height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.strokeStyle = '#1E1C16'; ctx.lineWidth = 2.4;
      if (image) dessiner(image);
    }
    function dessiner(src) {
      // Image posée sans déformation (signature importée), centrée dans le cadre.
      const i = new Image(); i.onload = () => { const r = canvas.getBoundingClientRect(); ctx.clearRect(0, 0, r.width, r.height);
        const k = Math.min(r.width / i.width, r.height / i.height), w = i.width * k, h = i.height * k; ctx.drawImage(i, (r.width - w) / 2, (r.height - h) / 2, w, h); }; i.src = src;
    }
    canvas.addEventListener('pointerdown', e => { e.preventDefault(); canvas.setPointerCapture(e.pointerId); dernier = pos(e); actif = true; });
    canvas.addEventListener('pointermove', e => {
      if (!actif) return;
      const p = pos(e);
      ctx.beginPath(); ctx.moveTo(dernier.x, dernier.y);
      ctx.quadraticCurveTo(dernier.x, dernier.y, (dernier.x + p.x) / 2, (dernier.y + p.y) / 2); ctx.lineTo(p.x, p.y); ctx.stroke();
      dernier = p; vide = false;
    });
    const fin = () => { if (!actif) return; actif = false; image = exporter(); };
    canvas.addEventListener('pointerup', fin); canvas.addEventListener('pointercancel', fin);
    function exporter() {
      const k = Math.min(1, 600 / canvas.width), o = document.createElement('canvas');
      o.width = Math.round(canvas.width * k); o.height = Math.round(canvas.height * k);
      o.getContext('2d').drawImage(canvas, 0, 0, o.width, o.height);
      return o.toDataURL('image/png');
    }
    new ResizeObserver(() => taille()).observe(canvas);
    return {
      taille, estVide: () => vide && !image,
      effacer() { const r = canvas.getBoundingClientRect(); ctx.clearRect(0, 0, r.width, r.height); vide = true; image = ''; },
      poser(src) { image = src || ''; vide = !src; if (src) dessiner(src); else { const r = canvas.getBoundingClientRect(); ctx.clearRect(0, 0, r.width, r.height); } },
      image: () => image || (vide ? '' : exporter()),
    };
  }

  // ---------- Images ----------
  async function lireImage(fichier) {
    const url = URL.createObjectURL(fichier);
    try { return await new Promise((ok, ko) => { const i = new Image(); i.onload = () => ok(i); i.onerror = () => ko(new Error('Image illisible')); i.src = url; }); }
    finally { setTimeout(() => URL.revokeObjectURL(url), 1000); }
  }
  // Photo compressée en JPEG (côté max, qualité) → data URL.
  async function photoCompressee(fichier, cote = 1280, qualite = 0.7) {
    const img = await lireImage(fichier);
    const k = Math.min(1, cote / Math.max(img.width, img.height)), c = document.createElement('canvas');
    c.width = Math.round(img.width * k); c.height = Math.round(img.height * k);
    c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
    return c.toDataURL('image/jpeg', qualite);
  }
  // Tampon scanné ou photographié : fond clair rendu transparent, encre conservée, recadré, PNG ≤ 700 px.
  async function tamponDetoure(fichier) {
    const img = await lireImage(fichier);
    const k = Math.min(1, 700 / Math.max(img.width, img.height)), c = document.createElement('canvas');
    c.width = Math.round(img.width * k); c.height = Math.round(img.height * k);
    const ctx = c.getContext('2d'); ctx.drawImage(img, 0, 0, c.width, c.height);
    const d = ctx.getImageData(0, 0, c.width, c.height), p = d.data;
    let x0 = c.width, y0 = c.height, x1 = 0, y1 = 0;
    for (let i = 0; i < p.length; i += 4) {
      const lum = 0.299 * p[i] + 0.587 * p[i + 1] + 0.114 * p[i + 2];
      if (p[i + 3] < 20 || lum > 200) { p[i + 3] = 0; continue; }
      if (lum > 150) p[i + 3] = Math.round(p[i + 3] * (200 - lum) / 50);
      const n = i / 4, x = n % c.width, y = (n - x) / c.width;
      if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
    }
    ctx.putImageData(d, 0, 0);
    if (x1 <= x0 || y1 <= y0) return c.toDataURL('image/png');
    const m = 6, o = document.createElement('canvas');
    o.width = Math.min(c.width, x1 - x0 + 2 * m); o.height = Math.min(c.height, y1 - y0 + 2 * m);
    o.getContext('2d').drawImage(c, Math.max(0, x0 - m), Math.max(0, y0 - m), o.width, o.height, 0, 0, o.width, o.height);
    return o.toDataURL('image/png');
  }
  const tailleImage = src => new Promise(ok => { const i = new Image(); i.onload = () => ok({ w: i.width, h: i.height }); i.onerror = () => ok({ w: 1, h: 1 }); i.src = src; });

  // ---------- Liste de n° de badges collée / importée ----------
  // Accepte : une colonne copiée depuis Excel, des n° séparés par espaces, virgules ou points-virgules, et des plages « 1001-1080 ».
  function analyserNumeros(texte) {
    const sortie = [];
    for (const brut of String(texte || '').split(/[\r\n,;\t]+/)) {
      const v = brut.trim(); if (!v) continue;
      const plage = v.match(/^([A-Za-z]*)(\d+)\s*(?:-|à|a|→)\s*\1?(\d+)$/);
      if (plage && plage[3].length >= plage[2].length - 1) {
        const pre = plage[1], debut = parseInt(plage[2], 10), finN = parseInt(plage[3], 10), larg = plage[2].length;
        if (finN >= debut && finN - debut < 2000) { for (let n = debut; n <= finN; n++) sortie.push((pre + String(n).padStart(larg, '0')).toUpperCase()); continue; }
      }
      for (const morceau of v.split(/\s+/)) if (morceau) sortie.push(morceau.toUpperCase());
    }
    return sortie;
  }

  // ---------- QR code ----------
  async function qrSvg(texte, taille = 220) {
    if (!window.qrcode) await chargerScript('https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.min.js');
    const q = window.qrcode(0, 'M'); q.addData(texte); q.make();
    const n = q.getModuleCount(), m = 4, cell = taille / (n + 2 * m);
    let d = '';
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) if (q.isDark(y, x)) d += `M${((x + m) * cell).toFixed(2)} ${((y + m) * cell).toFixed(2)}h${cell.toFixed(2)}v${cell.toFixed(2)}h-${cell.toFixed(2)}z`;
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${taille} ${taille}" width="${taille}" height="${taille}" role="img" aria-label="QR code"><rect width="100%" height="100%" fill="#fff"/><path d="${d}" fill="#000"/></svg>`;
  }

  const urlPage = page => new URL(page, location.href).href.split('#')[0].replace(/\?.*$/, '');
  const lienSignature = jeton => urlPage('signer-badges.html') + '?t=' + jeton;
  const QUALITES = { proprietaire: 'Propriétaire', locataire: 'Locataire', autre: 'Autre' };
  const ETATS = { commence: 'Commencé', livres: 'Badges livrés au syndic', distribution: 'Distribution en cours', recensement: 'Recensement en cours',
    recensement_termine: 'Recensement terminé', commande: 'Matériel commandé', installation: 'Installation en cours', reserves: 'Réserves à lever',
    attente_facturation: 'Installation terminée, en attente de facturation', facture: 'Facturé, chantier terminé', termine: 'Terminé' };
  // ---------- Avancement d'un chantier : étapes, étape en cours, pourcentage ----------
  // Chaque étape vaut de 0 à 1 (fraction pour les étapes « x sur n ») ; le pourcentage est la moyenne.
  function avancement(c) {
    const k = c.compteurs || {}, rec = c.recensement || {}, so = c.sondage || {}, camp = c.campagne || {}, fo = c.fourniture || {}, etat = c.etat || 'commence';
    const apres = (...e) => e.includes(etat);
    const n = c.nb_logements_saisis || 0, nc = c.nb_commandes || 0, ni = Math.max(c.nb_invites || 0, nc), nr = c.nb_rdv || 0, ne = c.nb_emarges || 0;
    const fini = apres('attente_facturation', 'facture', 'termine'), facture = !!(c.facture || {}).url || apres('facture', 'termine');
    const vigik = c.travaux === 'vigik' || c.travaux === 'interphone_vigik';
    const pl = (x, mot) => `${x} ${mot}${x > 1 ? 's' : ''}`;
    const badges = { cle: 'badges', titre: 'Remise des badges', fait: k.livres > 0 && k.remis >= k.livres ? 1 : k.livres ? k.remis / k.livres : 0,
      enCours: `Remise des badges : ${k.remis || 0} / ${k.livres || 0} remis`, attente: 'En attente de la livraison des badges' };
    let E;
    if (c.type !== 'complet') {
      E = [
        { cle: 'livres', titre: 'Badges livrés au syndic', fait: k.livres > 0 || apres('livres', 'distribution', 'termine') ? 1 : 0, attente: 'En attente de la livraison des badges au syndic' },
        badges,
        { cle: 'termine', titre: 'Chantier terminé', fait: etat === 'termine' ? 1 : 0, attente: 'Clôture du chantier' },
      ];
    } else {
      const commande = apres('commande', 'installation', 'reserves', 'attente_facturation', 'facture', 'termine'), surSite = apres('installation', 'reserves', 'attente_facturation', 'facture', 'termine');
      E = [
        { cle: 'etiquettes', titre: 'Étiquettes de numérotation (validées par Harmonie)', fait: rec.etiquettes_le ? 1 : 0,
          attente: 'En attente de la pose des étiquettes de numérotation des appartements (validation Harmonie)' },
        { cle: 'fichier', titre: 'Fichier des copropriétaires', fait: rec.etape === 'pret' ? 1 : n ? 0.5 : 0,
          enCours: `Création du fichier des copropriétaires par le syndic (${pl(n, 'appartement')} saisi${n > 1 ? 's' : ''})`, attente: 'En attente du fichier des copropriétaires (syndic)' },
        { cle: 'sondage', titre: 'Recensement envoyé aux copropriétaires', fait: so.clos_le || (n && ni >= n) ? 1 : so.ouvert_le && n ? ni / n : 0,
          enCours: `Envoi du recensement : ${ni} / ${n} copropriétaires`, attente: 'Recensement à envoyer aux copropriétaires' },
        { cle: 'reponses', titre: 'Recensements signés par les copropriétaires', fait: so.clos_le || (n && nc >= n) ? 1 : n ? nc / n : 0,
          enCours: `Recensement en cours : ${nc} / ${n} signés`, attente: 'En attente des réponses des copropriétaires' },
        { cle: 'commande', titre: 'Commande envoyée au fournisseur', fait: fo.envoyee_le || commande ? 1 : 0, attente: 'En attente de la commande du matériel par Harmonie Électricité' },
        { cle: 'reception', titre: 'Matériel reçu', fait: fo.recu_le || surSite ? 1 : 0, attente: 'En attente de la livraison du matériel' },
        { cle: 'campagne', titre: 'Campagne d’information (date d’intervention, affichage)', fait: camp.planifiee_le || (camp.jours || []).length || surSite ? 1 : 0,
          attente: 'Planification de la campagne d’information : date d’intervention et feuille d’affichage' },
        { cle: 'rdv', titre: 'Rendez-vous validés par tous les appartements', fait: surSite || (n && nr >= n) ? 1 : n ? nr / n : 0,
          enCours: `Rendez-vous : ${nr} / ${n} appartements`, attente: 'En attente des rendez-vous des copropriétaires et locataires' },
        { cle: 'installation', titre: 'Installation et émargement', fait: fini || (n && ne >= n) ? 1 : n && ne ? ne / n : etat === 'installation' ? 0.1 : 0,
          enCours: `Installation : ${ne} / ${n} appartements émargés`, attente: 'En attente de l’installation' },
      ];
      // Les badges sont souvent remis avant l'intervention : étape en parallèle, comptée dans le pourcentage.
      // Badges récupérés appartement par appartement (stock syndic et intervenants exclus).
      const nba = c.nb_badges_attendus || 0, nbo = c.nb_badges_ok || 0;
      if (vigik) E.push({ ...badges, parallele: true, ...(nba ? { fait: nbo / nba, enCours: `Badges récupérés : ${nbo} / ${nba} appartements` } : {}) });
      E.push({ cle: 'facture', titre: 'Facturé, chantier terminé', fait: facture ? 1 : 0,
        attente: fini ? 'Installation terminée, en attente de facturation' : etat === 'reserves' ? 'Réserves à lever' : 'Facturation' });
    }
    E.forEach(e => { e.fait = Math.max(0, Math.min(1, +e.fait || 0)); });
    const suite = E.filter(e => !e.parallele), i = suite.findIndex(e => e.fait < 1), courante = i < 0 ? null : suite[i];
    const pc = Math.round(E.reduce((t, e) => t + e.fait, 0) / E.length * 100);
    const par = E.find(e => e.parallele && e.fait < 1 && k.livres > 0);
    const libelle = (!courante ? (c.type === 'complet' ? 'Facturé, chantier terminé' : 'Chantier terminé') : courante.fait > 0 && courante.enCours ? courante.enCours : courante.attente) + (par ? ' · ' + par.enCours : '');
    return { etapes: E, suite, index: i, courante, pc, libelle };
  }
  function friseHtml(c) {
    const a = avancement(c);
    const aide = a.etapes.map(e => (e.fait >= 1 ? '✓ ' : e === a.courante ? '▸ ' : e.parallele ? '∥ ' : '· ') + e.titre).join('\n');
    return `<div class="frise" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${a.pc}" title="${esc(aide)}"><i style="width:${a.pc}%"></i><span>${a.pc} %</span></div>
      <div class="frise-legende"><span>${a.index < 0 ? '' : `Étape ${a.index + 1} / ${a.suite.length} · `}${esc(a.libelle)}</span></div>`;
  }

  const appt = l => l.numero ? 'Appt ' + l.numero : l.lot ? 'Lot ' + l.lot : 'Appartement';
  const STATUTS_BADGE = { stock: 'En stock', reserve: 'Réservé', remis: 'Remis', perdu: 'Perdu', desactive: 'Désactivé' };

  // ---------- PDF : bon de remise de badges émargé ----------
  async function pdfRemise(r) {
    const JsPDF = await jsPdf();
    const doc = new JsPDF({ unit: 'mm', format: 'a4', compress: true });
    const W = 210, M = 15, ENC = [23, 24, 28], GRIS = [107, 102, 88], OR = [168, 132, 63], FILET = [217, 212, 200];
    const s = r.syndic || {}, c = r.copro || {};
    const T = (t, x, y, o = {}) => { doc.setFont('helvetica', o.b ? 'bold' : 'normal'); doc.setFontSize(o.s || 10); doc.setTextColor(...(o.c || ENC)); doc.text(String(t ?? ''), x, y, o.al ? { align: o.al } : undefined); };
    let y = 18;
    // En-tête : le syndic émet le bon
    T(s.nom || 'Syndic', M, y, { s: 15, b: true });
    const coord = [[s.adresse, [s.cp, s.ville].filter(Boolean).join(' ')].filter(Boolean).join(', '), [s.tel, s.email].filter(Boolean).join(' • '), s.siret && 'SIRET ' + s.siret].filter(Boolean);
    coord.forEach((l, i) => T(l, M, y + 5.5 + i * 4.3, { s: 8.5, c: GRIS }));
    T('BON DE REMISE DE BADGES', W - M, y - 2, { s: 8.5, c: OR, al: 'right' });
    T('N° ' + (r.numero || ''), W - M, y + 5, { s: 13, b: true, al: 'right' });
    T(r.statut === 'annule' ? 'ANNULÉ le ' + dateCourte(r.annule_le) : 'Émis le ' + dateCourte(r.cree_le), W - M, y + 10.5, { s: 8.5, c: r.statut === 'annule' ? [180, 68, 47] : GRIS, al: 'right' });
    y += 8 + Math.max(2, coord.length) * 4.3 + 4;
    doc.setDrawColor(...OR); doc.setLineWidth(0.5); doc.line(M, y, W - M, y); y += 9;

    const section = t => { T(t.toUpperCase(), M, y, { s: 8, b: true, c: OR }); y += 2; doc.setDrawColor(...FILET); doc.setLineWidth(0.2); doc.line(M, y, W - M, y); y += 5.5; };
    const kv = lignes => {
      const cw = (W - 2 * M) / 2; let h = 0;
      lignes.filter(l => l[1]).forEach((l, i, t) => {
        const x = M + (i % 2) * cw;
        T(l[0], x, y, { s: 7.5, c: GRIS });
        const lignesTxt = doc.splitTextToSize(String(l[1]), cw - 4); doc.setFont('helvetica', 'normal'); doc.setFontSize(10); doc.setTextColor(...ENC); doc.text(lignesTxt, x, y + 4.5);
        h = Math.max(h, 4.5 + lignesTxt.length * 4.4);
        if (i % 2 === 1 || i === t.length - 1) { y += h + 3; h = 0; }
      });
    };
    section('Résidence');
    kv([['Copropriété', c.nom], ['Adresse', [c.adresse, [c.cp, c.ville].filter(Boolean).join(' ')].filter(Boolean).join(', ')], ['Référence', c.reference]]);
    section('Bénéficiaire');
    kv([['Nom', r.proprietaire], ['Qualité', QUALITES[r.qualite] || r.qualite], ['Logement', [r.batiment && 'Bât. ' + r.batiment, r.lot].filter(Boolean).join(' • ')],
      ['Téléphone', r.tel], ['E-mail', r.email]]);
    section(`Badges remis (${(r.badges || []).length})`);
    const acces = r.acces || {}, avecDroits = (r.badges || []).some(b => acces[b]);
    const per = avecDroits ? 2 : 4, cw = (W - 2 * M) / per;
    (r.badges || []).forEach((b, i) => {
      const x = M + (i % per) * cw; T(`${i + 1}.`, x, y, { s: 8, c: GRIS }); T(b, x + 6, y, { s: 10.5, b: true });
      if (acces[b]) T(acces[b], x + 6, y + 4.2, { s: 8, c: GRIS }); // droit d'accès Vigik
      if (i % per === per - 1 || i === r.badges.length - 1) y += avecDroits ? 10 : 6;
    });
    y += 1;
    if (r.commentaire) { section('Commentaire'); const l = doc.splitTextToSize(r.commentaire, W - 2 * M); doc.setFont('helvetica', 'normal'); doc.setFontSize(10); doc.setTextColor(...ENC); doc.text(l, M, y); y += l.length * 4.4 + 4; }
    if (y > 200) { doc.addPage(); y = 20; }
    doc.setFillColor(247, 244, 238); doc.rect(M, y, W - 2 * M, 12, 'F');
    const att = doc.splitTextToSize(`Le bénéficiaire reconnaît avoir reçu le${(r.badges || []).length > 1 ? 's' : ''} ${(r.badges || []).length} badge${(r.badges || []).length > 1 ? 's' : ''} d’accès listé${(r.badges || []).length > 1 ? 's' : ''} ci-dessus pour la résidence ${c.nom || ''}. Tout badge perdu ou volé doit être signalé sans délai au syndic afin d’être désactivé.`, W - 2 * M - 8);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5); doc.setTextColor(...GRIS); doc.text(att, M + 4, y + 5); y += 18;

    const bw = (W - 2 * M - 8) / 2, bh = 42;
    // Cadre syndic : tampon + signature du gestionnaire
    T('POUR LE SYNDIC', M, y, { s: 7.5, b: true, c: OR }); T(s.signataire || r.agent_nom || '', M, y + 5, { s: 10 });
    doc.setDrawColor(...FILET); doc.setLineWidth(0.3); doc.rect(M, y + 8, bw, bh);
    if (s.tampon) { try { const t = await tailleImage(s.tampon); const h = Math.min(bh - 6, (bw / 2) * t.h / t.w), w = h * t.w / t.h; doc.addImage(s.tampon, 'PNG', M + 3, y + 11, w, h); } catch {} }
    if (s.signature) { try { const t = await tailleImage(s.signature); const w = bw / 2 - 2, h = Math.min(bh - 8, w * t.h / t.w); doc.addImage(s.signature, 'PNG', M + bw / 2, y + 8 + (bh - h) / 2, w, h); } catch {} }
    // Cadre résident
    const x2 = M + bw + 8;
    T('LE BÉNÉFICIAIRE · LU ET APPROUVÉ', x2, y, { s: 7.5, b: true, c: OR }); T(r.signataire || r.proprietaire || '', x2, y + 5, { s: 10 });
    doc.rect(x2, y + 8, bw, bh);
    if (r.signature) { try { const t = await tailleImage(r.signature); const w = bw - 6, h = Math.min(bh - 6, w * t.h / t.w); doc.addImage(r.signature, 'PNG', x2 + 3, y + 8 + (bh - h) / 2, w, h); } catch {} }
    else { T(r.statut === 'annule' ? 'Remise annulée' : 'En attente de signature', x2 + bw / 2, y + 8 + bh / 2, { s: 9, c: GRIS, al: 'center' }); }
    y += 8 + bh + 6;
    if (r.signe_le) T(`Signé le ${horodatage(r.signe_le)} ${r.mode_signature === 'distance' ? 'à distance, depuis le lien personnel envoyé au bénéficiaire' : 'sur place'}.`, M, y, { s: 8.5, c: GRIS });
    if (r.agent_nom) T(`Remise effectuée par ${r.agent_nom}.`, M, y + 4.5, { s: 8.5, c: GRIS });
    if (r.statut === 'annule' && r.annule_motif) T('Motif d’annulation : ' + r.annule_motif, M, y + 9, { s: 8.5, c: [180, 68, 47] });

    // Photos des badges remis
    const photos = r.photos || [];
    if (photos.length) {
      doc.addPage(); y = 18;
      T('PHOTOS DES BADGES REMIS', M, y, { s: 8, b: true, c: OR }); T('N° ' + (r.numero || ''), W - M, y, { s: 8, c: GRIS, al: 'right' }); y += 6;
      const pw = (W - 2 * M - 6) / 2;
      for (let i = 0; i < photos.length; i++) {
        try {
          const t = await tailleImage(photos[i]); const h = Math.min(110, pw * t.h / t.w), w = h * t.w / t.h;
          const x = M + (i % 2) * (pw + 6);
          if (i % 2 === 0 && i > 0) y += 116;
          if (y + h > 280) { doc.addPage(); y = 18; }
          doc.addImage(photos[i], 'JPEG', x, y, w, h);
        } catch {}
      }
    }
    // Pied de page
    const n = doc.getNumberOfPages();
    for (let p = 1; p <= n; p++) {
      doc.setPage(p);
      doc.setDrawColor(...FILET); doc.setLineWidth(0.2); doc.line(M, 284, W - M, 284);
      // Logo Harmonie Électricité (noir et or) en pied de page, quand logos.js est chargé.
      let xt = M;
      if (typeof LOGO_NOIR_OR !== 'undefined') { try { doc.addImage(LOGO_NOIR_OR, 'PNG', M, 285.6, 20, 20 * LOGO_NOIR_OR_RATIO); xt = M + 24; } catch {} }
      T(`${s.nom || ''} • Bon ${r.numero || ''} • Accès installés par ${ENTREPRISE.nom}, ${ENTREPRISE.tel}`, xt, 289, { s: 7, c: GRIS });
      T(`Page ${p} / ${n}`, W - M, 289, { s: 7, c: GRIS, al: 'right' });
    }
    return doc.output('blob');
  }
  // ---------- PDF : bon de commande signé par le copropriétaire ----------
  const euros = n => (Math.round((+n || 0) * 100) / 100).toLocaleString('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + ' €';
  const QUALITES_COMMANDE = { occupant: 'Propriétaire occupant', bailleur: 'Propriétaire bailleur' };
  async function pdfCommande(k) {
    const JsPDF = await jsPdf();
    const doc = new JsPDF({ unit: 'mm', format: 'a4', compress: true });
    const W = 210, M = 15, ENC = [23, 24, 28], GRIS = [107, 102, 88], OR = [168, 132, 63], FILET = [217, 212, 200];
    const c = k.copro || {}, lg = k.logement || {};
    const T = (t, x, y, o = {}) => { doc.setFont('helvetica', o.b ? 'bold' : 'normal'); doc.setFontSize(o.s || 10); doc.setTextColor(...(o.c || ENC)); doc.text(String(t ?? ''), x, y, o.al ? { align: o.al } : undefined); };
    let y = 16;
    if (typeof LOGO_NOIR_OR !== 'undefined') { try { doc.addImage(LOGO_NOIR_OR, 'PNG', M, y - 4, 42, 42 * LOGO_NOIR_OR_RATIO); } catch {} }
    else T(ENTREPRISE.nom, M, y + 4, { s: 14, b: true });
    T([ENTREPRISE.adresse, ENTREPRISE.tel + ' • ' + ENTREPRISE.email].join('   '), M, y + 18, { s: 8, c: GRIS });
    T('BON DE COMMANDE', W - M, y, { s: 8.5, c: OR, al: 'right' });
    T('N° ' + (k.numero || ''), W - M, y + 7, { s: 13, b: true, al: 'right' });
    T(k.statut === 'remplace' ? 'Remplacé par un bon plus récent' : 'Signé le ' + horodatage(k.signe_le), W - M, y + 12.5, { s: 8.5, c: k.statut === 'remplace' ? [180, 68, 47] : GRIS, al: 'right' });
    y += 24; doc.setDrawColor(...OR); doc.setLineWidth(0.5); doc.line(M, y, W - M, y); y += 9;
    const section = t => { T(t.toUpperCase(), M, y, { s: 8, b: true, c: OR }); y += 2; doc.setDrawColor(...FILET); doc.setLineWidth(0.2); doc.line(M, y, W - M, y); y += 5.5; };
    const kv = lignes => {
      const cw = (W - 2 * M) / 2; let h = 0;
      lignes.filter(l => l[1]).forEach((l, i, t) => {
        const x = M + (i % 2) * cw;
        T(l[0], x, y, { s: 7.5, c: GRIS });
        const tx = doc.splitTextToSize(String(l[1]), cw - 4); doc.setFont('helvetica', 'normal'); doc.setFontSize(10); doc.setTextColor(...ENC); doc.text(tx, x, y + 4.5);
        h = Math.max(h, 4.5 + tx.length * 4.4);
        if (i % 2 === 1 || i === t.length - 1) { y += h + 3; h = 0; }
      });
    };
    section('Résidence');
    kv([['Copropriété', c.nom], ['Adresse', [c.adresse, [c.cp, c.ville].filter(Boolean).join(' ')].filter(Boolean).join(', ')], ['Référence', c.reference]]);
    section('Copropriétaire');
    kv([['Nom', [k.prenom, k.nom].filter(Boolean).join(' ')], ['Qualité', QUALITES_COMMANDE[k.qualite] || k.qualite],
      ['Appartement (étiquette)', k.numero_appt || lg.numero], ['N° de lot', lg.lot], ['Téléphone', k.telephone], ['E-mail', k.email]]);
    section('Matériel commandé');
    const cols = [M, M + 104, M + 120, M + 146, W - M];
    T('Désignation', cols[0], y, { s: 7.5, c: GRIS }); T('Qté', cols[1] + 8, y, { s: 7.5, c: GRIS, al: 'right' }); T('P.U. HT', cols[2] + 22, y, { s: 7.5, c: GRIS, al: 'right' });
    T('TVA', cols[3] + 8, y, { s: 7.5, c: GRIS, al: 'right' }); T('Total TTC', cols[4], y, { s: 7.5, c: GRIS, al: 'right' }); y += 5;
    for (const l of k.lignes || []) {
      doc.setFont('helvetica', 'normal'); doc.setFontSize(9.5); doc.setTextColor(...ENC);
      const nom = doc.splitTextToSize((l.marque ? l.marque + ' ' : '') + (l.ref ? l.ref + ' — ' : '') + l.nom, 92);
      doc.text(nom, cols[0], y);
      T(l.qte, cols[1] + 8, y, { s: 9.5, al: 'right' }); T(euros(l.prix_ht), cols[2] + 22, y, { s: 9.5, al: 'right' });
      T(String(l.tva).replace('.', ',') + ' %', cols[3] + 8, y, { s: 9.5, al: 'right' }); T(euros(l.total_ttc), cols[4], y, { s: 9.5, b: true, al: 'right' });
      y += nom.length * 4.3 + 2.5; doc.setDrawColor(...FILET); doc.line(M, y - 1.5, W - M, y - 1.5); y += 1.5;
    }
    y += 2;
    [['Total HT', euros(k.total_ht)], ['TVA', euros((+k.total_ttc || 0) - (+k.total_ht || 0))], ['Total TTC', euros(k.total_ttc)]].forEach(([a, b], i) => {
      T(a, W - M - 40, y, { s: i === 2 ? 11 : 9.5, b: i === 2, c: i === 2 ? ENC : GRIS, al: 'right' }); T(b, W - M, y, { s: i === 2 ? 11 : 9.5, b: i === 2, al: 'right' }); y += i === 1 ? 7 : 5.5;
    });
    y += 3;
    doc.setFillColor(247, 244, 238); doc.rect(M, y, W - 2 * M, 16, 'F');
    const att = doc.splitTextToSize(`Je soussigné(e) ${[k.prenom, k.nom].filter(Boolean).join(' ')} confirme le choix du matériel ci-dessus pour mon appartement, dans le cadre du remplacement du système d’interphonie de la résidence. Ce montant vous sera facturé par votre syndic de copropriété. TVA à taux réduit (10 %) applicable aux travaux dans les logements de plus de deux ans.`, W - 2 * M - 8);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(8.3); doc.setTextColor(...GRIS); doc.text(att, M + 4, y + 5); y += 22;
    T('LE COPROPRIÉTAIRE · BON POUR ACCORD', M, y, { s: 7.5, b: true, c: OR }); T([k.prenom, k.nom].filter(Boolean).join(' '), M, y + 5, { s: 10 });
    const bw = 90, bh = 40; doc.setDrawColor(...FILET); doc.setLineWidth(0.3); doc.rect(M, y + 8, bw, bh);
    if (k.signature) { try { const t = await tailleImage(k.signature); const w = bw - 6, h = Math.min(bh - 6, w * t.h / t.w); doc.addImage(k.signature, 'PNG', M + 3, y + 8 + (bh - h) / 2, w, h); } catch {} }
    T(`Signé électroniquement le ${horodatage(k.signe_le)}${k.par === 'gestionnaire' ? ', saisi par le gestionnaire' : ', depuis le lien personnel du copropriétaire'}.`, M, y + bh + 14, { s: 8.5, c: GRIS });
    const n = doc.getNumberOfPages();
    for (let p = 1; p <= n; p++) {
      doc.setPage(p); doc.setDrawColor(...FILET); doc.setLineWidth(0.2); doc.line(M, 284, W - M, 284);
      T(`${ENTREPRISE.nom} • Bon de commande ${k.numero || ''} • ${c.nom || ''}`, M, 289, { s: 7, c: GRIS });
      T(`Page ${p} / ${n}`, W - M, 289, { s: 7, c: GRIS, al: 'right' });
    }
    return doc.output('blob');
  }
  const nomFichierCommande = k => `Bon de commande ${k.numero} - ${(k.copro && k.copro.nom) || ''} - appt ${k.numero_appt || (k.logement && k.logement.numero) || ''}.pdf`.replace(/[\\/:*?"<>|]+/g, ' ').replace(/\s+/g, ' ');

  // ---------- Agenda : fichier .ics (Google Agenda, Outlook, iPhone) ----------
  function icsBlob(evts) {
    const d = t => new Date(t).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
    const e = t => String(t || '').replace(/\\/g, '\\\\').replace(/[,;]/g, m => '\\' + m).replace(/\r?\n/g, '\\n');
    const L = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Harmonie Electricite//Portail//FR', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH'];
    for (const v of evts) L.push('BEGIN:VEVENT', 'UID:' + (v.uid || Math.random().toString(36).slice(2)) + '@harmonie-electricite', 'DTSTAMP:' + d(Date.now()),
      'DTSTART:' + d(v.debut), 'DTEND:' + d(v.fin), 'SUMMARY:' + e(v.titre), 'LOCATION:' + e(v.lieu), 'DESCRIPTION:' + e(v.description), 'END:VEVENT');
    L.push('END:VCALENDAR');
    return new Blob([L.join('\r\n')], { type: 'text/calendar;charset=utf-8' });
  }

  // ---------- Feuille d'affichage des parties communes (QR code de prise de rendez-vous) ----------
  async function pdfAffiche(d) {
    const JsPDF = await jsPdf();
    if (!window.qrcode) await chargerScript('https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.min.js');
    const doc = new JsPDF({ unit: 'mm', format: 'a4', compress: true });
    const W = 210, M = 18, ENC = [23, 24, 28], GRIS = [90, 86, 78], OR = [168, 132, 63], ROUGE = [166, 64, 44];
    const c = d.copro || {}, camp = d.campagne || {}, vigikSeul = c.travaux === 'vigik';
    const lien = urlPage('rdv.html') + '?j=' + camp.jeton_public;
    const T = (t, x, y, o = {}) => { doc.setFont('helvetica', o.b ? 'bold' : 'normal'); doc.setFontSize(o.s || 12); doc.setTextColor(...(o.c || ENC)); doc.text(t, x, y, o.al ? { align: o.al, maxWidth: o.mw } : { maxWidth: o.mw }); };
    let y = 16;
    if (typeof LOGO_NOIR_OR !== 'undefined') { try { doc.addImage(LOGO_NOIR_OR, 'PNG', W / 2 - 25, y, 50, 50 * LOGO_NOIR_OR_RATIO); } catch {} }
    y += 30;
    T('RÉSIDENCE ' + String(c.nom || '').toUpperCase(), W / 2, y, { s: 13, b: true, c: OR, al: 'center' }); y += 12;
    T(vigikSeul ? 'Installation du nouveau contrôle d’accès' : 'Remplacement de l’interphone', W / 2, y, { s: 26, b: true, al: 'center' }); y += 10;
    T('Intervention dans chaque appartement', W / 2, y, { s: 15, c: GRIS, al: 'center' }); y += 14;
    // Jours d'intervention
    const jours = (camp.jours || []).map(j => {
      const dt = new Date(j.date + 'T12:00:00');
      return `${dt.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' })} de ${j.debut.replace(':', 'h')} à ${j.fin.replace(':', 'h')}`;
    });
    doc.setFillColor(243, 235, 221); doc.roundedRect(M, y, W - 2 * M, 10 + jours.length * 9, 3, 3, 'F'); y += 9;
    jours.forEach(j => { T(j.charAt(0).toUpperCase() + j.slice(1), W / 2, y, { s: 17, b: true, al: 'center' }); y += 9; });
    y += 10;
    T('Prenez rendez-vous :', W / 2, y, { s: 16, b: true, al: 'center' }); y += 7;
    T('scannez ce QR code avec l’appareil photo de votre téléphone', W / 2, y, { s: 13, al: 'center' }); y += 5;
    // QR code dessiné en carrés (net à l'impression)
    const q = window.qrcode(0, 'M'); q.addData(lien); q.make();
    const n = q.getModuleCount(), taille = 74, cell = taille / n, x0 = W / 2 - taille / 2;
    doc.setFillColor(0, 0, 0);
    for (let yy = 0; yy < n; yy++) for (let xx = 0; xx < n; xx++) if (q.isDark(yy, xx)) doc.rect(x0 + xx * cell, y + yy * cell, cell + 0.02, cell + 0.02, 'F');
    y += taille + 7;
    T(lien, W / 2, y, { s: 8.5, c: GRIS, al: 'center' }); y += 11;
    const txt = [
      'Locataires et occupants : indiquez votre nom, votre téléphone et le numéro de votre appartement (étiquette blanche collée sur le cadre de votre porte), puis choisissez un créneau.',
      'Une personne majeure doit être présente pendant le rendez-vous. Vous ne pouvez pas être là ? Demandez à un voisin ou à une personne de confiance de vous représenter : pensez à vous dépanner entre voisins !',
    ];
    txt.forEach(t => { doc.setFont('helvetica', 'normal'); doc.setFontSize(12.5); doc.setTextColor(...ENC); const l = doc.splitTextToSize(t, W - 2 * M - 6); doc.text(l, W / 2, y, { align: 'center' }); y += l.length * 6 + 3; });
    { y += 1; doc.setDrawColor(...ROUGE); doc.setLineWidth(0.6); doc.roundedRect(M, y, W - 2 * M, 14, 2, 2);
      T('En cas d’absence au rendez-vous, le nouveau déplacement sera facturé 50 € TTC.', W / 2, y + 9, { s: 12, b: true, c: ROUGE, al: 'center' }); y += 19; }
    if (vigikSeul) {
      y += 2; doc.setDrawColor(...ROUGE); doc.setLineWidth(0.6); doc.roundedRect(M, y, W - 2 * M, 16, 2, 2);
      T('Après l’intervention, les anciens badges ne fonctionneront plus.', W / 2, y + 10, { s: 13, b: true, c: ROUGE, al: 'center' }); y += 22;
    }
    y = Math.max(y + 4, 262);
    doc.setDrawColor(...OR); doc.setLineWidth(0.4); doc.line(M, y, W - M, y); y += 7;
    T(`Sans téléphone ? Appelez ${ENTREPRISE.nom} au ${ENTREPRISE.tel}${d.syndic?.nom ? ' ou votre syndic, ' + d.syndic.nom + (d.syndic.tel ? ' (' + d.syndic.tel + ')' : '') : ''}.`, W / 2, y, { s: 11, c: GRIS, al: 'center', mw: W - 2 * M });
    return doc.output('blob');
  }

  // ---------- Lettres de recensement (courrier, ou pièce jointe de l'e-mail) : une page par copropriétaire ----------
  async function pdfLettresRecensement(d, logements, lien) {
    const JsPDF = await jsPdf();
    if (!window.qrcode) await chargerScript('https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.min.js');
    const doc = new JsPDF({ unit: 'mm', format: 'a4', compress: true });
    const W = 210, M = 20, ENC = [23, 24, 28], GRIS = [90, 86, 78], OR = [168, 132, 63];
    const c = d.copro || {};
    const T = (t, x, y, o = {}) => { doc.setFont('helvetica', o.b ? 'bold' : 'normal'); doc.setFontSize(o.s || 12); doc.setTextColor(...(o.c || ENC)); doc.text(t, x, y, o.al ? { align: o.al } : undefined); };
    logements.forEach((l, i) => {
      if (i) doc.addPage();
      let y = 18;
      if (typeof LOGO_NOIR_OR !== 'undefined') { try { doc.addImage(LOGO_NOIR_OR, 'PNG', M, y - 4, 44, 44 * LOGO_NOIR_OR_RATIO); } catch {} }
      T(d.syndic?.nom || '', W - M, y + 2, { s: 10, c: GRIS, al: 'right' });
      y += 34;
      T(l.nom || 'Madame, Monsieur', M, y, { s: 13, b: true }); y += 6;
      T([l.lot && 'Lot n° ' + l.lot, c.nom].filter(Boolean).join(' — '), M, y, { s: 11, c: GRIS }); y += 16;
      T(c.travaux === 'vigik' ? 'Installation du contrôle d’accès : vos badges' : 'Remplacement de l’interphone : choisissez votre poste', M, y, { s: 17, b: true }); y += 10;
      doc.setFont('helvetica', 'normal'); doc.setFontSize(12); doc.setTextColor(...ENC);
      const msg = doc.splitTextToSize((d.sondage?.texte || d.texte || '') + '\n\nScannez le QR code ci-dessous avec l’appareil photo de votre téléphone (ou ouvrez le lien) : vous verrez les modèles proposés avec leurs prix, puis vous signerez votre choix sur votre téléphone. Cela prend deux minutes.', W - 2 * M);
      doc.text(msg, M, y); y += msg.length * 5.6 + 8;
      const q = window.qrcode(0, 'M'); q.addData(lien(l)); q.make();
      const n = q.getModuleCount(), taille = 70, cell = taille / n, x0 = W / 2 - taille / 2;
      doc.setFillColor(0, 0, 0);
      for (let a = 0; a < n; a++) for (let b = 0; b < n; b++) if (q.isDark(a, b)) doc.rect(x0 + b * cell, y + a * cell, cell + 0.02, cell + 0.02, 'F');
      y += taille + 7;
      T(lien(l), W / 2, y, { s: 8.5, c: GRIS, al: 'center' }); y += 14;
      T('Ce lien est personnel : il ne concerne que votre lot.', W / 2, y, { s: 10.5, c: GRIS, al: 'center' });
      doc.setDrawColor(...OR); doc.setLineWidth(0.4); doc.line(M, 272, W - M, 272);
      T(`Une question ? ${ENTREPRISE.nom} — ${ENTREPRISE.tel}${d.syndic?.nom ? ' • ' + d.syndic.nom : ''}`, W / 2, 279, { s: 10, c: GRIS, al: 'center' });
    });
    return doc.output('blob');
  }

  // ---------- Envoi par le service Gmail d'Harmonie (le même que l'app d'émargement) ----------
  const ENVOI_GMAIL_URL = 'https://send-email-harmonie.harmonie-electricite.workers.dev';
  let jetonGmail = null;
  async function envoiGmail(dest, objet, texte, blob, nom) {
    try {
      if (!jetonGmail) {
        const r = await fetch(SUPA_URL + '/rest/v1/notes?id=eq.he_gcal_refresh&select=payload', { headers: { apikey: SUPA_KEY, Authorization: 'Bearer ' + SUPA_KEY } });
        jetonGmail = r.ok ? (await r.json())[0]?.payload?.refresh_token : null;
      }
      if (!jetonGmail) return 'autorisation Google introuvable';
      const b64 = blob ? await new Promise(ok => { const f = new FileReader(); f.onload = () => ok(String(f.result).split(',')[1]); f.readAsDataURL(blob); }) : undefined;
      const rep = await fetch(ENVOI_GMAIL_URL, { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refresh_token: jetonGmail, to: dest, subject: objet, bodyText: texte, pdfBase64: b64, pdfFilename: nom }) }).catch(() => null);
      if (!rep) return 'pas de connexion au service d’envoi';
      const res = await rep.json().catch(() => null);
      return res && res.success ? '' : String(res?.error?.message || res?.message || 'erreur ' + rep.status).slice(0, 140);
    } catch (e) { return e.message || 'erreur'; }
  }

  // Lien « Ajouter à Google Agenda » (ouvre Google Agenda avec l'événement prérempli).
  function lienGoogleAgenda(v) {
    const d = t => new Date(t).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
    return 'https://calendar.google.com/calendar/render?action=TEMPLATE&text=' + encodeURIComponent(v.titre) + '&dates=' + d(v.debut) + '/' + d(v.fin)
      + '&details=' + encodeURIComponent(v.description || '') + '&location=' + encodeURIComponent(v.lieu || '');
  }

  // ---------- PDF : tableau simple (fiche de programmation Vigik, correspondance des badges) ----------
  async function pdfTableau(titre, sousTitre, colonnes, lignes, largeurs) {
    const JsPDF = await jsPdf();
    const doc = new JsPDF({ unit: 'mm', format: 'a4', orientation: 'landscape', compress: true });
    const W = 297, M = 12, ENC = [23, 24, 28], GRIS = [107, 102, 88], OR = [168, 132, 63], FILET = [217, 212, 200];
    const T = (t, x, y, o = {}) => { doc.setFont('helvetica', o.b ? 'bold' : 'normal'); doc.setFontSize(o.s || 9); doc.setTextColor(...(o.c || ENC)); doc.text(String(t ?? ''), x, y); };
    const total = largeurs.reduce((a, b) => a + b, 0), k = (W - 2 * M) / total, ws = largeurs.map(x => x * k);
    let y = 14;
    const entete = () => {
      if (typeof LOGO_NOIR_OR !== 'undefined') { try { doc.addImage(LOGO_NOIR_OR, 'PNG', M, y - 6, 34, 34 * LOGO_NOIR_OR_RATIO); } catch {} }
      T(titre, M + 40, y, { s: 13, b: true }); T(sousTitre, M + 40, y + 5.5, { s: 9, c: GRIS }); y += 14;
      let x = M; doc.setFillColor(243, 235, 221); doc.rect(M, y - 4.5, W - 2 * M, 7, 'F');
      colonnes.forEach((c, i) => { T(c, x + 1.5, y, { s: 8, b: true, c: OR }); x += ws[i]; }); y += 6;
    };
    entete();
    for (const l of lignes) {
      const cellules = l.map((v, i) => doc.splitTextToSize(String(v ?? ''), ws[i] - 3));
      const h = Math.max(...cellules.map(c => c.length)) * 4 + 2;
      if (y + h > 200) { doc.addPage(); y = 14; entete(); }
      let x = M; doc.setFont('helvetica', 'normal'); doc.setFontSize(9); doc.setTextColor(...ENC);
      cellules.forEach((c, i) => { doc.text(c, x + 1.5, y); x += ws[i]; });
      y += h; doc.setDrawColor(...FILET); doc.setLineWidth(0.15); doc.line(M, y - 3.5, W - M, y - 3.5);
    }
    const n = doc.getNumberOfPages();
    for (let p = 1; p <= n; p++) { doc.setPage(p); T(`${ENTREPRISE.nom} • ${titre} • page ${p} / ${n}`, M, 203, { s: 7, c: GRIS }); }
    return doc.output('blob');
  }

  // ---------- Appartements : grandes tuiles cliquables et fiche complète (espace syndic et portail admin) ----------
  // actions = { pdfCommande(id), pdfRemise(id) } : ouverture des documents signés selon l'espace.
  const catalogues = {};
  async function vueAppartements(conteneur, d, actions) {
    const marque = d.copro.marque_interphone;
    if (marque && !catalogues[marque]) { try { catalogues[marque] = await rpc('ps_catalogue_lire', { p_marque: marque }); } catch { catalogues[marque] = []; } }
    const cat = new Map((catalogues[marque] || []).map(a => [a.ref, a]));
    const nomAffiche = l => (l.commande?.nom || l.nom || '').toUpperCase();
    const badgesDe = (l, loc) => l.remises.filter(r => r.statut === 'signe' && ((r.qualite === 'locataire' || r.mode === 'installation') === loc)).flatMap(r => r.badges);
    conteneur.innerHTML = d.logements.length ? `<div class="apparts">${d.logements.map(l => {
      const k = l.commande, em = l.emarge || {}, att = (k?.lignes || []).filter(x => x.type === 'badge').reduce((t, x) => t + x.qte, 0);
      const remis = badgesDe(l, false).length + badgesDe(l, true).length;
      return `<button type="button" class="appart" data-appart="${esc(l.id)}">
        <div class="num"><small>${l.numero ? 'Appartement' : l.lot ? 'Lot' : 'Appartement'}</small>${esc(l.numero || l.lot || '?')}</div>
        <div class="qui">${esc(nomAffiche(l) || '—')}${k?.qualite === 'bailleur' ? ' · bailleur' : ''}</div>
        <div class="etats"><span class="${k ? 'ok' : ''}">${k ? '✓ commande' : 'commande'}</span><span class="${l.rdv ? 'ok' : ''}">${l.rdv ? '✓ rdv' : 'rdv'}</span>
          ${att ? `<span class="${remis >= att ? 'ok' : ''}">badges ${remis}/${att}</span>` : ''}<span class="${em.statut === 'signe' ? 'ok' : ''}">${em.statut === 'signe' ? '✓ installé' : 'installation'}</span></div>
      </button>`;
    }).join('')}</div>` : '<div class="vide">Aucun appartement : le fichier des copropriétaires n’est pas encore fait.</div>';
    conteneur.querySelectorAll('[data-appart]').forEach(b => b.onclick = () => ficheAppartement(d.logements.find(l => l.id === b.dataset.appart), d, cat, actions, nomAffiche, badgesDe));
  }
  function ficheAppartement(l, d, cat, actions, nomAffiche, badgesDe) {
    let dlg = document.getElementById('dlgFicheAppart');
    if (!dlg) { dlg = document.createElement('dialog'); dlg.id = 'dlgFicheAppart'; dlg.className = 'fiche-appart'; document.body.append(dlg); }
    const k = l.commande, r = l.rdv, em = l.emarge || {}, kv = lignes => `<div class="kv">${lignes.filter(x => x[1]).map(([a, b]) => `<span>${esc(a)}</span><span>${b}</span>`).join('')}</div>`;
    const postes = (k?.lignes || []).filter(x => x.type === 'combine' || x.type === 'moniteur'), plaque = (k?.lignes || []).some(x => x.type === 'plaque');
    const locataire = r && r.qualite === 'locataire' ? r : null;
    const bp = badgesDe(l, false), bl = badgesDe(l, true);
    const docsPostes = postes.map(x => { const a = cat.get(x.ref) || {}; return [a.notice && `<a class="btn btn-petit" href="${esc(a.notice)}" target="_blank" rel="noopener">Notice ${esc(x.ref)}</a>`, a.brochure && `<a class="btn btn-petit" href="${esc(a.brochure)}" target="_blank" rel="noopener">Brochure ${esc(x.ref)}</a>`].filter(Boolean).join(' '); }).join(' ');
    dlg.innerHTML = `<div class="dlg">
      <div class="sourcil">${esc(d.copro.nom)}</div>
      <h3>${l.numero ? 'Appartement ' + esc(l.numero) : l.lot ? 'Lot ' + esc(l.lot) : 'Appartement'}${l.numero && l.lot ? ` <span class="aide">— lot ${esc(l.lot)}</span>` : ''}</h3>
      <h4>Nom affiché sur l’interphone</h4><div style="font-size:20px;letter-spacing:.06em;color:var(--he-white)">${esc(nomAffiche(l) || '—')}</div>
      <h4>Propriétaire${k?.qualite === 'bailleur' ? ' (bailleur)' : k?.qualite === 'occupant' ? ' (occupant)' : ''}</h4>
      ${kv([['Nom', esc([k?.prenom, k?.nom].filter(Boolean).join(' ') || l.nom || '')], ['Téléphone', esc(k?.telephone || l.telephone || '')], ['E-mail', esc([k?.email, ...(l.emails || [])].filter(Boolean).filter((x, i, t) => t.indexOf(x) === i).join(', '))]])}
      ${locataire ? `<h4>Locataire</h4>${kv([['Nom', esc([locataire.prenom, locataire.nom].join(' '))], ['Téléphone', esc(locataire.telephone || '')], ['E-mail', esc(locataire.email || '')]])}` : k?.qualite === 'bailleur' ? '<h4>Locataire</h4><p class="aide">Pas encore connu (il se fait connaître en prenant rendez-vous par l’affiche).</p>' : ''}
      <h4>Matériel</h4>
      ${k ? kv([['Poste', esc(postes.map(x => (x.qte > 1 ? x.qte + ' × ' : '') + [x.marque, x.ref].filter(Boolean).join(' ') + ' — ' + x.nom).join(' + ') || '—')], ['Plaque de propreté', plaque ? 'Oui' : 'Non']]) : '<p class="aide">Pas encore de bon de commande signé.</p>'}
      ${docsPostes ? `<div class="docs" style="margin-top:8px">${docsPostes}</div>` : ''}
      <h4>Badges</h4>
      ${kv([['Propriétaire', bp.length ? `<span class="mono">${esc(bp.join(' • '))}</span>` : 'aucun remis'], ['Locataire', bl.length ? `<span class="mono">${esc(bl.join(' • '))}</span>` : l.badges_locataire ? `${l.badges_locataire} réservé${l.badges_locataire > 1 ? 's' : ''} (remis le jour de l’installation)` : '—']])}
      ${(() => { const att = (k?.lignes || []).filter(x => x.type === 'badge').reduce((t, x) => t + x.qte, 0), enAtt = l.remises.filter(x => x.statut === 'attente').reduce((t, x) => t + x.badges.length, 0);
        const reste = att - bp.length - bl.length - enAtt - (l.badges_locataire || 0);
        return reste > 0 ? `<p style="margin-top:8px"><b style="color:var(--he-white)">${reste} badge${reste > 1 ? 's' : ''} à remettre</b>${enAtt ? ` • ${enAtt} en attente de signature` : ''}</p>` + (actions.remettre ? `<div class="actions" style="margin-top:6px"><button type="button" class="btn btn-or" data-remettre="${esc(l.id)}">Remettre des badges</button></div>` : '') : ''; })()}
      <h4>Rendez-vous et installation</h4>
      ${kv([['Rendez-vous', r ? esc(new Date(r.debut).toLocaleString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' })) + ` — ${esc([r.prenom, r.nom].join(' '))}` : '—'], ['Installation', em.statut === 'signe' ? 'Faite le ' + esc(dateCourte(em.signe_le)) : em.statut === 'absent' ? 'Absent' : '—']])}
      <h4>Documents signés</h4>
      <div class="docs">${[k && `<button type="button" class="btn btn-petit" data-doc-commande="${esc(k.id)}">Bon de commande ${esc(k.numero)}</button>`,
        ...l.remises.filter(x => x.statut === 'signe' && x.mode !== 'installation').map(x => `<button type="button" class="btn btn-petit" data-doc-remise="${esc(x.id)}">Remise de badges ${esc(x.numero)}</button>`),
        em.bon_url && `<a class="btn btn-petit" href="${esc(em.bon_url)}" target="_blank" rel="noopener">Bon d’intervention ${esc(em.bon || '')}</a>`].filter(Boolean).join('') || '<span class="aide">Aucun document signé pour l’instant.</span>'}</div>
      <div class="actions"><button type="button" class="btn btn-or" data-fermer-fiche>Fermer</button></div></div>`;
    dlg.querySelector('[data-fermer-fiche]').onclick = () => dlg.close();
    dlg.querySelectorAll('[data-doc-commande]').forEach(b => b.onclick = () => actions.pdfCommande(b.dataset.docCommande));
    dlg.querySelectorAll('[data-doc-remise]').forEach(b => b.onclick = () => actions.pdfRemise(b.dataset.docRemise));
    dlg.querySelectorAll('[data-remettre]').forEach(b => b.onclick = () => { dlg.close(); actions.remettre(b.dataset.remettre); });
    dlg.showModal();
  }

  const nomFichierRemise = r => `Bon de remise ${r.numero} - ${(r.copro && r.copro.nom) || ''} - ${r.proprietaire || ''}.pdf`.replace(/[\\/:*?"<>|]+/g, ' ').replace(/\s+/g, ' ');

  // Ouvre / télécharge / partage un PDF.
  function telecharger(blob, nom) {
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = nom; document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 60000);
  }
  function imprimer(blob) {
    const url = URL.createObjectURL(blob), w = window.open(url, '_blank');
    if (!w) telecharger(blob, 'document.pdf');
    else setTimeout(() => { try { w.focus(); w.print(); } catch {} }, 800);
  }
  // Envoi par e-mail : sur téléphone, feuille de partage avec le PDF joint ; sur ordinateur, PDF téléchargé + message prêt.
  async function envoyerParEmail(blob, nom, dest, objet, texte) {
    const fichier = new File([blob], nom, { type: 'application/pdf' });
    if (navigator.canShare && navigator.canShare({ files: [fichier] }) && estTel()) {
      if (dest) navigator.clipboard?.writeText(dest).catch(() => {});
      try { await navigator.share({ files: [fichier], title: objet, text: texte }); if (dest) toast('Adresse ' + dest + ' copiée : collez-la comme destinataire.'); return; }
      catch (e) { if (e.name === 'AbortError') return; }
    }
    // Ordinateur : un message « mailto » ne peut pas porter de pièce jointe. Le PDF est déposé en ligne
    // (adresse impossible à deviner) et le message prérempli contient son lien de téléchargement.
    toast('Préparation du message…');
    const url = await deposerPdf(blob);
    if (url) {
      location.href = `mailto:${encodeURIComponent(dest || '')}?subject=${encodeURIComponent(objet)}&body=${encodeURIComponent(texte + '\n\nVotre bon (PDF) : ' + url)}`;
      toast('Le message s’ouvre avec le lien du bon : il ne reste qu’à l’envoyer.', 5000);
      return;
    }
    telecharger(blob, nom);
    location.href = `mailto:${encodeURIComponent(dest || '')}?subject=${encodeURIComponent(objet)}&body=${encodeURIComponent(texte + '\n\n(PDF joint : ' + nom + ')')}`;
    toast('Dépôt en ligne impossible : PDF téléchargé, joignez-le au message qui s’ouvre.', 6000);
  }
  // Dépôt du PDF dans le stockage Supabase, sous un nom aléatoire ; renvoie son adresse publique (ou null).
  async function deposerPdf(blob) {
    const cle = Array.from(crypto.getRandomValues(new Uint8Array(16)), b => b.toString(16).padStart(2, '0')).join('');
    const chemin = `emargement/remises/${cle}.pdf`;
    try {
      const r = await fetch(`${SUPA_URL}/storage/v1/object/bon-photos/${chemin}`, { method: 'POST', headers: { apikey: SUPA_KEY, Authorization: 'Bearer ' + SUPA_KEY, 'Content-Type': 'application/pdf', 'x-upsert': 'false' }, body: blob });
      return r.ok ? `${SUPA_URL}/storage/v1/object/public/bon-photos/${chemin}` : null;
    } catch { return null; }
  }

  return { rpc, $, esc, horodatage, dateCourte, estTel, lienSms, toast, copier, chargerScript, pad, photoCompressee, tamponDetoure, analyserNumeros, qrSvg,
    urlPage, lienSignature, SUPA_URL, SUPA_KEY, QUALITES, ETATS, STATUTS_BADGE, pdfRemise, nomFichierRemise, pdfCommande, nomFichierCommande, euros, QUALITES_COMMANDE, avancement, friseHtml, icsBlob, pdfAffiche, appt, vueAppartements, pdfLettresRecensement, envoiGmail, lienGoogleAgenda, pdfTableau, telecharger, imprimer, envoyerParEmail, ENTREPRISE };
})();
