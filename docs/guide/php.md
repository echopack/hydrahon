---
description: The PHP Hydrahon API mapped to this one, and the pitfalls that don't exist here anymore.
---

# Coming from PHP Hydrahon

If you've used [clancats/hydrahon](https://github.com/ClanCats/Hydrahon), most of this will look familiar. The chain is the same idea: start from a table, add clauses, translate for a dialect. The big difference is what goes into the chain. PHP Hydrahon takes strings, so `where('views', '>', 18)` is checked by nobody until the server reads it. Here, columns are typed handles and conditions are Echo expressions, so most of what went wrong at runtime there doesn't compile here.

## The API, side by side

| PHP Hydrahon | hydrahon |
|:--|:--|
| `$h->table('users')` | `$u = app::UserTable()`, from [hydragen](./hydragen.md) |
| `->select(['id', 'name'])` | `Select(from: $u)->fields([$u->id, $u->name])` |
| `->where('views', '>', 18)` | `->where($u->views > 18)` |
| `->orWhere(...)`, nested `where(function ($q) {...})` | `\|\|` and parentheses in the expression |
| `->whereIn('id', [1, 2])` | `->where($u->id in [1, 2])` |
| `->whereNull('email')` | `->where($u->email->isNull())` |
| `->leftJoin('posts as p', 'p.user_id', '=', 'u.id')` | `->join(left: $p, on: $p->userId == $u->id)` |
| `->addFieldCount('p.id', 'posts')` | `fn::count($p->id)->named('posts')` in `fields` |
| `->groupBy('name')` | `->group([$u->name])` |
| `->orderBy('name', 'desc')` | `->order([$u->name->desc()])` |
| `->limit(10)->offset(20)`, `->page(2, 25)` | the same |
| `->count()` | `$q->count()`, a new statement |
| `->insert([...])` | `Insert(into: $u)->row([$u->name => ...])` |
| `->update()->set('views', 26)` | `Update($u)->set([$u->views => 26])` |
| `->delete()` | `Delete(from: $u)` |
| `new Expression('views + 1')` | `$u->views + 1`, or [`raw<T>`](./raw.md) |
| `->get()`, `->execute()` | your driver, see [Running statements](./drivers.md) |

That last row is the other big change. PHP Hydrahon ran the query through a callback you gave it. hydrahon hands you an [](api:hydrahon::Sql), and running it is your code.

## The pitfalls that are gone

Each of these is something PHP Hydrahon got wrong, and each one has a test in `tests/regressions.eco` so it never comes back.

### An empty whereIn deleted every row

`whereIn('id', [])` dropped the condition, so the delete had no `WHERE` at all. Here an empty list matches nothing:

```echo
array<int64> $none = [];
$q = Delete(from: $u)->where($u->id in $none);
// MySQL: DELETE FROM `users` WHERE 1 = 0
```

### limit(0) meant no limit

```echo
$q = Select(from: $u)->limit(0);
// Postgres: SELECT * FROM "users" LIMIT 0
```

Zero rows means zero rows.

### where('email', null) never matched

It rendered `email = NULL`, which is never true in SQL. A null value now renders `IS NULL`:

```echo
string? $nobody = null;
$q = Select(from: $u)->where($u->email == $nobody);
// MySQL: SELECT * FROM `users` WHERE `users`.`email` IS NULL
```

And a literal `null` doesn't compile at all, so you write `isNull()` and mean it. [Conditions](./conditions.md#null) has why.

### set('email', null) couldn't set NULL

```echo
$q = Update($u)->set([$u->email => null])->where($u->id == 1);
// MySQL: UPDATE `users` SET `email` = ? WHERE `users`.`id` = ?
```

The `?` is bound to NULL. On a column that isn't nullable, this one doesn't compile either.

### Bulk inserts misaligned their rows

The column list came from the first row, and later rows were taken in whatever order their keys came in. Here each value goes under its column:

```echo
$q = Insert(into: $u)
    ->row([$u->name => 'a', $u->email => 'x'])
    ->row([$u->email => 'y', $u->name => 'b']);
// MySQL: INSERT INTO `users` (`name`, `email`) VALUES (?, ?), (?, ?)
```

The parameters come out as `a, x, b, y`. A row that sets other columns is an error, not a guess.

### count() changed the query you counted

It reset the fields and the limit of the query it ran on. `count()` now builds a new statement and leaves the original alone, and with a limit it counts the limited rows:

```echo
$q = Select(from: $u)->fields([$u->name])->limit(5);
$c = $q->count();
// MySQL: SELECT COUNT(*) AS `count`
//     FROM (SELECT 1 FROM `users` LIMIT 5) AS `_h`
```

### One query object, shared

Changing a query you had passed somewhere else changed it there too. A `Select` is a struct here, so assigning it copies it. [Select](./select.md#copying-branches) has the example.

### Join conditions lost their parentheses

Extra join conditions were glued onto the `ON` clause without parentheses, so an `OR` in them escaped. Here `on:` is one expression, grouped the way you wrote it:

```echo
$q = Select(from: $u)->join(left: $p, on: $p->userId == $u->id && ($p->id > 1 || $p->title like 'a%'));
// MySQL: SELECT * FROM `users` LEFT JOIN `blog`.`posts` AS `p`
//     ON `p`.`user_id` = `users`.`id` AND (`p`.`id` > ? OR `p`.`title` LIKE ?)
```

### Identifiers were parsed

Every dot was split and every `' as '` became an alias, so a name containing either broke. Names are never parsed here. A name is a name:

```echo
$t = hydrahon::Table(name: 'odd.name as x');
Term<int64> $c = $t->column<int64>('a.b');
$q = Select(from: $t)->fields([$c]);
// MySQL: SELECT `odd.name as x`.`a.b` FROM `odd.name as x`
```

### MySQL-only clauses went everywhere

A `DELETE ... LIMIT` went to Postgres as is, and Postgres refused it. Here it's refused before it leaves your program:

```echo
$q = Delete(from: $u)->where($u->id == 1)->limit(1);
// Postgres: error: unsupported by this dialect: DELETE with LIMIT
// SQLite: error: unsupported by this dialect: DELETE with LIMIT
```
