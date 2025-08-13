# Usage: double-cliquer via merge.bat ou:
# powershell -ExecutionPolicy Bypass -File .\Merge-Interactive.ps1

param()

$ErrorActionPreference = "Stop"

function Run {
  param([string[]]$Args)
  if (-not $Args -or $Args.Count -eq 0) { throw "Internal error: Run() called with no git args." }
  & git @Args
  if ($LASTEXITCODE -ne 0) { throw ("git {0}" -f ($Args -join " ")) }
}

Write-Host "=== Interactive Git Merge Helper ==="

# Aller à la racine du repo (dossier du script)
Set-Location -Path (Split-Path -Parent $MyInvocation.MyCommand.Path)

# Marquer le repo comme safe (utile sur partage réseau)
$repoPath = (Resolve-Path .).Path
git config --global --add safe.directory "$repoPath" | Out-Null

# Stash automatique si working tree non clean
$dirty = (git status --porcelain)
$stashed = $false
if ($dirty) {
  Write-Host "Working tree not clean — stashing changes temporarily..." -ForegroundColor Yellow
  Run @("stash","push","--include-untracked","-m","temp-stash-before-merge")
  $stashed = $true
}

# Lister les remotes pour info
Write-Host "`nRemotes disponibles :" -ForegroundColor Cyan
git remote -v

# Demander le remote avec valeur par défaut 'origin'
$Remote = Read-Host "Remote name [origin]"
if ([string]::IsNullOrWhiteSpace($Remote)) { $Remote = "origin" }

Write-Host "Fetching from $Remote..."
Run @("fetch",$Remote,"--prune")

# Demander la branche distante à récupérer
$Branch = Read-Host "Enter branch to fetch (ex: codex/fix-sqlite_cantopen-error)"
if ([string]::IsNullOrWhiteSpace($Branch)) {
  Write-Host "No branch provided. Exit."
  if ($stashed) { Write-Host "Restoring stashed changes..." -ForegroundColor Yellow; git stash pop | Out-Null }
  exit 0
}

# Vérifier existence de la branche distante
$exists = git ls-remote --heads $Remote $Branch
if ([string]::IsNullOrWhiteSpace($exists)) {
  Write-Host "Remote branch '$Branch' does not exist on '$Remote'." -ForegroundColor Red
  if ($stashed) { Write-Host "Restoring stashed changes..." -ForegroundColor Yellow; git stash pop | Out-Null }
  exit 1
}

# Créer/mettre à jour une branche temporaire locale depuis la distante
$Temp = "_merge_tmp_" + ($Branch -replace "[^A-Za-z0-9_\-]", "_")
Write-Host "Checking out temp local branch '$Temp' from '$Remote/$Branch'..."
Run @("checkout","-B",$Temp,"$Remote/$Branch")

# Détecter la branche par défaut (main/master)
$Default = "main"
git show-ref --verify --quiet refs/heads/main
if ($LASTEXITCODE -ne 0) {
  git show-ref --verify --quiet refs/heads/master
  if ($LASTEXITCODE -eq 0) { $Default = "master" }
}
Write-Host ("Default branch detected: {0}" -f $Default)

# Proposer le merge maintenant
$ans = Read-Host ("Merge '{0}' into '{1}' now? (y/N)" -f $Branch, $Default)
if ($ans -match '^(y|Y)$') {
  # Mettre la branche par défaut à jour
  Run @("checkout",$Default)
  Run @("pull",$Remote,$Default,"--no-rebase")

  # Merge no-ff pour conserver l'historique
  try {
    Run @("merge","--no-ff",$Temp)
  } catch {
    Write-Host "Merge conflicts detected. Resolve them, then run:" -ForegroundColor Yellow
    Write-Host "  git add ."
    Write-Host ("  git commit")
    Write-Host ("  git push {0} {1}" -f $Remote, $Default)
    Write-Host "Temp branch kept for debug: $Temp"
    if ($stashed) { Write-Host "Restoring stashed changes..." -ForegroundColor Yellow; git stash pop | Out-Null }
    exit 1
  }

  # Push
  Run @("push",$Remote,$Default)
  Write-Host "Merge completed and pushed."

  # Nettoyage de la branche temporaire locale
  try { Run @("branch","-D",$Temp) } catch { }

  # Option: supprimer la branche source distante
  $del = Read-Host ("Delete remote source branch '{0}' on '{1}'? (y/N)" -f $Branch, $Remote)
  if ($del -match '^(y|Y)$') {
    try { Run @("push",$Remote,"--delete",$Branch) } catch { Write-Host "Cannot delete remote branch (permissions?)." -ForegroundColor Yellow }
  }

  # Option: supprimer la branche source locale (si existe)
  git show-ref --verify --quiet ("refs/heads/" + $Branch)
  if ($LASTEXITCODE -eq 0) {
    $dell = Read-Host ("Delete local branch '{0}'? (y/N)" -f $Branch)
    if ($dell -match '^(y|Y)$') { try { Run @("branch","-D",$Branch) } catch { } }
  }

} else {
  Write-Host "No merge executed. You are on temp branch '$Temp' tracking '$Remote/$Branch'."
  Write-Host "Later you can run:"
  Write-Host "  git checkout $Default"
  Write-Host "  git merge --no-ff $Temp"
  Write-Host "  git push $Remote $Default"
}

# Restaure le stash si on en a créé un
if ($stashed) {
  Write-Host "Restoring stashed changes..." -ForegroundColor Yellow
  git stash pop | Out-Null
}

Write-Host "Done."
