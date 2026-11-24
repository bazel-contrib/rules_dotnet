@echo off
SETLOCAL ENABLEEXTENSIONS
SETLOCAL ENABLEDELAYEDEXPANSION

rem Usage of rlocation function:
rem        call :rlocation <runfile_path> <abs_path>
rem        The rlocation function maps the given <runfile_path> to its absolute
rem        path and stores the result in a variable named <abs_path>.
rem        This function fails if the <runfile_path> doesn't exist in manifest
rem        file.
:: Start of rlocation
goto :rlocation_end
:rlocation
if "%~2" equ "" (
  echo>&2 ERROR: Expected two arguments for rlocation function.
  exit 1
)
if "%RUNFILES_MANIFEST_ONLY%" neq "1" (
  set "%~2=%~1"
  exit /b 0
)
rem Inside blocks, paths are quoted or expanded late, so that a `)` in one
rem cannot end the block.
if exist "%RUNFILES_DIR%" (
  set "RUNFILES_MANIFEST_FILE=!RUNFILES_DIR!_manifest"
)
if "%RUNFILES_MANIFEST_FILE%" equ "" (
  set "RUNFILES_MANIFEST_FILE=%~f0.runfiles\MANIFEST"
)
if not exist "%RUNFILES_MANIFEST_FILE%" (
  set "RUNFILES_MANIFEST_FILE=%~f0.runfiles_manifest"
)
set "MF=%RUNFILES_MANIFEST_FILE:/=\%"
if not exist "%MF%" (
  echo>&2 ERROR: Manifest file !MF! does not exist.
  exit 1
)
set "runfile_path=%~1"
set abs_path=
rem A manifest line is the runfiles path, a space, then the absolute path, which
rem can contain spaces itself: split at the first space only.
for /F "tokens=1* usebackq" %%i in (`%SYSTEMROOT%\system32\findstr.exe /b /l /c:"!runfile_path! " "%MF%"`) do (
  set "abs_path=%%j"
)
if "!abs_path!" equ "" (
  echo>&2 ERROR: !runfile_path! not found in runfiles manifest
  exit 1
)
set "%~2=!abs_path!"
exit /b 0
:rlocation_end
:: End of rlocation

set RUNFILES_MANIFEST_ONLY=1
rem Unquoted: cmd keeps quotes as part of the value.
set DOTNET_MULTILEVEL_LOOKUP=false
set DOTNET_NOLOGO=1
set DOTNET_CLI_TELEMETRY_OPTOUT=1
rem The toolchain carries one runtime, so a tool built for an older major
rem release runs on it, as `dotnet tool install --allow-roll-forward` lets it.
if not defined DOTNET_ROLL_FORWARD set DOTNET_ROLL_FORWARD=Major
TEMPLATED_environment

call :rlocation "TEMPLATED_dotnet" dotnet_executable
for %%F in ("!dotnet_executable!") do set "DOTNET_ROOT=%%~dpF"

call :rlocation "TEMPLATED_executable" run_script

rem `bazel run` starts the tool in its runfiles tree, but a command-line tool
rem is meant to act on the directory it was invoked from. Unset during a build
rem action, where the tool's inputs are declared and the runfiles tree is right.
if defined BUILD_WORKING_DIRECTORY cd /d "%BUILD_WORKING_DIRECTORY%"

rem Delayed expansion would strip every `!` from the arguments.
setlocal DisableDelayedExpansion
"%dotnet_executable%" exec "%run_script%" %*
