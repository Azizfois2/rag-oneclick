@echo off
rem ===========================================================================
rem  Oracle 26ai Agentic RAG - one-click setup for Windows
rem
rem  Double-click this file. It checks and repairs, in order:
rem     Docker -> Oracle container -> waiting for the database -> Python ->
rem     packages -> .env + API key -> tablespace/user/grants -> vector memory ->
rem     database self-test -> Jupyter kernel -> opens the notebook
rem
rem  If something cannot be fixed automatically it stops and tells you exactly
rem  what to do. Everything it does is idempotent: running it again is safe.
rem
rem  Switches:
rem     START.bat /check    set everything up and verify, do not open the notebook
rem     START.bat /run      also execute the notebook once before opening it
rem     START.bat /check /nopause    unattended mode for scripting
rem ===========================================================================
setlocal EnableExtensions EnableDelayedExpansion
title Oracle 26ai Agentic RAG - setup
cd /d "%~dp0"

rem ------------------------------------------------------------- settings
set "PKG=%~dp0"
if "%PKG:~-1%"=="\" set "PKG=%PKG:~0,-1%"
set "TOOLS=%PKG%\tools"
set "NOTEBOOK=%PKG%\notebook\oracle_agentic_rag_hybrid_search.ipynb"
set "ENVF=%PKG%\.env"
set "LOGDIR=%PKG%\logs"
set "VENV=%USERPROFILE%\rag-venv"
if defined RAG_VENV set "VENV=%RAG_VENV%"
set "PY=%VENV%\Scripts\python.exe"
set "CONTAINER=oracle-26ai-free"
set "IMAGE=container-registry.oracle.com/database/free:latest-lite"
set "SYS_PWD=OraclePwd123"
set "APP_USER=vector"
set "APP_PWD=vector"
set "DSN=localhost:1521/FREEPDB1"
set "PORT=8888"
set "TOKEN=rag"

set "MODE=normal"
if /I "%~1"=="/check" set "MODE=check"
if /I "%~1"=="/run" set "MODE=autorun"
set "NOPAUSE=0"
if /I "%~1"=="/nopause" set "NOPAUSE=1"
if /I "%~2"=="/nopause" set "NOPAUSE=1"
set "WARN=0"

if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1
for /f "usebackq delims=" %%t in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"`) do set "STAMP=%%t"
set "LOG=%LOGDIR%\setup-%STAMP%.log"
set "TMP=%TEMP%\rag_setup_%STAMP%.tmp"
echo Oracle 26ai Agentic RAG setup> "%LOG%"
echo started %DATE% %TIME%>> "%LOG%"
echo mode=%MODE% venv=%VENV%>> "%LOG%"

echo ==================================================================
echo   Oracle 26ai Agentic RAG - one-click setup
echo   log file: %LOG%
echo ==================================================================
echo.

rem ============================================================ 1. package
echo [1/10] Checking the package files ...
if not exist "%TOOLS%\db_setup.py" goto :err_package
if not exist "%TOOLS%\db_verify.py" goto :err_package
if not exist "%TOOLS%\set_vector_memory.py" goto :err_package
if not exist "%TOOLS%\doctor.py" goto :err_package
if not exist "%TOOLS%\check_key.py" goto :err_package
if not exist "%NOTEBOOK%" goto :err_package
echo   OK   package files present

rem ============================================================ 2. docker
echo.
echo [2/10] Checking Docker ...
where docker >nul 2>&1
if errorlevel 1 goto :err_nodocker
docker info >"%TMP%" 2>&1
if errorlevel 1 goto :err_docker_down
type "%TMP%">>"%LOG%"
echo   OK   Docker engine is running

rem ============================================================ 3. container
echo.
echo [3/10] Preparing the Oracle container ...
docker inspect "%CONTAINER%" >nul 2>&1
if errorlevel 1 goto :create_container

set "CSTATE=unknown"
for /f "usebackq delims=" %%s in (`docker inspect -f "{{.State.Status}}" %CONTAINER% 2^>nul`) do set "CSTATE=%%s"
if /I "!CSTATE!"=="running" goto :container_ok
echo   container exists but is "!CSTATE!" - starting it ...
call :RUN docker start %CONTAINER%
if errorlevel 1 goto :err_start
:container_ok
echo   OK   container %CONTAINER% is running
goto :wait_db

