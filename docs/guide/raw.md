---
description: raw<T> for the SQL hydrahon doesn't have, how its placeholders work, and the one rule.
---

# Raw SQL

Sooner or later you need SQL hydrahon doesn't have: a JSON function, a date function, a vendor operator. `hydrahon::raw<T>` is the escape hatch. You give it SQL text and the values for its `?` placeholders, and it gives you a `Term<T>` that goes anywhere a column goes.

```echo
Term<int64> $len = hydrahon::raw<int64>('LENGTH(?)', ['abc']);
$q = Select(from: $u)->where($u->views > $len + 1);
// Postgres: SELECT * FROM "users" WHERE "users"."views" > (LENGTH($1)) + $2
```

A few things happened there. `T` is whatever you claim it is, so `$len + 1` picked the `int64` operator. Each `?` took the next value from the list and got renumbered for Postgres. And the raw text got parentheses, because it's going into a bigger expression.

That last part matters more than it looks. Raw SQL is always parenthesized below the top level, so an `OR` inside it can't leak into the surrounding `AND`:

```echo
Term<bool> $either = hydrahon::raw<bool>('a = 1 OR b = 2', []);
$q = Select(from: $u)->where($u->active)->where($either);
// MySQL: SELECT * FROM `users` WHERE `users`.`active` AND (a = 1 OR b = 2)
```

## The one rule

Values go through `?`. Never through string interpolation.

```echo
string $name = 'whatever the user typed';
Term<bool> $safe = hydrahon::raw<bool>('LOWER(name) = LOWER(?)', [$name]);
```

The SQL string goes into the statement exactly as written. hydrahon doesn't quote anything in it, doesn't qualify column names, and can't tell whether it's valid on any dialect. `raw<bool>("name = '{$name}'", [])` is an injection with extra steps, and nothing here will catch it.

## Placeholders

hydrahon finds the `?` placeholders by reading the text the way the dialect does. A `?` inside a quoted string or a comment isn't a placeholder:

```echo
Term<bool> $quoted = hydrahon::raw<bool>('name = \'?\' OR id = ?', [7]);
$q = Select(from: $u)->where($quoted);
// Postgres: SELECT * FROM "users" WHERE name = '?' OR id = $1
```

"The way the dialect does" is a real difference. MySQL takes backslash escapes inside strings and `#` comments. Postgres has `$tag$` strings and `E'...'`. So the same raw text can have a different number of placeholders on different dialects. If you write raw SQL for more than one, keep it boring.

When the count of `?` and the count of values disagree, it doesn't render:

```echo
Term<bool> $short = hydrahon::raw<bool>('a = ? AND b = ?', [1]);
$q = Select(from: $u)->where($short);
// MySQL: error: invalid statement: raw placeholders and params differ in count
```

The values are an `array<hydrahon::Value>`, and every literal hydrahon understands converts into one on its own. [Values and types](./values.md) has the list.
