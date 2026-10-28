---
description: Fields, joins, grouping, ordering, paging, counting, and why copying a select branches it.
---

# Select

A [](api:hydrahon::Select) is a struct you build up with chained calls. Each call changes the statement and hands it back, so a chain reads top to bottom like the SQL it becomes. Without any calls, you get everything:

```echo
$u = app::UserTable();
$q = Select(from: $u);
// MySQL: SELECT * FROM `users`
```

The examples on this page use the `app::User` and `app::Post` tables from [Getting started](./index.md), with `$u = app::UserTable()` and `$p = app::PostTable(alias: 'p')`.

## Fields

`fields` takes a list, and the list mixes types freely:

```echo
$q = Select(from: $u)->fields([$u->id, $u->name]);
// MySQL: SELECT `users`.`id`, `users`.`name` FROM `users`
```

`$u->id` is a `Term<int64>` and `$u->name` a `Term<string>`. Both convert to a [](api:hydrahon::Field) on their own, which is why one array can hold them. Several `fields` calls add up.

`named` gives a field an alias, and `distinct` drops duplicate rows:

```echo
$q = Select(from: $u)->fields([$u->name->named('who')])->distinct();
// MySQL: SELECT DISTINCT `users`.`name` AS `who` FROM `users`
```

Any expression is a field, not just a column: `fn::count()`, `$u->views * 2`, a subquery. [Arithmetic and functions](./expressions.md) has those.

## Joins

The kind of join is the label: `inner:`, `left:`, `right:`, `full:`, and `cross:`, which takes no condition.

```echo
$q = Select(from: $u)
    ->fields([$u->name, $p->title])
    ->join(inner: $p, on: $p->userId == $u->id);
// MySQL: SELECT `users`.`name`, `p`.`title` FROM `users`
//     INNER JOIN `blog`.`posts` AS `p` ON `p`.`user_id` = `users`.`id`
```

`on:` is an ordinary condition, so it's typed like every other one. `$p->userId == $u->name` will not compile: there's no `Term<int64> == Term<string>`. Joining on the wrong column is the most common bad join there is, and here it's a compile-time error.

Not every database has every join. MySQL has no `FULL JOIN`, and SQLite only has `RIGHT` and `FULL` since 3.39. hydrahon refuses instead of writing SQL the server rejects:

```echo
$q = Select(from: $u)->join(full: $p, on: $p->userId == $u->id);
// MySQL: error: unsupported by this dialect: FULL JOIN
// Postgres: SELECT * FROM "users" FULL OUTER JOIN "blog"."posts" AS "p"
//     ON "p"."user_id" = "users"."id"
```

To join the same table twice, give each handle an alias. [Table handles](./tables.md#aliases-and-self-joins) has an example.

## Where

`where` takes a `Term<bool>`, and several calls must all hold:

```echo
$q = Select(from: $u)->where($u->active)->where($u->views > 10);
// MySQL: SELECT * FROM `users` WHERE `users`.`active` AND `users`.`views` > ?
```

That's all `where` does. Everything interesting is in the condition, and [Conditions](./conditions.md) owns it.

## Group and having

```echo
$q = Select(from: $u)
    ->fields([$u->name, fn::count($p->id)->named('posts')])
    ->join(left: $p, on: $p->userId == $u->id)
    ->group([$u->name])
    ->having(fn::count($p->id) > 2);
// MySQL: SELECT `users`.`name`, COUNT(`p`.`id`) AS `posts` FROM `users`
//     LEFT JOIN `blog`.`posts` AS `p` ON `p`.`user_id` = `users`.`id`
//     GROUP BY `users`.`name` HAVING COUNT(`p`.`id`) > ?
```

`group` mixes types the way `fields` does. `having` works like `where`, with one difference: it takes a `Term<bool>` only, not a nullable one.

## Order

A bare term sorts ascending. `desc()` turns it around:

```echo
$q = Select(from: $u)->order([$u->name, $u->id->desc()]);
// MySQL: SELECT * FROM `users` ORDER BY `users`.`name` ASC, `users`.`id` DESC
```

Any expression sorts, not just columns:

```echo
$q = Select(from: $u)->order([fn::lower($u->name)->desc(), ($u->views * 2)->asc()]);
// SQLite: SELECT * FROM "users"
//     ORDER BY LOWER("users"."name") DESC, "users"."views" * ? ASC
```

## Limit, offset and page

```echo
$q = Select(from: $u)->limit(20)->offset(40);
// MySQL: SELECT * FROM `users` LIMIT 20 OFFSET 40
```

`page` does the arithmetic for you. It counts from 0:

```echo
$q = Select(from: $u)->page(2, 25);
// MySQL: SELECT * FROM `users` LIMIT 25 OFFSET 50
```

A later `limit` or `page` replaces an earlier one. `limit(0)` is kept, and it asks for no rows. That sounds useless until a limit comes from user input and a 0 quietly turns into "everything".

An offset without a limit is where the dialects disagree the most. hydrahon writes whatever each one needs:

```echo
$q = Select(from: $u)->offset(5);
// MySQL: SELECT * FROM `users` LIMIT 18446744073709551615 OFFSET 5
// Postgres: SELECT * FROM "users" OFFSET 5
// SQLite: SELECT * FROM "users" LIMIT -1 OFFSET 5
```

## Counting

Paging needs the total, so `count()` turns a select into the statement that counts its rows. The original stays as it is:

```echo
$q = Select(from: $u)->where($u->active)->order([$u->name]);
$c = $q->count();
// MySQL: SELECT COUNT(*) AS `count` FROM `users` WHERE `users`.`active`
```

The order is gone, because it can't change a count. Read the result as the `count` column.

Once the statement has a limit, a group, `DISTINCT`, aggregates or a union, `COUNT(*)` over the same tables would count the wrong thing. So `count()` wraps it as a derived table instead:

```echo
$q = Select(from: $u)->where($u->active)->limit(10);
$c = $q->count();
// MySQL: SELECT COUNT(*) AS `count`
//     FROM (SELECT 1 FROM `users` WHERE `users`.`active` LIMIT 10) AS `_h`
```

One catch: a derived table can't repeat a column name, and `*` across a join does exactly that. MySQL refuses to count `DISTINCT` or `UNION` rows of `*` across a join. List the fields instead.

## Copying branches

A `Select` is a struct, and Echo structs copy on assignment. So a copy is a branch, and changing it leaves the original alone:

```echo
$base = Select(from: $u)->where($u->active);
$page = $base;
$page->limit(10);
// MySQL: SELECT * FROM `users` WHERE `users`.`active` LIMIT 10
```

`$base` still has no limit. Build the shared part once, branch off the variants. If you're coming from PHP Hydrahon, where one shared query object got mutated under you, this is the fix.
