#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "=== Assistant de merge interactif (Bash) — FR ==="

# 1) Branche par défaut : main > master
DEFAULT=main
if ! git rev-parse --verify refs/heads/main >/dev/null 2>&1; then
  if git rev-parse --verify refs/heads/master >/dev/null 2>&1; then
    DEFAULT=master
  fi
fi

# 2) Branche courante
CURR="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [[ -z "${CURR:-}" ]]; then
  echo "[ERREUR] Impossible de déterminer la branche courante."
  exit 1
fi

# --- util: déploiement docker ---
deploy() {
  echo "[DÉPLOIEMENT] docker compose up --build -d"
  docker compose up --build -d
}

# --- util: MAJ rapide du main (tes 5 commandes) ---
quick_update_main() {
  echo "[MAJ] Passage sur '${DEFAULT}'..."
  git checkout "${DEFAULT}"

  echo "[MAJ] Ajout de tous les fichiers..."
  if [[ -n "$(git status --porcelain)" ]]; then
    git add .
    read -rp "[MAJ] Message de commit [Mise à jour des fichiers en cours] : " MSG
    MSG="${MSG:-Mise à jour des fichiers en cours}"
    git commit -m "$MSG"
  else
    echo "[MAJ] Aucun changement à committer."
  fi

  echo "[MAJ] Récupération distante (pull --rebase)..."
  git pull origin "${DEFAULT}" --rebase

  echo "[MAJ] Push vers GitHub..."
  git push origin "${DEFAULT}"

  echo "✅ MAJ rapide du main terminée."
}

# 3) Sauvegarde des modifs locales (WIP) + push adapté
if [[ -n "$(git status --porcelain)" ]]; then
  echo "[INFO] Modifications locales détectées sur ${CURR} — création d'un commit de sauvegarde..."
  git add .
  git commit -m "WIP: sauvegarde avant test/merge"

  if [[ "$CURR" == _merge_tmp_* ]]; then
    SRC_BRANCH="$(git config --get "branch.${CURR}.ploufSource" || true)"
    if [[ -n "${SRC_BRANCH:-}" ]]; then
      echo "[INFO] Push du WIP vers la branche distante d'origine: origin/${SRC_BRANCH}"
      git push origin HEAD:"${SRC_BRANCH}"
    else
      if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        echo "[INFO] Push du WIP vers l'upstream de ${CURR}..."
        git pull --rebase
        git push
      else
        echo "[INFO] Aucun mapping ploufSource ni upstream pour ${CURR} — WIP non poussé (local uniquement)."
      fi
    fi
  else
    if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
      echo "[INFO] Mise à jour locale (pull --rebase) puis push du WIP..."
      git pull --rebase
      git push
    else
      echo "[INFO] Pas d'upstream configuré pour ${CURR} — pas de pull/push pour le WIP."
    fi
  fi
fi

