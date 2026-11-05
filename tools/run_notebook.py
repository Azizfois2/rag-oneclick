"""Run the notebook headlessly, once, and report exactly which cell failed.

Used by START.bat /run to produce a finished notebook without the user having to
press anything. Writes the executed copy next to the original (suffix .executed).

Exit codes
  0  every code cell ran
  1  at least one cell failed (details are printed)
"""
import argparse
import sys
import traceback

import nbformat
from nbclient import NotebookClient


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--notebook", required=True)
    ap.add_argument("--kernel", default="rag")
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--output", default="")
    a = ap.parse_args()

    nb = nbformat.read(a.notebook, as_version=4)
    client = NotebookClient(nb, timeout=a.timeout, kernel_name=a.kernel, allow_errors=True)

    print(f"  running {a.notebook}")
    print("  this can take a few minutes: it downloads an embedding model and")
    print("  asks Gemini a few questions.")
    try:
        client.execute()
    except Exception:
        print("  EXECUTION ABORTED")
        traceback.print_exc()
        return 1

    failed = []
    for i, cell in enumerate(nb.cells):
        if cell.cell_type != "code":
            continue
        head = (cell.source.strip().splitlines() or [""])[0][:66]
        errs = [o for o in cell.get("outputs", []) if o.get("output_type") == "error"]
        if errs:
            failed.append((i, errs[0]))
            print(f"  [cell {i:2d}] FAIL  {head}")
            print(f"              {errs[0].get('ename')}: "
                  f"{str(errs[0].get('evalue')).splitlines()[0][:220]}")
        else:
            print(f"  [cell {i:2d}] ok    {head}")

    out = a.output or a.notebook.replace(".ipynb", ".executed.ipynb")
    try:
        nbformat.write(nb, out)
        print(f"  saved executed copy: {out}")
    except Exception as exc:
        print(f"  note could not save the executed copy: {exc}")

    if failed:
        print()
        print(f"  {len(failed)} cell(s) failed. Open the notebook and run them by hand;")
        print("  the errors above say exactly what went wrong.")
        return 1

    print("  OK   the whole notebook ran")
    return 0


if __name__ == "__main__":
    sys.exit(main())
