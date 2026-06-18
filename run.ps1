<#
.SYNOPSIS
    GTA Online - BattlEye hosts patch (Windows)
.DESCRIPTION
    Bloque les domaines BattlEye dans C:\Windows\System32\drivers\etc\hosts
    pour permettre aux joueurs Windows de jouer avec des amis Linux.
    Ne necessite PAS Proton BattlEye Runtime (Windows natif).
.USAGE
    irm https://git.maitregeek.eu/maitregeek/gta-on-linux/raw/commit/main/run.ps1 | iex
    ou
    .\run.ps1 apply
    .\run.ps1 remove
#>

# === Auto-elevation UAC ===
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[INFO] Elevation necessaire, relancement en admin..." -ForegroundColor Yellow
    $cmd = "-ExecutionPolicy Bypass -Command `"irm https://git.maitregeek.eu/maitregeek/gta-on-linux/raw/commit/main/run.ps1 | iex`""
    Start-Process powershell -Verb RunAs -ArgumentList $cmd
    exit
}

# === Config ===
$HOSTS_FILE    = "$env:SystemRoot\System32\drivers\etc\hosts"
$BACKUP_PREFIX = "$env:SystemRoot\System32\drivers\etc\hosts.gta-battleye-backup"
$IP_BLOCK      = "0.0.0.0"
$DOMAINS       = @(
    "paradise-s1.battleye.com",
    "test-s1.battleye.com",
    "paradiseenhanced-s1.battleye.com"
)

# === Logging ===
function Log  { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Warn { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Err  { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }

# === Backup ===
function Backup-Hosts {
    $ts     = (Get-Date -Format "yyyyMMdd-HHmmss")
    $backup = "${BACKUP_PREFIX}-${ts}"
    Copy-Item $HOSTS_FILE $backup -ErrorAction Stop
    Log "Backup cree : $backup"
}

# === Helpers ===
function Test-DomainPresent {
    param([string]$domain)
    $content = Get-Content $HOSTS_FILE -Raw
    return ($content -match "(?m)^[^\S\r\n]*$([regex]::Escape($IP_BLOCK))[^\S\r\n]+$([regex]::Escape($domain))[^\S\r\n]*$")
}

function Test-AnyDomainPresent {
    $content = Get-Content $HOSTS_FILE -Raw
    foreach ($d in $DOMAINS) {
        if ($content -match [regex]::Escape($d)) { return $true }
    }
    return $false
}

# === Apply ===
function Apply-Rules {
    Log "Application des regles BattlEye dans $HOSTS_FILE..."

    if (-not (Test-Path $HOSTS_FILE)) { Err "Fichier hosts introuvable : $HOSTS_FILE" }

    Backup-Hosts

    $added = 0
    foreach ($domain in $DOMAINS) {
        if (Test-DomainPresent $domain) {
            Log "Entree deja presente pour ${domain}, skip."
        } else {
            # Commente les lignes existantes avec une IP differente
            $lines = Get-Content $HOSTS_FILE
            $newLines = $lines | ForEach-Object {
                if ($_ -match [regex]::Escape($domain) -and $_ -notmatch "^#") {
                    "# GTA-BE-OLD # $_"
                } else { $_ }
            }
            Set-Content $HOSTS_FILE $newLines -Encoding UTF8

            Add-Content $HOSTS_FILE "`n$IP_BLOCK $domain" -Encoding UTF8
            Log "Ajout : $IP_BLOCK $domain"
            $added++
        }
    }

    if ($added -eq 0) {
        Log "Aucune nouvelle entree ajoutee. Tout etait deja en place."
    } else {
        # Flush DNS
        ipconfig /flushdns | Out-Null
        Log "Cache DNS vide."
        Log "Regles BattlEye ajoutees. Redemarrez le jeu pour prendre en compte les changements."
        Log ""
        Log "IMPORTANT : Lancez d'abord le mode Histoire, puis rejoignez une session privee"
        Log "           (invite-only / friends-only) pour GTA Online."
    }
}

# === Remove ===
function Remove-Rules {
    Log "Suppression des regles BattlEye dans $HOSTS_FILE..."

    if (-not (Test-AnyDomainPresent)) {
        Log "Aucune entree BattlEye trouvee, rien a faire."
        return
    }

    Backup-Hosts

    $lines = Get-Content $HOSTS_FILE
    $pattern = ($DOMAINS | ForEach-Object { [regex]::Escape($_) }) -join "|"
    $filtered = $lines | Where-Object { $_ -notmatch $pattern }
    Set-Content $HOSTS_FILE $filtered -Encoding UTF8

    ipconfig /flushdns | Out-Null
    Log "Entrees BattlEye supprimees. Cache DNS vide."
    Log "Vous pouvez restaurer un backup depuis : ${BACKUP_PREFIX}-YYYYMMDD-HHMMSS"
}

# === Usage ===
function Print-Usage {
    Write-Host ""
    Write-Host "Usage: .\run.ps1 [apply|remove]" -ForegroundColor White
    Write-Host ""
    Write-Host "  apply   : Ajoute les entrees BattlEye dans le fichier hosts" -ForegroundColor Gray
    Write-Host "  remove  : Supprime ces entrees du fichier hosts" -ForegroundColor Gray
    Write-Host ""
    Write-Host "One-liner (depuis n'importe quel PowerShell) :" -ForegroundColor White
    Write-Host "  irm https://git.maitregeek.eu/maitregeek/gta-on-linux/raw/commit/main/run.ps1 | iex" -ForegroundColor Green
    Write-Host ""
}

# === Main ===
Write-Host ""
Write-Host "=== GTA Online - BattlEye hosts patch (Windows) ===" -ForegroundColor Magenta
Write-Host ""

# Quand pipe depuis iex, $args est vide -> on prompt
$ACTION = if ($args.Count -gt 0) { $args[0] } else {
    Write-Host "Action :" -ForegroundColor White
    Write-Host "  1) apply  - Bloquer les domaines BattlEye" -ForegroundColor Gray
    Write-Host "  2) remove - Retirer le blocage" -ForegroundColor Gray
    Write-Host ""
    $choice = Read-Host "Choix [1/2] (defaut: 1)"
    if ($choice -eq "2") { "remove" } else { "apply" }
}

switch ($ACTION.ToLower()) {
    "apply"  { Apply-Rules }
    "remove" { Remove-Rules }
    default  { Print-Usage; exit 1 }
}

Write-Host ""
Write-Host "Termine. Appuyez sur Entree pour fermer." -ForegroundColor Green
Read-Host | Out-Null