@echo off
cd /d "%~dp0"
set ARGS=
if /i "%~1"=="undo" set ARGS=-Undo
if /i "%~1"=="blockext" set ARGS=-BlockExtensions

echo Applying security policies to Chrome, Edge, Brave and Firefox...
echo   harden-browsers.bat undo      - remove them
echo   harden-browsers.bat blockext  - also block installing new extensions
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0harden-browsers.ps1" %ARGS%
