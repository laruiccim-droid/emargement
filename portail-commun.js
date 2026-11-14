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
      const i = new Image(); i.onload = () => { const r = canvas.getBoundingClientRect(); ctx.clearRect(0, 0, r.width, r.height); ctx.drawImage(i, 0, 0, r.width, r.height); }; i.src = src;
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
    recensement_termine: 'Recensement terminé', commande: 'Matériel commandé', installation: 'Installation en cours', reserves: 'Réserves à lever', termine: 'Terminé' };
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
    const per = 4, cw = (W - 2 * M) / per;
    (r.badges || []).forEach((b, i) => { const x = M + (i % per) * cw; T(`${i + 1}.`, x, y, { s: 8, c: GRIS }); T(b, x + 6, y, { s: 10.5, b: true }); if (i % per === per - 1 || i === r.badges.length - 1) y += 6; });
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
    telecharger(blob, nom);
    location.href = `mailto:${encodeURIComponent(dest || '')}?subject=${encodeURIComponent(objet)}&body=${encodeURIComponent(texte + '\n\n(PDF joint : ' + nom + ')')}`;
    toast('PDF téléchargé : joignez-le au message qui s’ouvre.', 5000);
  }

  return { rpc, $, esc, horodatage, dateCourte, estTel, lienSms, toast, copier, chargerScript, pad, photoCompressee, tamponDetoure, analyserNumeros, qrSvg,
    urlPage, lienSignature, SUPA_URL, SUPA_KEY, QUALITES, ETATS, STATUTS_BADGE, pdfRemise, nomFichierRemise, telecharger, imprimer, envoyerParEmail, ENTREPRISE };
})();
