@echo off
rem Starts Alcadeias with AutoHotkey v2, whatever .ahk files are set to open with.
set "AHK2=%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
if not exist "%AHK2%" set "AHK2=%ProgramFiles%\AutoHotkey\v2\AutoHotkey32.exe"
if not exist "%AHK2%" set "AHK2=%LOCALAPPDATA%\Programs\AutoHotkey\v2\AutoHotkey64.exe"
if not exist "%AHK2%" (
    echo AutoHotkey v2 was not found. Install it from https://www.autohotkey.com
    pause
    exit /b 1
)
start "" "%AHK2%" "%~dp0Alcadeias.ahk" %*
