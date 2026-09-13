@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-user-reset-test.ps1"
if errorlevel 1 (
  echo.
  echo User reset test failed.
)
pause
