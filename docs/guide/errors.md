---
description: Why a statement doesn't render, the two kinds of error, and every message.
---

# Errors

`sql()` answers `result<Sql, Error>`. It never panics, and it never hands you SQL it knows is wrong. A statement that renders is SQL the dialect accepts (as far as hydrahon can know without a server). A statement that doesn't render tells you why.

```echo
$q = Delete(from: $u)->where($u->id == 1)->limit(1);
hydrahon::Sql $sql = guard $q->sql<Postgres>() else ($e) {
    die("render: {$e}");
}
// Postgres: error: unsupported by this dialect: DELETE with LIMIT
```

`"{$e}"` is the message. To react to a specific case, match on [](api:hydrahon::Error).

## Two kinds

[](api:hydrahon::Error) has exactly two cases, and the difference is the useful part:

- `unsupported(Feature)`: the statement is fine, but this dialect can't say it. Another dialect might. The message starts with `unsupported by this dialect:`.
- `invalid(Problem)`: the statement is wrong in every dialect. It's a bug in the code that built it. The message starts with `invalid statement:`.

So an `unsupported` is a portability question, and an `invalid` is a fix.

Rendering keeps going after the first problem but reports only that first one. Fix it, and the next one shows up.

## unsupported

| Message | Refused by |
|:--|:--|
| `RETURNING` | MySQL, SQLite before 3.35 |
| `UPDATE with LIMIT`, `UPDATE with ORDER BY` | Postgres, SQLite |
| `DELETE with LIMIT`, `DELETE with ORDER BY` | Postgres, SQLite |
| `RIGHT JOIN` | SQLite before 3.39 |
| `FULL JOIN` | MySQL, SQLite before 3.39 |
| `upsert` | SQLite before 3.24 |
| `ORDER BY or LIMIT inside a UNION branch` | SQLite |
| `WITH before INSERT` | MySQL, MariaDB |
| `WITH before UPDATE`, `WITH before DELETE` | MariaDB |
| `count of DISTINCT or UNION * across a join` | MySQL |

The last one comes from `count()`: it wraps the query as a derived table, and `*` across a join repeats column names, which MySQL won't take there. List the fields instead of `*`.

## invalid

| Message | What happened |
|:--|:--|
| `insert without rows` | an `Insert` with no `row()` |
| `insert rows set different columns` | one row sets a column another doesn't |
| `update without assignments` | an `Update` with no `set()` |
| `a column is set twice` | the same column twice in one row, SET, or upsert update |
| `an assignment target is not a column` | `[$u->views + 1 => 3]`, or `excluded()` outside an upsert |
| `a column belongs to another table` | a column of `$p` in a row of `$u` |
| `conflict update needs a target on this dialect` | `conflict()->update(...)` on Postgres or SQLite |
| `conflict without update or ignore` | a `conflict` with neither, or with both |
| `raw placeholders and params differ in count` | a [raw](./raw.md) fragment with a `?` too many or too few |
| `division by a literal zero` | `$u->views / 0` |
| `a subquery reads the insert target under its table name, which hides the target row` | see below |

The last one deserves a sentence. An INSERT can't alias its target, so its columns are written with the table's real name. If a subquery inside the insert reads the same table under that same name, a column reference would quietly bind to the subquery's row instead of the target row. hydrahon refuses rather than guess. Give the subquery's handle an alias.

## What doesn't get here

A typo in a column, a value of the wrong type, a comparison with a literal `null`: those don't compile, so they never reach `sql()`. And a statement that renders can still fail at the server, on a missing table, a constraint, a deadlock. That error comes from your driver.
