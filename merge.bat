@echo off
setlocal enabledelayedexpansion
REM === Interactive Git Merge Helper (.BAT only) ===
REM - Commit WIP si repo sale (toujours), pull/push uniquement si upstream existe
REM - Si on est sur _merge_tmp_*, on bascule sur la branche par defaut APRES le WIP commit

cd /d "%~dp0"
echo === Interactive Git Merge Helper ===

REM 0) Safe dir
git config --global --add safe.directory "%CD%" >NUL 2>&1

REM 1) Branche courante
for /f "delims=" %%A in ('git rev-parse --abbrev-ref HEAD') do set CURR=%%A
if "%CURR%"=="" (
  echo Impossible de determiner la branche courante. Abandon.
  goto :error
)

REM 2) Si repo non clean: commit WIP
set DIRTY=
for /f %%A in ('git status --porcelain') do ( set DIRTY=1 & goto :dirtfound )
goto :after_dirty
:dirtfound
echo Working tree not clean — creating a WIP commit on "%CURR%"...
git add . || goto :error
git commit -m "sauvegarde avant de recuperer la branche provisoire" || goto :error

REM 2b) Pull --rebase + push uniquement si un upstream est configure
git rev-parse --abbrev-ref --symbolic-full-name @{u} >NUL 2>&1
if errorlevel 1 (
  echo No upstream configured for "%CURR%". Skipping pull/push for WIP commit.
) else (
  echo Rebase on top of upstream of "%CURR%" ...
  git pull --rebase || goto :error
  git push || goto :error
)
:after_dirty

REM 3) Detecter branche par defaut (main/master)
set "DEFAULT=main"
git show-ref --verify --quiet refs/heads/main
if errorlevel 1 (
  git show-ref --verify --quiet refs/heads/master
  if not errorlevel 1 set "DEFAULT=master"
)

REM 4) Si on est sur une branche temporaire, revenir maintenant sur la branche par defaut
if /I "%CURR:~0,11%"=="_merge_tmp_" (
  echo You are on temp branch "%CURR%". Switching to "%DEFAULT%"...
  git checkout "%DEFAULT%" || goto :error
  for /f "delims=" %%A in ('git rev-parse --abbrev-ref HEAD') do set CURR=%%A
)

REM 5) Choix du remote (defaut origin)
echo.
echo Remotes disponibles:
git remote -v
echo.
set "REMOTE=origin"
set /p REMOTE=Remote name [origin]: 
if "%REMOTE%"=="" set "REMOTE=origin"

echo Fetching from %REMOTE%...
git fetch %REMOTE% --prune || goto :error

REM 6) Demander la branche distante a recuperer
echo.
set "BRANCH="
set /p BRANCH=Branch to fetch (ex: codex/fix-sqlite_cantopen-error): 
if "%BRANCH%"=="" (
  echo No branch provided. Exit.
  goto :done
)

REM 7) Verifier existence de la branche distante
set FOUND=
for /f "tokens=1" %%A in ('git ls-remote --heads %REMOTE% %BRANCH%') do ( set FOUND=1 )
if not defined FOUND (
  echo Remote branch "%BRANCH%" does not exist on "%REMOTE%".
  goto :done
)

REM 8) Creer/maj branche temporaire locale depuis origin/BRANCH
set "TEMP=_merge_tmp_%BRANCH:/=_%"
echo Checking out temp local branch "%TEMP%" from "%REMOTE%/%BRANCH%"...
git checkout -B "%TEMP%" "%REMOTE%/%BRANCH%" || goto :error

REM 9) Merge dans la branche par defaut
echo Default branch detected: %DEFAULT%
set ANSW=
set /p ANSW=Merge "%BRANCH%" into "%DEFAULT%" now? (y/N): 
if /I not "%ANSW%"=="Y" (
  echo No merge executed. You are on temp branch "%TEMP%" tracking "%REMOTE%/%BRANCH%".
  goto :done
)

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
  goto :done
)

git push %REMOTE% %DEFAULT% || goto :error
echo Merge completed and pushed.

REM 10) Nettoyage: supprimer la branche temporaire locale
git branch -D "%TEMP%" >NUL 2>&1

:done
echo Done.
endlocal
exit /b 0

:error
echo.
echo ERROR: a git command failed. Aborting