:create_container
docker ps --format "{{.Names}} {{.Ports}}" >"%TMP%" 2>&1
findstr /C:":1521->" "%TMP%" >nul
if not errorlevel 1 goto :err_port
echo   First run: creating the container. The image is about 1 GB, so this
echo   can take several minutes on a slow connection.
call :RUN docker run -d --name %CONTAINER% --restart unless-stopped -p 1521:1521 -e ORACLE_PWD=%SYS_PWD% %IMAGE%
if errorlevel 1 goto :err_create
echo   OK   container created

rem ============================================================ 4. wait for db
:wait_db
echo.
echo [4/10] Waiting for the database to accept connections ...
echo   First start needs 3-5 minutes. Later starts about 1 minute.
call :wait_for_db
if errorlevel 1 goto :err_db_timeout
echo   OK   database is healthy

rem ============================================================ 5. python
echo.
echo [5/10] Locating Python and the virtual environment ...
set "PYCMD="
py -3.11 -c "import sys" >nul 2>&1
if not errorlevel 1 set "PYCMD=py -3.11"
if defined PYCMD goto :py_found
py -3.12 -c "import sys" >nul 2>&1
if not errorlevel 1 set "PYCMD=py -3.12"
if defined PYCMD goto :py_found
py -3.10 -c "import sys" >nul 2>&1
if not errorlevel 1 set "PYCMD=py -3.10"
if defined PYCMD goto :py_found
python -c "import sys; assert (3,10)<=sys.version_info[:2]<=(3,12)" >nul 2>&1
if not errorlevel 1 set "PYCMD=python"
if defined PYCMD goto :py_found
rem Last resort: the usual install locations, in case the py launcher and PATH
rem are both missing or point somewhere unusable.
for %%p in ("%LOCALAPPDATA%\Programs\Python\Python311\python.exe" "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" "%LOCALAPPDATA%\Programs\Python\Python310\python.exe" "%ProgramFiles%\Python311\python.exe" "%ProgramFiles%\Python312\python.exe" "C:\Python311\python.exe") do if not defined PYCMD if exist "%%~p" set "PYCMD="%%~p""
if not defined PYCMD goto :err_nopython
:py_found
echo   OK   using %PYCMD%

if not exist "%PY%" goto :make_venv
"%PY%" -c "import sys; assert (3,10)<=sys.version_info[:2]<=(3,12)" >nul 2>&1
if errorlevel 1 goto :recreate_venv
echo   OK   virtual environment exists: %VENV%
goto :venv_ok

:recreate_venv
echo   The existing virtual environment uses an unsupported Python - rebuilding it.
rmdir /s /q "%VENV%" >nul 2>&1

:make_venv
echo   Creating a virtual environment in %VENV% ...
call :RUN %PYCMD% -m venv "%VENV%"
if errorlevel 1 goto :err_venv
if not exist "%PY%" goto :err_venv
echo   OK   virtual environment created

rem ============================================================ 6. packages
:venv_ok
echo.
echo [6/10] Checking Python packages ...
if not exist "%VENV%\.rag-ready" goto :do_install
call :RUN "%PY%" "%TOOLS%\doctor.py" --quick
if errorlevel 1 goto :do_install
echo   OK   packages present
goto :pkgs_ok

:do_install
echo   Installing packages. This is the long step: 5-15 minutes, mostly torch.
echo   You can leave it alone, it prints progress below.
call :RUN "%PY%" -m pip install --upgrade pip
call :RUN "%PY%" -m pip install -r "%PKG%\requirements.txt"
if errorlevel 1 goto :err_pip
> "%VENV%\.rag-ready" echo ok
call :RUN "%PY%" "%TOOLS%\doctor.py"
if errorlevel 1 goto :err_imports

