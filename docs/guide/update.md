---
description: Update with set, Delete, and the MySQL-only order and limit, plus Truncate and Drop.
---

# Update, delete, truncate

## Update

`set` takes the same map literal an insert row does, and a value can read the row it's updating:

```echo
$q = Update($u)->set([$u->views => $u->views + 1, $u->email => null])->where($u->id == 7);
// MySQL: UPDATE `users` SET `views` = `users`.`views` + ?, `email` = ?
//     WHERE `users`.`id` = ?
```

Notice the missing label. It's `Select(from:)`, `Insert(into:)` and `Delete(from:)`, but plain `Update($u)`. An UPDATE has exactly one table and there's no other constructor to tell it apart from, so there's nothing for a label to say. `Truncate($u)` and `Drop($u)` work the same way.

Several `set` calls add up. Setting the same column twice is an error, not a "last one wins":

```echo
$q = Update($u)->set([$u->name => 'a'])->set([$u->name => 'b']);
// MySQL: error: invalid statement: a column is set twice
```

An update without a single `set` doesn't render either.

A value can be a whole subquery, through `scalar`:

```echo
$posts = Select(from: $p)->fields([fn::count()])->where($p->userId == $u->id);
$q = Update($u)->set([$u->views => $posts->scalar<int64>()]);
// MySQL: UPDATE `users` SET `views` = (SELECT COUNT(*)
//     FROM `blog`.`posts` AS `p` WHERE `p`.`user_id` = `users`.`id`)
```

An alias on the handle stays: `UPDATE "users" AS "x"`.

## Delete

```echo
$q = Delete(from: $u)->where($u->id in [4, 5]);
// MySQL: DELETE FROM `users` WHERE `users`.`id` IN (?, ?)
```

Without a `where`, a delete deletes every row. hydrahon won't stop you, and SQL doesn't either:

```echo
$q = Delete(from: $u);
// MySQL: DELETE FROM `users`
```

The one place it does step in is the empty `in` list. There, "every row" is never what you meant, so `$u->id in []` matches nothing. [Conditions](./conditions.md#in) has the story.

## Order and limit

MySQL can sort the rows of an UPDATE or DELETE and stop after a few. Postgres and SQLite can't, and hydrahon refuses rather than silently dropping the clause:

```echo
$q = Delete(from: $u)->where($u->active)->order([$u->id->desc()])->limit(1);
// MySQL: DELETE FROM `users` WHERE `users`.`active` ORDER BY `users`.`id` DESC
//     LIMIT 1
// Postgres: error: unsupported by this dialect: DELETE with ORDER BY
```

Dropping it would be the worst possible outcome. "Delete the newest row" would quietly become "delete every active row".

## RETURNING and WITH

Both statements take `returning`, the same as [Insert](./insert.md#returning). Postgres has it, SQLite since 3.35, MySQL not at all:

```echo
$q = Delete(from: $u)->where($u->id == 3)->returning([$u->id, $u->name->named('n')]);
// Postgres: DELETE FROM "users" WHERE "users"."id" = $1
//     RETURNING "id", "name" AS "n"
```

Both take `with` too, with a [CTE handle](./subqueries.md#common-table-expressions) to read it. MariaDB refuses `WITH` in front of an UPDATE or DELETE. MySQL takes it.

## Truncate

`Truncate` empties a table:

```echo
$q = Truncate($u);
// MySQL: TRUNCATE TABLE `users`
// SQLite: DELETE FROM "users"
```

SQLite has no TRUNCATE, and an unconditional DELETE is what it optimizes into the same thing. Keep in mind that TRUNCATE isn't just a fast DELETE on the other two: on MySQL it commits the transaction you're in and resets `AUTO_INCREMENT`. That's the server, not hydrahon. hydrahon only writes the words.

## Drop

```echo
$p = app::PostTable();
$q = Drop($p)->ifExists();
// Postgres: DROP TABLE IF EXISTS "blog"."posts"
```

That's the only DDL in here. There is no CREATE or ALTER: the schema stays in plain SQL, wherever you keep it today, with every feature your database has.
