---
layout: home
hero:
  name: hydrahon
  text: Typed SQL for Echo
  tagline: Statements built from typed table handles, rendered for MySQL, Postgres or SQLite as text plus bound parameters. A wrong column or a wrong value doesn't compile.
  actions:
    - theme: brand
      text: Get started
      link: /guide/
    - text: API reference
      link: /api/
features:
  - title: Typos don't compile
    details: Columns are typed handles generated from your structs. A misspelled column is an unknown property, and comparing a number column with a string has no operator to find.
    link: /guide/conditions
  - title: One statement, three dialects
    details: Quoting, placeholders, LIMIT quirks, integer division and upsert syntax are the renderer's problem. What a dialect can't say is an error, never a dropped clause.
    link: /guide/dialects
  - title: Values never touch the text
    details: Every value is a bound parameter. A null comparison is IS NULL, and an empty in list matches nothing instead of deleting every row.
    link: /guide/conditions
  - title: Bring your own driver
    details: An Sql is text plus parameters in placeholder order. A Binder hands them to whatever driver you use, in one small adapter.
    link: /guide/drivers
---

You want SQL from Echo, and you don't want to glue strings together to get it. Describe the table once, and build statements from it:

```echo
$u = app::UserTable();
$q = Select(from: $u)
    ->fields([$u->id, $u->name])
    ->where($u->active && $u->views >= 100)
    ->order([$u->name])
    ->limit(20);

hydrahon::Sql $sql = guard $q->sql<Postgres>();
// Postgres: SELECT "users"."id", "users"."name" FROM "users"
//     WHERE "users"."active" AND "users"."views" >= $1
//     ORDER BY "users"."name" ASC LIMIT 20
```

`app::UserTable` comes from `hydragen`, which reads a plain struct marked `#[hydrahon::table: 'users']`. That `guard` is the error handling: a statement the dialect can't express comes back as an error, not as broken SQL. [Getting started](/guide/) builds from there.

```bash
epm add echopack/hydrahon --git https://github.com/echopack/hydrahon --range ^0.1
```

It's all Echo, with no dependencies. hydrahon renders, your driver runs.
