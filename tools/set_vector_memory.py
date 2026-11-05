"""Make sure the vector memory area is enabled.

HNSW indexes in Oracle 26ai live in a dedicated SGA pool whose size is controlled
by VECTOR_MEMORY_SIZE. It defaults to 0 (off), and creating an HNSW index then
fails with:

    ORA-51962: The vector memory area is out of space for the current container

The setting can only be changed in the SPFILE, so a restart is required.

Exit codes
  0   already active - nothing to do
  10  written to the SPFILE - the caller must restart the database
  3   could not connect
  5   unexpected Oracle error
"""
import argparse
import os
import sys

import oracledb

TARGET_BYTES = 256 * 1024 * 1024


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dsn", default="localhost:1521/FREEPDB1")
    ap.add_argument("--sys-password", default=os.getenv("ORACLE_SYS_PWD", "OraclePwd123"))
    a = ap.parse_args()

    try:
        conn = oracledb.connect(
            user="sys", password=a.sys_password, dsn=a.dsn,
            mode=oracledb.AUTH_MODE_SYSDBA,
        )
    except oracledb.Error as exc:
        print(f"  FAIL {str(exc).strip().splitlines()[0]}")
        return 3

    cur = conn.cursor()
    try:
        cur.execute("SELECT value FROM v$parameter WHERE name = 'vector_memory_size'")
        row = cur.fetchone()
        active = int(row[0]) if row and row[0] not in (None, "") else 0

        if active > 0:
            print(f"  OK   vector_memory_size is active: {active:,} bytes")
            return 0

        cur.execute("SELECT value FROM v$spparameter WHERE name = 'vector_memory_size'")
        row = cur.fetchone()
        stored = 0
        if row and row[0] not in (None, ""):
            try:
                stored = int(row[0])
            except ValueError:
                stored = 0

        if stored > 0:
            print(f"  SET  SPFILE already holds {stored:,} bytes - only a restart is needed")
        else:
            cur.execute(f"ALTER SYSTEM SET vector_memory_size = {TARGET_BYTES} SCOPE = SPFILE")
            # The "256M" form is silently stored as an empty value on this image,
            # which comes back as 0 after the restart. Verify what actually stuck.
            cur.execute("SELECT value FROM v$spparameter WHERE name = 'vector_memory_size'")
            row = cur.fetchone()
            stored = int(row[0]) if row and str(row[0]).strip().isdigit() else 0
            if stored <= 0:
                print("  FAIL the SPFILE accepted the statement but stored an empty value")
                return 5
            print(f"  SET  vector_memory_size = {stored:,} bytes written to the SPFILE")
        print("       A database restart is required; START.bat performs it automatically.")
        return 10
    except oracledb.Error as exc:
        print(f"  FAIL {str(exc).strip().splitlines()[0]}")
        return 5
    finally:
        try:
            cur.close()
            conn.close()
        except Exception:
            pass


if __name__ == "__main__":
    sys.exit(main())
