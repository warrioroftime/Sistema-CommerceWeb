@echo off
title GestorFlex
echo.
echo   ╔══════════════════════════════════════╗
echo   ║        GestorFlex - Iniciando        ║
echo   ╚══════════════════════════════════════╝
echo.

:: Detecta diretório do script
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"

:: Backend
start "GestorFlex Backend" /min cmd /c "cd /d "%ROOT%\gestorflex\backend" && node src/app.js"

echo   Aguardando backend...
timeout /t 4 /nobreak > nul

:: Frontend
start "GestorFlex Frontend" /min cmd /c "cd /d "%ROOT%\gestorflex\frontend" && node serve.js"

echo   Aguardando frontend...
timeout /t 3 /nobreak > nul

:: Abre o navegador
start http://localhost:5500

echo.
echo   [OK] Sistema iniciado!
echo.
echo   Acesse: http://localhost:5500
echo.
echo   Para encerrar os servidores, execute parar.bat
echo.
pause
