@echo off
SETLOCAL ENABLEEXTENSIONS
SETLOCAL ENABLEDELAYEDEXPANSION

::
: This wrapper script is used because the C#/F# compilers both embed absolute paths
: into their outputs and those paths are not deterministic. The compilers also
: allow overriding these paths using pathmaps. Since the paths can not be known
: at analysis time we need to override them at execution time.
::

set DOTNET_EXECUTABLE=%1
set COMPILER=%2
for %%F in ("%COMPILER%") do set COMPILER_BASENAME=%%~nxF

set PATHMAP_FLAG=-pathmap

:: Needed because unfortunately the F# compiler uses a different flag name
if %COMPILER_BASENAME% == fsc.dll set PATHMAP_FLAG=--pathmap

set PATHMAP=%PATHMAP_FLAG%:"%cd%=."

shift
set args=%1
:loop
shift
if [%1]==[] goto afterloop
set args=%args% %1
set "arg=%~1"
if "!arg:~0,1!"=="@" set "PARAMS=!arg:~1!"
goto loop
:afterloop

rem Escape \ and * in args before passsing it with double quote
if defined args (
  set args=!args:\=\\\\!
  set args=!args:"=\"!
)

rem fsc sizes the PE debug directory from the absolute pdb path before the
rem pathmap applies, so the pdb path needs a root whose length does not follow
rem the exec root. Bazel points TEMP into the output base, so the junction
rem lives under %SystemRoot%\Temp with a fixed-length name instead.
set PDB_ARG=
set LINK_DIR=
if not "%COMPILER_BASENAME%" == "fsc.dll" goto run
if not defined PARAMS goto run
set TRIES=0
:mkroot
set /a TRIES+=1
if !TRIES! gtr 20 (
  echo compiler_wrapper: cannot create a directory under %SystemRoot%\Temp 1>&2
  exit /b 1
)
rem cmd seeds RANDOM per second; the centiseconds keep same-second actions apart.
set "N1=0000!RANDOM!"
set "N2=0000!RANDOM!"
set "LINK_DIR=%SystemRoot%\Temp\dx_fsc.!TIME:~-2!!N1:~-5!!N2:~-5!"
mkdir "!LINK_DIR!" 2>nul || goto mkroot
mklink /J "!LINK_DIR!\r" "%cd%" >nul || (
  rmdir "!LINK_DIR!"
  exit /b 1
)
set "ROOT=!LINK_DIR!\r"
for /f "usebackq delims=" %%L in ("!PARAMS!") do (
  set "line=%%L"
  if "!line:~0,6!"=="--pdb:" if not "!line:~7,1!"==":" (
    set "rel=!line:~6!"
    set PDB_ARG="--pdb:!ROOT!\!rel:/=\!"
  )
)
set PATHMAP=%PATHMAP_FLAG%:"%cd%=.,!ROOT!=."

:run
"%DOTNET_EXECUTABLE%" %args% !PDB_ARG! %PATHMAP%
set EXIT_CODE=!ERRORLEVEL!
if defined LINK_DIR (
  rmdir "!LINK_DIR!\r"
  rmdir "!LINK_DIR!"
)
exit /b !EXIT_CODE!
