---
description: Typed comparisons, and/or/not, in, between, like, NULL, and conditions built at runtime.
---

# Conditions

A condition in hydrahon is a `Term<bool>`, and you build it with the operators Echo already has. No `where('views', '>=', 100)`, no operator as a string. `$u->views >= 100` is an expression the compiler checks: `Term<int64> >= int64` exists, so it compiles.

```echo
$q = Select(from: $u)->where($u->active && $u->views >= 100);
// MySQL: SELECT * FROM `users` WHERE `users`.`active` AND `users`.`views` >= ?
```

`Term<int64> >= string` doesn't exist, so this is where a wrong value stops:

```echo
$u->views >= 'lots';   // will not compile
$u->name == 5;         // will not compile
$p->userId == $u->name; // will not compile
```

And the `100`? It's a bound parameter, not text. Every value in a condition is.

## The operators

| Operator | Works on | Renders |
|:--|:--|:--|
| `==`, `!=` | every kind | `=`, `<>`, or `IS NULL` / `IS NOT NULL` against a null value |
| `<`, `<=`, `>`, `>=` | every kind but `bool` | as written |
| `in` | every kind | `IN (...)` |
| `like` | `string` | `LIKE` |
| `&&`, `\|\|`, `!` | `bool` | `AND`, `OR`, `NOT` |
| `+`, `-`, `*`, `/`, `%` | numbers | see [Arithmetic and functions](./expressions.md) |

The right side is a value or another term of the same type, so comparing two columns is the same thing:

```echo
$q = Select(from: $u)->join(inner: $p, on: $p->userId == $u->id);
// MySQL: SELECT * FROM `users` INNER JOIN `blog`.`posts` AS `p`
//     ON `p`.`user_id` = `users`.`id`
```

An `int32` variable against an `int64` column is fine, by the way. Echo widens it.

## And, or, not

`&&` binds tighter than `||`, same as in Echo, same as in SQL. hydrahon writes parentheses where your grouping needs them, and only there:

```echo
Term<bool> $loose = $u->active || $u->views > 1 && $u->views < 3;
$q = Select(from: $u)->where($loose);
// MySQL: SELECT * FROM `users` WHERE `users`.`active` OR `users`.`views` > ?
//     AND `users`.`views` < ?

Term<bool> $grouped = ($u->active || $u->views > 1) && $u->views < 3;
$q = Select(from: $u)->where($grouped);
// MySQL: SELECT * FROM `users` WHERE (`users`.`active` OR `users`.`views` > ?)
//     AND `users`.`views` < ?
```

Several `where` calls are joined with `AND`, and an `OR` inside one stays inside its parentheses:

```echo
$q = Select(from: $u)
    ->where($u->active || $u->views > 1)
    ->where($u->age == 30);
// MySQL: SELECT * FROM `users` WHERE (`users`.`active` OR `users`.`views` > ?)
//     AND `users`.`age` = ?
```

`!` is `NOT`:

```echo
$q = Select(from: $u)->where(!$u->active);
// MySQL: SELECT * FROM `users` WHERE NOT `users`.`active`
```

## in

`in` is an infix operator, written the way it reads:

```echo
$q = Select(from: $u)->where($u->id in [1, 2, 3]);
// Postgres: SELECT * FROM "users" WHERE "users"."id" IN ($1, $2, $3)
```

Now the case that matters. `WHERE id IN ()` is a syntax error in SQL, and the classic workaround is to drop the condition when the list is empty. Do that in a delete and "delete these zero users" becomes "delete every user". hydrahon writes a condition that matches nothing instead:

```echo
array<int64> $none = [];
$q = Delete(from: $u)->where($u->id in $none);
// MySQL: DELETE FROM `users` WHERE 1 = 0
```

On a nullable column, `in` still takes a plain `array<T>`. A NULL in an `IN` list never matches anything anyway.

To check against the rows of another query, use `$u->id->in($query)`. [Subqueries](./subqueries.md) has it.

## between

Both ends included:

```echo
$q = Select(from: $u)->where($u->views->between(10, 99));
// MySQL: SELECT * FROM `users` WHERE `users`.`views` BETWEEN ? AND ?
```

## like

```echo
$q = Select(from: $u)->where($u->name like 'ma%');
// MySQL: SELECT * FROM `users` WHERE `users`.`name` LIKE ?
// SQLite: SELECT * FROM "users" WHERE "users"."name" LIKE ? ESCAPE '\'
```

The pattern is a parameter like any other value, so it can't break the SQL. It can still match more than you meant, though: hydrahon does not escape `%` and `_` in it. If the pattern comes from a user, put a backslash in front of those yourself. MySQL and Postgres treat the backslash as the escape character by default, and hydrahon adds `ESCAPE '\'` on SQLite, so the same pattern means the same thing on all three.

## NULL

Here is the catch:

```echo
$q = Select(from: $u)->where($u->email == null); // will not compile
```

Echo checks a comparison with a literal `null` itself, before any operator of hydrahon's gets a say, so this never reaches the library. Spell it out:

```echo
$q = Select(from: $u)->where($u->email->isNull());
// MySQL: SELECT * FROM `users` WHERE `users`.`email` IS NULL
```

`isNotNull()` is the other one. A nullable value that happens to be null at runtime does reach hydrahon, and it does the right thing:

```echo
string? $wanted = null;
$q = Select(from: $u)->where($u->email == $wanted);
// MySQL: SELECT * FROM `users` WHERE `users`.`email` IS NULL
```

`= NULL` never matches anything in SQL, so hydrahon never writes it. With a value, the same line renders `= ?`. With `!=`, it's `IS NOT NULL`.

Ordering is different. `$u->age > 18` works on the nullable `age`, but the value has to be a plain `int64`: an `int64?` on the right will not compile. "Older than nothing" has no sensible SQL, so you decide what a missing bound means before you get here.

## Nullable conditions

A comparison always gives you a `Term<bool>`, even on a nullable column. A `Term<bool?>` comes from a nullable `bool` column, or from a function over one. `where` takes it, and a NULL row is filtered out like a false one, which is what SQL does.

`having` and `join(on:)` only take `Term<bool>`. If you've got a `bool?`, decide what NULL means: `fn::coalesce($nullableFlag, false)`.

## Conditions at runtime

Search forms, filters, API query parameters: often you don't know the conditions until runtime. For `AND`, you don't need anything special, since `where` calls add up:

```echo
bool $onlyActive = true;
int64 $minViews = 10;

$q = Select(from: $u);
if ($onlyActive) {
    $q->where($u->active);
}
if ($minViews > 0) {
    $q->where($u->views >= $minViews);
}
// MySQL: SELECT * FROM `users` WHERE `users`.`active` AND `users`.`views` >= ?
```

For `OR`, collect the parts and fold them with [](api:hydrahon::Cond):

```echo
array<Term<bool>> $parts = [$u->active, $u->views > 1];
$q = Select(from: $u)->where(Cond::any($parts));
// MySQL: SELECT * FROM `users` WHERE `users`.`active` OR `users`.`views` > ?
```

`Cond::all` is the `AND` version. Mind the empty list: `Cond::all([])` is always true (`1 = 1`), and `Cond::any([])` is always false (`1 = 0`). That's the math, and it's also the safe answer: "any of no filters" matches nothing.
