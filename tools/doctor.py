"""Check the Python environment the notebook will run in.

Usage:  python doctor.py [--quick]

  --quick   only the few imports needed to start (a couple of seconds)
  default   imports every library the notebook needs, including torch
            (slower, roughly 10-20 seconds, but catches anything broken)

Exit codes
  0  everything imports
  5  at least one import failed
"""
import sys

IMPORTS = [
    ("oracledb", "oracle driver"),
    ("langchain_core", "langchain core"),
    ("langchain_oracledb", "Oracle vector store"),
    ("langchain_openai", "OpenAI fallback"),
    ("langchain_google_genai", "Gemini integration"),
    ("langchain_huggingface", "embedding wrapper"),
    ("langgraph", "agent framework"),
    ("sentence_transformers", "local embeddings"),
    ("dotenv", "dotenv"),
    ("nbclient", "notebook runner"),
]

QUICK = {
    "oracledb",
    "langchain_core",
    "langchain_oracledb",
    "langchain_google_genai",
    "langgraph",
}


def main() -> int:
    quick = "--quick" in sys.argv
    v = sys.version_info
    bad = (v.major != 3 or v.minor < 10 or v.minor > 12)

    print(f"  {'FAIL' if bad else 'OK  '} Python {v.major}.{v.minor}.{v.micro}")
    print(f"       interpreter: {sys.executable}")
    if bad:
        print("       Python 3.10-3.12 is required. 3.11 is the tested version.")

    failed = []
    for module, label in IMPORTS:
        if quick and module not in QUICK:
            continue
        try:
            __import__(module)
            print(f"  OK   import {module:<24} ({label})")
        except Exception as exc:
            failed.append(module)
            print(f"  FAIL import {module:<24} ({label})")
            print(f"       {type(exc).__name__}: {str(exc).splitlines()[0][:160]}")

    if not quick:
        try:
            import torch

            cuda = "yes" if torch.cuda.is_available() else "no"
            print(f"  OK   torch {torch.__version__} (GPU acceleration available: {cuda})")
            print("       CPU is fine for this notebook.")
        except Exception as exc:
            print(f"  note torch details unavailable: {exc}")

    if failed:
        print()
        print("  Missing or broken packages: " + ", ".join(failed))
        print("  Fix by running START.bat again, or manually:")
        print(f'    "{sys.executable}" -m pip install -r requirements.txt')
        return 5

    if bad:
        return 5
    return 0


if __name__ == "__main__":
    sys.exit(main())
