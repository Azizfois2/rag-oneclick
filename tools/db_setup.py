"""Prepare Oracle 26ai Free for the RAG notebook.

Creates (only if missing):
  * the USERS tablespace  - the lite image ships without one, and new users
                            otherwise default to SYSTEM which has almost no space
  * the VECTOR app user   - password 'vector', default tablespace USERS, quota
  * the grants the notebook needs

Idempotent: safe to run as often as you like.

Exit codes
  0  everything is in place
  3  could not connect (database not up yet, wrong port, wrong SYS password)
  4  connected but the app user still cannot log in
  5  an unexpected Oracle error
"""
import argparse
import os
import sys

import oracledb

TS = "USERS"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dsn", default="localhost:1521/FREEPDB1")
    ap.add_argument("--sys-password", default=os.getenv("ORACLE_SYS_PWD", "OraclePwd123"))
    ap.add_argument("--user", default="vector")
    ap.add_argument("--password", default="vector")
    a = ap.parse_args()

    print(f"  connecting as SYSDBA to {a.dsn} ...")
    try:
        conn = oracledb.connect(
            user="sys", password=a.sys_password, dsn=a.dsn,
            mode=oracledb.AUTH_MODE_SYSDBA,
        )
    except oracledb.Error as exc:
        first = str(exc).strip().splitlines()[0]
        print(f"  FAIL {first}")
        if "ORA-01017" in first or "ORA-01031" in first:
            print("       The SYS password does not match this container.")
            print("       If it was created with a different ORACLE_PWD, edit SYS_PWD")
            print("       near the top of START.bat and run it again.")
        elif "DPY-6005" in first or "ORA-12541" in first or "ORA-12514" in first:
            print("       Nothing is accepting connections on that address.")
            print("       Is the container healthy and is port 1521 published?")
            print("       Check with:  docker ps")
        elif "ORA-01033" in first or "ORA-01109" in first:
            print("       The database is still starting or the pluggable database")
            print("       is not open. Wait a minute and run START.bat again.")
        return 3

    cur = conn.cursor()
    try:
        # -- USERS tablespace ------------------------------------------------
        cur.execute("SELECT 1 FROM dba_tablespaces WHERE tablespace_name = :1", [TS])
        if cur.fetchone():
            print(f"  OK   tablespace {TS} already exists")
        else:
            cur.execute(
                "SELECT name FROM v$datafile "
                "WHERE con_id = SYS_CONTEXT('USERENV','CON_ID')"
            )
            rows = cur.fetchall()
            folder = os.path.dirname(rows[0][0]) if rows else "/opt/oracle/oradata/FREE/FREEPDB1"
            datafile = f"{folder}/users01.dbf"
            cur.execute(
                f"CREATE TABLESPACE {TS} DATAFILE '{datafile}' "
                "SIZE 128M AUTOEXTEND ON NEXT 64M MAXSIZE 4G"
            )
            print(f"  OK   created tablespace {TS} ({datafile}, autoextend to 4G)")

        # -- application user ------------------------------------------------
        cur.execute("SELECT 1 FROM dba_users WHERE username = :1", [a.user.upper()])
        if cur.fetchone():
            cur.execute(f'ALTER USER {a.user} IDENTIFIED BY "{a.password}"')
            print(f"  OK   user {a.user} already exists (password set to the expected one)")
        else:
            cur.execute(
                f'CREATE USER {a.user} IDENTIFIED BY "{a.password}" '
                f"DEFAULT TABLESPACE {TS} QUOTA UNLIMITED ON {TS}"
            )
            print(f"  OK   created user {a.user} with default tablespace {TS}")

        cur.execute(f"ALTER USER {a.user} QUOTA UNLIMITED ON {TS}")
        conn.commit()

        # -- grants ----------------------------------------------------------
        for role in ("CONNECT", "RESOURCE", "DB_DEVELOPER_ROLE", "CTXAPP"):
            try:
                cur.execute(f"GRANT {role} TO {a.user}")
                print(f"  OK   granted {role}")
            except oracledb.Error as exc:
                first = str(exc).strip().splitlines()[0]
                print(f"  warn could not grant {role}: {first}")
        conn.commit()
    except oracledb.Error as exc:
        print(f"  FAIL {str(exc).strip().splitlines()[0]}")
        return 5
    finally:
        try:
            cur.close()
            conn.close()
        except Exception:
            pass

    # -- prove the app user can log in ---------------------------------------
    try:
        test = oracledb.connect(user=a.user, password=a.password, dsn=a.dsn)
        test.close()
        print(f"  OK   login as {a.user} works")
    except oracledb.Error as exc:
        print(f"  FAIL login as {a.user} failed: {str(exc).strip().splitlines()[0]}")
        return 4

    return 0


if __name__ == "__main__":
    sys.exit(main())