:pkgs_ok
rem ============================================================ 7. env + key
echo.
echo [7/10] Checking .env and the Gemini API key ...
if exist "%ENVF%" goto :env_ok
copy /y "%PKG%\.env.template" "%ENVF%" >nul
echo   Created .env from the template.
:env_ok
call :RUN "%PY%" "%TOOLS%\check_key.py" "%ENVF%"
if not errorlevel 1 goto :key_ok
if "%MODE%"=="check" goto :key_warn
echo.
echo   No Gemini API key yet.
echo     1. A free key is available at: https://aistudio.google.com/apikey
echo     2. Notepad will open. Paste the key right after  GEMINI_API_KEY=
echo     3. Save the file, close Notepad, and this setup continues.
echo.
start "" "https://aistudio.google.com/apikey"
start /wait notepad "%ENVF%"
call :RUN "%PY%" "%TOOLS%\check_key.py" "%ENVF%"
if not errorlevel 1 goto :key_ok
:key_warn
echo   WARNING  No usable key yet. Everything else gets set up; only the agent
echo            cell needs it, so you can add it to .env later and re-run that cell.
set "WARN=1"
:key_ok

rem ============================================================ 8. db objects
echo.
echo [8/10] Preparing tablespace, application user and grants ...
call :RUN "%PY%" "%TOOLS%\db_setup.py" --dsn "%DSN%" --sys-password "%SYS_PWD%" --user "%APP_USER%" --password "%APP_PWD%"
if errorlevel 1 goto :err_dbsetup

rem ============================================================ 9. vector memory
echo.
echo [9/10] Checking the vector memory area needed for HNSW indexes ...
call :RUN "%PY%" "%TOOLS%\set_vector_memory.py" --dsn "%DSN%" --sys-password "%SYS_PWD%"
set "VMRC=%ERRORLEVEL%"
if "%VMRC%"=="10" goto :vm_restart
if "%VMRC%"=="3" goto :err_dbsetup
if not "%VMRC%"=="0" goto :err_vectormem
goto :vm_ok

:vm_restart
echo   Restarting the container so the setting takes effect ...
call :RUN docker restart %CONTAINER%
if errorlevel 1 goto :err_restart
echo   Waiting for the database to come back ...
call :wait_for_db
if errorlevel 1 goto :err_db_timeout
:vm_ok

rem ============================================================ 10. verify
echo.
echo [10/10] Verifying the database and registering the Jupyter kernel ...
call :RUN "%PY%" "%TOOLS%\db_verify.py" --dsn "%DSN%" --user "%APP_USER%" --password "%APP_PWD%"
set "DBRC=%ERRORLEVEL%"
if "%DBRC%"=="5" goto :err_vectormem
if not "%DBRC%"=="0" goto :err_dbverify

call :RUN "%PY%" -m ipykernel install --user --name rag --display-name "Python (rag)"
if errorlevel 1 goto :err_kernel

rem ============================================================ summary
:ready
echo.
echo ==================================================================
echo   SETUP COMPLETE
echo ==================================================================
echo   database : Oracle 26ai Free in Docker [%CONTAINER%]
echo   python   : %VENV%
echo   kernel   : Python (rag)
echo   notebook : %NOTEBOOK%
echo   log      : %LOG%
if "%WARN%"=="1" echo   WARNING  : no Gemini API key yet, see above
echo.

if "%MODE%"=="check" goto :end_check
if "%MODE%"=="autorun" goto :auto_run
goto :launch

:auto_run
echo   Running the notebook once, unattended. This takes a few minutes.
call :RUN "%PY%" "%TOOLS%\run_notebook.py" --notebook "%NOTEBOOK%" --kernel rag
if errorlevel 1 echo   WARNING  the notebook did not finish cleanly. It still opens; see the cell list above.

:launch
rem A server that is still starting up answers nothing, so probe a few times
rem before deciding to start a second one on another port.
set "ALIVE=0"
set "PROBES=0"
:probe_loop
powershell -NoProfile -Command "try{Invoke-WebRequest 'http://127.0.0.1:%PORT%/api/status?token=%TOKEN%' -UseBasicParsing -TimeoutSec 4|Out-Null;exit 0}catch{exit 1}" >nul 2>&1
if not errorlevel 1 set "ALIVE=1"
if "!ALIVE!"=="1" goto :probe_done
set /a PROBES+=1
if !PROBES! GEQ 3 goto :probe_done
ping -n 3 127.0.0.1 >nul 2>&1
goto :probe_loop
:probe_done
if "!ALIVE!"=="1" goto :open_existing

