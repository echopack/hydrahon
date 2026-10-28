---
description: Arithmetic on columns, why division is nullable, aliases, and the typed fn:: catalog.
---

# Arithmetic and functions

Columns do math. `$u->views + 1` is a `Term<int64>`, and a term goes anywhere a column goes: in the select list, a condition, an order, a SET.

```echo
$q = Update($u)->set([$u->views => $u->views + 1])->where($u->id == 7);
// MySQL: UPDATE `users` SET `views` = `users`.`views` + ?
//     WHERE `users`.`id` = ?
```

`+`, `-`, `*`, `/` and `%` work on the number kinds: `int64`, `uint64`, `float64` and `hydrahon::Decimal`. Unary `-` works on the signed ones. Both sides have to be the same kind, the same way as in Echo: an integer column times a `Decimal` will not compile.

## Division is the weird one

Integer division truncates in Postgres and SQLite. In MySQL, `/` on two integers gives you a decimal. Same statement, different number, which is exactly what a query builder shouldn't do. So for integers, hydrahon writes `DIV` on MySQL:

```echo
$q = Select(from: $u)->fields([$u->views / 3]);
// MySQL: SELECT `users`.`views` DIV ? FROM `users`
// Postgres: SELECT "users"."views" / $1 FROM "users"
```

Now the types. Divide by a column and the result is nullable, even when both columns aren't:

```echo
Term<int64?> $ratio = $u->views / $u->id;
```

Why? Because the divisor could be 0 at runtime, and MySQL and SQLite answer that with NULL (Postgres raises an error). The type tells you about the worst case instead of letting a NULL surprise you later. A non-zero literal divisor keeps the result non-null.

A literal zero doesn't render at all. The servers disagree on what it means, and it's never what you meant:

```echo
$q = Select(from: $u)->fields([$u->views / 0]);
// MySQL: error: invalid statement: division by a literal zero
```

## Naming a field

An expression in the select list comes back under whatever name the server makes up. `named` picks one:

```echo
$q = Select(from: $u)->fields([$u->name, ($u->views * 2)->named('score')]);
// MySQL: SELECT `users`.`name`, `users`.`views` * ? AS `score` FROM `users`
```

## Functions

The function catalog lives in `hydrahon::fn`. With `use hydrahon::fn;`, they're `fn::count()`, `fn::sum(...)` and friends:

```echo
$q = Select(from: $u)->fields([fn::count()->named('n'), fn::max($u->createdAt)->named('newest')]);
// MySQL: SELECT COUNT(*) AS `n`, MAX(`users`.`created_at`) AS `newest`
//     FROM `users`
```

Every function is typed like the operators: one overload per kind it makes sense for, so `fn::sum($u->name)` will not compile.

| Function | Takes | Gives |
|:--|:--|:--|
| `fn::count()` | nothing | `Term<int64>`, `COUNT(*)` |
| `fn::count($x)` | any term | `Term<int64>`, the rows where `$x` isn't NULL |
| `fn::countDistinct($x)` | any term | `Term<int64>` |
| `fn::sum($x)` | a number | the same kind, nullable |
| `fn::avg($x)` | a number | `float64?`, or `Decimal?` for a `Decimal` |
| `fn::min($x)`, `fn::max($x)` | anything ordered but `Bytes` | the same kind, nullable |
| `fn::abs($x)` | a signed number | the same kind |
| `fn::lower($x)`, `fn::upper($x)` | a string | a string |
| `fn::length($x)` | a string | `int64`, in characters |
| `fn::coalesce($x, $fallback)` | a nullable term | see below |
| `fn::now()` | nothing | `Term<hydrahon::DateTime>`, `CURRENT_TIMESTAMP` |

`length` counts characters, not bytes: `CHAR_LENGTH` on MySQL and Postgres, `LENGTH` on SQLite.

### Aggregates are nullable

`sum`, `avg`, `min` and `max` give you a nullable term, whatever the column. The sum of no rows is NULL in SQL, not 0. The compiler holds you to it:

```echo
Term<int64?> $total = fn::sum($u->views);
Term<float64?> $mean = fn::avg($u->views);
```

When you want the 0, say so with `coalesce`. A plain fallback makes the result non-null again:

```echo
Term<int64> $safe = fn::coalesce(fn::sum($u->views), 0);
$q = Select(from: $u)->fields([$safe->named('total')]);
// Postgres: SELECT COALESCE(SUM("users"."views"), $1) AS "total" FROM "users"
```

A non-null term as the fallback does the same. A nullable fallback keeps it nullable, because both could be NULL.

### Missing a function?

The catalog is small: functions that all three dialects agree on. For anything else (a JSON function, a date function, something vendor-specific), [raw SQL](./raw.md) gives you a typed term from a string.
