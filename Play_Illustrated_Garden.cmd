@echo off
setlocal
set "PICTOUR_ENGINE=%~dp0..\Godot\4.7.2\Godot_v4.7.2-stable_win64.exe"
if defined GODOT_EXE set "PICTOUR_ENGINE=%GODOT_EXE%"
if not exist "%PICTOUR_ENGINE%" (
    echo Godot 4.7.2 was not found. Set GODOT_EXE to your Godot executable.
    pause
    exit /b 1
)
start "" "%PICTOUR_ENGINE%" --path "%~dp0." res://Illustrated_Garden_Game.tscn --windowed --resolution 1280x720 --max-fps 240 --disable-vsync
endlocal
