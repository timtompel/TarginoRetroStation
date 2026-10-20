@echo off
start "Targino RetroStation" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0TarginoRetroStation\Launcher.ps1"
