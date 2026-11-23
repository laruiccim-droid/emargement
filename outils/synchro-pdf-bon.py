# Recopie le générateur de PDF des bons d'intervention de l'app métier (bon.html) dans bon-pdf.js,
# pour que l'espace syndic et le portail admin produisent exactement le même bon que l'app.
# À relancer après toute modification de la mise en page du bon dans l'app métier :
#   python outils/synchro-pdf-bon.py [chemin de bon.html]
import os, re, sys

ici = os.path.dirname(os.path.abspath(__file__))
source = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.expanduser('~'), 'Downloads', 'Site-web', 'app-metier', 'bon.html')
s = open(source, encoding='utf-8').read()

def bloc(debut, fin_regex):
    i = s.index(debut)
    m = re.compile(fin_regex, re.M).search(s, i)
    return s[i:m.end()]

logo = re.search(r"^const LOGO_HE_B64 = '[^']*';", s, re.M).group(0)
picto = re.search(r"^const PICTO_HE_B64 = '[^']*';", s, re.M).group(0)
inner = bloc('async function _genererPDFInner(docData) {', r'^}\s*$')

# Le PDF est rendu (blob) au lieu d'être téléchargé ou envoyé.
marque = '  // ── TÉLÉCHARGEMENT ou retour base64'
assert marque in inner, 'fin du générateur introuvable'
inner = inner.replace(marque, "  return doc.output('blob');\n" + marque, 1)

js = """// =====================================================================================
// bon-pdf.js — PDF du bon d'intervention, IDENTIQUE à celui de l'app métier.
// Fichier généré par outils/synchro-pdf-bon.py à partir de app-metier/bon.html : ne pas modifier à la main.
// Usage : const blob = await BonPDF.generer(payloadDuBon, 'detail' | 'semi' | 'sansprix');
// La chaîne des bons précédents (bonLieData) doit déjà être complète (fournie par le serveur).
// =====================================================================================
window.BonPDF = (function () {
  'use strict';
  %s
  %s
  // Environnement minimal attendu par le générateur de l'app (pas de formulaire ici).
  let PDF_MODE = 'detail', DOC_TYPE = 'bon', DOC_NUM = '';
  const LIGNES = [], PHOTOS = [];
  function toast() {}
  function sigIsEmpty() { return true; }
  async function _completerChaineBonLie() {}

  %s

  async function generer(payload, mode) {
    PDF_MODE = mode || payload.pdfMode || 'detail';
    DOC_NUM = payload.numero || payload.id || '';
    return _genererPDFInner(Object.assign({ type: 'bon' }, payload));
  }
  const nomFichier = p => ('BI_' + (p.numero || p.id || '') + '_' + (p.client || '').replace(/\\s+/g, '_') + '.pdf').replace(/[\\\\/:*?"<>|]+/g, ' ');
  return { generer, nomFichier };
})();
""" % (logo, picto, inner)

open(os.path.join(ici, '..', 'bon-pdf.js'), 'w', encoding='utf-8').write(js)
print('bon-pdf.js régénéré depuis', source, '(', len(js), 'caractères )')
