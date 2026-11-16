@echo off
cd /d "%~dp0"

if not exist "%~dp0make-installer.ps1" (
  echo.
  echo ERROR: make-installer.ps1 was not found next to build-me.bat.
  echo You started this file from inside the archive, so the other files were not unpacked.
  echo.
  echo What to do: close this window, unpack ALL files from the archive into a normal folder
  echo ^(right-click the archive - Extract All / Extract to folder^), then run build-me.bat
  echo from that new folder.
  echo.
  pause
  exit /b 1
)

echo === Dark Crown: automatic build ===
echo Missing programs - LibreWolf and Inno Setup - will be downloaded and installed.
echo If Windows asks for permission, click Yes.
echo.

if exist "%~dp0dist\DarkCrown-Setup.exe" del "%~dp0dist\DarkCrown-Setup.exe"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0make-installer.ps1"

echo.
if exist "%~dp0dist\DarkCrown-Setup.exe" goto ok
echo FAILED: the installer was not created. Read the messages above.
goto end

:ok
echo SUCCESS! The installer is on your Desktop and here:
echo %~dp0dist\DarkCrown-Setup.exe

:end
echo.
pause
