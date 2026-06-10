@echo off
REM ====================================================================
REM  Workstreams UI — one-click launcher
REM  Always: start the server if it isn't running, then open the URL.
REM  Self-locating (%~dp0 = this file's dir = the workstreams-ui root),
REM  so it carries no machine-specific path and works wherever the repo
REM  is cloned. Idempotent: if the server is already up it just opens the
REM  browser; it never double-starts.
REM ====================================================================
setlocal
title Workstreams UI launcher
set "UIDIR=%~dp0"
set "PORT=7733"
set "URL=http://127.0.0.1:%PORT%/"

REM --- 1. Already serving? Just open the browser. ---
curl -s -o nul --max-time 2 "%URL%" >nul 2>&1
if %ERRORLEVEL%==0 (
  echo [launcher] Workstreams UI already running on %PORT%. Opening %URL%
  start "" "%URL%"
  goto :eof
)

REM --- 2. Not running: verify node, then start the server detached+minimized. ---
where node >nul 2>&1
if not %ERRORLEVEL%==0 (
  echo [launcher] ERROR: node is not on PATH. Install Node.js, then re-run.
  pause
  exit /b 1
)
echo [launcher] Starting Workstreams UI server from "%UIDIR%" ...
start "Workstreams UI server (port %PORT%)" /min /d "%UIDIR%" cmd /c node server\server.js

REM --- 3. Poll for readiness (up to ~25s), then open the browser. ---
set /a tries=0
:wait
>nul timeout /t 1 /nobreak
curl -s -o nul --max-time 2 "%URL%" >nul 2>&1
if %ERRORLEVEL%==0 goto ready
set /a tries+=1
if %tries% LSS 25 goto wait

echo.
echo [launcher] ERROR: server did not respond on %PORT% within 25s.
echo            Start it manually to see the error:
echo              cd /d "%UIDIR%"  ^&^&  node server\server.js
pause
exit /b 1

:ready
echo [launcher] Workstreams UI is up. Opening %URL%
start "" "%URL%"
goto :eof
