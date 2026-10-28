---
description: Install hydrahon and hydragen, describe a table, and render your first statement.
---

# Getting started

You want SQL from Echo, and you don't want to glue strings together to get it. hydrahon builds statements out of typed table handles and renders them for MySQL, Postgres or SQLite. What comes out is SQL text plus the values for its placeholders. Running it is your driver's job, not this library's.

The namespace is `hydrahon`. The table handles come from a small generator called `hydragen`, and that is the one step here that isn't just Echo code.

## Install it

From your project directory:

```bash
epm add echopack/hydrahon --git https://github.com/echopack/hydrahon --range ^0.1
```

That writes a `#[requires:]` line and vendors the sources. hydrahon has no dependencies and no C.

hydragen is a separate program, so it gets installed once per machine, not per project:

```bash
git clone https://github.com/echopack/hydrahon
cd hydrahon/cli
epm install
echoc install
```

`epm install` vendors libjson, the only thing hydragen depends on. `echoc install` builds it in release mode and copies `hydragen` to `~/.echo/bin`.

## A complete pass

Let's go from a struct to a SQL string, so the rest of the docs have somewhere to sit.

### Describe the table

A table is a plain Echo struct with an attribute on it:

```echo title="src/schema.eco"
namespace app;

#[hydrahon::table: 'users']
#[hydrahon::columns: 'snake']
public struct User
{
    public int64 $id;
    public string $name;
    public string? $email;
    public bool $active;
    public int32 $views;
    public int32? $age;
    public hydrahon::DateTime $createdAt;
}
```

`#[hydrahon::table]` names the table. `columns: 'snake'` turns `createdAt` into `created_at`. A `?` on the type makes the column nullable, and that nullability follows the column into every condition you write with it.

hydrahon does no DDL. The table itself gets created however you create tables today; this struct only says what's there.

### Generate the handle

hydragen writes the handles into `.hydrahon/tables.eco`. Your manifest has to include that file, behind a guard:

```echo title="module.eco"
#[if: !HYDRAHON_NOGEN]
#[sources: ".hydrahon/*.eco"]
#[end]
```

The guard is there so a broken generated file can never stop hydragen from writing a fixed one. [hydragen](./hydragen.md) has the full story. Now run it from the module directory:

```bash
hydragen
```

```txt
hydragen  1 table(s)
wrote     .hydrahon/tables.eco
```

What you get is `app::UserTable`, a class with one typed column per field:

```echo plain
$u = app::UserTable();
// $u->id         Term<int64>
// $u->email      Term<string?>
// $u->views      Term<int64>, every integer is int64 in SQL
// $u->createdAt  Term<hydrahon::DateTime>
```

### Build a statement

The examples in these docs assume these imports:

```echo
use hydrahon::{Select, Insert, Update, Delete, Truncate, Drop, Term, Cond, Values};
use hydrahon::{Mysql, Postgres, Sqlite};
use hydrahon::fn;
```

Now a select:

```echo
$u = app::UserTable();
$q = Select(from: $u)
    ->fields([$u->id, $u->name])
    ->where($u->active && $u->views >= 100)
    ->order([$u->name])
    ->limit(20);
```

`$u->active && $u->views >= 100` is a plain Echo expression. `$u->views` is a `Term<int64>`, so `>= 100` picks hydrahon's `Term<int64> >= int64` operator, and the result is a `Term<bool>`, which is what `where` takes. Compare it with a string and it will not compile. There is no string version of that operator to find.

Every call changes `$q` and hands it back, so the chain reads top to bottom like the SQL it turns into.

### Render it

Rendering is picking a dialect:

```echo
$u = app::UserTable();
$q = Select(from: $u)
    ->fields([$u->id, $u->name])
    ->where($u->active && $u->views >= 100)
    ->order([$u->name])
    ->limit(20);

hydrahon::Sql $sql = guard $q->sql<Postgres>();
echo $sql->text;
// Postgres: SELECT "users"."id", "users"."name" FROM "users"
//     WHERE "users"."active" AND "users"."views" >= $1
//     ORDER BY "users"."name" ASC LIMIT 20
echo $sql->params->count();  // 1
```

The `100` never touches the text. It sits in `$sql->params` and goes to the server as a bound value. Every value you put in a statement does: there is no way to splice one into the SQL by accident.

Swap `Postgres` for `Mysql` and the same statement comes out with backticks and `?`. That's the whole idea: one statement, three dialects.

### When it doesn't render

So, what happens if this fails? `sql()` answers `result<Sql, Error>`. A statement can be fine in general and still be something a dialect can't say:

```echo
$u = app::UserTable();
$p = app::PostTable(alias: 'p');
$q = Select(from: $u)->join(full: $p, on: $p->userId == $u->id);

hydrahon::Sql $sql = guard $q->sql<Mysql>() else ($e) {
    die("render: {$e}");
}
// MySQL: error: unsupported by this dialect: FULL JOIN
```

MySQL has no `FULL JOIN`, so hydrahon refuses to render one instead of writing SQL the server would reject. Omit the `else` and the crash hook stops the program. [Errors](./errors.md) lists everything that can come back here.

### Hand it to a driver

An `Sql` is text and parameters. Your driver takes it from there: `bind` hands every parameter to a [](api:hydrahon::Binder) you write once per driver, first placeholder first. [Running statements](./drivers.md) walks through a complete one for libmysql.

The whole thing, against a live MySQL, is `examples/shop`. It expects libmysql checked out next to hydrahon:

```bash
cd examples/shop
hydragen
MYSQL_URL=mysql://root@127.0.0.1/test echoc run
```

## Where to go next

- **Table handles** is what hydragen generates, aliases, and [tables without hydragen](./tables.md).
- **Reading** is [Select](./select.md), [Conditions](./conditions.md), [arithmetic and `fn::`](./expressions.md), and [subqueries](./subqueries.md).
- **Writing** is [Insert and upsert](./insert.md), then [update, delete and truncate](./update.md).
- **Rendering** is [Dialects](./dialects.md) and what each one refuses, then [Running statements](./drivers.md).
- **Coming from PHP Hydrahon** is [this page](./php.md).
