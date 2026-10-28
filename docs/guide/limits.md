---
description: What hydrahon leaves to other code, the rough edges, and how the project is tested.
---

# What isn't here

hydrahon builds statements and renders them. Everything on either side of that is someone else's job, and this page lists those jobs so you don't go looking.

## Not here

- **Running anything.** No connections, no pool, no transactions. Your driver does that, and [Running statements](./drivers.md) is the glue.
- **Reading results.** Rows come back from your driver in its own types. There is no mapping back into your `#[hydrahon::table]` structs.
- **DDL.** No CREATE, no ALTER, no migrations. `Drop` is the only exception. Your schema stays in SQL.
- **A schema check against the database.** hydragen reads your structs, not your tables. If the struct says `email` and the table says `mail`, the server finds out first.
- **Every function.** The `fn::` catalog covers what the three dialects agree on. The rest is [raw SQL](./raw.md).
- **Locking clauses.** No `FOR UPDATE` and no `LOCK IN SHARE MODE`.
- **Typed subquery columns.** `in($query)` and `scalar<T>()` trust you about what the inner query selects.

## Rough edges

- Columns are 64 bits wide. An `int32` field becomes a `Term<int64>`, which is fine for SQL but means a hand-written `Term<int32>` gets no operators at all.
- `Table::column<T>()` believes whatever `T` you give it. Generated handles are the safe path.
- The `like` pattern is yours to escape.

## How it's tested

`echoc test` renders every statement shape in all three dialects and compares the exact SQL text and the parameters. That runs on macOS, Linux and Windows in CI, together with a check that the generated operator files are current:

```bash
echoc test
echoc run tools/operators.eco -- --check
```

`src/operators.eco`, `src/fn.eco`, `src/assign.eco` and parts of `src/term.eco` are generated. Echo needs every typed operator spelled out per kind, so `tools/operators.eco` writes them. Change the generator, then run it without `--check` to rewrite them.

Comparing text only proves hydrahon writes what it means to write. `scripts/test-live.sh` checks that the servers agree: it renders every statement from the tests, then has a real SQLite, MySQL and Postgres parse each one, without running it. Point `MYSQL_IMAGE` at a MariaDB image and the MySQL run checks MariaDB instead. It needs Docker and `sqlite3`:

```bash
scripts/test-live.sh                 # all three
scripts/test-live.sh sqlite mysql    # just these
MYSQL_IMAGE=mariadb:11 scripts/test-live.sh mysql
```

hydragen has its own tests in `cli/`, and `scripts/test-gen.sh` runs it end to end against a scratch module.

## The example

`examples/shop` is a whole program against a live MySQL: a schema, the generated handles, the libmysql binder from [Running statements](./drivers.md), an upsert, a report with a join and a count. It expects libmysql checked out next to hydrahon.

```bash
cd examples/shop
hydragen
MYSQL_URL=mysql://root@127.0.0.1/test echoc run
```
