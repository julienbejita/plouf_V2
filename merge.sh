#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "=== Assistant de merge interactif (Bash) — FR ==="

DEFAULT=main
if ! git rev-parse --verify refs/heads/main >/dev/null 2>&1; then
  if git rev-parse --verify refs/heads/master >/dev/null 2>&1; then
    DEFAULT=master
  fi
fi

CURR="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [[ -z "${CURR:-}" ]]; then
  echo "[ERREUR] Impossible de déterminer la branche courante."
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "[INFO] Modifications locales détectées sur ${CURR} — création d'un commit de sauvegarde..."
  git add .
  git commit -m "WIP: sauvegarde avant test/merge"
  if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    echo "[INFO] Mise à jour locale (pull --rebase) puis push du WIP..."
    git pull --rebase
    git push
  fi
fi

# === PHASE 2 : si on est déjà sur une branche temporaire
if [[ "$CURR" == _merge_tmp_* ]]; then
  echo
  echo "[PHASE TEST] Vous êtes sur la branche temporaire : ${CURR}"
  echo "  1) ACCEPTER : fusionner dans '${DEFAULT}' et déployer"
  echo "  2) REFUSER  : revenir sur '${DEFAULT}' et supprimer la branche temporaire"
  echo "  3) ANNULER  : ne rien faire"
  read -rp "Votre choix [1/2/3] : " CHX

  if [[ "$CHX" == "1" ]]; then
    echo "[ACTION] Passage sur '${DEFAULT}' et mise à jour..."
    git checkout "${DEFAULT}"
    git pull origin "${DEFAULT}" --no-rebase

    echo "[ACTION] Fusion --no-ff de '${CURR}' vers '${DEFAULT}'..."
    if ! git merge --no-ff "${CURR}"; then
      echo "[CONFLIT] Conflits détectés, corrigez-les avant de continuer."
      exit 0
    fi

    git push origin "${DEFAULT}"
    echo "[OK] Fusion poussée sur origin/${DEFAULT}."
    git branch -D "${CURR}" || true

    echo "[DEPLOIEMENT] Reconstruction et relance du Docker..."
    docker compose up --build -d

    echo "✅ Terminé."
    exit 0

  elif [[ "$CHX" == "2" ]]; then
    echo "[ACTION] Retour sur '${DEFAULT}'..."
    git checkout "${DEFAULT}"
    for b in $(git for-each-ref --format='%(refname:short)' refs/heads/_merge_tmp_* 2>/dev/null); do
      git branch -D "$b" || true
    done
    echo "✅ Retour sur '${DEFAULT}' et nettoyage effectué."
    exit 0

  else
    echo "❌ Annulé."
    exit 0
  fi
fi

# === PHASE 1 : création branche temporaire de test
if [[ "$CURR" != "$DEFAULT" ]]; then
  echo "[ACTION] Bascule vers '${DEFAULT}'..."
  git checkout "${DEFAULT}"
fi

echo
echo "[PRÉPARATION] Récupération des branches distantes..."
git fetch origin --prune

echo "--- Branches distantes disponibles ---"
git for-each-ref --format='%(refname:short)' refs/remotes/origin | sed 's#^origin/##' | grep -v '^HEAD$' || true
echo "---------------------------------------"

read -rp "Quelle branche distante voulez-vous tester ? : " BRANCH_INPUT
BRANCH="${BRANCH_INPUT#origin/}"

if [[ -z "${BRANCH}" ]]; then
  echo "[ANNULATION] Aucune branche saisie."
  exit 0
fi

if ! git ls-remote --heads origin "${BRANCH}" >/dev/null 2>&1; then
  echo "[ERREUR] La branche 'origin/${BRANCH}' n'existe pas."
  exit 1
fi

TEMP="_merge_tmp_${BRANCH//\//_}"
echo "[ACTION] Création/MàJ de '${TEMP}' depuis 'origin/${BRANCH}'..."
git checkout -B "${TEMP}" "origin/${BRANCH}"

echo "[DEPLOIEMENT] Reconstruction et relance du Docker..."
docker compose up --build -d

echo "✅ Branche de test prête : '${TEMP}'. Vous pouvez maintenant tester."
echo "ℹ️ Relancez ce script pour valider ou refuser les changements."
