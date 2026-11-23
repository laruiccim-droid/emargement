// =====================================================================================
// bon-pdf.js — PDF du bon d'intervention, IDENTIQUE à celui de l'app métier.
// Fichier généré par outils/synchro-pdf-bon.py à partir de app-metier/bon.html : ne pas modifier à la main.
// Usage : const blob = await BonPDF.generer(payloadDuBon, 'detail' | 'semi' | 'sansprix');
// La chaîne des bons précédents (bonLieData) doit déjà être complète (fournie par le serveur).
// =====================================================================================
window.BonPDF = (function () {
  'use strict';
  const LOGO_HE_B64 = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAlAAAAEoCAYAAACXe890AAAACXBIWXMAABcRAAAXEQHKJvM/AAAgAElEQVR4nO3d0XHbSLr28ae/2ns5A3GKAUgbgTnFAKwTgeAIrLnklekrXo4cgaEIVhMAa6gIjhQAa6kIjhUBvgs0bY4sNLpJoNEA/r8q1ewaFNkSIeJB94sXpigKAQAAwN//63oAAAAAfUOAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAgAACESAAoCEGWPeGWNmxph3XY8FwE+mKIquxwAAo2WMmUi6tF8zSe8kXXh865Ok75I2kh4lPRZFsWthiOgBux9Nuh3Fmx6Lovje9SDaMNgAZXemrGp7URTLSEOpZYzJVL3jb4qi2EQbjAdjzEzlB32V70VR3MYZjT9jzKbhp/yu8sD1y//v4j2z+1Hm+fD7FN+jEHZG5t738UVRzNobTRhjzKXK92omv7Dk61nl7yQviuKx7sEx2M+Lvz0e+rUoipuWhxPMGLOU9Lli88Mx+1UHz9ml31M7hjXlX10PoEUTuXemZZxheMkkvXds38QZhrel3OOVMeY+wbNh55iP9OGtfzTGSOXBbKfy/YsRhCfy/xkvjTF5z88MM7XznrbCBr4bleM+b+llziV9kvTJGPMsKZd025P3+ZP93Nh0PRDABzVQCGLPnH0OWsuWh9IH5yp/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';
  const PICTO_HE_B64 = 'data:image/png;base64,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';
  // Environnement minimal attendu par le générateur de l'app (pas de formulaire ici).
  let PDF_MODE = 'detail', DOC_TYPE = 'bon', DOC_NUM = '';
  const LIGNES = [], PHOTOS = [];
  function toast() {}
  function sigIsEmpty() { return true; }
  async function _completerChaineBonLie() {}

  async function _genererPDFInner(docData) {
  toast('Génération du PDF…');
  // Compléter la chaîne bonLieData si des maillons manquent (bons sauvegardés avant le fix)
  await _completerChaineBonLie(docData, 0);

  // Charger jsPDF dynamiquement
  if (!window.jsPDF) {
    await new Promise(function(resolve, reject) {
      const s = document.createElement('script');
      s.src = 'https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js';
      s.onload = resolve; s.onerror = reject;
      document.head.appendChild(s);
    });
  }

  const { jsPDF } = window.jspdf;
  const doc = new jsPDF({ orientation:'portrait', unit:'mm', format:'a4' });

  // Use provided doc data or read from form
  const d = docData || null;
  const isBon = d ? (d.type === 'bon') : (DOC_TYPE === 'bon');
  const client  = (d ? d.client  : document.getElementById('f-client').value.trim())  || '—';
  const adresse = (d ? d.adresse : document.getElementById('f-adresse').value.trim()) || '';
  const tel     = (d ? d.tel     : document.getElementById('f-tel').value.trim())     || '';
  const email   = (d ? d.email   : document.getElementById('f-email').value.trim())   || '';
  const date    = (d ? d.date    : document.getElementById('f-date').value) || new Date().toLocaleDateString('fr-FR');
  const hDebut  = d ? (d.heureDebut||'') : document.getElementById('f-heure-debut').value;
  const hFin    = d ? (d.heureFin||'')   : document.getElementById('f-heure-fin').value;
  const duree   = d ? (d.duree||'')      : document.getElementById('f-duree').value;
  const motif   = (d ? d.motif   : document.getElementById('f-motif').value.trim())   || '';
  const rapport = (d ? d.rapport : document.getElementById('f-rapport').value.trim()) || '';
  const notes   = d ? '' : document.getElementById('f-notes-internes').value.trim();
  const showHeures = d ? (d.showHeures !== false) : (document.getElementById('f-show-heures') ? document.getElementById('f-show-heures').checked : true);
  const photos = d ? (d.photos||[]) : PHOTOS;
  const tvaRate = d ? (d.tvaRate||20) : (parseFloat(document.getElementById('f-tva').value) || 20);
  const validite   = d ? (d.validite||'')    : (document.getElementById('f-validite')    ? document.getElementById('f-validite').value    : '');
  const conditions = d ? (d.conditions||'')  : (document.getElementById('f-conditions')  ? document.getElementById('f-conditions').value  : '');
  const lignesPDF  = d ? (function() {
    const mainLignes = d.lignes || [];
    // N'ajouter les lignes des sessions que si le bon a des sessions distinctes
    // (multi-sessions où les lignes n'ont PAS encore été fusionnées dans d.lignes)
    // En mode édition validé, d.lignes contient déjà toutes les lignes fusionnées
    const hasFusedLignes = d.statut === 'valide' && (!d.sessions || !d.sessions.length);
    const hasRealSessions = d.sessions && d.sessions.length > 0;
    if (!hasRealSessions) return mainLignes;
    // Vérifier si les lignes des sessions sont déjà dans mainLignes (éviter le doublon)
    // On considère que si d.lignes existe et d.sessions aussi, les lignes sont déjà fusionnées
    // sauf si une session a des lignes qui ne sont PAS dans mainLignes
    return mainLignes; // En mode édition, d.lignes contient déjà tout
  })() : LIGNES;
  const docNum     = d ? (d.numero||DOC_NUM) : DOC_NUM;

  const ht  = lignesPDF.reduce(function(s,l){ return s+l.qty*l.pu; }, 0);
  const tva = ht * tvaRate / 100;
  const ttc = ht + tva;

  // Couleurs
  const ORANGE  = [185, 148, 62];  // doré design system
  const DARK    = [15, 15, 15];
  const GREY    = [100, 100, 100];
  const LGREY   = [240, 240, 240];
  const WHITE   = [255, 255, 255];
  const GREEN   = [34, 197, 94];

  let y = 0;
  const W = 210; // largeur A4
  const M = 14;  // marge gauche
  const MR = W - M; // marge droite

  // ── EN-TÊTE ──────────────────────────────────────────────
  // Barre orange fine en haut
  doc.setFillColor(...ORANGE);
  doc.rect(0, 0, W, 3, 'F');

  // Picto rond (gauche)
  try {
    doc.addImage(PICTO_HE_B64, 'PNG', M, 5, 26, 26);
  } catch(e) {}

  // Logo texte HARMONIE ÉLECTRICITÉ
  try {
    doc.addImage(LOGO_HE_B64, 'PNG', M + 30, 10, 52, 15);
  } catch(e) {
    doc.setTextColor(...ORANGE);
    doc.setFontSize(16);
    doc.setFont('helvetica', 'bold');
    doc.text('HARMONIE', M + 30, 19);
    doc.setFontSize(9);
    doc.text('ÉLECTRICITÉ', M + 30, 26);
  }

  // Nom sous le logo
  doc.setTextColor(...GREY);
  doc.setFontSize(7);
  doc.setFont('helvetica', 'normal');
  doc.text('Mathieu LARUICCI', M, 35);

  // Coordonnées en haut à droite
  doc.setFontSize(7.5);
  doc.setTextColor(...DARK);
  doc.setFont('helvetica', 'normal');
  doc.text('225 Chemin des Bochets — 73170 Yenne', MR, 11, { align:'right' });
  doc.text('06 31 13 47 01', MR, 17, { align:'right' });
  doc.text('contact@harmonie-electricite.com', MR, 23, { align:'right' });
  doc.text('www.harmonie-electricite.com', MR, 29, { align:'right' });
  // Spécialités
  doc.setFontSize(6.5);
  doc.setTextColor(...GREY);
  doc.text('Alarme · Vidéosurveillance · Contrôle d\'accès · Borne IRVE · Automatisme', MR, 35, { align:'right' });

  // Ligne séparatrice orange sous l'en-tête
  doc.setDrawColor(...ORANGE);
  doc.setLineWidth(0.6);
  doc.line(M, 38.5, W - M, 38.5);
  doc.setLineWidth(0.2);

  y = 44;

  // ── TITRE DOCUMENT ───────────────────────────────────────
  doc.setFillColor(...LGREY);
  doc.rect(M, y, W - 2*M, 12, 'F');
  doc.setTextColor(...DARK);
  doc.setFontSize(14);
  doc.setFont('helvetica', 'bold');
  doc.text(isBon ? 'BON D\'INTERVENTION' : 'DEVIS', M + 4, y + 8);

  doc.setFontSize(10);
  doc.setFont('helvetica', 'normal');
  doc.setTextColor(...GREY);
  doc.text('N° ' + DOC_NUM, MR, y + 8, { align:'right' });

  y += 16;

  // ── BLOC CLIENT + DATE ───────────────────────────────────
  // Bloc client (gauche)
  doc.setFillColor(250, 250, 250);
  doc.roundedRect(M, y, 90, 32, 2, 2, 'F');
  doc.setDrawColor(220, 220, 220);
  doc.roundedRect(M, y, 90, 32, 2, 2, 'S');

  doc.setFontSize(7);
  doc.setFont('helvetica', 'bold');
  doc.setTextColor(...ORANGE);
  doc.text('CLIENT', M + 4, y + 6);

  doc.setFontSize(10);
  doc.setFont('helvetica', 'bold');
  doc.setTextColor(...DARK);
  doc.text(client, M + 4, y + 13);

  doc.setFontSize(8);
  doc.setFont('helvetica', 'normal');
  doc.setTextColor(...GREY);
  let cy = y + 19;
  if (adresse) { doc.text(adresse.slice(0,45), M + 4, cy); cy += 5; }
  if (tel)     { doc.text('Tél : ' + tel, M + 4, cy); cy += 5; }
  if (email)   { doc.text(email.slice(0,40), M + 4, cy); }

  // Bloc date/horaires (droite)
  const bx = W - M - 90;
  doc.setFillColor(250, 250, 250);
  doc.roundedRect(bx, y, 90, 32, 2, 2, 'F');
  doc.setDrawColor(220, 220, 220);
  doc.roundedRect(bx, y, 90, 32, 2, 2, 'S');

  doc.setFontSize(7);
  doc.setFont('helvetica', 'bold');
  doc.setTextColor(...ORANGE);
  doc.text('INFORMATIONS', bx + 4, y + 6);

  doc.setFontSize(8);
  doc.setFont('helvetica', 'normal');
  doc.setTextColor(...DARK);

  const sessionsInfo = d ? (d.sessions || []) : [];
  if (sessionsInfo.length > 1 && isBon) {
    // Multi-sessions — afficher résumé de chaque session
    let iy = y + 13;
    sessionsInfo.forEach(function(s, idx) {
      const sLabel = 'S' + (idx+1) + ' : ' + (s.date||date)
        + (showHeures && s.heureDebut ? '  ' + s.heureDebut + '→' + (s.heureFin||'') : '')
        + (s.duree ? '  (' + s.duree + ')' : '');
      doc.text(sLabel, bx + 4, iy);
      iy += 6;
    });
    if (showHeures) {
      let totalMin = 0;
      sessionsInfo.forEach(function(s) {
        if (s.duree) {
          const m = s.duree.match(/(\d+)h(\d+)min|(\d+)h|(\d+)min/);
          if (m) { const h=parseInt(m[1]||m[3]||0), mn=parseInt(m[2]||m[4]||0); totalMin+=h*60+mn; }
        }
      });
      if (totalMin > 0) {
        const th=Math.floor(totalMin/60), tm=totalMin%60;
        doc.setFont('helvetica', 'bold');
        doc.text('Total : ' + (th?th+'h':'') + String(tm).padStart(2,'0') + 'min', bx + 4, iy);
        iy += 6;
      }
    }
    y += Math.max(38, (sessionsInfo.length * 6) + 20);
  } else {
    // Session unique
    doc.text('Date : ' + date, bx + 4, y + 13);
    if (hDebut && hFin && showHeures) {
      doc.text('Arrivée : ' + hDebut + '   Départ : ' + hFin, bx + 4, y + 19);
    }
    if (duree && showHeures) {
      doc.text('Durée : ' + duree, bx + 4, y + 25);
    }
    if (!isBon && validite) {
      doc.text('Validité : ' + validite, bx + 4, y + 25);
    }
    y += 38;
  }


    // Session unique — afficher motif + rapport + tableau normalement
    if (motif) {
      const PAGE_H = 297;
      const SAFE_BOTTOM = PAGE_H - 20;
      const LINE_H = 4.5;
      if (y + 14 > SAFE_BOTTOM) { doc.addPage(); y = 14; }
      doc.setFontSize(7);
      doc.setFont('helvetica', 'bold');
      doc.setTextColor(...ORANGE);
      doc.text('MOTIF / DESCRIPTION', M, y + 4);
      y += 7;
      doc.setFontSize(9);
      doc.setFont('helvetica', 'normal');
      doc.setTextColor(...DARK);
      const motifLines = doc.splitTextToSize(motif, W - 2*M);
      motifLines.forEach(function(line) {
        if (y + LINE_H > SAFE_BOTTOM) {
          doc.addPage(); y = 14;
          doc.setFontSize(9); doc.setFont('helvetica', 'normal'); doc.setTextColor(...DARK);
        }
        doc.text(line, M, y);
        y += LINE_H;
      });
      y += 4;
    }

    // ── Multi-sessions : afficher détail par session ───────
    const sessions = d ? (d.sessions || []) : [];
    if (sessions.length > 0 && isBon) {
      if (y + MIN_SECTION > SAFE_PDF) { doc.addPage(); y = 14; }
      doc.setFontSize(7);
      doc.setFont('helvetica', 'bold');
      doc.setTextColor(...ORANGE);
      doc.text('DÉTAIL DES SESSIONS', M, y + 4);
      y += 7;

      // Toutes les sessions sont dans sessions[] — la session 1 y est maintenant incluse
      sessions.forEach(function(s, idx) {
        if (y + 14 > SAFE_PDF) { doc.addPage(); y = 14; }
        doc.setFontSize(8);
        doc.setFont('helvetica', 'bold');
        doc.setTextColor(...DARK);
        let sessionHeader = 'Session ' + (idx + 1);
        if (s.date) sessionHeader += ' — ' + s.date;
        if (showHeures && s.heureDebut) sessionHeader += ' · ' + s.heureDebut + ' → ' + (s.heureFin||'') + (s.duree ? ' (' + s.duree + ')' : '');
        doc.text(sessionHeader, M, y);
        y += 5;

        // Rapport spécifique à cette session
        if (s.rapport) {
          doc.setFontSize(8);
          doc.setFont('helvetica', 'normal');
          doc.setTextColor(...GREY);
          const rapLines = doc.splitTextToSize(s.rapport, W - 2*M - 4);
          rapLines.forEach(function(line) {
            if (y + 4 > SAFE_PDF) { doc.addPage(); y = 14; doc.setFontSize(8); doc.setFont('helvetica','normal'); doc.setTextColor(...GREY); }
            doc.text(line, M + 2, y);
            y += 4;
          });
          y += 2;
        }

        // Lignes spécifiques à cette session (pas fusionnées)
        const sLignes = s.lignes || [];
        if (sLignes.length) {
          sLignes.forEach(function(l) {
            doc.setFontSize(7.5);
            doc.setFont('helvetica', 'normal');
            doc.setTextColor(...DARK);
            const ligneText = '  • ' + (l.ref ? '['+l.ref+'] ' : '') + (l.nom||'') + ' — ' + (l.qty||1) + ' ' + (l.unite||'U') + ' × ' + (parseFloat(l.pu)||0).toFixed(2) + '€ = ' + ((l.qty||1)*(parseFloat(l.pu)||0)).toFixed(2) + '€ HT';
            const ll = doc.splitTextToSize(ligneText, W - 2*M - 4);
            if (y + ll.length * 4 + 1 > SAFE_PDF) { doc.addPage(); y = 14; doc.setFontSize(7.5); doc.setFont('helvetica','normal'); doc.setTextColor(...DARK); }
            doc.text(ll, M + 2, y);
            y += ll.length * 4 + 1;
          });
        }
        y += 3;
      });

      // Total durée toutes sessions
      if (showHeures) {
        let totalMin = 0;
        sessions.forEach(function(s) {
          if (s.duree) {
            const m = s.duree.match(/(\d+)h(\d+)min|(\d+)h|(\d+)min/);
            if (m) {
              const h = parseInt(m[1]||m[3]||0), mn = parseInt(m[2]||m[4]||0);
              totalMin += h*60 + mn;
            }
          }
        });
        if (totalMin > 0) {
          if (y + 6 > SAFE_PDF) { doc.addPage(); y = 14; }
          const th = Math.floor(totalMin/60), tm = totalMin%60;
          doc.setFontSize(8);
          doc.setFont('helvetica', 'bold');
          doc.setTextColor(...ORANGE);
          doc.text('Durée totale : ' + (th?th+'h':'') + String(tm).padStart(2,'0') + 'min', M, y);
          y += 6;
        }
      }
    } else if (rapport && isBon) {
      const PAGE_H = 297;
      const FOOTER_H = 20; // espace réservé pour le pied de page
      const SAFE_BOTTOM = PAGE_H - FOOTER_H;
      const LINE_H = 4.5;

      // Saut de page si le titre ne rentre plus
      if (y + 14 > SAFE_BOTTOM) { doc.addPage(); y = 14; }

      doc.setFontSize(7);
      doc.setFont('helvetica', 'bold');
      doc.setTextColor(...ORANGE);
      doc.text('RAPPORT D\'INTERVENTION', M, y + 4);
      y += 7;
      doc.setFontSize(9);
      doc.setFont('helvetica', 'normal');
      doc.setTextColor(...DARK);
      const rapLines = doc.splitTextToSize(rapport, W - 2*M);

      // Imprimer ligne par ligne avec saut de page si nécessaire
      rapLines.forEach(function(line) {
        if (y + LINE_H > SAFE_BOTTOM) {
          doc.addPage();
          y = 14;
          doc.setFontSize(9);
          doc.setFont('helvetica', 'normal');
          doc.setTextColor(...DARK);
        }
        doc.text(line, M, y);
        y += LINE_H;
      });
      y += 4;
    }
    y += 2;

  // ── TABLEAU}
  // Mode d'affichage : PDF_MODE (sélection en cours) > docData.pdfMode (sauvegardé) > 'detail'
  const pdfMode = PDF_MODE || (docData && docData.pdfMode) || 'detail';
  const showPU    = pdfMode === 'detail';
  const showTotal = pdfMode !== 'sansprix';
  const SAFE_PDF  = 277; // limite basse de la zone imprimable (297 - pied de page 20mm)
  // Espace minimal avant d'imprimer un titre de section + en-tête tableau + 2 lignes
  const MIN_SECTION = 38;

  // ── INTERVENTIONS PRÉCÉDENTES (chaîne complète) ──────────
  // Construire la chaîne complète : bonLieData → bonLieData.bonLieData → ...
  var _chainePrev = [];
  var _ptr = docData && docData.bonLieData;
  while (_ptr && _chainePrev.length < 20) { // garde-fou 20 niveaux max
    _chainePrev.push(_ptr);
    _ptr = _ptr.bonLieData || null;
  }
  _chainePrev.reverse(); // afficher du plus ancien au plus récent

  // ── INTERVENTION COURANTE (détail) — affichée en premier ──
  if (y + MIN_SECTION > SAFE_PDF) { doc.addPage(); y = 14; }

  doc.setFontSize(7);
  doc.setFont('helvetica', 'bold');
  doc.setTextColor(...ORANGE);
  var _labelCurrent = _chainePrev.length > 0
    ? 'DÉTAIL INTERVENTION COURANTE — DU ' + (d && d.date ? d.date : '')
    : 'DÉTAIL DES PRESTATIONS';
  doc.text(_labelCurrent, M, y + 4);
  y += 7;

  // En-tête tableau — adapté selon le mode
  doc.setFillColor(...DARK);
  doc.rect(M, y, W - 2*M, 7, 'F');
  doc.setTextColor(...WHITE);
  doc.setFontSize(7.5);
  doc.setFont('helvetica', 'bold');
  doc.text('Réf.', M + 2, y + 5);
  doc.text('Désignation', M + 20, y + 5);
  doc.text('Qté', M + 115, y + 5, { align:'right' });
  doc.text('Unité', M + 130, y + 5, { align:'right' });
  if (showPU)    doc.text('PU HT', M + 152, y + 5, { align:'right' });
  if (showTotal && showPU) doc.text('Total HT', W - M - 2, y + 5, { align:'right' });
  y += 7;

  // Lignes tableau
  doc.setFont('helvetica', 'normal');
  let rowIndex = 0;
  lignesPDF.forEach(function(l, i) {
    const nomLines = doc.splitTextToSize(l.nom || '', 90);
    const nbLignes = Math.min(nomLines.length, 5);
    const rowH = Math.max(7, nbLignes * 4.5 + 2);
    if (y + rowH > SAFE_PDF) {
      doc.addPage();
      y = 14;
      doc.setFillColor(...DARK);
      doc.rect(M, y, W - 2*M, 7, 'F');
      doc.setTextColor(...WHITE);
      doc.setFontSize(7.5);
      doc.setFont('helvetica', 'bold');
      doc.text('Réf.', M + 2, y + 5);
      doc.text('Désignation', M + 20, y + 5);
      doc.text('Qté', M + 115, y + 5, { align:'right' });
      doc.text('Unité', M + 130, y + 5, { align:'right' });
      if (showPU)    doc.text('PU HT', M + 152, y + 5, { align:'right' });
      if (showTotal && showPU) doc.text('Total HT', W - M - 2, y + 5, { align:'right' });
      y += 7;
      rowIndex = 0;
      doc.setFont('helvetica', 'normal');
    }
    if (rowIndex % 2 === 0) {
      doc.setFillColor(248, 248, 248);
      doc.rect(M, y, W - 2*M, rowH, 'F');
    }
    rowIndex++;
    doc.setDrawColor(230, 230, 230);
    doc.rect(M, y, W - 2*M, rowH, 'S');
    doc.setTextColor(...DARK);
    doc.setFontSize(8);
    doc.text((l.ref||'').slice(0,12), M + 2, y + 5);
    const nomLinesLimited = nomLines.slice(0, 5);
    doc.text(nomLinesLimited, M + 20, y + 5);
    const midY = y + rowH / 2 + 2;
    doc.text(String(l.qty), M + 115, midY, { align:'right' });
    doc.text(l.unite||'U', M + 130, midY, { align:'right' });
    if (showPU) {
      doc.text((parseFloat(l.pu)||0).toFixed(2) + ' €', M + 152, midY, { align:'right' });
      doc.setFont('helvetica', 'bold');
      doc.text(((l.qty||0) * (parseFloat(l.pu)||0)).toFixed(2) + ' €', W - M - 2, midY, { align:'right' });
      doc.setFont('helvetica', 'normal');
    }
    y += rowH;
  });

  // Rang total HT en pied de tableau de l'intervention courante
  if (showTotal && lignesPDF.length > 0) {
    if (y + 8 > SAFE_PDF) { doc.addPage(); y = 14; }
    doc.setFillColor(45, 45, 45);
    doc.rect(M, y, W - 2*M, 8, 'F');
    doc.setTextColor(...WHITE);
    doc.setFontSize(8);
    doc.setFont('helvetica', 'bold');
    doc.text('TOTAL HT', M + 2, y + 5.5);
    doc.text(ht.toFixed(2) + ' €', W - M - 2, y + 5.5, { align:'right' });
    y += 8;
  }

  y += 4;

  // ── INTERVENTIONS PRÉCÉDENTES (chaîne complète) ──────────
  for (var _ci = 0; _ci < _chainePrev.length; _ci++) {
  var bonLieData = _chainePrev[_ci];
  if (bonLieData && bonLieData.lignes && bonLieData.lignes.length) {
    const bonLieHT  = bonLieData.lignes.reduce(function(s,l){ return s+(parseFloat(l.qty)||0)*(parseFloat(l.pu)||0); }, 0);
    const bonLieTTC = bonLieData.totalTTC || bonLieHT * (1 + (bonLieData.tvaRate||20)/100);

    if (y + MIN_SECTION > SAFE_PDF) { doc.addPage(); y = 14; }
    doc.setFontSize(7);
    doc.setFont('helvetica', 'bold');
    doc.setTextColor(...ORANGE);
    var _labelPrev = _chainePrev.length > 1
      ? 'INTERV. PRÉCÉDENTE ' + (_ci + 1) + '/' + _chainePrev.length + ' — ' + (bonLieData.numero||'') + ' du ' + (bonLieData.date||'')
      : 'INTERVENTION PRÉCÉDENTE — ' + (bonLieData.numero||'') + ' du ' + (bonLieData.date||'');
    doc.text(_labelPrev, M, y + 4);
    y += 7;

    // Heures intervention précédente
    if (bonLieData.heureDebut) {
      doc.setFontSize(8);
      doc.setFont('helvetica', 'italic');
      doc.setTextColor(...GREY);
      doc.text('Horaires : ' + bonLieData.heureDebut + (bonLieData.heureFin ? ' – ' + bonLieData.heureFin : '') + (bonLieData.duree ? '  (' + bonLieData.duree + ')' : ''), M, y + 4);
      y += 6;
    }

    // En-tête tableau précédent
    doc.setFillColor(60, 60, 60);
    doc.rect(M, y, W - 2*M, 7, 'F');
    doc.setTextColor(...WHITE);
    doc.setFontSize(7.5);
    doc.setFont('helvetica', 'bold');
    doc.text('Réf.', M + 2, y + 5);
    doc.text('Désignation', M + 20, y + 5);
    doc.text('Qté', M + 115, y + 5, { align:'right' });
    doc.text('Unité', M + 130, y + 5, { align:'right' });
    if (showPU) doc.text('PU HT', M + 152, y + 5, { align:'right' });
    if (showTotal && showPU) doc.text('Total HT', W - M - 2, y + 5, { align:'right' });
    y += 7;

    doc.setFont('helvetica', 'normal');
    bonLieData.lignes.forEach(function(l, ri) {
      const nomLines2 = doc.splitTextToSize(l.nom||'', 92);
      const rowH2 = Math.max(8, nomLines2.length * 4 + 3);
      if (y + rowH2 > SAFE_PDF) { doc.addPage(); y = 14; }
      if (ri % 2 === 0) { doc.setFillColor(248,248,248); doc.rect(M, y, W-2*M, rowH2, 'F'); }
      doc.setDrawColor(230,230,230); doc.rect(M, y, W-2*M, rowH2, 'S');
      doc.setTextColor(...DARK); doc.setFontSize(8);
      doc.text((l.ref||'').slice(0,12), M+2, y+5);
      doc.text(nomLines2.slice(0,5), M+20, y+5);
      const midY2 = y + rowH2/2 + 2;
      doc.text(String(l.qty), M+115, midY2, { align:'right' });
      doc.text(l.unite||'U', M+130, midY2, { align:'right' });
      if (showPU) {
        doc.text((parseFloat(l.pu)||0).toFixed(2)+' €', M+152, midY2, { align:'right' });
        doc.setFont('helvetica','bold');
        doc.text(((l.qty||0)*(parseFloat(l.pu)||0)).toFixed(2)+' €', W-M-2, midY2, { align:'right' });
        doc.setFont('helvetica','normal');
      }
      y += rowH2;
    });

    // Rang total HT en pied de tableau de l'intervention précédente
    if (showTotal) {
      if (y + 8 > SAFE_PDF) { doc.addPage(); y = 14; }
      doc.setFillColor(45, 45, 45);
      doc.rect(M, y, W - 2*M, 8, 'F');
      doc.setTextColor(...WHITE);
      doc.setFontSize(8);
      doc.setFont('helvetica', 'bold');
      doc.text('TOTAL HT', M + 2, y + 5.5);
      doc.text(bonLieHT.toFixed(2) + ' €', W - M - 2, y + 5.5, { align:'right' });
      y += 8;
    }

    // Rapport intervention précédente
    if (bonLieData.rapport) {
      y += 3;
      doc.setFontSize(7); doc.setFont('helvetica','bold'); doc.setTextColor(...ORANGE);
      doc.text('RAPPORT D\'INTERVENTION PRÉCÉDENTE', M, y + 4);
      y += 7;
      doc.setFontSize(8.5); doc.setFont('helvetica','normal'); doc.setTextColor(...DARK);
      const rapLinesPrev = doc.splitTextToSize(bonLieData.rapport, W - 2*M);
      rapLinesPrev.forEach(function(line) {
        if (y + 5 > SAFE_PDF) { doc.addPage(); y = 14; doc.setFontSize(8.5); doc.setFont('helvetica','normal'); doc.setTextColor(...DARK); }
        doc.text(line, M, y); y += 5;
      });
      y += 2;
    }

    // Photos intervention précédente
    const photosPrev = bonLieData.photos || [];
    if (photosPrev.length > 0) {
      if (y > 200) { doc.addPage(); y = 20; }
      doc.setFontSize(7); doc.setFont('helvetica','bold'); doc.setTextColor(...ORANGE);
      doc.text('PHOTOS — INTERVENTION PRÉCÉDENTE', M, y + 4);
      y += 8;
      const photoWp = 50; const photoMp = 6;
      let pxp = M;
      for (var pip = 0; pip < photosPrev.length; pip++) {
        var photop = photosPrev[pip];
        var photoSrcp = photop.dataUrl || null;
        if (!photoSrcp && photop.url) {
          await new Promise(function(resolve) {
            var xhrp = new Image(); xhrp.crossOrigin = 'anonymous';
            xhrp.onload = function() {
              var cvp = document.createElement('canvas');
              cvp.width = xhrp.naturalWidth; cvp.height = xhrp.naturalHeight;
              cvp.getContext('2d').drawImage(xhrp, 0, 0);
              photoSrcp = cvp.toDataURL('image/jpeg', 0.9); resolve();
            };
            xhrp.onerror = function() { photoSrcp = null; resolve(); };
            xhrp.src = photop.url;
          });
        }
        if (!photoSrcp) continue;
        try {
          var tmpIp = new Image(); tmpIp.src = photoSrcp;
          var ratiop = tmpIp.naturalHeight > 0 ? tmpIp.naturalWidth / tmpIp.naturalHeight : 1;
          var photoHp = Math.round(photoWp / ratiop);
          if (photoHp > 60) photoHp = 60;
          if (pxp + photoWp > W - M) { pxp = M; y += photoHp + photoMp + 8; }
          if (y + photoHp > doc.internal.pageSize.getHeight() - 20) { doc.addPage(); y = 20; pxp = M; }
          doc.addImage(photoSrcp, 'JPEG', pxp, y, photoWp, photoHp);
          doc.setDrawColor(200,200,200); doc.rect(pxp, y, photoWp, photoHp, 'S');
          if (photop.url) doc.link(pxp, y, photoWp, photoHp, { url: photop.url });
          if (photop.caption) {
            doc.setFontSize(7); doc.setFont('helvetica','italic'); doc.setTextColor(...GREY);
            doc.text(photop.caption.slice(0,25), pxp + photoWp/2, y + photoHp + 4, { align:'center' });
          }
          pxp += photoWp + photoMp;
        } catch(e2) {}
      }
      y += 70;
    }

    y += 4;
    doc.setDrawColor(200,200,200);
    doc.line(M, y, W-M, y);
    y += 6;
  }
  } // fin boucle chaîne interventions précédentes

  y += 4;

  // ── TOTAUX ───────────────────────────────────────────────
  if (showTotal) {
    const totW = 80;
    const totX = W - M - totW;

    // Totaux cumulés si bon lié — somme toute la chaîne _chainePrev
    const bonLieHTVal = _chainePrev.reduce(function(acc, b) {
      return acc + (b.lignes||[]).reduce(function(s,l){ return s+(parseFloat(l.qty)||0)*(parseFloat(l.pu)||0); },0);
    }, 0);
    const htCumul  = ht + bonLieHTVal;
    const tvaCumul = htCumul * tvaRate / 100;
    const ttcCumul = htCumul + tvaCumul;

    // boxH dynamique : 1 ligne par interv. précédente + 1 courante + 1 TVA
    const _nbLigTot = _chainePrev.length > 0 ? _chainePrev.length + 2 : 2;
    const boxH = _nbLigTot * 7 + 1;
    if (y + boxH + 14 > SAFE_PDF) { doc.addPage(); y = 14; }
    doc.setFillColor(250, 250, 250);
    doc.rect(totX, y, totW, boxH, 'F');
    doc.setDrawColor(220, 220, 220);
    doc.rect(totX, y, totW, boxH, 'S');

    doc.setFontSize(8.5);
    doc.setFont('helvetica', 'normal');
    if (_chainePrev.length > 0) {
      var _yOff = 7;
      for (var _ti = 0; _ti < _chainePrev.length; _ti++) {
        var _bp = _chainePrev[_ti];
        var _bpHT = (_bp.lignes||[]).reduce(function(s,l){ return s+(parseFloat(l.qty)||0)*(parseFloat(l.pu)||0); },0);
        doc.setTextColor(...GREY);
        doc.text((_bp.numero || ('Interv. ' + (_ti+1))) + ' HT', totX + 4, y + _yOff);
        doc.setTextColor(...DARK);
        doc.text(_bpHT.toFixed(2) + ' €', W - M - 2, y + _yOff, { align:'right' });
        _yOff += 7;
      }
      doc.setTextColor(...GREY);
      doc.text('Interv. courante HT', totX + 4, y + _yOff);
      doc.setTextColor(...DARK);
      doc.text(ht.toFixed(2) + ' €', W - M - 2, y + _yOff, { align:'right' });
      _yOff += 7;
      doc.setTextColor(...GREY);
      doc.text('TVA ' + tvaRate + '%', totX + 4, y + _yOff);
      doc.setTextColor(...DARK);
      doc.text(tvaCumul.toFixed(2) + ' €', W - M - 2, y + _yOff, { align:'right' });
    } else {
      doc.setTextColor(...GREY);
      doc.text('Total HT', totX + 4, y + 7);
      doc.text('TVA ' + tvaRate + '%', totX + 4, y + 14);
      doc.setTextColor(...DARK);
      doc.text(ht.toFixed(2) + ' €', W - M - 2, y + 7, { align:'right' });
      doc.text(tva.toFixed(2) + ' €', W - M - 2, y + 14, { align:'right' });
    }

    y += boxH;

    // Total TTC — fond orange/doré
    doc.setFillColor(...ORANGE);
    doc.rect(totX, y, totW, 10, 'F');
    doc.setTextColor(...WHITE);
    doc.setFontSize(10);
    doc.setFont('helvetica', 'bold');
    doc.text('TOTAL TTC', totX + 4, y + 7);
    doc.text((_chainePrev.length > 0 ? ttcCumul : ttc).toFixed(2) + ' €', W - M - 2, y + 7, { align:'right' });

    y += 14;
  } else {
    // Mode sans prix — mention simple
    doc.setFontSize(8);
    doc.setFont('helvetica', 'italic');
    doc.setTextColor(...GREY);
    doc.text('Les prix feront l\'objet d\'un devis séparé.', M, y + 4);
    y += 12;
  }

  // Conditions devis
  if (!isBon && conditions) {
    doc.setFontSize(8);
    doc.setFont('helvetica', 'italic');
    doc.setTextColor(...GREY);
    doc.text('Conditions : ' + conditions, M, y);
    y += 8;
  }

  // ── SIGNATURES ───────────────────────────────────────────
  // Vérifier si on a de la place (sinon nouvelle page)
  if (y > 220) { doc.addPage(); y = 20; }

  y += 4;
  doc.setFontSize(7);
  doc.setFont('helvetica', 'bold');
  doc.setTextColor(...ORANGE);
  doc.text('SIGNATURES', M, y);
  y += 5;

  const sigW = (W - 2*M - 10) / 2;

  // Cadre signature client
  doc.setDrawColor(200, 200, 200);
  doc.setFillColor(252, 252, 252);
  doc.rect(M, y, sigW, 35, 'FD');
  doc.setFontSize(7);
  doc.setFont('helvetica', 'normal');
  doc.setTextColor(...GREY);
  doc.text('Signature du client', M + sigW/2, y + 5, { align:'center' });

  // Signature client — priorité aux données sauvegardées (depuis docs), sinon canvas
  try {
    const savedSigClient = d && d.sigClientData;
    if (savedSigClient && savedSigClient.length > 100) {
      doc.addImage(savedSigClient, 'PNG', M + 2, y + 7, sigW - 4, 24);
    } else {
      const canvasClient = document.getElementById('sig-client');
      if (canvasClient && !sigIsEmpty('sig-client')) {
        doc.addImage(canvasClient.toDataURL('image/png'), 'PNG', M + 2, y + 7, sigW - 4, 24);
      }
    }
  } catch(e) {}

  doc.setFontSize(7);
  doc.setTextColor(...DARK);
  doc.text(client, M + sigW/2, y + 33, { align:'center' });

  // Cadre signature intervenant
  const sig2X = M + sigW + 10;
  doc.setDrawColor(200, 200, 200);
  doc.setFillColor(252, 252, 252);
  doc.rect(sig2X, y, sigW, 35, 'FD');
  doc.setFontSize(7);
  doc.setFont('helvetica', 'normal');
  doc.setTextColor(...GREY);
  doc.text('Signature de l\'intervenant', sig2X + sigW/2, y + 5, { align:'center' });

  // Signature intervenant — priorité aux données sauvegardées
  try {
    const savedSigInt = d && d.sigIntervenantData;
    if (savedSigInt && savedSigInt.length > 100) {
      doc.addImage(savedSigInt, 'PNG', sig2X + 2, y + 7, sigW - 4, 24);
    } else {
      const canvasInt = document.getElementById('sig-intervenant');
      if (canvasInt && !sigIsEmpty('sig-intervenant')) {
        doc.addImage(canvasInt.toDataURL('image/png'), 'PNG', sig2X + 2, y + 7, sigW - 4, 24);
      }
    }
  } catch(e) {}

  doc.setFontSize(7);
  doc.setTextColor(...DARK);
  doc.text('Mathieu LARUICCI', sig2X + sigW/2, y + 33, { align:'center' });

  y += 40;

  // ── PHOTOS ───────────────────────────────────────────────
  if (photos && photos.length > 0) {
    if (y + MIN_SECTION > SAFE_PDF) { doc.addPage(); y = 14; }
    doc.setFontSize(7);
    doc.setFont('helvetica', 'bold');
    doc.setTextColor(...ORANGE);
    doc.text('PHOTOS', M, y + 4);
    y += 8;

    const photoW = 50; // 5cm en mm
    const photoMargin = 6;
    let px = M;

    for (var pi = 0; pi < photos.length; pi++) {
      var photo = photos[pi];
      var photoSrc = photo.dataUrl || photo.url || null;
      if (!photoSrc) continue;
      try {
        // Charger depuis URL si nécessaire (photo uploadée sur Storage)
        if (!photo.dataUrl && photo.url) {
          await new Promise(function(resolve) {
            var xhr = new Image();
            xhr.crossOrigin = 'anonymous';
            xhr.onload = function() {
              var cv = document.createElement('canvas');
              cv.width = xhr.naturalWidth; cv.height = xhr.naturalHeight;
              cv.getContext('2d').drawImage(xhr, 0, 0);
              photoSrc = cv.toDataURL('image/jpeg', 0.9);
              resolve();
            };
            xhr.onerror = function() { photoSrc = null; resolve(); };
            xhr.src = photo.url;
          });
          if (!photoSrc) continue;
        }
        // Calculer hauteur proportionnelle
        var tmpImg = new Image();
        tmpImg.src = photoSrc;
        var ratio = tmpImg.naturalHeight > 0 ? tmpImg.naturalWidth / tmpImg.naturalHeight : 1;
        var photoH = Math.round(photoW / ratio);
        if (photoH > 60) photoH = 60; // max 6cm hauteur

        // Nouvelle ligne si pas assez de place
        if (px + photoW > W - M) {
          px = M;
          y += photoH + photoMargin + 8;
        }
        if (y + photoH > SAFE_PDF) {
          doc.addPage(); y = 14; px = M;
        }

        doc.addImage(photoSrc, 'JPEG', px, y, photoW, photoH);
        doc.setDrawColor(200, 200, 200);
        doc.rect(px, y, photoW, photoH, 'S');
        if (photo.url) doc.link(px, y, photoW, photoH, { url: photo.url });

        // Légende
        if (photo.caption) {
          doc.setFontSize(7);
          doc.setFont('helvetica', 'italic');
          doc.setTextColor(...GREY);
          doc.text(photo.caption.slice(0, 25), px + photoW/2, y + photoH + 4, { align:'center' });
        }

        px += photoW + photoMargin;
      } catch(imgErr) {}
    }
    y += 70;
  }

  // ── PIED DE PAGE ─────────────────────────────────────────
  const pageH = doc.internal.pageSize.getHeight();
  // Ligne orange séparatrice
  doc.setDrawColor(...ORANGE);
  doc.setLineWidth(0.6);
  doc.line(M, pageH - 14, W - M, pageH - 14);
  doc.setLineWidth(0.2);
  doc.setFontSize(7);
  doc.setFont('helvetica', 'normal');
  doc.setTextColor(...DARK);
  doc.text(
    'Harmonie Électricité · 225 Chemin des Bochets, 73170 Yenne · 06 31 13 47 01 · contact@harmonie-electricite.com · www.harmonie-electricite.com',
    W/2, pageH - 8, { align:'center' }
  );
  doc.setTextColor(...GREY);
  doc.setFontSize(6);
  doc.text('Alarme · Vidéosurveillance · Contrôle d\'accès · Automatisme · Borne de recharge IRVE', W/2, pageH - 3.5, { align:'center' });

  return doc.output('blob');
  // ── TÉLÉCHARGEMENT ou retour base64 ──────────────────────
  const filename = (isBon ? 'BI' : 'Devis') + '_' + docNum + '_' + client.replace(/\s+/g,'_') + '.pdf';

  if (window._pdfReturnBase64) {
    // Retourner en base64 pur pour envoi Gmail
    return doc.output('datauristring').split(',')[1];
  }

  const pdfBlob = doc.output('blob');
  const blobUrl = URL.createObjectURL(pdfBlob);

  // Mode "voir/télécharger" depuis l'espace client : ouvrir le PDF dans le
  // lecteur du navigateur (qui propose lui-même le téléchargement).
  if (window._pdfOpenInViewer) {
    window.location.replace(blobUrl);
    return;
  }

  // Sur iOS/Safari, doc.save() ouvre dans le navigateur au lieu de télécharger
  // On utilise un blob URL + lien de téléchargement forcé
  const link = document.createElement('a');
  link.href = blobUrl;
  link.download = filename;
  link.style.display = 'none';
  document.body.appendChild(link);
  link.click();
  setTimeout(function() {
    document.body.removeChild(link);
    URL.revokeObjectURL(blobUrl);
  }, 1000);
  toast('PDF téléchargé : ' + filename);
}

  async function generer(payload, mode) {
    PDF_MODE = mode || payload.pdfMode || 'detail';
    DOC_NUM = payload.numero || payload.id || '';
    return _genererPDFInner(Object.assign({ type: 'bon' }, payload));
  }
  const nomFichier = p => ('BI_' + (p.numero || p.id || '') + '_' + (p.client || '').replace(/\s+/g, '_') + '.pdf').replace(/[\\/:*?"<>|]+/g, ' ');
  return { generer, nomFichier };
})();
