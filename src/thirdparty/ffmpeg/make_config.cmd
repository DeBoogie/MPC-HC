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

set BUILDDIR="%~dp0"

IF EXIST "..\..\..\build.user.bat" CALL "..\..\..\build.user.bat"
IF NOT DEFINED MPCHC_GIT     IF DEFINED GIT     (SET MPCHC_GIT=%GIT%)
IF NOT DEFINED MPCHC_MSYS    IF DEFINED MSYS    (SET MPCHC_MSYS=%MSYS%)       ELSE (GOTO MissingVar)

IF NOT EXIST "%MPCHC_MSYS%"    GOTO MissingVar

IF NOT DEFINED VCTOOLS IF DEFINED MPCHC_VS_PATH (
  SET "VCTOOLS=%MPCHC_VS_PATH%\Common7\Tools"
)

IF NOT DEFINED VCTOOLS (
  FOR /f "delims=" %%A IN ('"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -property installationPath -requires Microsoft.Component.MSBuild Microsoft.VisualStudio.Component.VC.ATLMFC Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -latest') DO SET "VCTOOLS=%%A\Common7\Tools"
)

IF NOT EXIST "%VCTOOLS%" (
  ECHO ERROR: "Visual Studio environment variable(s) is missing - possible it's not installed on your PC"
  GOTO END
)

:VarOk
SET PATH=%MPCHC_MSYS%\usr\bin;%MPCHC_MINGW64%\bin;%VCTOOLS%;%PATH%

call bash configure_ffmpeg-min.sh
exit /b

:MissingVar
ECHO Not all build dependencies were found.
ECHO.
ECHO See "..\..\..\..\..\docs\Compilation.md" for more information.
ENDLOCAL
EXIT /B 1
