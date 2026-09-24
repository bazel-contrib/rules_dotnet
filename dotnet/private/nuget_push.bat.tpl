@echo off
SETLOCAL ENABLEEXTENSIONS
SETLOCAL ENABLEDELAYEDEXPANSION

rem Pushes the packages of a `nuget_push` target with `dotnet nuget push`.
rem See nuget_push.sh.tpl for what the arguments and environment mean. On
rem Windows an explicit source or key has to be spelled `--source <feed>`
rem and `--api-key <key>`, as separate words.

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
set DOTNET_MULTILEVEL_LOOKUP=false
set DOTNET_NOLOGO=1
set DOTNET_CLI_TELEMETRY_OPTOUT=1
set DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
set DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE=1
rem USERPROFILE and DOTNET_CLI_HOME stay as they are, so the user's NuGet.Config applies.

call :rlocation "TEMPLATED_dotnet" dotnet_executable
for %%F in ("!dotnet_executable!") do set DOTNET_ROOT=%%~dpF

set source_from_target=TEMPLATED_source
set config_file=TEMPLATED_config_file

set has_source=0
set has_api_key=0
set has_symbol_api_key=0
for %%a in (%*) do (
  if /I "%%~a"=="--source" set has_source=1
  if /I "%%~a"=="-s" set has_source=1
  if /I "%%~a"=="--api-key" set has_api_key=1
  if /I "%%~a"=="-k" set has_api_key=1
  if /I "%%~a"=="--symbol-api-key" set has_symbol_api_key=1
  if /I "%%~a"=="-sk" set has_symbol_api_key=1
)

set args=
if "!has_source!"=="0" (
  if "!source_from_target!"=="" (
    echo>&2 nuget_push: no package source. Set `source` on the target or pass --source ^<feed^>.
    exit /b 1
  )
  set args=--source "!source_from_target!"
)
if "!has_api_key!"=="0" if defined NUGET_API_KEY set args=!args! --api-key "!NUGET_API_KEY!"
if "!has_symbol_api_key!"=="0" if defined NUGET_SYMBOL_API_KEY set args=!args! --symbol-api-key "!NUGET_SYMBOL_API_KEY!"
if not "!config_file!"=="" (
  call :rlocation "!config_file!" config_path
  set args=!args! --configfile "!config_path!"
)

rem Resolved before changing directory; the results are absolute.
set count=0
for %%p in (TEMPLATED_packages) do (
  call :rlocation "%%~p" package_!count!
  set /a count+=1
)

if defined BUILD_WORKING_DIRECTORY cd /d "%BUILD_WORKING_DIRECTORY%"

set /a last=count-1
for /L %%i in (0,1,!last!) do (
  if defined RULES_DOTNET_NUGET_PUSH_DRY_RUN (
    echo "!dotnet_executable!" nuget push "!package_%%i!" TEMPLATED_push_args !args! %*
  ) else (
    "!dotnet_executable!" nuget push "!package_%%i!" TEMPLATED_push_args !args! %*
    if errorlevel 1 exit /b !errorlevel!
  )
)
exit /b 0
