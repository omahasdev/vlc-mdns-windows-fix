@echo off
rem Put the original libmicrodns_plugin.dll of VLC back (undo install.cmd).
rem Uses the backup that install.cmd made for the installed VLC version.
call "%~dp0install.cmd" restore
