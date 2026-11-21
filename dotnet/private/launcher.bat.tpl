@echo off
SETLOCAL ENABLEEXTENSIONS
SETLOCAL ENABLEDELAYEDEXPANSION

rem Usage of rlocation function:
rem        call :rlocation <runfile_path> <abs_path>
rem        The rlocation function maps the given <runfile_path> to its absolute
rem        path and stores the result in a variable named <abs_path>.
rem        This function fails if the <runfile_path> doesn't exist in mainifest
rem        file.
:: Start of rlocation
goto :rlocation_end
:rlocation
if "%~2" equ "" (
  echo>&2 ERROR: Expected two arguments for rlocation function.
  exit 1
)
if "%RUNFILES_MANIFEST_ONLY%" neq "1" (
  set %~2=%~1
  exit /b 0
)
if exist "%RUNFILES_DIR%" (
  set RUNFILES_MANIFEST_FILE=%RUNFILES_DIR%_manifest
)
if "%RUNFILES_MANIFEST_FILE%" equ "" (
  set RUNFILES_MANIFEST_FILE=%~f0.runfiles\MANIFEST
)
if not exist "%RUNFILES_MANIFEST_FILE%" (
  set RUNFILES_MANIFEST_FILE=%~f0.runfiles_manifest
)
set MF=%RUNFILES_MANIFEST_FILE:/=\%
if not exist "%MF%" (
  echo>&2 ERROR: Manifest file %MF% does not exist.
  exit 1
)
set runfile_path=%~1
for /F "tokens=2* usebackq" %%i in (`%SYSTEMROOT%\system32\findstr.exe /l /c:"!runfile_path! " "%MF%"`) do (
  set abs_path=%%i
)
if "!abs_path!" equ "" (
  echo>&2 ERROR: !runfile_path! not found in runfiles manifest
  exit 1
)
set %~2=!abs_path!
exit /b 0
:rlocation_end
:: End of rlocation

set RUNFILES_MANIFEST_ONLY=1
set DOTNET_MULTILEVEL_LOOKUP="false"
set DOTNET_NOLOGO="1"
set DOTNET_CLI_TELEMETRY_OPTOUT="1"
if not defined WINDIR if defined SystemRoot set WINDIR=%SystemRoot%
if not defined USERPROFILE if defined TEST_TMPDIR set USERPROFILE=%TEST_TMPDIR%
if not defined LOCALAPPDATA if defined TEST_TMPDIR set LOCALAPPDATA=%TEST_TMPDIR%
TEMPLATED_environment

set dotnet_executable="TEMPLATED_dotnet"
call :rlocation "TEMPLATED_dotnet" dotnet_executable
for %%F in (%dotnet_executable%) do set DOTNET_ROOT=%%~dpF

call :rlocation "TEMPLATED_executable" run_script

rem The deps.json lists each assembly by its runfiles path, so the host probes
rem the runfiles tree this launcher runs from. Its location is only known now:
rem an action that supports path mapping stages a tool's runfiles outside the
rem output directory of the tool's configuration. Bazel names the tree in
rem RUNFILES_DIR for a test and lays it out beside the launcher otherwise. With
rem only a runfiles manifest (--noenable_runfiles) there is no tree to probe.
set probing_path=
if defined RUNFILES_DIR set "probing_path=!RUNFILES_DIR:/=\!"
rem A trailing backslash would escape the quote that closes the argument.
if defined probing_path if "!probing_path:~-1!" equ "\" set "probing_path=!probing_path:~0,-1!"
if defined probing_path if not exist "!probing_path!\" set probing_path=
if not defined probing_path if exist "%~f0.runfiles\" set "probing_path=%~f0.runfiles"
set probing_option=
if defined probing_path set probing_option=--additionalprobingpath "!probing_path!"

set args=%*
if /i "!run_script:~-4!"==".exe" (
  "!run_script!" !args!
) else (
  "!dotnet_executable!" exec !probing_option! "!run_script!" !args!
)
