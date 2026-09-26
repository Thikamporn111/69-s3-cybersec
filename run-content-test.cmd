@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-content-test.ps1"
if errorlevel 1 (
  echo.
  echo Content test failed.
)
pause
