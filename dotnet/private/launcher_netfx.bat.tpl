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

rem A .NET Framework executable needs no .NET host.

set RUNFILES_MANIFEST_ONLY=1

rem `bazel test` leaves these unset, and .NET Framework reads them.
if not defined WINDIR if defined SystemRoot set "WINDIR=%SystemRoot%"
if not defined USERPROFILE if defined TEST_TMPDIR set "USERPROFILE=!TEST_TMPDIR:/=\!"
if not defined LOCALAPPDATA if defined TEST_TMPDIR set "LOCALAPPDATA=!TEST_TMPDIR:/=\!"

call :rlocation "TEMPLATED_executable" executable

rem Delayed expansion would strip every `!` from the arguments.
setlocal DisableDelayedExpansion
"%executable%" %*
