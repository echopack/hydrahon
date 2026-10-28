---
description: What hydragen generates, aliases and self joins, CTE handles, and tables without hydragen.
---

# Table handles

A statement never takes a table name or a column name as a string. It takes a handle: an object with one typed column per field of your struct. That's the whole trick behind "a typo doesn't compile". There is no string to mistype, so `$u->emial` is an unknown property, and the compiler says so.

## What hydragen writes

For `app::User`, hydragen writes `app::UserTable`. Trimmed down, it looks like this:

```echo title=".hydrahon/tables.eco"
public class UserTable : hydrahon::Source
{
    public const hydrahon::Term<int64> $id;
    public const hydrahon::Term<string?> $email;
    public const hydrahon::Term<int64> $views;
    // ...

    public constructor() { /* the table `users` */ }
    public constructor(alias: string $alias) { /* `users` AS alias */ }
    public constructor(cte: string $name) { /* a CTE shaped like `users` */ }

    public const function all() : hydrahon::Field { /* `users`.* */ }
}
```

Each column is a `public const` [](api:hydrahon::Term) of the field's type. `$u->email` is a `Term<string?>` because the field is `string?`, and that `?` decides which operators you get later.

Look at `$views`, though. The struct says `int32`, the handle says `int64`. hydragen widens every integer to `int64` (`uint64` stays) and every float to `float64`. SQL doesn't care about your integer width, and it means one set of operators per kind instead of eight. An `int32` value still compares fine against it. [hydragen](./hydragen.md) has the full mapping.

## Using one

```echo
$u = app::UserTable();
$q = Select(from: $u)->fields([$u->id, $u->email]);
// MySQL: SELECT `users`.`id`, `users`.`email` FROM `users`
```

Columns always render qualified. In a one-table select that's noise. The moment a second table shows up, it's what keeps `id` from meaning two things.

A handle is cheap. Make one where you need it instead of threading one through your program.

## Aliases and self joins

`alias:` gives the handle a name of its own. Every column of it renders under that name:

```echo
$a = app::UserTable(alias: 'a');
$b = app::UserTable(alias: 'b');
$q = Select(from: $a)
    ->fields([$a->id, $b->all()])
    ->join(inner: $b, on: $a->id == $b->id && $b->active);
// Postgres: SELECT "a"."id", "b".* FROM "users" AS "a"
//     INNER JOIN "users" AS "b" ON "a"."id" = "b"."id" AND "b"."active"
```

Two handles, one table, no confusion. `$b->all()` is `"b".*` as a select field.

An alias stays on SELECT, UPDATE and DELETE. INSERT, TRUNCATE and DROP have no use for one, so they drop it and write the table's real name.

## CTE handles

`cte:` builds a handle shaped like the table, but reading a common table expression of that name instead:

```echo
$u = app::UserTable();
$recent = app::UserTable(cte: 'recent');
$q = Select(from: $recent)
    ->with(name: 'recent', Select(from: $u)->where($u->active))
    ->where($recent->views > 3);
// MySQL: WITH `recent` AS (SELECT * FROM `users` WHERE `users`.`active`)
//     SELECT * FROM `recent` WHERE `recent`.`views` > ?
```

Same columns, same types, different name. [Subqueries, unions and CTEs](./subqueries.md) owns the rest of `with`.

## Without hydragen

Sometimes a table only exists at runtime, or you don't want a generator for one throwaway query. [](api:hydrahon::Table) is what a handle wraps, and it hands out columns itself:

```echo
$t = hydrahon::Table(name: 'audit_log', $schema: 'ops');
Term<int64> $id = $t->column<int64>('id');
Term<string> $what = $t->column<string>('what');
$q = Select(from: $t)->fields([$what])->where($id > 100);
// Postgres: SELECT "audit_log"."what" FROM "ops"."audit_log"
//     WHERE "audit_log"."id" > $1
```

Here is the catch: `column<T>()` believes you. Name a column that doesn't exist and the server tells you, not the compiler. Claim the wrong `T` and you get the wrong operators. The generated handles exist so neither can happen.

## Source

Every statement constructor takes a [](api:hydrahon::Source): an interface with one method, `table()`. Generated handles implement it, and so does `Table`. If you'd rather write a handle class by hand, implement `Source` and it plugs into everything. hydrahon's own tests do exactly that.
