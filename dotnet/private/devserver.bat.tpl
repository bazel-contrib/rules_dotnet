@echo off
SETLOCAL ENABLEEXTENSIONS
SETLOCAL ENABLEDELAYEDEXPANSION

rem Usage of rlocation function:
rem        call :rlocation <runfile_path> <abs_path>
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

set DOTNET_MULTILEVEL_LOOKUP="false"
set DOTNET_NOLOGO="1"
set DOTNET_CLI_TELEMETRY_OPTOUT="1"

call :rlocation "TEMPLATED_dotnet" dotnet_executable
for %%F in (%dotnet_executable%) do set DOTNET_ROOT=%%~dpF

call :rlocation "TEMPLATED_devserver" devserver
call :rlocation "TEMPLATED_application" application

rem The server resolves `wwwroot` against the content root, and would otherwise
rem take that from the working directory. The served directory need not sit
rem beside the application, so the content root is derived from it.
call :rlocation "TEMPLATED_wwwroot" wwwroot
for %%F in ("!wwwroot!") do set contentroot=%%~dpF

"!dotnet_executable!" exec "!devserver!" --applicationpath "!application!" --contentroot "!contentroot!" %*
