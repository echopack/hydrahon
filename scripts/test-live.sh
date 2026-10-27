#!/usr/bin/env bash
# Check that every statement the offline tests render is SQL the real databases accept.
#
# The tests dump each statement they build, in every dialect that renders it. This script makes
# the test schema in each database and has the server parse every statement without running it:
# PREPARE on MySQL and Postgres (TRUNCATE and DROP inside a rolled back transaction there), and
# EXPLAIN on SQLite. A mariadb image gets the statements rendered with `Mysql(mariadb: true)`.
#
#   scripts/test-live.sh                 all three
#   scripts/test-live.sh sqlite mysql    just these
#   MYSQL_IMAGE=mariadb:11 PG_IMAGE=postgres:16 scripts/test-live.sh
#
# One container runs at a time and is removed with its volume afterwards.

set -uo pipefail

cd "$(dirname "$0")/.."
MYSQL_IMAGE="${MYSQL_IMAGE:-mysql:8.0}"
PG_IMAGE="${PG_IMAGE:-postgres:16}"
ECHOC="${ECHOC:-echoc}"
targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then
    targets=(sqlite mysql postgres)
fi

dump="$(mktemp -d)"
container=""
# remove the running server, if any
stop_container() {
    if [ -n "$container" ]; then
        docker rm -fv "$container" >/dev/null 2>&1
    fi
    container=""
}
cleanup() {
    stop_container
    rm -rf "$dump"
}
trap cleanup EXIT

echo "rendering statements"
if ! HYDRAHON_DUMP="$dump" "$ECHOC" test >"$dump/test.log" 2>&1; then
    cat "$dump/test.log"
    exit 1
