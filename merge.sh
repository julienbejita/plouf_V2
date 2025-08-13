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

# --- Étape A : proposer de mettre à jour main depuis origin AVANT tout commit WIP ---
read -rp "[OPTION] Mettre à jour '${DEFAULT}' depuis origin (pull --rebase) AVANT le commit de sauvegarde ? (y/N) : " UPDATE_FIRST
if [[ "${UPDATE_FIRST,,}" == "y" ]]; then
  # Se placer sur '${DEFAULT}' si besoin
  if [[ "$CURR" != "$DEFAULT" ]]; then
    echo "[ACTION] Bascule vers '${DEFAULT}'..."
    git checkout "${DEFAULT}"
    CURR="${DEFAULT}"
  fi

  # Si repo sale : stash temporaire
  STASHED=0
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "[INFO] Modifications locales détectées — stash temporaire le temps d'actualiser '${DEFAULT}'..."
    git stash push --include-untracked -m "plouf-temp-before-pull"
    STASHED=1
  fi

  echo "[MAJ] Pull --rebase depuis origin/${DEFAULT}..."
  git pull origin "${DEFAULT}" --rebase

  # Restaure le stash si on en a créé un
  if [[ "${STASHED}" -eq 1 ]]; then
    echo "[INFO] Restauration des changements locaux (stash pop)..."
    if ! git stash pop; then
      echo
      echo "[CONFLIT] Des conflits sont apparus lors du 'stash pop'."
      echo "Corrige les conflits puis exécute :"
      echo "  git add . && git commit"
      echo "Ensuite relance ce script."
      exit 0
    fi
  fi
fi

# --- Étape B : commit WIP + push adapté (APRÈS la mise à jour éventuelle) ---
if [[ -n "$(git status --porcelain)" ]]; then
  echo "[INFO] Modifications locales détectées sur ${CURR} — création d'un commit de sauvegarde..."
  git add .
  git commit -m "WIP: sauvegarde avant test/merge"

  if [[ "$CURR" == _merge_tmp_* ]]; then
    # Push WIP vers la branche distante d'origine si mappée
    SRC_BRANCH="$(git config --get "branch.${CURR}.ploufSource" || true)"
    if [[ -n "${SRC_BRANCH:-}" ]]; then
      echo "[INFO] Push du WIP vers la branche distante d'origine: origin/${SRC_BRANCH}"
      git push origin HEAD:"${SRC_BRANCH}"
    else
      # Sinon: upstream si présent
      if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        echo "[INFO] Push du WIP vers l'upstream de ${CURR}..."
        git pull --rebase
        git push
      else
        echo "[INFO] Aucun mapping ploufSource ni upstream pour ${CURR} — WIP non poussé (local uniquement)."
      fi
    fi
  else
    # Branche normale : pousser si upstream configuré
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
  read -rp "Votre choix [1/2/3] : " CHX

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

    # Proposer suppression de la branche distante d'origine si connue
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
# Se placer sur la branche par défaut si besoin
if [[ "$CURR" != "$DEFAULT" ]]; then
  echo "[INFO] Vous êtes sur '${CUR
