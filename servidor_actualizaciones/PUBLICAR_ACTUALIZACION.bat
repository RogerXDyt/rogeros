@echo off
title Publicar actualizacion de RogerOS
echo Empaqueta los cambios de RogerOS Linux\src, sube la version, la firma
echo y la sube a Cloudflare. Despues el PC puede estar apagado: los RogerOS
echo la recibiran igualmente al pulsar Actualizar.
echo.
wsl -d Debian -u root -- bash "/mnt/c/Users/Administrador.RogerPCGamer/Desktop/RogerOS Linux/src/publicar.sh"
if errorlevel 1 goto fin
echo.
python "%~dp0subir_nube.py"
:fin
echo.
pause
