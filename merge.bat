@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM === Interactive merge helper (2 phases) ===
REM Phase 1 (on main/master): pick remote branch, create local temp _merge_tmp_*, checkout -> test
REM Phase 2 (on _merge_tmp_*): accept (merge --no-ff -> main/master + push + delete temp) or reject

cd /d "%~dp0"
echo === Interactive merge helper (CMD) ===

REM Safe dir for network shares
git config --global --add safe.directory "%CD%" >NUL 2>&1

REM Detect default branch
set "DEFAULT=main"
git rev-parse --verify refs/heads/main >NUL 2>&1 || (
  git rev-parse --verify refs/heads/master >NUL 2>&1 && set "DEFAULT=master"
)

REM Current branch
for /f "delims=" %%A in ('git rev-parse --abbrev-ref HEAD') do set "CURR=%%A"
if not defined CURR (
  echo [ERROR] Cannot detect current branch.
  goto :ERR
)

REM WIP commit if dirty
set "DIRTY="
for /f %%Z in ('git status --porcelain') do set "DIRTY=1"
if defined DIRTY (
  echo [INFO] Local changes on %CURR% - creating WIP commit...
  git add . || goto :ERR
  git commit -m "WIP: save before test/merge" || goto :ERR
  git rev-parse --abbrev-ref --symbolic-full-name @{u} >NUL 2>&1
  if not errorlevel 1 (
    echo [INFO] Rebase on upstream then push...
    git pull --rebase || goto :ERR
    git push || goto :ERR
  ) else (
    echo [INFO] No upstream for %CURR% - skip pull/push.
  )
)

REM Phase 2: if on temp branch
echo %CURR% | findstr /B "_merge_tmp_" >NUL
if not errorlevel 1 (
  echo.
  echo You are on temp branch: %CURR%
  echo   1 - Accept: merge --no-ff into %DEFAULT% and push
  echo   2 - Reject: switch back to %DEFAULT% and delete temp branch
  echo   3 - Cancel
  set /p CHX=Your choice [1/2/3]: 
  if /I "%CHX%"=="1" goto :ACCEPT
  if /I "%CHX%"=="2" goto :REJECT
  echo [CANCEL] Nothing done.
  goto :OK
)

REM Phase 1: ensure on DEFAULT
if /I not "%CURR%"=="%DEFAULT%" (
  echo [INFO] Switching to %DEFAULT%...
  git checkout "%DEFAULT%" || goto :ERR
)

echo.
echo [INFO] Fetching origin...
git fetch origin --prune || goto :ERR

echo.
echo --- Remote branches (origin) ---
git for-each-ref --format="%%(refname:short)" refs/remotes/origin | findstr /V "origin/HEAD"
echo ---------------------------------
set /p BRANCH=Branch to test (ex: codex/remove-import/export-buttons): 
if "%BRANCH%"=="" (
  echo [CANCEL] No branch given.
  goto :OK
)

REM Check remote branch exists
set "FOUND="
for /f "delims=" %%R in ('git ls-remote --heads origin "%BRANCH%"') do set "FOUND=1"
if not defined FOUND (
  echo [ERROR] origin/%BRANCH% not found.
  goto :OK
)

REM Create/checkout temp branch
set "TEMP=_merge_tmp_%BRANCH:/=_%"
echo [ACTION] Creating/updating %TEMP% from origin/%BRANCH% ...
git checkout -B "%TEMP%" "origin/%BRANCH%" || goto :ERR
echo [OK] Temp branch ready. Test your app on "%TEMP%".
echo Run this script again to accept or reject.
goto :OK

:ACCEPT
echo [ACTION] Merging into %DEFAULT% ...
git checkout "%DEFAULT%" || goto :ERR
git pull origin %DEFAULT% --no-rebase || goto :ERR
git merge --no-ff "%CURR%"
if errorlevel 1 (
  echo [CONFLICT] Resolve, then: git add . ^&^& git commit ^&^& git push origin %DEFAULT%
  goto :OK
)
git push origin %DEFAULT% || goto :ERR
echo [OK] Pushed to origin/%DEFAULT%. Deleting temp branch...
git branch -D "%CURR%" >NUL 2>&1
goto :OK

:REJECT
echo [ACTION] Reject changes. Switching back to %DEFAULT% ...
git checkout "%DEFAULT%" || goto :ERR
echo Deleting local temp branches _merge_tmp_* ...
for /f "delims=" %%B in ('git for-each-ref --format^="%%(refname:short)" refs/heads/_merge_tmp_* 2^>NUL') do git branch -D "%%B" >NUL 2>&1
goto :OK

:ERR
echo.
echo [ERROR] A git command failed. Aborting.
:OK
echo.
echo Done.
endlocal
exit /b 0
