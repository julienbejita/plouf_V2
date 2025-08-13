# Usage: double-cliquer via .bat ou:
# powershell -ExecutionPolicy Bypass -File .\Merge-Interactive.ps1

$ErrorActionPreference = "Stop"

function Run($args) {
  & git @args
  if ($LASTEXITCODE -ne 0) {
    throw ("git " + ($args -join " "))
  }
}

Write-Host "=== Interactive Git Merge Helper ==="

# Aller dans le dossier du script (suppose le script dans la racine du repo)
Set-Location -Path (Split-Path -Parent $MyInvocation.MyCommand.Path)

# safe.directory (utile sur partage reseau)
$repoPath = (Resolve-Path .).Path
git config --global --add safe.directory "$repoPath" | Out-Null

# Check clean worktree
$dirty = (git status --porcelain)
if ($dirty) {
  Write-Host "Working tree not clean. Please commit or stash your changes, then retry." -ForegroundColor Yellow
  exit 1
}

# Remote (par defaut: origin)
$remote = Read-Host "Remote name [origin]"
if ([string]::IsNullOrWhiteSpace($remote)) { $remote = "origin" }

# Fetch / prune
Write-Host "Fetching from $remote..."
Run @("fetch",$remote,"--prune")

# Demander la branche source
$branch = Read-Host "Enter branch to fetch (ex: codex/fix-sqlite_cantopen-error)"
if ([string]::IsNullOrWhiteSpace($branch)) {
  Write-Host "No branch provided. Exit."
  exit 0
}

# Verifier existence branche distante
$exists = git ls-remote --heads $remote $branch
if ([string]::IsNullOrWhiteSpace($exists)) {
  Write-Host "Remote branch '$branch' does not exist on '$remote'." -ForegroundColor Red
  exit 1
}

# Creer/maj branche temporaire depuis la branche distante
$temp = "_merge_tmp_" + ($branch -replace "[^A-Za-z0-9_\-]", "_")
Write-Host "Checking out temp local branch '$temp' from '$remote/$branch'..."
Run @("checkout","-B",$temp,"$remote/$branch")

# Detecter branche par defaut (main/master)
$default = "main"
git show-ref --verify --quiet refs/heads/main
if ($LASTEXITCODE -ne 0) {
  git show-ref --verify --quiet refs/heads/master
  if ($LASTEXITCODE -eq 0) { $default = "master" }
}
Write-Host ("Default branch detected: {0}" -f $default)

# Option: merge dans main ?
$ans = Read-Host ("Merge '{0}' into '{1}' now? (y/N)" -f $branch, $default)
if ($ans -match '^(y|Y)$') {
  # Update main/master
  Run @("checkout",$default)
  Run @("pull",$remote,$default,"--no-rebase")

  # Merge no-ff pour conserver l'historique complet
  try {
    Run @("merge","--no-ff",$temp)
  } catch {
    Write-Host "Merge conflicts detected. Resolve them, then run:" -ForegroundColor Yellow
    Write-Host "  git add ."
    Write-Host "  git commit"
    Write-Host ("  git push {0} {1}" -f $remote, $default)
    Write-Host "Temp branch kept for debug: $temp"
    exit 1
  }

  # Push
  Run @("push",$remote,$default)
  Write-Host "Merge completed and pushed."

  # Nettoyage temp local
  try { Run @("branch","-D",$temp) } catch { }

  # Option: supprimer la branche source distante (si voulu)
  $del = Read-Host ("Delete remote source branch '{0}' on '{1}'? (y/N)" -f $branch, $remote)
  if ($del -match '^(y|Y)$') {
    try { Run @("push",$remote,"--delete",$branch) } catch { Write-Host "Cannot delete remote branch (permissions?)." -ForegroundColor Yellow }
  }

  # Option: supprimer la branche source locale (si existe)
  $hasLocal = git show-ref --verify --quiet ("refs/heads/" + $branch)
  if ($LASTEXITCODE -eq 0) {
    $dell = Read-Host ("Delete local branch '{0}'? (y/N)" -f $branch)
    if ($dell -match '^(y|Y)$') { try { Run @("branch","-D",$branch) } catch { } }
  }

} else {
  Write-Host "No merge executed. You are on temp branch '$temp' tracking '$remote/$branch'."
  Write-Host "You can later run:"
  Write-Host "  git checkout $default"
  Write-Host "  git merge --no-ff $temp"
  Write-Host "  git push $remote $default"
}

Write-Host "Done."
