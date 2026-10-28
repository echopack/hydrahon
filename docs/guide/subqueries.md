---
description: A select inside a select with in, exists and scalar, unions, and common table expressions.
---

# Subqueries, unions and CTEs

A `Select` can sit inside another statement in three ways: as a list for `in`, as a yes or no for `exists`, and as a single value for `scalar`. The inner query is just a `Select` you built the normal way, so everything on the [Select](./select.md) page works inside it.

## in

`$column->in($query)` checks against the rows of a one-column query:

```echo
$authors = Select(from: $p)->fields([$p->userId])->where($p->id > 5);
$q = Select(from: $u)->where($u->id->in($authors));
// Postgres: SELECT * FROM "users" WHERE "users"."id" IN
//     (SELECT "p"."user_id" FROM "blog"."posts" AS "p" WHERE "p"."id" > $1)
```

The parameters are numbered across the whole statement, inner query included.

Here is the catch: hydrahon can't check that `$authors` selects exactly one column of the right type. That's a select list the compiler only sees as `array<Field>`. The server will tell you if it doesn't.

## exists

`exists()` is a `Term<bool>`, so it goes into `where` like any other condition. The useful kind is correlated, where the inner query refers to the outer row:

```echo
$mine = Select(from: $p)->where($p->userId == $u->id);
$q = Select(from: $u)->where($mine->exists());
// MySQL: SELECT * FROM `users` WHERE EXISTS
//     (SELECT * FROM `blog`.`posts` AS `p` WHERE `p`.`user_id` = `users`.`id`)
```

This is where aliases earn their keep. Every column renders qualified, so `users`.`id` in there means the outer row, and the inner query can't silently capture it.

## scalar

`scalar<T>()` turns a query that yields one column and at most one row into a `Term<T>`. It goes anywhere a value goes, the select list included:

```echo
$n = Select(from: $p)->fields([fn::count()])->where($p->userId == $u->id);
$q = Select(from: $u)->fields([$u->name, $n->scalar<int64>()->named('posts')]);
// MySQL: SELECT `users`.`name`, (SELECT COUNT(*) FROM `blog`.`posts` AS `p`
//     WHERE `p`.`user_id` = `users`.`id`) AS `posts` FROM `users`
```

`scalar<T>()` takes your word for `T`. If the query yields a string, claiming `int64` compiles fine and goes wrong at the server.

## A select without a table

`Select(fields:)` has no FROM at all. Its main use is asking a yes or no question as a row:

```echo
$any = Select(from: $p)->where($p->userId == 7);
$q = Select(fields: [$any->exists()->named('found')]);
// MySQL: SELECT EXISTS (SELECT * FROM `blog`.`posts` AS `p`
//     WHERE `p`.`user_id` = ?) AS `found`
```

## Unions

`union` drops duplicate rows, `union(all:)` keeps them. Both append a branch to the statement you call them on:

```echo
$q = Select(from: $u)->fields([$u->id])->where($u->active);
$more = Select(from: $u)->fields([$u->id])->where($u->views > 100);
$q->union(all: $more)->order([$u->id])->limit(5);
// MySQL: SELECT `users`.`id` FROM `users` WHERE `users`.`active` UNION ALL
//     SELECT `users`.`id` FROM `users` WHERE `users`.`views` > ?
//     ORDER BY `id` ASC LIMIT 5
```

The `order` and `limit` belong to the whole union, not the last branch. That's why the order writes the bare `id`: after a union, there is no `users` table to qualify it with, only the result's columns.

An order or a limit inside one branch is a different thing. MySQL and Postgres take it in parentheses, SQLite doesn't take it at all:

```echo
$top = Select(from: $u)->fields([$u->id])->order([$u->views->desc()])->limit(3);
$q = Select(from: $u)->fields([$u->id])->where($u->active)->union($top);
// MySQL: SELECT `users`.`id` FROM `users` WHERE `users`.`active` UNION
//     (SELECT `users`.`id` FROM `users` ORDER BY `users`.`views` DESC LIMIT 3)
// SQLite: error: unsupported by this dialect: ORDER BY or LIMIT inside a UNION branch
```

## Common table expressions

`with(name:)` puts a `WITH name AS (...)` in front of the statement. To read from it, build a handle with `cte:` and the same name. It has the table's columns, under the CTE's name:

```echo
$recent = app::UserTable(cte: 'recent');
$q = Select(from: $recent)
    ->with(name: 'recent', Select(from: $u)->where($u->active))
    ->where($recent->views > 3);
// Postgres: WITH "recent" AS (SELECT * FROM "users" WHERE "users"."active")
//     SELECT * FROM "recent" WHERE "recent"."views" > $1
```

UPDATE, DELETE and INSERT take `with` too. MySQL refuses it in front of an INSERT, and MariaDB in front of anything but a SELECT.

### Recursive

`with(recursive:)` lets the query read its own name, usually as a seed unioned with a step. A tree is the classic case. There's no generated handle for a CTE that isn't shaped like a table, so this one uses plain [`Table` columns](./tables.md#without-hydragen):

```echo
$c = hydrahon::Table(name: 'categories');
Term<int64> $id = $c->column<int64>('id');
Term<int64?> $parent = $c->column<int64?>('parent_id');

$tree = hydrahon::Table(cte: 'tree');
Term<int64> $treeId = $tree->column<int64>('id');

$seed = Select(from: $c)->fields([$id, $parent])->where($id == 1);
$step = Select(from: $c)->fields([$id, $parent])->join(inner: $tree, on: $parent == $treeId);
$seed->union(all: $step);

$q = Select(from: $tree)->with(recursive: 'tree', $seed);
// Postgres: WITH RECURSIVE "tree" AS (
//       SELECT "categories"."id", "categories"."parent_id" FROM "categories"
//       WHERE "categories"."id" = $1
//       UNION ALL
//       SELECT "categories"."id", "categories"."parent_id" FROM "categories"
//       INNER JOIN "tree" ON "categories"."parent_id" = "tree"."id"
//     ) SELECT * FROM "tree"
```

That's category 1 and everything below it, however deep.
