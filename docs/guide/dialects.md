---
description: What changes between MySQL, Postgres and SQLite, configuring a dialect, and writing your own.
---

# Dialects

You build a statement once. The dialect is picked when you render it:

```echo
$q = Select(from: $u)->where($u->id == 7);
// MySQL: SELECT * FROM `users` WHERE `users`.`id` = ?
// Postgres: SELECT * FROM "users" WHERE "users"."id" = $1
// SQLite: SELECT * FROM "users" WHERE "users"."id" = ?
```

`$q->sql<Mysql>()`, `$q->sql<Postgres>()`, `$q->sql<Sqlite>()`. The quoting and the placeholders are the obvious part. The rest is where a hand-written query quietly means something else on the next database.

## What changes

| | MySQL | Postgres | SQLite |
|:--|:--|:--|:--|
| Identifiers | `` `users` `` | `"users"` | `"users"` |
| Placeholders | `?` | `$1`, `$2`, ... | `?` |
| Offset without a limit | `LIMIT 18446744073709551615` | nothing | `LIMIT -1` |
| Integer `/` | `DIV` | `/` | `/` |
| `fn::length` | `CHAR_LENGTH` | `CHAR_LENGTH` | `LENGTH` |
| `like` | as is | as is | `ESCAPE '\'` added |
| Upsert | `ON DUPLICATE KEY UPDATE` | `ON CONFLICT ... DO UPDATE` | the same, from 3.24 |
| Upsert ignore | `INSERT IGNORE` | `ON CONFLICT DO NOTHING` | the same, from 3.24 |
| `RETURNING` | refused | yes | from 3.35 |
| `RIGHT JOIN` | yes | yes | from 3.39 |
| `FULL JOIN` | refused | yes | from 3.39 |
| UPDATE and DELETE with `order` or `limit` | yes | refused | refused |
| `WITH` before INSERT | refused | yes | yes |
| `WITH` before UPDATE or DELETE | yes, MariaDB refuses | yes | yes |
| `order` or `limit` inside a union branch | yes | yes | refused |
| `Truncate` | `TRUNCATE TABLE` | `TRUNCATE TABLE` | `DELETE FROM` |

"Refused" means `sql()` answers an error instead of SQL. Never a dropped clause: a DELETE that loses its LIMIT deletes more than you asked for. [Errors](./errors.md) has every message.

## Configured dialects

`sql<D>()` uses the dialect's defaults. When a dialect has options, build one and pass it in:

```echo
$q = Insert(into: $u)
    ->row([$u->name => 'Mario', $u->email => 'mario@x.ch'])
    ->conflict([$u->email])
    ->update(inserted: [$u->name]);

Mysql $mysql = Mysql($rowAlias: true);
hydrahon::Sql $sql = guard $q->sql($mysql);
echo $sql->text;
// INSERT INTO `users` (`name`, `email`) VALUES (?, ?) AS `new`
//     ON DUPLICATE KEY UPDATE `name` = `new`.`name`
```

### Mysql

- `$rowAlias`, off by default. Upserts refer to the incoming row as `AS new ... new.col` instead of `VALUES(col)`. MySQL has the row alias since 8.0.19 and warns about `VALUES()` since 8.0.20. MariaDB refuses it, and older MySQL doesn't know it, so the default is the spelling every version understands.
- `$mariadb`, off by default. MariaDB takes `WITH` only in front of a SELECT, so with this on, `with` on an UPDATE or DELETE is refused instead of sent.

### Sqlite

- `$version`, the number `sqlite3_libversion_number()` returns: `3045000` for 3.45.0, which is the default. Upserts need 3.24, RETURNING 3.35, RIGHT and FULL joins 3.39.

hydrahon never talks to the database, so it can't ask which version is on the other end. You can, once, and pass it in:

```echo
Sqlite $old = Sqlite(3023000);
$q = Insert(into: $u)->row([$u->email => 'mario@x.ch'])->conflict([$u->email])->ignore();
hydrahon::Sql $sql = guard $q->sql($old) else ($e) {
    die("{$e}");
}
// unsupported by this dialect: upsert
```

### Postgres

No options. It does what Postgres does.

## Raw SQL per dialect

A dialect also says how its SQL is lexed: which strings take backslash escapes, whether `#` starts a comment, whether `$tag$` quotes a string. hydrahon needs that for exactly one thing, finding the `?` placeholders in [raw SQL](./raw.md) without counting the ones in strings and comments. It's [](api:hydrahon::Syntax) if you're curious.

## Your own dialect

A dialect is anything that implements [](api:hydrahon::Dialect). It doesn't render anything. It answers the questions where databases differ (how to quote, how to write placeholder `n`, what it supports, what a function is called) and the one shared renderer asks.

```echo
struct Colon : hydrahon::Dialect
{
    public const function quote(const string& $ident, str::text& $out) : void
    {
        $out->push(91);    // [
        $out->append($ident);
        $out->push(93);    // ]
    }

    public const function placeholder(usize $n, str::text& $out) : void
    {
        $out->push(58);    // :
        $out->append(str::from($n));
    }

    public const function supports(hydrahon::Feature $f) : bool
    {
        return true;
    }

    // ... unlimited, upsert, excluded, incoming, truncate, call, symbol, syntax
}
```

That's enough for `SELECT [users].[name] FROM [users] WHERE [users].[id] = :1`. [](api:hydrahon::Binary) and [](api:hydrahon::Function) are public for this reason only: a dialect's `symbol` and `call` get them and can spell them its own way.
