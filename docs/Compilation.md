# Compilation instructions

## Part A: Preparing the Visual Studio environment

### Visual Studio 2022

1. Install Visual Studio (any edition will work fine). Select at minimum the following components:
    - C++ core features
    - IntelliCode
    - Windows Universal C Runtime
    - Windows Universal CRT SDK
    - C++ build tools (x86 & x64)
    - C++ ATL
    - C++ MFC
    - A current Windows 10/11 SDK

The modernized fork targets Windows 10 or newer. The legacy Windows 7/8 compatibility toolchain is intentionally not required.


## Part B: Install Python 3 (optional)

This is required for building the translation DLL files.

1. Install a current Python 3 release.
2. Run this command to install the required library:
    `python -m pip install --upgrade polib`


## Part C: Preparing the MSYS and GCC environment (optional)

This is required for building LAV Filters, which is used as the internal codecs by MPC-HC.

You can skip compilation of LAV Filters by selecting the "Release Lite"/"Debug Lite" build configuration
in the MPC-HC project file. This can be useful for making quick builds during development. The resulting
binary will be missing the internal filter functionality. So don't use this configuration for actual
releases.

1. Download MSYS2 from <http://www.msys2.org/>.
   If you are using a 64-bit Operating System, which you should be, get the 64-bit version.
2. Install it to for example **`C:\MSYS64\`**. The installation path should be specified in your **build.user.bat** configuration script that you will create later.
3. Run `msys2_shell.bat`
4. Install some additional required tools by running this command:
   ```text
   pacman -S make pkg-config diffutils
   ```
5. Then update all packages by running this command:
   ```text
   pacman -Syu
   ```
   When you are asked to restart MSYS, say yes. Start MSYS again and repeat the above command. Once everything is updated, you can close MSYS.
6. Download the latest mingw-w64-gcc package from <http://files.1f0.de/mingw/> and extract it to folder **`C:\MSYS64\mingw64`** (overwriting any existing files).
7. It is recommended to add **`C:\MSYS64\mingw64\bin`** and **`C:\MSYS64\usr\bin`** to the %PATH% environment variable.
   This allows you to run GCC and all other MSYS tools from the Windows command line.  
   Windows Control Panel > System > Advanced System Settings > Environment variables.  
   On Windows 10 you can access the legacy control panel by clicking on the Windows Start menu and typing `control.exe`.

## Part D: NASM

1. Download NASM from <https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/win64/nasm-2.16.03-win64.zip>
2. Put nasm.exe in a folder that is included in %PATH%. For example **`C:\Windows`**.

## Part E: Config file with paths

Create a file named **build.user.bat** in the source code folder of MPC-HC. It should have the following contents: (with paths adapted for your system!)

```bat
@ECHO OFF
REM [Required for LAVFilters] MSYS2/MinGW paths:
SET "MPCHC_MSYS=C:\MSYS64"
SET "MPCHC_MINGW32=C:\MSYS64\mingw64"
SET "MPCHC_MINGW64=C:\MSYS64\mingw64"
SET "MSYSTEM=MINGW32"
SET "MSYS2_PATH_TYPE=inherit"
REM [Optional] Specify GIT location if it is not already set in %PATH%
SET "MPCHC_GIT=C:\Program Files\Git"
REM [Optional] If you plan to modify the translations, install a current Python 3 and set the variable to its path
REM SET "MPCHC_PYTHON=C:\Path\To\Python"
REM [Optional] If you want to customize the Windows SDK version used, set this variable
SET "MPCHC_WINSDK_VER=10.0"
```

Notes:

* For Visual Studio, we will try to detect the VS installation path automatically. If that fails you need to specify the installation path yourself. For example:
  ```
  SET "MPCHC_VS_PATH=%ProgramFiles(x86)%\Microsoft Visual Studio\2022\Community\"
  ```
* If you installed the MSYS package in another directory then make sure that you have set the correct paths in your **build.user.bat** file.
* If you don't have Git installed then the build version will be inaccurate, the revision number will be a hard-coded as zero.


## Part F: Downloading the MPC-HC source

You need Git for downloading the source code.

Install **Git for Windows** from <https://git-for-windows.github.io/> and also **Git Extensions** from <http://gitextensions.github.io/>.
The build uses Git only to stamp the version number. It looks for `git.exe` in `MPCHC_GIT`
(see **build.user.bat** in Part F), on `%PATH%`, in the default Git for Windows install
locations, and finally in the copy that Visual Studio installs with its C++ workload, so no
particular install option is required and Git Bash is not used.

Use Git to clone MPC-HC's repository to **C:\mpc-hc** (or anywhere else you like).

1. Install Git
2. Run these commands:

    ```text
    git clone --recursive https://github.com/DeBoogie/MPC-HC.git
    ```

    or

    ```text
    git clone https://github.com/DeBoogie/MPC-HC.git
    git submodule update --init --recursive
    ```

    If a submodule update fails, try running:

    ```text
    git submodule foreach --recursive git fetch --tags
    ```

    then run the update again

    ```text
    git submodule update --init --recursive
    ```


## Build environment diagnostics

Before compiling, run the prerequisite checker:

```powershell
powershell -ExecutionPolicy Bypass -File tools\check-build-env.ps1
```

Use `-Full` to also validate the MSYS2/MinGW requirements for the internal LAV Filters build, and `-Packaging` to validate Inno Setup and 7-Zip. `build.bat` invokes the same checker automatically when prerequisite discovery fails, so missing Visual Studio components are reported individually instead of as a generic dependency error.

## External runtime bootstrap

MPC Video Renderer is an external runtime dependency rather than source code compiled by this repository. Its exact shipped binaries are declared in `dependencies\manifest.json`. Populate `distrib\mpcvr` with checksum-verified copies by running:

```powershell
powershell -ExecutionPolicy Bypass -File tools\bootstrap-dependencies.ps1
```

The manifest pins the official MPC-HC release archives, their SHA-256 digests, the archive entries to extract, and the expected MPC Video Renderer file version. A hash or file-version mismatch is a hard failure. The downloaded archives are cached under `build\dependency-cache` and are not committed.

## Part G: Compiling the MPC-HC source

The recommended local build is the x64 Release target:

```bat
build.bat Build x64 MPCHC Release
```

For a quick compile that skips the internal LAV Filters build, use:

```bat
build.bat Build x64 MPCHC Release Lite
```

The Lite configuration is for development checks only; release packages should include the internal filters. Run `build.bat help` for the complete set of switches.

You can also open **mpc-hc.sln** in Visual Studio 2022, select **x64** and **Release**, and build the solution normally.


## Reproducible local release

The supported release entry point is:

```powershell
powershell -ExecutionPolicy Bypass -File tools\release.ps1
```

It validates the full build and packaging environment, bootstraps pinned runtime dependencies, runs the modernization checks, builds the x64 Release packages, and copies the resulting installer/archive artifacts into `release-output` with a JSON manifest containing the source commit and SHA-256 digest for each artifact. `-Lite` is available for development-only packaging and intentionally does not represent a normal release.

## Part H: Building the installer

Install a current Inno Setup 6 release from <https://jrsoftware.org/isdl.php>.
Install everything and then go to **C:\mpc-hc\distrib**, open **mpc-hc_setup.iss** with Inno Setup,
read the first comments in the script and compile it.

### NOTES

* **build.bat** can build the installer by using the **installer** or the **packages** switch.
* Use Inno Setup's built-in IDE if you want to edit the iss file and don't change its encoding since it can break easily.
