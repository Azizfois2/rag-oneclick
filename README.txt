===========================================================================
 Oracle 26ai Agentic RAG - one-click project
===========================================================================

WHAT THIS IS
  A complete agentic RAG demo: documents + embeddings + vector search +
  keyword search + hybrid search, all inside one Oracle 26ai Free database,
  with a Gemini-powered agent on top.

  Everything runs locally in Docker. Nothing is uploaded except the
  questions you ask Gemini.

---------------------------------------------------------------------------
BEFORE YOU START (one-time)
---------------------------------------------------------------------------
  1. Windows 10/11 with 8 GB RAM or more. 16 GB is comfortable.
  2. Docker Desktop installed and RUNNING (the whale icon on the taskbar
     must have stopped animating).  https://www.docker.com/products/docker-desktop/
  3. Python 3.11 installed.  Easiest way:
        winget install -e --id Python.Python.3.11
     (3.10 and 3.12 also work. 3.13 does not.)
  4. About 10 GB of free disk space on C:
  5. A free Google AI Studio key: https://aistudio.google.com/apikey
     START.bat will open that page and Notepad for you the first time.

---------------------------------------------------------------------------
RUN IT
---------------------------------------------------------------------------
  Double-click:   START.bat

  First run:  15-25 minutes. It downloads the Oracle image (about 1 GB),
              creates the container, waits for the database, builds a Python
              environment and installs the ML libraries (the slow part).

  Later runs: about 1 minute. It reuses everything and just opens the
              notebook.

  When it finishes, a browser tab opens with the notebook. Press
  Shift+Enter on the cells from top to bottom once, then ask questions in
  section 12. Ask = edit the text in quotes and press Shift+Enter.

  KEEP THE BLACK WINDOW (START.bat) OPEN while you work.
  Closing it stops JupyterLab. Your data is safe either way.

---------------------------------------------------------------------------
SWITCHES
---------------------------------------------------------------------------
  START.bat /check     Set up and verify everything, but do not open the
                       notebook. Use this to prove your machine is ready.
  START.bat /run       Also execute the notebook once before opening it, so
                       it already has results in it.

---------------------------------------------------------------------------
WHAT IT CHECKS AND FIXES AUTOMATICALLY
---------------------------------------------------------------------------
  - Docker installed and running
  - Oracle container created, started, and healthy (waits up to 20 minutes)
  - Port 1521 conflicts with another container
  - Python version, virtual environment creation/rebuild
  - All Python packages, then imports them to prove they work
  - Missing .env, and a missing Gemini key (opens the page and Notepad)
  - The USERS tablespace that the Oracle "lite" image does not ship with
  - The application user, password, quota and grants
  - vector_memory_size, which HNSW indexes need, including the restart
  - A real self-test: creates an HNSW index, checks the query plan, drops it
  - The Jupyter kernel registration

  It never destroys data. Running it twice is safe.

---------------------------------------------------------------------------
IF IT STOPS
---------------------------------------------------------------------------
  It stops at the first thing it cannot fix and prints:
    - what failed
    - the usual causes
    - the exact command or setting to fix it
  Full transcript of every run:   logs\setup-YYYYMMDD-HHMMSS.log

  Common ones:

  "Docker ... engine is not running"
      Start Docker Desktop, wait for "Engine running", run START.bat again.

  "no suitable Python found"
      winget install -e --id Python.Python.3.11
      then close the window and run START.bat again.

  "database did not become healthy in 20 minutes"
      Give Docker Desktop at least 4 GB of memory:
      Settings - Resources - Memory. Then Apply and restart Docker.

  "SYS password mismatch"
      Your container was created with a different ORACLE_PWD.
      Either edit SYS_PWD near the top of START.bat, or delete the container
      with "docker rm -f oracle-26ai-free" and let START.bat rebuild it.

  "HNSW vector indexes are still being rejected"
      docker restart oracle-26ai-free
      wait for healthy, then run START.bat again.

---------------------------------------------------------------------------
IMPORTANT - DATA SAFETY
---------------------------------------------------------------------------
  The Oracle container has no mounted volume, so its data lives inside it.

    SAFE:     docker stop oracle-26ai-free
              docker start oracle-26ai-free
              docker restart oracle-26ai-free
              stopping/starting Docker Desktop, rebooting Windows

    DESTROYS: docker rm -f oracle-26ai-free
              the Delete button in Docker Desktop for this container

  If you destroy it, just run START.bat again: it rebuilds the database and
  empty table, but the ingested documents are gone (they are re-created by
  the notebook).

---------------------------------------------------------------------------
GEMINI FREE TIER
---------------------------------------------------------------------------
  Roughly 20 requests per day PER MODEL, and one agent question costs 2-6
  requests because the agent searches more than once. That is a few
  questions per model per day.

  The notebook automatically falls back to another model when one runs out,
  and the quota resets at midnight Pacific time.

  Free-tier prompts may be used to improve Google's products. This project
  uses synthetic sample news only - do not point it at confidential data.