echo   Starting JupyterLab ...
echo     address : http://localhost:%PORT%/lab?token=%TOKEN%
echo     KEEP THIS WINDOW OPEN while you work - closing it stops JupyterLab.
echo     Your database and all data stay safe either way.
echo.
"%VENV%\Scripts\jupyter-lab.exe" --IdentityProvider.token=%TOKEN% --ServerApp.password= --ServerApp.root_dir="%PKG%\notebook" --ServerApp.port=%PORT% --ServerApp.port_retries=20 "%NOTEBOOK%"
echo.
echo   JupyterLab stopped. Your data is safe.
call :maybe_pause
exit /b 0

:open_existing
echo   JupyterLab is already running - opening it in your browser.
start "" "http://localhost:%PORT%/lab/tree/oracle_agentic_rag_hybrid_search.ipynb?token=%TOKEN%"
echo   Done.
exit /b 0

:end_check
echo   /check requested: not opening the notebook.
echo   Everything above was verified.
call :maybe_pause
exit /b 0

rem ============================================================ errors
:err_package
echo.
echo   ==============================================================
echo    STOPPED: package files are missing
echo   ==============================================================
echo    START.bat expects the folders "tools" and "notebook" next to it.
echo    Extract the whole ZIP again - copying START.bat on its own is not enough.
goto :halt

:err_nodocker
echo.
echo   ==============================================================
echo    STOPPED: Docker is not installed, or "docker" is not on PATH
echo   ==============================================================
echo    1. Install Docker Desktop for Windows:
echo         https://www.docker.com/products/docker-desktop/
echo    2. Reboot Windows after installing, so PATH is updated
echo    3. Run START.bat again
echo    Check with:  docker --version
goto :halt

:err_docker_down
echo.
echo   ==============================================================
echo    STOPPED: Docker is installed but its engine is not running
echo   ==============================================================
echo    Docker said:
type "%TMP%"
echo.
echo    Fix:
echo      - Start "Docker Desktop" from the Start menu
echo      - Wait until it reports "Engine running" and the whale icon is still
echo      - If it mentions access denied or permission denied: add your Windows
echo        account to the group "docker-users", then sign out and back in
echo      - Run START.bat again
goto :halt

:err_port
echo.
echo   ==============================================================
echo    STOPPED: port 1521 is already taken by another container
echo   ==============================================================
echo    It publishes port 1521:
findstr /C:":1521->" "%TMP%"
echo.
echo    Stop or remove that container, then run START.bat again:
echo      docker ps
echo      docker stop CONTAINER_NAME
goto :halt

:err_create
echo.
echo   ==============================================================
echo    STOPPED: could not create the Oracle container
echo   ==============================================================
echo    Usual causes: no internet, a proxy or firewall blocking
echo    container-registry.oracle.com, or too little free disk space.
echo    The image needs about 1 GB, the data another 2-3 GB.
echo    Retry by hand to see the full error:
echo      docker run -d --name %CONTAINER% -p 1521:1521 -e ORACLE_PWD=%SYS_PWD% %IMAGE%
goto :halt

:err_start
echo.
echo   ==============================================================
echo    STOPPED: could not start the container
echo   ==============================================================
echo    Try by hand:   docker start %CONTAINER%
echo    Or look at:    docker logs --tail 50 %CONTAINER%
goto :halt

:err_restart
echo.
echo   ==============================================================
echo    STOPPED: could not restart the container
echo   ==============================================================
echo    Try by hand:   docker restart %CONTAINER%
goto :halt

:err_db_timeout
echo.
echo   ==============================================================
echo    STOPPED: the database did not become healthy in 20 minutes
echo   ==============================================================
echo    Usual causes:
echo      - Docker Desktop has less than 4 GB of memory assigned.
echo        Docker Desktop - Settings - Resources - Memory, then Apply and restart
echo      - not enough free disk space on C:
echo      - the container crashed while starting
echo    Look at the end of its log:
echo      docker logs --tail 40 %CONTAINER%
echo    Then run START.bat again.
goto :halt

:err_nopython
echo.
echo   ==============================================================
echo    STOPPED: no suitable Python found, need 3.10 - 3.12
echo   ==============================================================
echo    Tested on Python 3.11. Python 3.13 is rejected on purpose, some of
echo    the libraries this project needs do not support it yet.
echo.
echo    Install with one command:
echo      winget install -e --id Python.Python.3.11
echo    Or download from https://www.python.org/downloads/
echo      tick "Add python.exe to PATH" and "py launcher" during setup
echo    Then close this window and run START.bat again.
goto :halt

