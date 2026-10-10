@echo off
rem Plays this build. Needs the Voxel Tools 1.7 build of Godot (see the README).
rem Set CONTRACTOR_GODOT to its path if it isn't in the default place.
rem Extra arguments go to the game, e.g.  play.bat -- --host   or   play.bat -- --join 127.0.0.1
setlocal
set "GODOT=%CONTRACTOR_GODOT%"
if not defined GODOT set "GODOT=%USERPROFILE%\Downloads\GodotVoxel_1.7\godot.windows.editor.x86_64.exe"
if not exist "%GODOT%" (
	echo Could not find the Voxel Tools build of Godot at:
	echo   %GODOT%
	echo Set CONTRACTOR_GODOT to the full path of godot.windows.editor.x86_64.exe and try again.
	pause
	exit /b 1
)
start "" "%GODOT%" --main-pack "%~dp0contractor.pck" %*
