@echo off
setlocal
set "PICTOUR_ENGINE=%~dp0..\Godot\4.7.2\Godot_v4.7.2-stable_win64.exe"
if defined GODOT_EXE set "PICTOUR_ENGINE=%GODOT_EXE%"
if not exist "%PICTOUR_ENGINE%" (
    echo Godot 4.7.2 was not found. Set GODOT_EXE to your Godot executable.
    pause
    exit /b 1
)
if /I "%~1"=="no-vsync" goto no_vsync
if /I "%~1"=="vsync" goto vsync
start "" "%PICTOUR_ENGINE%" --path "%~dp0." --windowed --resolution 1280x720 --max-fps 240
goto finished
:no_vsync
start "" "%PICTOUR_ENGINE%" --path "%~dp0." --windowed --resolution 1280x720 --max-fps 240 --disable-vsync
goto finished
:vsync
start "" "%PICTOUR_ENGINE%" --path "%~dp0." res://Tests/VSync_Comparison.tscn --windowed --resolution 1280x720 --max-fps 240
:finished
endlocal
