@echo off
set SCRIPT=%~dp0Merge-Interactive.ps1
"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy Bypass -File "%SCRIPT%"
pause
@echo off
setlocal enabledelayedexpansion
REM === Interactive Git Merge Helper (.BAT only) ===
REM Flux modifié : si le repo est sale -> commit de sauvegarde + pull --rebase + push

cd /d "%~dp0"
echo === Interactive Git Merge Helper ===

REM 1) Safe directory (utile sur partages reseau)
git config --global --add safe.directory "%CD%" >NUL 2>&1

REM 2) Branche courante
for /f "delims=" %%A in ('git rev-parse --abbrev-ref HEAD') do set CURR=%%A
if "%CURR%"=="" (
  echo Impossible de determiner la branche courante. Abandon.
  goto :error
)

REM 3) Si repo non clean: commit de sauvegarde + pull --rebase + push
set DIRTY=
for /f %%A in ('git status --porcelain') do ( set DIRTY=1 & goto :dirtfound )
goto :after_dirty
:dirtfound
echo Working tree not clean — creating a WIP commit and pushing...
git add . || goto :error
git commit -m "sauvegarde avant de recuperer la branche provisoire" || goto :error
echo Rebase on top of origin/%CURR% ...
git pull origin %CURR% --rebase || goto :error
git push origin %CURR% || goto :error
:after_dirty

REM 4) Choix du remote (defaut origin)
echo.
echo Remotes disponibles:
git remote -v
echo.
set "REMOTE=origin"
set /p REMOTE=Remote name [origin]: 
if "%REMOTE%"=="" set "REMOTE=origin"

echo Fetching from %REMOTE%...
git fetch %REMOTE% --prune || goto :error

REM 5) Demander la branche distante a recuperer
echo.
set "BRANCH="
set /p BRANCH=Branch to fetch (ex: codex/fix-sqlite_cantopen-error): 
if "%BRANCH%"=="" (
  echo No branch provided. Exit.
  goto :end_ok
)

REM 6) Verifier existence de la branche distante
set FOUND=
for /f "tokens=1" %%A in ('git ls-remote --heads %REMOTE% %BRANCH%') do ( set FOUND=1 )
if not defined FOUND (
  echo Remote branch "%BRANCH%" does not exist on "%REMOTE%".
  goto :end_ok
)

REM 7) Creer/maj branche temporaire locale depuis origin/BRANCH
set "TEMP=_merge_tmp_%BRANCH:/=_%"
echo Checking out temp local branch "%TEMP%" from "%REMOTE%/%BRANCH%"...
git checkout -B "%TEMP%" "%REMOTE%/%BRANCH%" || goto :error

REM 8) Detecter branche par defaut (main/master)
set "DEFAULT=main"
git show-ref --verify --quiet refs/heads/main
if errorlevel 1 (
  git show-ref --verify --quiet refs/heads/master
  if not errorlevel 1 set "DEFAULT=master"
)
echo Default branch detected: %DEFAULT%

REM 9) Proposer le merge
set ANSW=
set /p ANSW=Merge "%BRANCH%" into "%DEFAULT%" now? (y/N): 
if /I not "%ANSW%"=="Y" (
  echo No merge executed. You are now on temp branch "%TEMP%" tracking "%REMOTE%/%BRANCH%".
  goto :end_ok
)

REM 10) Mettre a jour la branche par defaut, merger --no-ff, pousser
git checkout "%DEFAULT%" || goto :error
git pull %REMOTE% %DEFAULT% --no-rebase || goto :error

echo Merging --no-ff "%TEMP%" into "%DEFAULT%"...
git merge --no-ff "%TEMP%"
if errorlevel 1 (
  echo.
  echo Merge conflicts detected. Resolve them, then run:
  echo   git add .
  echo   git commit
  echo   git push %REMOTE% %DEFAULT%
  echo Temp branch kept: %TEMP%
  goto :end_ok
)

git push %REMOTE% %DEFAULT% || goto :error
echo Merge completed and pushed.

REM 11) Nettoyage: supprimer la branche temporaire locale
git branch -D "%TEMP%" >NUL 2>&1

:end_ok
echo Done.
endlocal
exit /b 0

:error
echo.
echo ERROR: a git command failed. Aborting.
endlocal
exit /b 1
 