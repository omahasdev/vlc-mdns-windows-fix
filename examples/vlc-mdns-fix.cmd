@echo off
rem Example launcher: keep the toolchain and the VLC SDK in a shared SDK folder
rem and the build data outside the repository. Copy this file to a folder in
rem your PATH and change the three paths below.
rem
rem   vlc-mdns-fix.cmd           build if necessary, then install
rem   vlc-mdns-fix.cmd restore   put the original DLL back
setlocal
set "VLC_MDNS_FIX_REPO=C:\src\vlc-mdns-windows-fix"
set "VLC_MDNS_FIX_SDK=C:\sdk"
set "VLC_MDNS_FIX_WORK=C:\sdk\vlc-mdns-fix"
call "%VLC_MDNS_FIX_REPO%\install.cmd" %*
