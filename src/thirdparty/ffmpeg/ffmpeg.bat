@ECHO OFF
REM (C) 2009-2017 see Authors.txt
REM
REM This file is part of MPC-HC.
REM
REM MPC-HC is free software; you can redistribute it and/or modify
REM it under the terms of the GNU General Public License as published by
REM the Free Software Foundation; either version 3 of the License, or
REM (at your option) any later version.
REM
REM MPC-HC is distributed in the hope that it will be useful,
REM but WITHOUT ANY WARRANTY; without even the implied warranty of
REM MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
REM GNU General Public License for more details.
REM
REM You should have received a copy of the GNU General Public License
REM along with this program.  If not, see <http://www.gnu.org/licenses/>.

setlocal enabledelayedexpansion

IF /I "%~1"=="help"   GOTO SHOWHELP
IF /I "%~1"=="/help"  GOTO SHOWHELP
IF /I "%~1"=="-help"  GOTO SHOWHELP
IF /I "%~1"=="--help" GOTO SHOWHELP
IF /I "%~1"=="/?"     GOTO SHOWHELP

PUSHD "%~dp0"

IF EXIST "..\..\..\build.user.bat" CALL "..\..\..\build.user.bat"

IF NOT DEFINED MPCHC_GIT     IF DEFINED GIT     (SET MPCHC_GIT=%GIT%)
IF NOT DEFINED MPCHC_MSYS    IF DEFINED MSYS    (SET MPCHC_MSYS=%MSYS%)       ELSE (GOTO MissingVar)

IF NOT EXIST "%MPCHC_MSYS%"    GOTO MissingVar


IF EXIST "%~dp0..\environments.bat" CALL "%~dp0..\environments.bat"

:VarOk
SET PATH=%MPCHC_MSYS%\usr\bin;%MPCHC_MINGW64%\bin;%PATH%

SET "BUILDTYPE=build"

SET ARG=%*
SET ARG=%ARG:/=%
SET ARG=%ARG:-=%

FOR %%A IN (%ARG%) DO (
	IF /I "%%A" == "clean" SET "BUILDTYPE=clean"
	IF /I "%%A" == "rebuild" SET "BUILDTYPE=rebuild"
	IF /I "%%A" == "64" SET "BIT=64BIT=yes"
	IF /I "%%A" == "Debug" SET "DEBUG=DEBUG=yes"
)

IF /I "%BUILDTYPE%" == "rebuild" (
  SET "BUILDTYPE=clean"
  CALL :SubMake clean
  SET "BUILDTYPE=build"
  CALL :SubMake
  EXIT /B !MAKE_RETURN!
) ELSE (
  CALL :SubMake
  EXIT /B !MAKE_RETURN!
)

:SubMake
SETLOCAL
IF "%BUILDTYPE%" == "clean" (
  SET JOBS=1
) ELSE (
  SET "BUILDTYPE="
  IF DEFINED NUMBER_OF_PROCESSORS (
    SET JOBS=%NUMBER_OF_PROCESSORS%
  ) ELSE (
    SET JOBS=4
  )
)

rem SET JOBS=1

set MAK="%~dp0\ffmpeg-msvc.mak"
pushd ..\LAVFilters\src\ffmpeg\
call make.exe -f %MAK% %BUILDTYPE% -j%JOBS% %BIT% %DEBUG%
ENDLOCAL
IF %ERRORLEVEL% NEQ 0 (
  SET MAKE_RETURN=%ERRORLEVEL%
)
popd
EXIT /B

:SHOWHELP
TITLE "%~nx0 %1"
ECHO. & ECHO.
ECHO Usage:   %~nx0 [32^|64] [Clean^|Build^|Rebuild] [Debug]
ECHO.
ECHO Notes:   The arguments are not case sensitive.
ECHO. & ECHO.
ECHO Executing "%~nx0" will use the defaults: "%~nx0"
ECHO.
EXIT /B

:MissingVar
ECHO Not all build dependencies were found.
ECHO.
ECHO See "..\..\..\..\..\docs\Compilation.md" for more information.
ENDLOCAL
EXIT /B 1
