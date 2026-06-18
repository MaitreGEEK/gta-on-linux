@echo off
:: gta-battleye-hosts-windows.bat
:: Patch /etc/hosts Windows pour GTA Online (BattlEye bypass - hosts only)
:: Usage: clic-droit -> "Executer en tant qu'administrateur"
:: Ou depuis cmd admin: gta-battleye-hosts-windows.bat [apply|remove]

setlocal EnableDelayedExpansion

set "HOSTS_FILE=%SystemRoot%\System32\drivers\etc\hosts"
set "BACKUP_PREFIX=%SystemRoot%\System32\drivers\etc\hosts.gta-battleye-backup"

set "DOMAINS[0]=paradise-s1.battleye.com"
set "DOMAINS[1]=test-s1.battleye.com"
set "DOMAINS[2]=paradiseenhanced-s1.battleye.com"
set "IP_BLOCK=0.0.0.0"

:: === Logging ===
:log
echo [INFO] %~1
goto :eof

:warn
echo [WARN] %~1
goto :eof

:err
echo [ERROR] %~1
exit /b 1

:: ===========================
::         MAIN ENTRY
:: ===========================

set "ACTION=%~1"
if "%ACTION%"=="" set "ACTION=apply"

:: Verifie admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Ce script doit etre execute en tant qu'Administrateur.
    echo Clic-droit sur le fichier ^> "Executer en tant qu'administrateur"
    pause
    exit /b 1
)

if /i "%ACTION%"=="apply"  goto :do_apply
if /i "%ACTION%"=="remove" goto :do_remove
goto :usage

:: ===========================
::         APPLY
:: ===========================
:do_apply
call :backup_hosts
call :apply_rules
pause
exit /b 0

:: ===========================
::         REMOVE
:: ===========================
:do_remove
call :backup_hosts
call :remove_rules
pause
exit /b 0

:: ===========================
::         USAGE
:: ===========================
:usage
echo.
echo Usage: %~nx0 [apply^|remove]
echo.
echo   apply   : Ajoute les entrees BattlEye dans le fichier hosts
echo   remove  : Supprime ces entrees du fichier hosts
echo.
echo Par defaut (double-clic) : apply
echo.
pause
exit /b 1

:: ===========================
::      BACKUP HOSTS
:: ===========================
:backup_hosts
for /f "tokens=1-3 delims=/ " %%a in ("%date%") do set "d=%%c%%b%%a"
for /f "tokens=1-2 delims=: " %%a in ("%time: =0%") do set "t=%%a%%b"
set "BACKUP=%BACKUP_PREFIX%-%d%-%t%"
copy "%HOSTS_FILE%" "%BACKUP%" >nul
echo [INFO] Backup cree : %BACKUP%
goto :eof

:: ===========================
::      APPLY RULES
:: ===========================
:apply_rules
echo [INFO] Application des regles Battleye dans %HOSTS_FILE%...

set "added=0"
for /l %%i in (0,1,2) do (
    call set "domain=%%DOMAINS[%%i]%%"
    call :check_domain_present "!domain!"
    if !ERRORLEVEL! equ 0 (
        echo [INFO] Entree deja presente pour !domain!, on ne modifie pas.
    ) else (
        echo %IP_BLOCK% !domain!>> "%HOSTS_FILE%"
        echo [INFO] Ajout : %IP_BLOCK% !domain!
        set "added=1"
    )
)

if "%added%"=="0" (
    echo [INFO] Aucune nouvelle entree ajoutee. Tout etait deja en place.
) else (
    echo [INFO] Regles Battleye ajoutees. Redemarrez le jeu pour prendre en compte les changements.
    echo.
    echo [INFO] Flush DNS...
    ipconfig /flushdns >nul
    echo [INFO] Cache DNS vide.
)
goto :eof

:: ===========================
::   CHECK DOMAIN PRESENT
:: ===========================
:check_domain_present
:: Retourne 0 si deja present, 1 sinon
findstr /i /r /c:"^[0-9. ]*%~1" "%HOSTS_FILE%" >nul 2>&1
goto :eof

:: ===========================
::      REMOVE RULES
:: ===========================
:remove_rules
echo [INFO] Suppression des regles Battleye dans %HOSTS_FILE%...

:: On verifie si au moins un domaine est present
set "found=0"
for /l %%i in (0,1,2) do (
    call set "domain=%%DOMAINS[%%i]%%"
    findstr /i /c:"!domain!" "%HOSTS_FILE%" >nul 2>&1
    if !ERRORLEVEL! equ 0 set "found=1"
)

if "%found%"=="0" (
    echo [INFO] Aucune entree Battleye trouvee dans %HOSTS_FILE%, rien a faire.
    goto :eof
)

:: Reecrit le fichier sans les lignes matchant les domaines
set "TMPFILE=%TEMP%\hosts_tmp_%RANDOM%.txt"
type nul > "%TMPFILE%"

for /f "usebackq delims=" %%L in ("%HOSTS_FILE%") do (
    set "line=%%L"
    set "skip=0"
    for /l %%i in (0,1,2) do (
        call set "domain=%%DOMAINS[%%i]%%"
        echo !line! | findstr /i /c:"!domain!" >nul 2>&1
        if !ERRORLEVEL! equ 0 set "skip=1"
    )
    if "!skip!"=="0" (
        echo !line!>> "%TMPFILE%"
    )
)

copy /y "%TMPFILE%" "%HOSTS_FILE%" >nul
del "%TMPFILE%"

ipconfig /flushdns >nul
echo [INFO] Entrees Battleye supprimees. Cache DNS vide.
goto :eof