// Robot BatiConnect — Harmonie Électricité
// Lancé par le favori « Robot BatiConnect » sur www.baticonnect.com (session de l'utilisateur déjà ouverte).
// Il reprend un chantier de l'app d'émargement et suit la procédure habituelle :
//   1. Ajouter un site (nom de la copropriété, résidence d'habitation, adresse, CP, ville, département)
//   2. Ajouter un bâtiment (propriétaires du listing + « Stock syndic » + « Société de nettoyage »)
//   3. Nommer chaque appartement au nom du propriétaire
//   4. Ajouter les badges (Titre(s) → Ajouter des titres → numéro du premier badge → Valider)
// Chaque étape vérifie ce qui existe déjà : relancer le robot reprend là où il s'est arrêté, sans doublon.
(() => {
  if (!/baticonnect\.com$/.test(location.hostname)) { alert('Ouvrez d’abord www.baticonnect.com (connecté), puis cliquez sur le favori.'); return; }
  if (document.getElementById('he-robot')) { document.getElementById('he-robot').style.display = 'block'; return; }

  const SUPA = 'https://bqzebkobyfktemnwfwbt.supabase.co/rest/v1/emargements', CLE = 'sb_publishable_vh62KxFcG1NuLcnya6WpMg_oFRtY-2v';
  const ENTETES = { apikey: CLE, Authorization: 'Bearer ' + CLE };
  const STOCK = 'Stock syndic', NETTOYAGE = 'Société de nettoyage';
  const pause = ms => new Promise(r => setTimeout(r, ms));
  const visible = e => !!e && e.offsetParent !== null;
  const attendre = async (f, ms = 15000, quoi = 'la page') => {
    const t = Date.now();
    while (Date.now() - t < ms) { const v = f(); if (v) return v; await pause(200); }
    throw new Error('délai dépassé en attendant ' + quoi);
  };
  const norm = s => (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\s+/g, ' ').trim();
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  /* ---------- Plan à partir du chantier ---------- */
  function plan(ch) {
    const m = (ch.adresse || '').match(/^(.*?)[,\s]*(\d{5})\s+(.+)$/);
    const adresse = m ? m[1].trim() : (ch.adresse || '').trim(), cp = m ? m[2] : '', ville = m ? m[3].trim() : '';
    const reels = ch.logements.filter(l => l.porte || l.etage);
    const horsLogement = ch.logements.filter(l => !(l.porte || l.etage));
    const nomProp = l => (l.nomListing || l.proprietaire || l.occupant || l.nomAffiche || '').trim();
    const badges = l => (l.badges || []).map(b => String(b).trim()).filter(Boolean);
    const apparts = reels.map(l => ({ nom: nomProp(l), badges: badges(l) })).filter(a => a.nom)
      .sort((a, b) => a.nom.localeCompare(b.nom, 'fr'));
    // Badges des fiches sans logement : vers « Stock syndic » ou « Société de nettoyage » selon leur nom.
    const stock = [], nettoyage = [];
    for (const l of horsLogement) (/nettoy|menage|ménage|entretien/i.test(nomProp(l)) ? nettoyage : stock).push(...badges(l));
    return {
      site: (ch.copropriete || ch.residence || '').trim(), adresse, cp, ville,
      departement: /^\d{5}$/.test(cp) ? cp.slice(0, 2) : '73',
      batiment: (ch.batimentVigik || ch.residence || '').trim(),
      // 000 = Société de nettoyage, puis les propriétaires par ordre alphabétique, puis le stock du syndic.
      apparts: [{ nom: NETTOYAGE, badges: nettoyage }, ...apparts, { nom: STOCK, badges: stock }],
    };
  }

  /* ---------- Fenêtres de BatiConnect ---------- */
  const dialogue = test => [...document.querySelectorAll('.ui-dialog')].find(d => visible(d) && test(d));
  const bouton = (d, texte) => [...d.querySelectorAll('.ui-dialog-buttonpane button')].find(b => b.innerText.trim() === texte);
  const saisir = (el, v) => { el.focus(); el.value = v; ['input', 'change', 'keyup', 'blur'].forEach(t => el.dispatchEvent(new Event(t, { bubbles: true }))); };
  const choisir = (sel, test) => { const o = [...sel.options].find(test); if (!o) return false; sel.value = o.value; sel.dispatchEvent(new Event('change', { bubbles: true })); return true; };
  const fermerDialogues = async () => {
    for (const d of [...document.querySelectorAll('.ui-dialog')].filter(visible)) {
      const b = bouton(d, 'Fermer') || bouton(d, 'Annuler'); if (b) { b.click(); await pause(400); }
    }
  };
  const alerteBatiConnect = () => {
    const d = [...document.querySelectorAll('.ui-dialog')].find(d => visible(d) && !d.querySelector('input:not([type=hidden]), select'));
    return d ? d.innerText.replace(/\s+/g, ' ').trim().slice(0, 200) : '';
  };

  async function allerAuxSites() {
    if (typeof loadSocietyInformation !== 'function') throw new Error('ouvrez la page « Mes sites » de BatiConnect avant de lancer le robot');
    await fermerDialogues();
    loadSocietyInformation(1); // liste « Mes sites », rechargée sans quitter la page
    await attendre(() => [...document.querySelectorAll('a[href*="loadSiteInformation"]')].some(visible), 15000, 'la liste des sites');
    await pause(500);
  }
  const lienSite = nom => [...document.querySelectorAll('a[href*="loadSiteInformation"]')].find(a => visible(a) && norm(a.innerText) === norm(nom));
  const idDe = (lien, fn) => +((lien.getAttribute('href') || '').match(new RegExp(fn + '\\((\\d+)'))?.[1] || 0);

  async function etapeSite(p, log) {
    await allerAuxSites();
    let lien = lienSite(p.site);
    if (lien) { log(`Site « ${p.site} » déjà présent : repris tel quel.`); return idDe(lien, 'loadSiteInformation'); }
    loadSiteForm(0);
    const d = await attendre(() => dialogue(d => d.querySelector('#s_name')), 15000, 'le formulaire du site');
    saisir(d.querySelector('#s_name'), p.site);
    const residence = d.querySelector('input[name=s_manage_type]'); if (residence && !residence.checked) residence.click(); // « Résidence d'habitation »
    // Case vide refusée par BatiConnect : un espace la remplace quand l'information manque.
    saisir(d.querySelector('#s_address'), p.adresse || ' ');
    saisir(d.querySelector('#s_postcode'), p.cp || ' ');
    saisir(d.querySelector('#s_city'), p.ville || ' ');
    if (!choisir(d.querySelector('#s_vigik_ga_id'), o => o.text.trim().startsWith(p.departement + ' '))) throw new Error('département ' + p.departement + ' introuvable');
    bouton(d, 'Valider').click();
    await attendre(() => !visible(d) || alerteBatiConnect(), 20000, 'la création du site');
    const alerte = alerteBatiConnect(); if (alerte && visible(d)) throw new Error('BatiConnect refuse le site : ' + alerte);
    await allerAuxSites();
    lien = await attendre(() => lienSite(p.site), 15000, 'le nouveau site dans la liste');
    log(`Site « ${p.site} » créé.`);
    return idDe(lien, 'loadSiteInformation');
  }

  async function ouvrirSite(id) {
    await fermerDialogues();
    loadSiteInformation(id);
    await attendre(() => [...document.querySelectorAll('a')].find(a => visible(a) && /Ajouter un bâtiment/.test(a.innerText)), 15000, 'la page du site');
    await pause(500);
  }
  const lienBatiment = nom => [...document.querySelectorAll('a[href*="loadBuildingInformation"]')].find(a => visible(a) && norm(a.innerText) === norm(nom));

  async function etapeBatiment(siteId, p, log) {
    await ouvrirSite(siteId);
    let lien = lienBatiment(p.batiment);
    if (lien) { log(`Bâtiment « ${p.batiment} » déjà présent : repris tel quel.`); return idDe(lien, 'loadBuildingInformation'); }
    [...document.querySelectorAll('a')].find(a => visible(a) && /Ajouter un bâtiment/.test(a.innerText)).click();
    const d = await attendre(() => dialogue(d => d.querySelector('#b_name')), 15000, 'le formulaire du bâtiment');
    saisir(d.querySelector('#b_name'), p.batiment);
    // Code bâtiment, préfixe et premier numéro d'appartement : laissés tels que BatiConnect les propose.
    if (!choisir(d.querySelector('#b_ug_number'), o => +o.value === p.apparts.length || o.text.trim() === String(p.apparts.length)))
      throw new Error(`BatiConnect ne propose pas ${p.apparts.length} appartements dans un bâtiment`);
    bouton(d, 'Valider').click();
    await attendre(() => !visible(d) || alerteBatiConnect(), 20000, 'la création du bâtiment');
    const alerte = alerteBatiConnect(); if (alerte && visible(d)) throw new Error('BatiConnect refuse le bâtiment : ' + alerte);
    await ouvrirSite(siteId);
    lien = await attendre(() => lienBatiment(p.batiment), 15000, 'le nouveau bâtiment');
    log(`Bâtiment « ${p.batiment} » créé avec ${p.apparts.length} appartements.`);
    return idDe(lien, 'loadBuildingInformation');
  }

  // Appartements du bâtiment, dans l'ordre des numéros : [{ numero, nom, ouvrir }]
  async function listeApparts(batId) {
    await fermerDialogues();
    loadBuildingInformation(batId);
    await attendre(() => [...document.querySelectorAll('a[href*="loadUserGroupInformation"]')].some(visible), 15000, 'la liste des appartements');
    const sel = [...document.querySelectorAll('select')].find(s => visible(s) && [...s.options].some(o => /^Tous/.test(o.text)));
    if (sel && sel.value !== [...sel.options].slice(-1)[0].value) { choisir(sel, o => /^Tous/.test(o.text)); await pause(1500); }
    const lignes = [...document.querySelectorAll('tr')].filter(tr => visible(tr) && tr.querySelector('a[href*="loadUserGroupInformation"]'));
    return lignes.map(tr => {
      const cellules = [...tr.cells].map(c => c.innerText.trim());
      const i = cellules.findIndex(c => /^\d{3,4}$/.test(c));
      return { numero: cellules[i], nom: cellules[i + 1] || '', lien: tr.querySelector('a[href*="loadUserGroupInformation"]') };
    }).filter(a => a.numero).sort((a, b) => +a.numero - +b.numero);
  }

  async function ouvrirAppart(a) {
    a.lien.click();
    return attendre(() => dialogue(d => d.querySelector('#ug_name')), 15000, 'la fiche de l’appartement');
  }

  // Un appartement déjà nommé comme prévu est repris ; les autres noms vont, dans l'ordre, aux appartements
  // encore au nom par défaut (« Appt.000 »…). Un appartement renommé à la main n'est jamais écrasé.
  const parDefaut = nom => /^appt\.?\s*\d*$/i.test(nom.trim()) || !nom.trim();
  async function etapeNoms(batId, p, log) {
    let n = 0;
    for (const voulu of p.apparts) {
      const liste = await listeApparts(batId);
      if (liste.some(a => norm(a.nom) === norm(voulu.nom))) continue;
      const a = liste.find(x => parDefaut(x.nom));
      if (!a) throw new Error(`plus d’appartement libre pour « ${voulu.nom} » (ajoutez un appartement au bâtiment ou renommez-en un à ce nom)`);
      const d = await ouvrirAppart(a);
      saisir(d.querySelector('#ug_name'), voulu.nom);
      bouton(d, 'Valider').click();
      await attendre(() => !visible(d) || alerteBatiConnect(), 15000, 'l’enregistrement du nom');
      const alerte = alerteBatiConnect(); if (alerte && visible(d)) throw new Error(`nom « ${voulu.nom} » refusé : ${alerte}`);
      n++; log(`Appartement ${a.numero} nommé « ${voulu.nom} ».`);
    }
    if (!n) log('Noms des appartements déjà à jour.');
  }

  const titresVisibles = () => [...document.querySelectorAll('.ui-dialog td')].filter(td => visible(td) && /^[0-9A-F]{6,}$/i.test(td.innerText.trim())).map(td => td.innerText.trim().toUpperCase());

  async function etapeBadges(batId, p, log, avance) {
    let total = 0, faits = 0;
    const tous = p.apparts.reduce((t, a) => t + a.badges.length, 0);
    for (const voulu of p.apparts) {
      if (!voulu.badges.length) continue;
      const a = (await listeApparts(batId)).find(x => norm(x.nom) === norm(voulu.nom));
      if (!a) throw new Error(`appartement « ${voulu.nom} » introuvable dans le bâtiment`);
      const d = await ouvrirAppart(a);
      const onglet = [...d.querySelectorAll('a, li, span')].find(e => visible(e) && e.childElementCount === 0 && e.innerText.trim() === 'TITRE(S)');
      onglet.click();
      await attendre(() => [...d.querySelectorAll('a[href*="loadTitleForm"]')].find(visible), 15000, 'l’onglet Titre(s)');
      await pause(500);
      for (const code of voulu.badges) {
        total++;
        if (titresVisibles().includes(code.toUpperCase())) { avance(total, tous); continue; }
        [...d.querySelectorAll('a[href*="loadTitleForm"]')].find(visible).click();
        const champ = await attendre(() => { const c = document.getElementById('t_code'); return visible(c) ? c : null; }, 15000, 'le formulaire du badge');
        await pause(300);
        const nb = document.getElementById('t_nb'); if (nb && nb.value !== '1') saisir(nb, '1');
        saisir(champ, code);
        const fb = dialogue(x => x.querySelector('#t_code'));
        bouton(fb, 'Valider').click();
        await attendre(() => titresVisibles().includes(code.toUpperCase()) || (visible(fb) && alerteBatiConnect()), 15000, `l’enregistrement du badge ${code}`);
        if (!titresVisibles().includes(code.toUpperCase())) throw new Error(`badge ${code} refusé : ${alerteBatiConnect() || 'raison inconnue'}`);
        faits++; avance(total, tous);
      }
      bouton(d, 'Fermer')?.click(); await pause(500);
      log(`${voulu.nom} : ${voulu.badges.length} badge${voulu.badges.length > 1 ? 's' : ''} en place.`);
    }
    log(faits ? `${faits} badge${faits > 1 ? 's' : ''} ajouté${faits > 1 ? 's' : ''}.` : 'Tous les badges étaient déjà en place.');
  }

  /* ---------- Fenêtre du robot ---------- */
  const css = `#he-robot{position:fixed;top:16px;right:16px;z-index:2147483647;width:420px;max-width:calc(100vw - 32px);max-height:calc(100vh - 32px);overflow:auto;
    background:#0A0A0A;color:#E8E5DE;border:1px solid #C9A86A;border-radius:10px;box-shadow:0 12px 40px rgba(0,0,0,.45);font:14px/1.45 'Segoe UI',system-ui,sans-serif;padding:16px}
    #he-robot h2{margin:0 0 2px;font-size:13px;letter-spacing:.14em;text-transform:uppercase;color:#C9A86A;font-weight:600}
    #he-robot .sous{color:#A39C8F;font-size:12px;margin-bottom:12px}
    #he-robot select,#he-robot button{font:inherit}
    #he-robot select{width:100%;padding:8px;border-radius:6px;border:1px solid #4A453C;background:#1C1A16;color:#E8E5DE}
    #he-robot button{border-radius:6px;padding:8px 14px;border:1px solid #C9A86A;background:transparent;color:#E8D5A8;cursor:pointer}
    #he-robot button.or{background:linear-gradient(135deg,#E0C68F,#C9A86A);color:#0A0A0A;font-weight:600;border:0}
    #he-robot button:disabled{opacity:.5;cursor:default}
    #he-robot .actions{display:flex;gap:8px;justify-content:flex-end;margin-top:12px;flex-wrap:wrap}
    #he-robot .plan{margin-top:12px;font-size:13px}
    #he-robot .plan b{color:#fff}
    #he-robot ol{margin:6px 0 0;padding-left:20px;max-height:180px;overflow:auto}
    #he-robot .journal{margin-top:12px;font-size:12.5px;max-height:220px;overflow:auto;border-top:1px solid #3A362F;padding-top:8px}
    #he-robot .journal div{margin:2px 0}#he-robot .erreur{color:#F2A36B}#he-robot .ok{color:#9BD49B}
    #he-robot .barre{height:6px;background:#2A2722;border-radius:3px;margin-top:10px;overflow:hidden}#he-robot .barre i{display:block;height:100%;width:0;background:#C9A86A;transition:width .3s}
    #he-robot .x{position:absolute;top:8px;right:10px;border:0;padding:4px 8px;color:#A39C8F}`;
  const st = document.createElement('style'); st.textContent = css; document.head.append(st);
  const box = document.createElement('div'); box.id = 'he-robot';
  box.innerHTML = `<button class="x" title="Fermer">✕</button><h2>Robot BatiConnect</h2><div class="sous">Harmonie Électricité · création du site, du bâtiment, des appartements et des badges</div>
    <select id="he-chantier"><option>Chargement des chantiers…</option></select>
    <div class="plan" id="he-plan"></div>
    <div class="barre"><i id="he-barre"></i></div>
    <div class="actions"><button id="he-lancer" class="or" disabled>Lancer la création</button></div>
    <div class="journal" id="he-journal"></div>`;
  document.body.append(box);
  const $ = id => box.querySelector('#' + id);
  box.querySelector('.x').onclick = () => { box.style.display = 'none'; };
  const log = (t, cls = '') => { const d = document.createElement('div'); d.className = cls; d.textContent = t; $('he-journal').append(d); $('he-journal').scrollTop = 1e9; };
  const avance = (n, total) => { $('he-barre').style.width = Math.round(100 * n / Math.max(1, total)) + '%'; };

  let chantiers = [], courant = null;
  const afficherPlan = () => {
    const ch = chantiers.find(c => c.id === $('he-chantier').value); courant = ch ? plan(ch.payload) : null;
    if (!courant) { $('he-plan').innerHTML = ''; $('he-lancer').disabled = true; return; }
    const p = courant, nbBadges = p.apparts.reduce((t, a) => t + a.badges.length, 0);
    const manque = [!p.site && 'nom du site', !p.batiment && 'nom du bâtiment'].filter(Boolean);
    $('he-plan').innerHTML = `<div>Site : <b>${esc(p.site)}</b></div>
      <div>Adresse : ${esc([p.adresse, p.cp, p.ville].filter(Boolean).join(' · ') || '(vide : un espace sera saisi)')} — département <b>${esc(p.departement)}</b></div>
      <div>Bâtiment : <b>${esc(p.batiment)}</b> — <b>${p.apparts.length}</b> appartements, <b>${nbBadges}</b> badges</div>
      <ol start="0">${p.apparts.map(a => `<li>${esc(a.nom)}${a.badges.length ? ` <span style="color:#A39C8F">(${a.badges.length} badge${a.badges.length > 1 ? 's' : ''})</span>` : ''}</li>`).join('')}</ol>
      ${manque.length ? `<div class="erreur">Manque : ${manque.join(', ')} (à compléter dans l’app, fenêtre Chantier).</div>` : ''}`;
    $('he-lancer').disabled = !!manque.length;
  };
  $('he-chantier').onchange = afficherPlan;

  (async () => {
    try {
      if (window.__heDonneesTest) chantiers = window.__heDonneesTest;
      else {
        const r = await fetch(`${SUPA}?select=id,payload&id=like.CH_*&order=id.desc&limit=200`, { headers: ENTETES });
        if (!r.ok) throw new Error('chantiers illisibles (' + r.status + ')');
        chantiers = (await r.json()).filter(c => /^noralsy/i.test(c.payload?.centrale || ''));
      }
      if (!chantiers.length) { $('he-chantier').innerHTML = '<option>Aucun chantier avec centrale Noralsy</option>'; log('Dans l’app, fenêtre Chantier → Centrale Vigik, choisissez « Noralsy EasyConnect ».', 'erreur'); return; }
      $('he-chantier').innerHTML = chantiers.map(c => `<option value="${esc(c.id)}">${esc(c.payload.copropriete || c.payload.residence || c.id)}${c.payload.reference ? ' — ' + esc(c.payload.reference) : ''}</option>`).join('');
      const voulu = window.__heChantier && chantiers.find(c => c.id === window.__heChantier);
      if (voulu) $('he-chantier').value = voulu.id;
      afficherPlan();
    } catch (e) { log('Erreur : ' + e.message, 'erreur'); }
  })();

  $('he-lancer').onclick = async () => {
    const p = courant; if (!p) return;
    if (!confirm(`Créer sur BatiConnect :\n• le site « ${p.site} »\n• le bâtiment « ${p.batiment} » (${p.apparts.length} appartements)\n• les badges du chantier ?\n\nCe qui existe déjà est repris sans doublon.`)) return;
    $('he-lancer').disabled = true; $('he-chantier').disabled = true; $('he-journal').innerHTML = ''; avance(0, 1);
    try {
      log('Étape 1/4 · site…'); const siteId = await etapeSite(p, log);
      log('Étape 2/4 · bâtiment…'); const batId = await etapeBatiment(siteId, p, log);
      log('Étape 3/4 · noms des appartements…'); await etapeNoms(batId, p, log);
      log('Étape 4/4 · badges…'); await etapeBadges(batId, p, log, avance);
      await fermerDialogues(); loadBuildingInformation(batId);
      avance(1, 1); log('Terminé : vérifiez le bâtiment affiché.', 'ok');
    } catch (e) {
      log('Arrêt : ' + e.message + '. Corrigez si besoin puis relancez : le robot reprendra là où il s’est arrêté.', 'erreur');
    } finally { $('he-lancer').disabled = false; $('he-chantier').disabled = false; }
  };
})();
