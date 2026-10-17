@echo off
rem Fix VLC 3.0 mDNS discovery on Windows: Chromecast (Renderer stuck on
rem "Scanning") and Local Network servers.
rem Builds libmicrodns_plugin.dll with the IP_MULTICAST_IF patch for the
rem installed VLC version if it is missing, then installs it as administrator.
rem Run it again after each VLC update.
rem
rem   install.cmd           build if necessary, then install
rem   install.cmd restore   put the original VLC DLL back
rem
rem Needs Git for Windows. Optional environment variables:
rem   GIT_BASH      bash.exe of Git for Windows
rem   VLC_MDNS_FIX_WORK  sources, DLLs and backups (default: .work in this folder)
rem   VLC_MDNS_FIX_SDK   toolchain and VLC SDK (default: VLC_MDNS_FIX_WORK)
rem   VLC_DIR       VLC install folder (default: from the registry)
setlocal
set "FIX=%~dp0scripts\vlc-mdns-fix.sh"

if /i "%~1"=="--elevated" goto elevated

if not defined GIT_BASH set "GIT_BASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined VLC_MDNS_FIX_WORK set "VLC_MDNS_FIX_WORK=%~dp0.work"
if not defined VLC_MDNS_FIX_SDK set "VLC_MDNS_FIX_SDK=%VLC_MDNS_FIX_WORK%"
if not exist "%GIT_BASH%" (
    echo ERROR: Git Bash not found: %GIT_BASH%
    echo Install Git for Windows or set GIT_BASH.
    exit /b 1
)

set "CMD_ARG=install"
if /i "%~1"=="restore" set "CMD_ARG=restore"
if "%CMD_ARG%"=="restore" goto elevate

"%GIT_BASH%" "%FIX%" build
if errorlevel 1 (
    pause
    exit /b 1
)

:elevate
rem An elevated process does not get this environment: give the values as arguments.
rem Start cmd.exe /s /c ""script" args": a .cmd file started directly with quoted
rem arguments loses its first and last quote, and the elevated window fails at once.
set "SELF=%~f0"
powershell -NoProfile -Command "$q = [char]34; $args2 = @($env:VLC_MDNS_FIX_WORK, $env:VLC_MDNS_FIX_SDK, $env:GIT_BASH, $env:VLC_DIR | ForEach-Object { $q + $_ + $q }) -join ' '; $line = '/s /c ' + $q + $q + $env:SELF + $q + ' --elevated ' + $env:CMD_ARG + ' ' + $args2 + $q; Start-Process -FilePath cmd.exe -ArgumentList $line -Verb RunAs -Wait"
if errorlevel 1 echo The administrator step was cancelled. Nothing was changed.
exit /b

:elevated
set "VLC_MDNS_FIX_WORK=%~3"
set "VLC_MDNS_FIX_SDK=%~4"
set "GIT_BASH=%~5"
set "VLC_DIR=%~6"
rem keep the output: this window closes, and the log helps when the step fails
if not exist "%VLC_MDNS_FIX_WORK%" mkdir "%VLC_MDNS_FIX_WORK%"
set "LOG=%VLC_MDNS_FIX_WORK%\%~2.log"
echo %DATE% %TIME% %* > "%LOG%"
"%GIT_BASH%" "%FIX%" %2 >> "%LOG%" 2>&1
type "%LOG%"
echo.
echo Log: %LOG%
pause