:err_venv
echo.
echo   ==============================================================
echo    STOPPED: could not create the virtual environment
echo   ==============================================================
echo    Try by hand:
echo      %PYCMD% -m venv "%VENV%"
goto :halt

:err_pip
echo.
echo   ==============================================================
echo    STOPPED: installing Python packages failed
echo   ==============================================================
echo    Usual causes:
echo      - no internet, or a proxy/firewall blocking pypi.org
echo      - not enough free disk space, about 4-5 GB are needed
echo      - behind a corporate proxy: set HTTPS_PROXY and run again
echo    Retry by hand to see the real error:
echo      "%PY%" -m pip install -r "%PKG%\requirements.txt"
goto :halt

:err_imports
echo.
echo   ==============================================================
echo    STOPPED: packages installed but do not import
echo   ==============================================================
echo    The FAIL lines above name the broken package. That is almost always
echo    a partial download - run START.bat again to finish it.
goto :halt

:err_dbsetup
echo.
echo   ==============================================================
echo    STOPPED: could not prepare the database
echo   ==============================================================
echo    See the FAIL line above. Most common reasons:
echo      - SYS password mismatch. Your container was created with a different
echo        ORACLE_PWD. Edit SYS_PWD near the top of START.bat and run again.
echo      - the database is still warming up: wait two minutes, run again.
echo      - the container is unhealthy: docker logs --tail 40 %CONTAINER%
goto :halt

:err_vectormem
echo.
echo   ==============================================================
echo    STOPPED: HNSW vector indexes are still being rejected
echo   ==============================================================
echo    The vector memory area is not enabled. Try a manual restart:
echo      docker restart %CONTAINER%
echo    Wait until it is healthy, then run START.bat again.
echo    To inspect it yourself:
echo      docker exec -it %CONTAINER% sqlplus -s / as sysdba
echo        show parameter vector_memory_size
goto :halt

:err_dbverify
echo.
echo   ==============================================================
echo    STOPPED: the database self-test failed
echo   ==============================================================
echo    The FAIL line above says what the database refused to do.
goto :halt

:err_kernel
echo   WARNING  could not register the Jupyter kernel "rag".
echo            You can still select the interpreter manually in VS Code:
echo              %PY%
set "WARN=1"
goto :ready

:halt
echo.
echo   Setup did not finish. Nothing was damaged: the database keeps whatever
echo   it already had, and re-running START.bat is always safe.
echo   Full log: %LOG%
call :maybe_pause
exit /b 1

rem ============================================================ helpers
:RUN
rem Run a command, show its output, and append it to the log.
%* >"%TMP%" 2>&1
set "RC=%ERRORLEVEL%"
type "%TMP%"
type "%TMP%">>"%LOG%"
exit /b %RC%

:wait_for_db
setlocal EnableDelayedExpansion
set /a TOTAL=0
set /a DOT=0
:wait_loop
set "HEALTH=none"
for /f "usebackq delims=" %%s in (`docker inspect -f "{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}" %CONTAINER% 2^>nul`) do set "HEALTH=%%s"
if /I "!HEALTH!"=="healthy" goto :wait_ok
if /I "!HEALTH!"=="unhealthy" goto :wait_bad
if /I not "!HEALTH!"=="none" goto :wait_tick
docker logs --tail 300 %CONTAINER% 2>&1 | findstr /C:"DATABASE IS READY TO USE" >nul
if not errorlevel 1 goto :wait_ok
:wait_tick
set /a TOTAL+=1
set /a DOT+=1
if !DOT! GEQ 12 (
  echo.
  set /a DOT=0
)
<nul set /p "=."
if !TOTAL! GEQ 120 goto :wait_timeout
ping -n 11 127.0.0.1 >nul 2>&1
goto :wait_loop
:wait_ok
echo.
endlocal
exit /b 0
:wait_timeout
echo.
endlocal
exit /b 1
:wait_bad
echo.
echo   The container reports "unhealthy" - it started but something inside failed.
endlocal
exit /b 1

:maybe_pause
if "%NOPAUSE%"=="1" exit /b 0
pause
exit /b 0
