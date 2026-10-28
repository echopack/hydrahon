---
description: Rows from map literals, many rows at once, upserts on all three dialects, and RETURNING.
---

# Insert and upsert

An [](api:hydrahon::Insert) takes rows, and a row is a map literal from columns to values:

```echo
$q = Insert(into: $u)->row([$u->name => 'Mario', $u->email => null]);
// MySQL: INSERT INTO `users` (`name`, `email`) VALUES (?, ?)
```

That map is a [](api:hydrahon::Values), and each entry picks its operator from the column's type. So `[$u->views => 'lots']` will not compile, and neither will `[$u->name => null]`, because `name` isn't nullable. `$u->email => null` is fine: `email` is `string?`.

A value can be an expression of the column's type instead of a plain value:

```echo
$q = Insert(into: $u)->row([$u->name => 'Mario', $u->createdAt => fn::now()]);
// SQLite: INSERT INTO "users" ("name", "created_at")
//     VALUES (?, CURRENT_TIMESTAMP)
```

## Many rows

Call `row` again. The entries don't have to come in the same order:

```echo
$q = Insert(into: $u)
    ->row([$u->name => 'Mario', $u->email => 'mario@x.ch'])
    ->row([$u->email => 'boris@x.ch', $u->name => 'Boris']);
// Postgres: INSERT INTO "users" ("name", "email") VALUES ($1, $2), ($3, $4)
```

The second row lists `email` first. Doesn't matter: hydrahon puts each value under its column. What does matter is that every row sets the same columns. A row that sets fewer isn't guessed at, it's an error:

```echo
$q = Insert(into: $u)
    ->row([$u->name => 'Mario', $u->email => 'mario@x.ch'])
    ->row([$u->name => 'Boris']);
// MySQL: error: invalid statement: insert rows set different columns
```

Rows from a loop are the same thing in a `foreach`:

```echo
array<string> $names = ['ada', 'grace', 'linus'];
$q = Insert(into: $u);
foreach ($names as const &$n) {
    $q->row([$u->name => $n, $u->views => 0]);
}
// Postgres: INSERT INTO "users" ("name", "views")
//     VALUES ($1, $2), ($3, $4), ($5, $6)
```

An insert without a single row doesn't render either. "Insert nothing" isn't SQL.

## Upsert

An upsert is an insert that does something else when a unique key is already taken. `conflict` names the key, and `update` says what to do with the row that's already there:

```echo
$q = Insert(into: $u)
    ->row([$u->email => 'mario@x.ch', $u->views => 1])
    ->conflict([$u->email])
    ->update([$u->views => $u->views + 1]);
// MySQL: INSERT INTO `users` (`email`, `views`) VALUES (?, ?)
//     ON DUPLICATE KEY UPDATE `views` = `users`.`views` + ?
// Postgres: INSERT INTO "users" ("email", "views") VALUES ($1, $2)
//     ON CONFLICT ("email") DO UPDATE SET "views" = "users"."views" + $3
```

Inside `update`, a column means the existing row. That's how `$u->views + 1` bumps a counter.

Two very different syntaxes, one statement. Here's the catch with that: MySQL has no conflict target. `ON DUPLICATE KEY` reacts to any unique key, so the `[$u->email]` only exists on Postgres and SQLite. Postgres and SQLite, on the other hand, need it: an upsert `update` without a target doesn't render there.

### Taking the new values

Most of the time you want the values you tried to insert. `update(inserted:)` takes those columns from the new row:

```echo
$q = Insert(into: $u)
    ->row([$u->name => 'Mario', $u->email => 'mario@x.ch'])
    ->conflict([$u->email])
    ->update(inserted: [$u->name]);
// MySQL: INSERT INTO `users` (`name`, `email`) VALUES (?, ?)
//     ON DUPLICATE KEY UPDATE `name` = VALUES(`name`)
// Postgres: INSERT INTO "users" ("name", "email") VALUES ($1, $2)
//     ON CONFLICT ("email") DO UPDATE SET "name" = EXCLUDED."name"
```

MySQL 8.0.19 and later prefer a row alias over `VALUES()`. `Mysql($rowAlias: true)` writes that instead, and [Dialects](./dialects.md#configured-dialects) has why it's not the default.

To mix old and new in one expression, `hydrahon::excluded($column)` is the new value of a column:

```echo
$q = Insert(into: $u)
    ->row([$u->email => 'mario@x.ch', $u->views => 5])
    ->conflict([$u->email])
    ->update([$u->views => $u->views + hydrahon::excluded($u->views)]);
// MySQL: INSERT INTO `users` (`email`, `views`) VALUES (?, ?)
//     ON DUPLICATE KEY UPDATE `views` = `users`.`views` + VALUES(`views`)
```

### Ignoring the conflict

`ignore` keeps the existing row and skips the new one:

```echo
$q = Insert(into: $u)->row([$u->email => 'mario@x.ch'])->conflict()->ignore();
// MySQL: INSERT IGNORE INTO `users` (`email`) VALUES (?)
// Postgres: INSERT INTO "users" ("email") VALUES ($1) ON CONFLICT DO NOTHING
```

`conflict()` without a target is fine here on all three. On MySQL, be aware that `INSERT IGNORE` also turns other errors into warnings, like a value too long for its column. That's MySQL, not hydrahon, but it's the closest thing MySQL has.

A `conflict` needs exactly one of `update` and `ignore`. Neither or both is an error. SQLite has upserts since 3.24.

## RETURNING

`returning` hands back columns of the rows you wrote:

```echo
$q = Insert(into: $u)->row([$u->name => 'Mario'])->returning([$u->id, $u->createdAt->named('at')]);
// Postgres: INSERT INTO "users" ("name") VALUES ($1)
//     RETURNING "id", "created_at" AS "at"
// MySQL: error: unsupported by this dialect: RETURNING
```

MySQL has no RETURNING, and SQLite has it since 3.35. On MySQL, the generated id is in your driver's result instead, like `lastInsertId` in libmysql.

## Aliases

An INSERT can't alias its target, so an alias on the handle is dropped. Inside an upsert, the existing row is written with the table's real name, whatever the handle is called:

```echo
$x = app::UserTable(alias: 'x');
$q = Insert(into: $x)
    ->row([$x->email => 'mario@x.ch'])
    ->conflict([$x->email])
    ->update([$x->views => $x->views + 1]);
// Postgres: INSERT INTO "users" ("email") VALUES ($1)
//     ON CONFLICT ("email") DO UPDATE SET "views" = "users"."views" + $2
```
