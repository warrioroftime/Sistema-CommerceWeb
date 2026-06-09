@echo off
title Parando GestorFlex
echo.
echo   Encerrando servidores GestorFlex...
echo.

taskkill /FI "WINDOWTITLE eq GestorFlex Backend*" /F /T > nul 2>&1
taskkill /FI "WINDOWTITLE eq GestorFlex Frontend*" /F /T > nul 2>&1

echo   [OK] Servidores encerrados.
echo.
timeout /t 2 /nobreak > nul
