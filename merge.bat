@echo off

REM ============================================================
REM  Assistant de merge interactif (FR) – 2 phases
REM  Phase 1 (sur main/master) : choisir une branche distante à tester
REM  Phase 2 (sur _merge_tmp_*) : accepter (merge --no-ff) ou refuser
REM ============================================================

cd /d "%~dp0"
echo === Assistant de merge interactif (FR) ===

REM 0) Déclarer le repo comme "safe" (partage réseau)
git config --global --add safe.directory "%CD%" >NUL 2>&1

REM 1) Détecter branche par défaut (main/master)
set "DEFAULT=main"
git show-ref --verify --quiet refs/heads/main
if errorlevel 1 (
  git show-ref --verify --quiet refs/heads/master
  if not errorlevel 1 set "DEFAULT=master"
)

REM 2) Branchement courant
for /f "delims=" %%A in ('git rev-parse --abbrev-ref HEAD') do set "CURR=%%A"
if not defined CURR (
  echo [ERREUR] Impossible de déterminer la branche courante.
  goto :FAIL
)

REM 3) Commit WIP si modifications locales
for /f %%Z in ('git status --porcelain') do (
  set "HAS_DIRTY=1"
  goto :DO_WIP
)
goto :AFTER_WIP

:DO_WIP
echo [INFO] Modifications locales détectées sur "%CURR%" — création d'un commit de sauvegarde...
git add . || goto :FAIL
git commit -m "sauvegarde avant operation de test/merge" || goto :FAIL
REM Pull/push seulement si upstream
git rev-parse --abbrev-ref --symbolic-full-name @{u} >NUL 2>&1
if errorlevel 1 (
  echo [INFO] Pas d'upstream pour "%CURR%" — on ne fait pas de pull/push.
) else (
  echo [INFO] Mise à jour locale (pull --rebase) puis push du WIP...
  git pull --rebase || goto :FAIL
  git push || goto :FAIL
)
:AFTER_WIP

REM ====== PHASE 2 : si on est sur une branche temporaire, proposer la décision ======
if /I "%CURR:~0,11%"=="_merge_tmp_" (
  echo.
  echo [PHASE TEST] Vous êtes actuellement sur la branche temporaire: %CURR%
  echo   1) Accepter et fusionner dans "%DEFAULT%" (merge --no-ff) puis pousser
  echo   2) Refuser et revenir sur "%DEFAULT%" (suppression de la branche temporaire)
  echo   3) Annuler (ne rien faire)
  set /p CHX=Votre choix [1/2/3] : 
  if /I "%CHX%"=="1" goto :ACCEPTER
  if /I "%CHX%"=="2" goto :REFUSER
  echo [ANNULATION] Aucune opération effectuée.
  goto :OK
)

REM ====== PHASE 1 : on n'est PAS sur une branche temporaire ======
if /I not "%CURR%"=="%DEFAULT%" (
  echo.
  echo [INFO] Vous êtes sur "%CURR%". Le flux de test commence depuis "%DEFAULT%".
  echo [ACTION] Bascule vers "%DEFAULT%"...
  git checkout "%DEFAULT%" || goto :FAIL
  set "CURR=%DEFAULT%"
)

echo.
echo [PREPARATION] Récupération des branches distantes (origin)...
git fetch origin --prune || goto :FAIL

echo.
echo --- Branches distantes disponibles (origin) ---
git for-each-ref --format="%%(refname:short)" refs/remotes/origin | findstr /V "origin/HEAD"
echo ------------------------------------------------

echo.
set "BRANCH="
set /p BRANCH=Quelle branche distante voulez-vous tester ? (ex: codex/remove-import/export-buttons) : 
if "%BRANCH%"=="" (
  echo [ANNULATION] Aucune branche saisie.
  goto :OK
)

REM Vérifier l'existence de la branche distante
set "FOUND="
for /f "delims=" %%R in ('git ls-remote --heads origin "%BRANCH%"') do set FOUND=1
if not defined FOUND (
  echo [ERREUR] La branche "origin/%BRANCH%" n'existe pas.
  goto :OK
)

REM Créer la branche temporaire locale depuis origin/BRANCH
set "TEMP=_merge_tmp_%BRANCH:/=_%"
echo [ACTION] Création/MAJ de "%TEMP%" depuis "origin/%BRANCH%"...
git checkout -B "%TEMP%" "origin/%BRANCH%" || goto :FAIL

echo.
echo [OK] Branche de test chargée: "%TEMP%".
echo Vous pouvez maintenant tester l'application (build, run, etc.).
echo Relancez ce script pour accepter ou refuser les modifications.
goto :OK


:ACCEPTER
echo.
echo [ACTION] Passage sur "%DEFAULT%" et mise à jour...
git checkout "%DEFAULT%" || goto :FAIL
git pull origin %DEFAULT% --no-rebase || goto :FAIL

echo [ACTION] Fusion --no-ff de "%CURR%" vers "%DEFAULT%"...
git merge --no-ff "%CURR%"
if errorlevel 1 (
  echo.
  echo [CONFLIT] Des conflits existent. Corrigez puis lancez :
  echo   git add .
  echo   git commit
  echo   git push origin %DEFAULT%
  echo La branche temporaire "%CURR%" est conservée.
  goto :OK
)

git push origin %DEFAULT% || goto :FAIL
echo [OK] Fusion poussée sur origin/%DEFAULT%.

echo [NETTOYAGE] Suppression de la branche temporaire locale "%CURR%"...
git branch -D "%CURR%" >NUL 2>&1
goto :OK


:REFUSER
echo.
echo [ACTION] Retour sur "%DEFAULT%"...
git checkout "%DEFAULT%" || goto :FAIL

echo [NETTOYAGE] Suppression des branches temporaires locales _merge_tmp_* ...
for /f "delims=" %%B in ('git for-each-ref --format^="%%(refname:short)" refs/heads/_merge_tmp_* 2^>NUL') do (
  git branch -D "%%B" >NUL 2>&1
)
echo [OK] Retour sur "%DEFAULT%" et suppression des branches temporaires effectués.
goto :OK


:OK
echo.
echo Terminé.
endlocal
exit /b 0

:FAIL
echo.
echo [ERREUR] Une commande git a échoué. Abandon.
endlocal
exit /b 1
