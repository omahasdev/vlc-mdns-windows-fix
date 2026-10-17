@echo off
rem Download the build inputs for the installed VLC 3.0.x without a build:
rem the llvm-mingw toolchain, the VLC SDK, the VLC module source and the
rem patched libmicrodns. Needs no administrator rights.
rem
rem   prepare.cmd [VLC_VERSION]
rem
rem Uses the same environment variables as install.cmd
rem (GIT_BASH, VLC_MDNS_FIX_WORK, VLC_MDNS_FIX_SDK, VLC_DIR).
setlocal
if not defined GIT_BASH set "GIT_BASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined VLC_MDNS_FIX_WORK set "VLC_MDNS_FIX_WORK=%~dp0.work"
if not exist "%GIT_BASH%" (
    echo ERROR: Git Bash not found: %GIT_BASH%
    echo Install Git for Windows or set GIT_BASH.
    exit /b 1
)
"%GIT_BASH%" "%~dp0scripts\vlc-mdns-fix.sh" prepare %1
