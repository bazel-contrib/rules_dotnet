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
goto loop
:afterloop

rem Escape \ and * in args before passsing it with double quote
if defined args (
  set args=!args:\=\\\\!
  set args=!args:"=\"!
)

set ANALYZER_CONFIG_ARG=
if defined RULES_DOTNET_ANALYZER_CONFIG_TEMPLATE (
  set ANALYZER_CONFIG=%TEMP%\rules-dotnet-analyzer-config-%RANDOM%-%RANDOM%.globalconfig
  set RESPONSE_FILE=%TEMP%\rules-dotnet-response-%RANDOM%-%RANDOM%.rsp
  set EXEC_ROOT=%cd:\=/%
  for /f "usebackq delims=" %%L in ("!RULES_DOTNET_ANALYZER_CONFIG_TEMPLATE!") do (
    set LINE=%%L
    for /f "delims=" %%R in ("!EXEC_ROOT!") do echo(!LINE:__RULES_DOTNET_EXEC_ROOT__=%%R!>>"!ANALYZER_CONFIG!"
  )
  set RESPONSE_FILE_INPUT=%3
  set RESPONSE_FILE_INPUT=!RESPONSE_FILE_INPUT:~1!
  for /f "usebackq delims=" %%L in ("!RESPONSE_FILE_INPUT!") do (
    set LINE=%%L
    for /f "delims=" %%R in ("!EXEC_ROOT!") do echo(!LINE:__RULES_DOTNET_EXEC_ROOT__=%%R!>>"!RESPONSE_FILE!"
  )
  set ANALYZER_CONFIG_ARG=/analyzerconfig:"!ANALYZER_CONFIG!"
)

if defined RESPONSE_FILE (
  "%DOTNET_EXECUTABLE%" "%COMPILER%" @"!RESPONSE_FILE!" %PATHMAP% !ANALYZER_CONFIG_ARG!
) else (
  "%DOTNET_EXECUTABLE%" %args% %PATHMAP%
)
set EXIT_CODE=%ERRORLEVEL%
if defined ANALYZER_CONFIG del /q "!ANALYZER_CONFIG!"
if defined RESPONSE_FILE del /q "!RESPONSE_FILE!"
exit /b %EXIT_CODE%
