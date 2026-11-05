"""Prove the database is really usable, end to end, in about 3 seconds.

Creates a scratch table, puts an HNSW vector index on it, checks the index is
VALID, checks the optimizer actually uses it, then drops the table again.

This is the check that catches the two things that silently break this project:
a user without a real tablespace, and the vector memory pool being disabled.

Exit codes
  0  pass
  2  failed
  3  could not log in
  5  HNSW index rejected - vector memory area not enabled (ORA-51962)
"""
import argparse
import array
import sys

import oracledb

TABLE = "RAG_SELFTEST"
VECTORS = ([0.11, 0.21, 0.31], [0.90, 0.80, 0.70], [0.20, 0.10, 0.40], [0.50, 0.55, 0.60])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dsn", default="localhost:1521/FREEPDB1")
    ap.add_argument("--user", default="vector")
    ap.add_argument("--password", default="vector")
    a = ap.parse_args()

    try:
        conn = oracledb.connect(user=a.user, password=a.password, dsn=a.dsn)
    except oracledb.Error as exc:
        print(f"  FAIL could not log in as {a.user}: {str(exc).strip().splitlines()[0]}")
        return 3

    cur = conn.cursor()

    try:
        cur.execute("SELECT version_full FROM v$instance")
        row = cur.fetchone()
        if row:
            print(f"  OK   connected as {a.user} to Oracle {row[0]}")
        else:
            print(f"  OK   connected as {a.user}")
    except oracledb.Error:
        print(f"  OK   connected as {a.user}")

    try:
        try:
            cur.execute(f"DROP TABLE {TABLE} PURGE")
        except oracledb.Error:
            pass

        cur.execute(f"CREATE TABLE {TABLE} (id NUMBER PRIMARY KEY, embedding VECTOR(3, FLOAT32))")
        for i, vec in enumerate(VECTORS, start=1):
            cur.execute(
                f"INSERT INTO {TABLE} (id, embedding) VALUES (:1, :2)",
                [i, array.array("f", vec)],
            )
        conn.commit()

        try:
            cur.execute(
                f"CREATE VECTOR INDEX {TABLE}_IDX ON {TABLE} (embedding) "
                "ORGANIZATION INMEMORY NEIGHBOR GRAPH DISTANCE COSINE "
                "WITH TARGET ACCURACY 90"
            )
        except oracledb.Error as exc:
            first = str(exc).strip().splitlines()[0]
            print(f"  FAIL could not create an HNSW index: {first}")
            if "ORA-51962" in first or "ORA-51961" in first:
                print("       The vector memory area is not enabled.")
                print("       START.bat sets VECTOR_MEMORY_SIZE and restarts the container.")
                print("       If this persists, the container may need a full restart:")
                print("         docker restart oracle-26ai-free")
                return 5
            if "ORA-00942" in first or "ORA-00959" in first:
                print("       The user cannot see its default tablespace - re-run START.bat.")
            return 2

        cur.execute(
            "SELECT index_name, index_type, status FROM user_indexes "
            "WHERE table_name = :1", [TABLE]
        )
        rows = cur.fetchall()
        wanted = f"{TABLE}_IDX"
        match = [r for r in rows if str(r[0]).upper() == wanted]
        if not match:
            print(f"  FAIL the vector index was not created; indexes found: {rows}")
            return 2
        name, itype, status = match[0]
        if str(status).upper() != "VALID":
            print(f"  FAIL vector index {name} is {status}, not VALID")
            return 2
        print(f"  OK   HNSW index created: {name} [{itype}] status {status}")

        # Does the optimizer actually use it? Informational, never fatal.
        try:
            cur.execute(
                f"EXPLAIN PLAN FOR SELECT id FROM {TABLE} "
                "ORDER BY VECTOR_DISTANCE(embedding, :v, COSINE) FETCH APPROX FIRST 2 ROWS ONLY",
                {"v": array.array("f", VECTORS[0])},
            )
            cur.execute("SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY())")
            plan = [(r[0] or "") for r in cur.fetchall()]
            if any("VECTOR INDEX" in line.upper() for line in plan):
                print("  OK   query plan uses the vector index")
            else:
                print("  note query plan did not mention the vector index (usually harmless")
                print("       on an almost empty table)")
        except oracledb.Error as exc:
            print(f"  note could not read the query plan: {str(exc).strip().splitlines()[0]}")

        return 0
    finally:
        try:
            cur.execute(f"DROP TABLE {TABLE} PURGE")
            conn.commit()
        except Exception:
            pass
        try:
            cur.close()
            conn.close()
        except Exception:
            pass


if __name__ == "__main__":
    sys.exit(main())