fi
for f in "$dump"/*.sql; do
    sort -u "$f" -o "$f"
done

failed=0

report() {
    # $1 dialect, $2 statement, $3 server output
    echo "FAIL [$1] $2"
    echo "     $3" | head -3
    failed=$((failed + 1))
}

sqlite_schema() {
    cat <<'SQL'
ATTACH DATABASE ':memory:' AS blog;
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, email TEXT UNIQUE, active BOOLEAN NOT NULL DEFAULT 0, views INTEGER NOT NULL DEFAULT 0, age INTEGER, created_at TEXT, a INTEGER, b INTEGER);
CREATE TABLE blog.posts (id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, title TEXT NOT NULL, price NUMERIC, UNIQUE (user_id, title));
CREATE TABLE "we`ird""" ("a""b`c" INTEGER);
CREATE TABLE "odd.name as x" ("a.b" INTEGER);
CREATE TABLE k (i INTEGER, ni INTEGER, u INTEGER, nu INTEGER, f REAL, nf REAL, d NUMERIC, nd NUMERIC, b BOOLEAN, nb BOOLEAN, s TEXT, ns TEXT, x BLOB, nx BLOB, day TEXT, nday TEXT, at TEXT, nat TEXT, time TEXT, ntime TEXT);
SQL
}

mysql_schema() {
    cat <<'SQL'
CREATE DATABASE IF NOT EXISTS blog;
CREATE TABLE users (id BIGINT PRIMARY KEY, name VARCHAR(100) NOT NULL, email VARCHAR(100) UNIQUE, active BOOL NOT NULL DEFAULT 0, views BIGINT NOT NULL DEFAULT 0, age INT, created_at DATETIME, a INT, b INT);
CREATE TABLE blog.posts (id BIGINT PRIMARY KEY, user_id BIGINT NOT NULL, title VARCHAR(200) NOT NULL, price DECIMAL(10,2), UNIQUE (user_id, title));
CREATE TABLE `we``ird"` (`a"b``c` BIGINT);
CREATE TABLE `odd.name as x` (`a.b` BIGINT);
CREATE TABLE k (i BIGINT, ni BIGINT, u BIGINT UNSIGNED, nu BIGINT UNSIGNED, f DOUBLE, nf DOUBLE, d DECIMAL(10,2), nd DECIMAL(10,2), b BOOL, nb BOOL, s VARCHAR(50), ns VARCHAR(50), x VARBINARY(50), nx VARBINARY(50), day DATE, nday DATE, at DATETIME, nat DATETIME, time TIME, ntime TIME);
SQL
}

pg_schema() {
    cat <<'SQL'
CREATE SCHEMA blog;
CREATE TABLE users (id BIGINT PRIMARY KEY, name VARCHAR(100) NOT NULL, email VARCHAR(100) UNIQUE, active BOOLEAN NOT NULL DEFAULT false, views BIGINT NOT NULL DEFAULT 0, age INT, created_at TIMESTAMP, a INT, b INT);
CREATE TABLE blog.posts (id BIGINT PRIMARY KEY, user_id BIGINT NOT NULL, title VARCHAR(200) NOT NULL, price NUMERIC(10,2), UNIQUE (user_id, title));
CREATE TABLE "we`ird""" ("a""b`c" BIGINT);
CREATE TABLE "odd.name as x" ("a.b" BIGINT);
CREATE TABLE k (i BIGINT, ni BIGINT, u NUMERIC(20), nu NUMERIC(20), f DOUBLE PRECISION, nf DOUBLE PRECISION, d NUMERIC(10,2), nd NUMERIC(10,2), b BOOLEAN, nb BOOLEAN, s TEXT, ns TEXT, x BYTEA, nx BYTEA, day DATE, nday DATE, at TIMESTAMP, nat TIMESTAMP, time TIME, ntime TIME);
SQL
}

check_sqlite() {
    local n=0
    while IFS= read -r stmt; do
        n=$((n + 1))
        out="$( { sqlite_schema; echo "EXPLAIN $stmt;"; } | sqlite3 -bail :memory: 2>&1 >/dev/null)"
        if [ -n "$out" ]; then
            report sqlite "$stmt" "$out"
        fi
    done <"$dump/sqlite.sql"
    echo "sqlite    $(sqlite3 --version | cut -d' ' -f1): $n statements"
}

wait_for() {
    # $1 a command that succeeds once the server answers
    for _ in $(seq 1 90); do
        if eval "$1" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    echo "server did not come up"
    return 1
}

check_mysql() {
    container="hydrahon-live-mysql"
    docker rm -fv "$container" >/dev/null 2>&1
    docker run -d --name "$container" -e MYSQL_ALLOW_EMPTY_PASSWORD=yes -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=yes -e MYSQL_DATABASE=test -e MARIADB_DATABASE=test "$MYSQL_IMAGE" >/dev/null || return 1
    local client="mysql"
    local file="$dump/mysql.sql"
    if [[ "$MYSQL_IMAGE" == mariadb* ]]; then
        client="mariadb"
        file="$dump/mariadb.sql"
    fi
    # over TCP: the image's init phase runs a socket-only server that answers and then restarts
    wait_for "docker exec $container $client -uroot -h127.0.0.1 -e 'SELECT 1' test" || return 1
    mysql_schema | docker exec -i "$container" "$client" -uroot test || return 1
    local n=0
    while IFS= read -r stmt; do
        n=$((n + 1))
        # hex keeps quotes and backslashes in the statement away from the client
        hex="$(printf '%s' "$stmt" | xxd -p | tr -d '\n')"
        out="$(printf "SET @s = X'%s';\nPREPARE s FROM @s;\nDEALLOCATE PREPARE s;\n" "$hex" | docker exec -i "$container" "$client" -uroot test 2>&1)"
        if [ -n "$out" ]; then
            report "$MYSQL_IMAGE" "$stmt" "$out"
        fi
    done <"$file"
    echo "$MYSQL_IMAGE: $n statements"
    stop_container
}

check_postgres() {
    container="hydrahon-live-pg"
    docker rm -fv "$container" >/dev/null 2>&1
    docker run -d --name "$container" -e POSTGRES_PASSWORD=x -e POSTGRES_DB=test "$PG_IMAGE" >/dev/null || return 1
    wait_for "docker exec $container psql -h 127.0.0.1 -U postgres -d test -c 'SELECT 1'" || return 1
    pg_schema | docker exec -i "$container" psql -q -v ON_ERROR_STOP=1 -U postgres -d test || return 1
    local n=0
    while IFS= read -r stmt; do
        n=$((n + 1))
        case "$stmt" in
            TRUNCATE*|DROP*) sql="BEGIN; $stmt; ROLLBACK;" ;;
            *) sql="PREPARE s AS $stmt; DEALLOCATE s;" ;;
        esac
        out="$(echo "$sql" | docker exec -i "$container" psql -q -v ON_ERROR_STOP=1 -U postgres -d test 2>&1 >/dev/null)"
        if [ -n "$out" ]; then
            report "$PG_IMAGE" "$stmt" "$out"
        fi
    done <"$dump/postgres.sql"
    echo "$PG_IMAGE: $n statements"
    stop_container
}

for t in "${targets[@]}"; do
    case "$t" in
        sqlite) check_sqlite ;;
        mysql) check_mysql || failed=$((failed + 1)) ;;
        postgres) check_postgres || failed=$((failed + 1)) ;;
        *) echo "unknown target $t (sqlite, mysql, postgres)"; exit 2 ;;
    esac
done

if [ "$failed" -gt 0 ]; then
    echo "$failed failure(s)"
    exit 1
fi
echo "all statements accepted"
