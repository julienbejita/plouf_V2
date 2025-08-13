@echo off
setlocal enabledelayedexpansion
REM ============================================================
REM  Merge interactif (FR) – 2 phases : TEST puis DECISION
REM  - Phase 1 (sur main/master) : liste des branches distantes,
REM    choix -> creation d'une branche temporaire _merge_tmp_* et checkout.
REM  - Phase 2 (sur _merge_tmp_*) : [1] merge --no-ff vers main/master,
REM    push et suppression ; [2] abandon -> retour main/master et suppression.
REM  - Sauvegarde locale : commit WIP; pull --rebase/push uniquement si upstream.
REM ============================================================

cd /d "%~dp0"
echo === Assistant de merge interactif (FR) ===

REM -- Safe directory (partages reseau) --
git config --global --add safe.directory "%CD%" >NUL 2>&1

REM -- Detecter branche par defaut (main/master) --
set "DEFAULT=main"
git show-ref --verify --quiet refs/heads/main
if errorlevel 1 (
  git show-ref --verify --quiet refs/heads/master
  if not errorlevel 1 set "DEFAULT=master"
)

REM -- Branche courante --
for /f "delims=" %%A in ('git rev-parse --abbrev-ref HEAD') do set CURR=%%A
if "%CURR%"=="" (
  echo [ERREUR] Impossible de determiner la branche courante.
  goto :error
)

REM --------- FONCTIONS UTIL ---------
:maybe_wip_commit
REM Si repo non clean: commit WIP; si upstream existe -> pull --rebase + push
set DIRTY=
for /f %%Z in ('git status --porcelain') do ( set DIRTY=1 & goto :do_wip )
goto :wip_done
:do_wip
echo [INFO] Modifications locales detectees sur "%CURR%" — creation d'un commit de sauvegarde...
git add . || goto :error
git commit -m "sauvegarde avant operation de test/merge" || goto :error

REM Upstream ?
git rev-parse --abbrev-ref --symbolic-full-name @{u} >NUL 2>&1
if errorlevel 1 (
  echo [INFO] Pas d'upstream configure pour "%CURR%". On n'effectue pas de pull/push pour le WIP.
) else (
  echo [INFO] Mise a jour locale (pull --rebase) puis push du WIP...
  git pull --rebase || goto :error
  git push || goto :error
)
:wip_done
goto :eof

:checkout_default
git checkout "%DEFAULT%" || goto :error
for /f "delims=" %%A in ('git rev-parse --abbrev-ref HEAD') do set CURR=%%A
goto :eof

:list_remote_branches
echo.
echo --- Branches distantes sur origin --- 
REM Filtrer les lignes HEAD et afficher uniquement origin/*
git branch -r | findstr /R "^  origin/" | findstr /V "origin/HEAD"
echo -------------------------------------
goto :eof
REM --------------------------------------

REM ===================== PHASE 2 : sur branche temporaire =====================
if /I "%CURR:~0,11%"=="_merge_tmp_" (
  echo.
  echo [ETAPE TEST] Vous etes sur la branche temporaire "%CURR%".
  echo Choisissez une action :
  echo   1 ^) Accepter : fusionner dans "%DEFAULT%" (merge --no-ff) et pousser
  echo   2 ^) Refuser  : revenir sur "%DEFAULT%" et supprimer la branche temporaire
  echo   3 ^) Annuler  : ne rien faire
  set /p CHX=Votre choix [1/2/3] : 
  if "%CHX%"=="1" (
    call :maybe_wip_commit
    echo [INFO] Passage sur "%DEFAULT%" et mise a jour...
    call :checkout_default
    git pull origin %DEFAULT% --no-rebase || goto :error

    echo [ACTION] Fusion --no-ff de "%CURR%" vers "%DEFAULT%"...
    git merge --no-ff "%CURR%"
    if errorlevel 1 (
      echo.
      echo [CONFLIT] Des conflits existent. Corrigez puis lancez :
      echo   git add .
      echo   git commit
      echo   git push origin %DEFAULT%
      echo La branche temporaire "%CURR%" est conservee.
      goto :done
    )

    git push origin %DEFAULT% || goto :error
    echo [OK] Fusion envoyee sur origin/%DEFAULT%.

    echo [NETTOYAGE] Suppression de la branche temporaire locale "%CURR%"...
    git branch -D "%CURR%" >NUL 2>&1

    echo [FIN] Operation terminee.
    goto :done
  ) else if "%CHX%"=="2" (
    call :maybe_wip_commit
    echo [INFO] Retour sur "%DEFAULT%"...
    call :checkout_default
    echo [NETTOYAGE] Suppression de la branche temporaire locale "%CURR%"...
    REM ATTENTION: on a change de branche, l'ancienne temp est inconnue ici.
    REM On recalcule son nom a partir de reflog si besoin, mais plus simple:
    REM demander confirmation et supprimer toutes _merge_tmp_* existantes.
    for /f "delims=" %%B in ('git for-each-ref --format^="%%(refname:short)" refs/heads/_merge_tmp_* 2^>NUL') do (
      git branch -D "%%B" >NUL 2>&1
    )
    echo [OK] Branche(s) temporaire(s) supprimee(s). Retour sur "%DEFAULT%".
    goto :done
  ) else (
    echo [ANNULATION] Aucune operation effectuee.
    goto :done
  )
)

REM ===================== PHASE 1 : sur main/master =====================
if /I not "%CURR%"=="%DEFAULT%" (
  echo.
  echo [INFO] Vous etes sur "%CURR%". Le flux de test commence depuis "%DEFAULT%".
  call :maybe_wip_commit
  echo [INFO] Bascule vers "%DEFAULT%"...
  call :checkout_default
)

echo.
echo [ETAPE PREPARATION] Liste des branches distantes disponibles (origin) :
call :list_remote_branches
echo.
set "BRANCH="
set /p BRANCH=Quelle branche distante voulez-vous tester ? (ex: codex/remove-import/export-buttons) : 
if "%BRANCH%"=="" (
  echo [ANNULATION] Aucune branche saisie.
  goto :done
)

REM Verification existence distante
set FOUND=
for /f "tokens=1" %%Z in ('git ls-remote --heads origin %BRANCH%') do ( set FOUND=1 )
if not defined FOUND (
  echo [ERREUR] La branche "origin/%BRANCH%" n'existe pas.
  goto :done
)

REM Creation/maj branche temporaire locale depuis origin/BRANCH
set "TEMP=_merge_tmp_%BRANCH:/=_%"
echo [ACTION] Creation de la branche temporaire "%TEMP%" depuis "origin/%BRANCH%"...
git checkout -B "%TEMP%" "origin/%BRANCH%" || goto :error

echo.
echo [OK] Branche chargee : "%TEMP%".
echo Vous pouvez maintenant TESTER l'application sur cette branche.
echo Relancez ce script pour DECIDER (accepter/refuser) les modifications.
goto :done

:done
echo.
echo Terminé.
endlocal
exit /b 0

:error
echo.
echo [ERREUR] Une commande git a echoue. Abandon.
endlocal
exit /b 1
