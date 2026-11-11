# Oracle 26ai Agentic RAG — one-click Windows setup

<p>
  <img alt="Windows" src="https://img.shields.io/badge/Windows-10%20%2F%2011-0078D6?logo=windows&logoColor=white">
  <img alt="Docker" src="https://img.shields.io/badge/Docker-Desktop-2496ED?logo=docker&logoColor=white">
  <img alt="Python" src="https://img.shields.io/badge/Python-3.10--3.12-3776AB?logo=python&logoColor=white">
  <img alt="Oracle" src="https://img.shields.io/badge/Oracle%2026ai-Free-F80000?logo=oracle&logoColor=white">
  <img alt="Jupyter" src="https://img.shields.io/badge/JupyterLab-notebook-F37626?logo=jupyter&logoColor=white">
</p>

A Windows bootstrap for the **Oracle 26ai Agentic RAG** lab. Double-click one file and it prepares Docker, the Oracle AI Database Free container, a Python environment, the notebook kernel and the Gemini key — then opens the notebook.

The lab itself keeps everything in one place: documents, embeddings, vector search, keyword search and hybrid search inside Oracle 26ai, with a Gemini-powered agent on top. Nothing leaves the machine except the questions sent to Gemini.

## What it sets up

- **Oracle 26ai Free** in Docker, on port `1521`, with the `vector` application user and the `USERS` tablespace that the lite image does not ship with.
- A **Python virtual environment** (`%USERPROFILE%\rag-venv`) with the pinned packages from `requirements.txt`.
- A **Jupyter kernel** named `Python (rag)`.
- A `.env` file with the Gemini key placeholder and the Oracle connection settings.
- `vector_memory_size`, which HNSW indexes need, including the container restart.
- A real self-test: create an HNSW index, check the query plan, drop it.

The notebook it opens is [`notebook/oracle_agentic_rag_hybrid_search.ipynb`](notebook/oracle_agentic_rag_hybrid_search.ipynb) — an agentic RAG walkthrough with vector, keyword and hybrid retrieval over a synthetic tech-news corpus.

## Requirements

| Requirement | Notes |
| --- | --- |
| Windows 10 or 11 | 8 GB RAM minimum, 16 GB comfortable |
| Docker Desktop | Installed and **running** (the whale icon must have stopped animating) |
| Python 3.10 – 3.12 | 3.11 recommended; 3.13 is rejected on purpose |
| Disk space | About 10 GB free on `C:` |
| Gemini API key | Free from [Google AI Studio](https://aistudio.google.com/apikey) |

`START.bat` opens the AI Studio page and Notepad for you on the first run if the key is missing.

## Quick start

```bat
START.bat
```

Or double-click `START.bat` in Explorer.

**First run:** 15–25 minutes. It downloads the Oracle image (about 1 GB), creates and starts the container, waits for the database, builds the venv and installs the ML packages.

**Later runs:** about one minute. Everything is reused and the notebook opens directly.

When JupyterLab opens, run the notebook cells from top to bottom once with `Shift+Enter`, then ask questions in section 12. Keep the `START.bat` console window open while you work — closing it stops JupyterLab.

## Switches

| Command | Effect |
| --- | --- |
| `START.bat /check` | Sets up and verifies everything without opening the notebook |
| `START.bat /run` | Executes the notebook once before opening it, so results are already visible |

## What it checks and fixes

- Docker installed and running.
- Oracle container created, started and healthy (waits up to 20 minutes).
- Port `1521` conflicts with another container.
- Python version, virtual environment creation and rebuild.
- All Python packages, then imports them to prove they work.
- Missing `.env` and a missing Gemini key.
- The `USERS` tablespace, application user, password, quota and grants.
- `vector_memory_size` for HNSW indexes, including the restart.
- Reserved-area and vector-index self-test.
- Jupyter kernel registration.

The script stops at the first problem it cannot fix and prints what failed, the usual causes, and the exact command or setting to correct it. Every run is logged to `logs\setup-YYYYMMDD-HHMMSS.log`.

## Troubleshooting

| Message | Fix |
| --- | --- |
| `Docker ... engine is not running` | Start Docker Desktop, wait for **Engine running**, run `START.bat` again |
| `no suitable Python found` | `winget install -e --id Python.Python.3.11`, then reopen the window and run `START.bat` |
| `database did not become healthy in 20 minutes` | Give Docker Desktop at least 4 GB of memory in *Settings → Resources*, then restart Docker |
| `SYS password mismatch` | Edit `SYS_PWD` near the top of `START.bat`, or `docker rm -f oracle-26ai-free` and let it rebuild |
| `HNSW vector indexes are still being rejected` | `docker restart oracle-26ai-free`, wait for healthy, run `START.bat` again |

## Data safety

The Oracle container is created **without a mounted volume**, so its data lives inside the container.

Safe:

```bat
docker stop oracle-26ai-free
docker start oracle-26ai-free
docker restart oracle-26ai-free
```

Also safe: stopping Docker Desktop or rebooting Windows.

Destructive:

```bat
docker rm -f oracle-26ai-free
```

Deleting the container from Docker Desktop has the same effect. Running `START.bat` again rebuilds the database and the empty table, but ingested documents are gone — the notebook recreates them from its sample data.

## Gemini free tier

Roughly **20 requests per day per model**, and one agent question costs 2–6 requests because the agent searches more than once. That is a few questions per model per day. The notebook falls back to another model when one is exhausted; quotas reset at midnight Pacific time.

Free-tier prompts may be used to improve Google's products. This project uses synthetic sample news only — do not point it at confidential data.

## Repository layout

| Path | Purpose |
| --- | --- |
| `START.bat` | Orchestrator: Docker, Python, packages, env, kernel, Jupyter |
| `notebook/` | The Agentic RAG hybrid-search notebook |
| `tools/doctor.py` | Preflight checks |
| `tools/db_setup.py`, `tools/db_verify.py` | Database user/tablespace setup and verification |
| `tools/set_vector_memory.py` | Sets `vector_memory_size` and restarts the container |
| `tools/check_key.py` | Validates the Gemini API key |
| `tools/run_notebook.py` | Executes the notebook for `/run` |
| `requirements.txt` | Pinned Python packages |
| `.env.template` | Connection and key template |

## Related project

[`oracle-rag`](https://github.com/Azizfois2/oracle-rag) is the companion Streamlit/terminal console that uses this environment and container: ask questions, compare retrieval modes, manage the corpus, measure quality and expose it over MCP.

## Notes

- The setup is idempotent: running `START.bat` twice is safe and never destroys data.
- The container uses `--restart unless-stopped`, so it comes back with Docker.
- No license file is included in this repository.