# ============================ PHASE 2 : déjà sur branche temporaire ============================
if [[ "$CURR" == _merge_tmp_* ]]; then
  echo
  echo "[PHASE TEST] Vous êtes sur la branche temporaire : ${CURR}"
  echo "  1) ACCEPTER : fusionner dans '${DEFAULT}' (merge --no-ff), pousser et déployer"
  echo "  2) REFUSER  : revenir sur '${DEFAULT}' et supprimer la branche temporaire"
  echo "  3) ANNULER  : ne rien faire"
  echo "  4) MAJ rapide du main (add/commit/pull --rebase/push)"
  read -rp "Votre choix [1/2/3/4] : " CHX

  if [[ "$CHX" == "4" ]]; then
    quick_update_main
    echo "ℹ️ Relancez si besoin pour poursuivre l’acceptation/refus."
    exit 0
  fi

  if [[ "$CHX" == "1" ]]; then
    echo "[ACTION] Passage sur '${DEFAULT}' et mise à jour..."
    git checkout "${DEFAULT}"
    git pull origin "${DEFAULT}" --no-rebase

    echo "[ACTION] Fusion --no-ff de '${CURR}' vers '${DEFAULT}'..."
    if ! git merge --no-ff "${CURR}"; then
      echo
      echo "[CONFLIT] Conflits détectés. Corrigez puis exécutez :"
      echo "  git add . && git commit && git push origin ${DEFAULT}"
      echo "La branche temporaire '${CURR}' est conservée."
      exit 0
    fi

    git push origin "${DEFAULT}"
    echo "[OK] Fusion poussée sur origin/${DEFAULT}."
    echo "[NETTOYAGE] Suppression de la branche temporaire locale '${CURR}'..."
    git branch -D "${CURR}" || true

    # ➕ NOUVEAU : proposer de supprimer aussi la branche distante d'origine
    SRC_BRANCH="$(git config --get "branch.${CURR}.ploufSource" || true)"
    if [[ -n "${SRC_BRANCH:-}" ]]; then
      read -rp "[OPTION] Supprimer aussi la branche distante 'origin/${SRC_BRANCH}' ? (y/N) : " DELR
      if [[ "${DELR,,}" == "y" ]]; then
        echo "[ACTION] Suppression de origin/${SRC_BRANCH}..."
        git push origin --delete "${SRC_BRANCH}" || true
      fi
    fi

    deploy
    echo "✅ Terminé."
    exit 0

  elif [[ "$CHX" == "2" ]]; then
    echo "[ACTION] Retour sur '${DEFAULT}'..."
    git checkout "${DEFAULT}"
    echo "[NETTOYAGE] Suppression des branches temporaires locales _merge_tmp_* ..."
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

# ============================ PHASE 1 : préparation ============================
# Option : MAJ rapide du main avant de choisir la branche de test
read -rp "[OPTION] Faire d’abord une MAJ rapide du main (add/commit/pull --rebase/push) ? (y/N) : " DOUP
if [[ "${DOUP,,}" == "y" ]]; then
  quick_update_main
fi

# Se placer sur la branche par défaut si besoin
if [[ "$CURR" != "$DEFAULT" ]]; then
  echo "[INFO] Vous êtes sur '${CURR}'. Le flux de test démarre depuis '${DEFAULT}'."
  echo "[ACTION] Bascule vers '${DEFAULT}'..."
  git checkout "${DEFAULT}"
fi

echo
echo "[PRÉPARATION] Récupération des branches distantes (origin)..."
git fetch origin --prune

echo
echo "--- Branches distantes disponibles (origin) ---"
git for-each-ref --format='%(refname:short)' refs/remotes/origin | sed 's#^origin/##' | grep -v '^HEAD$' || true
echo "-----------------------------------------------"

echo
read -rp "Quelle branche distante voulez-vous tester ? (ex: codex/remove-import/export-buttons ou origin/codex/remove-import/export-buttons) : " BRANCH_INPUT
BRANCH="${BRANCH_INPUT#origin/}"  # normalise: enlève "origin/" s'il est présent

if [[ -z "${BRANCH}" ]]; then
  echo "[ANNULATION] Aucune branche saisie."
  exit 0
fi

if ! git ls-remote --heads origin "${BRANCH}" >/devnull 2>&1; then
  echo "[ERREUR] La branche 'origin/${BRANCH}' n'existe pas."
  exit 1
fi

# Crée/MAJ la branche temporaire locale depuis origin/<BRANCH>
TEMP="_merge_tmp_${BRANCH//\//_}"
echo "[ACTION] Création/MàJ de '${TEMP}' depuis 'origin/${BRANCH}'..."
git checkout -B "${TEMP}" "origin/${BRANCH}"

# Enregistre le mapping source -> pour push WIP correct plus tard
git config "branch.${TEMP}.ploufSource" "${BRANCH}"

deploy
echo
echo "✅ Branche de test prête : '${TEMP}'."
echo "➡ Vous pouvez maintenant tester l'application."
echo "ℹ️ Relancez ce script depuis '${TEMP}' pour ACCEPTER (merge) ou REFUSER (retour ${DEFAULT} + suppression)."
