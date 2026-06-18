#Requires -RunAsAdministrator
<#
.SYNOPSIS
    GTA Online - BattlEye hosts patch (Windows)
.DESCRIPTION
    Bloque les domaines BattlEye dans C:\Windows\System32\drivers\etc\hosts
    pour permettre aux joueurs Windows de jouer avec des amis Linux.
.USAGE
    irm https://git.maitregeek.eu/maitregeek/gta-on-linux/raw/commit/main/run.ps1 | iex
    .\run.ps1 apply
    .\run.ps1 remove
#>

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[INFO] Elevation necessaire, relancement en admin..." -ForegroundColor Yellow
    $cmd = "-ExecutionPolicy Bypass -NoProfile -Command `"irm https://git.maitregeek.eu/maitregeek/gta-on-linux/raw/commit/main/run.ps1 | iex`""
    Start-Process powershell -Verb RunAs -ArgumentList $cmd -Wait
    exit
}

$HOSTS_FILE    = "$env:SystemRoot\System32\drivers\etc\hosts"
$BACKUP_PREFIX = "$env:SystemRoot\System32\drivers\etc\hosts.gta-battleye-backup"
$IP_BLOCK      = "0.0.0.0"
$DOMAINS       = @(
    "paradise-s1.battleye.com",
    "test-s1.battleye.com",
    "paradiseenhanced-s1.battleye.com"
)

function Log  { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Warn { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Err  { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red; Read-Host | Out-Null; exit 1 }

function Backup-Hosts {
    $ts     = (Get-Date -Format "yyyyMMdd-HHmmss")
    $backup = "${BACKUP_PREFIX}-${ts}"
    Copy-Item $HOSTS_FILE $backup -ErrorAction Stop
    Log "Backup cree : $backup"
}

function Read-HostsLines {
    [System.IO.File]::ReadAllLines($HOSTS_FILE, [System.Text.Encoding]::UTF8)
}

function Write-HostsLines {
    param([string[]]$lines)
    [System.IO.File]::WriteAllLines($HOSTS_FILE, $lines, [System.Text.Encoding]::UTF8)
}

function Test-DomainExactMatch {
    param([string[]]$lines, [string]$domain)
    $pattern = "^[^\S\r\n]*" + [regex]::Escape($IP_BLOCK) + "[^\S\r\n]+" + [regex]::Escape($domain) + "[^\S\r\n]*$"
    return ($lines | Where-Object { $_ -match $pattern }).Count -gt 0
}

function Test-DomainPresent {
    param([string[]]$lines, [string]$domain)
    return ($lines | Where-Object { $_ -match [regex]::Escape($domain) }).Count -gt 0
}

function Test-AnyDomainPresent {
    param([string[]]$lines)
    foreach ($d in $DOMAINS) {
        if (Test-DomainPresent $lines $d) { return $true }
    }
    return $false
}

function Apply-Rules {
    Log "Application des regles BattlEye dans $HOSTS_FILE..."
    if (-not (Test-Path $HOSTS_FILE)) { Err "Fichier hosts introuvable : $HOSTS_FILE" }

    Backup-Hosts
    [string[]]$lines = Read-HostsLines
    $added = 0

    foreach ($domain in $DOMAINS) {
        if (Test-DomainExactMatch $lines $domain) {
            Log "Entree deja presente pour ${domain}, skip."
            continue
        }

        if (Test-DomainPresent $lines $domain) {
            Log "Entree existante avec IP differente pour ${domain}, mise en commentaire."
            $lines = $lines | ForEach-Object {
                if ($_ -match [regex]::Escape($domain) -and $_ -notmatch "^#") {
                    "# GTA-BE-OLD # $_"
                } else { $_ }
            }
        }

        $lines += "$IP_BLOCK $domain"
        Log "Ajout : $IP_BLOCK $domain"
        $added++
    }

    Write-HostsLines $lines

    if ($added -eq 0) {
        Log "Aucune nouvelle entree ajoutee. Tout etait deja en place."
    } else {
        ipconfig /flushdns | Out-Null
        Log "Cache DNS vide."
        Log "Regles BattlEye ajoutees. Redemarrez le jeu pour prendre en compte les changements."
        Log ""
        Log "IMPORTANT : Lancez d'abord le mode Histoire, puis rejoignez une session privee"
        Log "           (invite-only / friends-only) pour GTA Online."
    }
}

function Remove-Rules {
    Log "Suppression des regles BattlEye dans $HOSTS_FILE..."
    if (-not (Test-Path $HOSTS_FILE)) { Err "Fichier hosts introuvable : $HOSTS_FILE" }

    [string[]]$lines = Read-HostsLines

    if (-not (Test-AnyDomainPresent $lines)) {
        Log "Aucune entree BattlEye trouvee, rien a faire."
        return
    }

    Backup-Hosts

    $pattern = ($DOMAINS | ForEach-Object { [regex]::Escape($_) }) -join "|"
    [string[]]$filtered = $lines | Where-Object { $_ -notmatch $pattern }

    Write-HostsLines $filtered

    ipconfig /flushdns | Out-Null
    Log "Entrees BattlEye supprimees. Cache DNS vide."
    Log "Restauration possible depuis : ${BACKUP_PREFIX}-YYYYMMDD-HHMMSS"
}

function Print-Usage {
    Write-Host ""
    Write-Host "Usage: .\run.ps1 [apply|remove]" -ForegroundColor White
    Write-Host ""
    Write-Host "  apply   : Ajoute les entrees BattlEye dans le fichier hosts" -ForegroundColor Gray
    Write-Host "  remove  : Supprime ces entrees du fichier hosts" -ForegroundColor Gray
    Write-Host ""
    Write-Host "One-liner :" -ForegroundColor White
    Write-Host "  irm https://git.maitregeek.eu/maitregeek/gta-on-linux/raw/commit/main/run.ps1 | iex" -ForegroundColor Green
    Write-Host ""
}

Write-Host ""
Write-Host "=== GTA Online - BattlEye hosts patch (Windows) ===" -ForegroundColor Magenta
Write-Host ""

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