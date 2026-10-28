# hydrahon

Typed SQL for Echo. Build statements from table handles generated out of your structs, and render them for MySQL, Postgres or SQLite as text plus bound parameters.

- A misspelled column or a value of the wrong type doesn't compile.
- One statement renders for three dialects: quoting, placeholders, LIMIT quirks and upserts included.
- What a dialect can't express is an error, never a silently dropped clause.
- Every value is a bound parameter. A null comparison renders `IS NULL`.
- An empty `in` list matches nothing, so a delete never widens to every row.
- Copying a statement branches it. The original stays as it was.
- No driver inside: an `Sql` is text plus parameters, and a small `Binder` hands them to yours.

The [guide](https://echopack.github.io/hydrahon/guide/) has the walk with all the catches. The [API](https://echopack.github.io/hydrahon/api/) is generated from the public comments.

## Installation

From your project directory:

```bash
epm add echopack/hydrahon --git https://github.com/echopack/hydrahon --range ^0.1
```

hydrahon has no dependencies and no C. The table handles come from `hydragen`, a separate program you install once:

```bash
git clone https://github.com/echopack/hydrahon
cd hydrahon/cli
epm install
echoc install
```

## Quick start

Describe a table with a plain struct:

```echo
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
}
```

Include the generated handles in your `module.eco`, then run `hydragen` in that directory:

```echo
#[if: !HYDRAHON_NOGEN]
#[sources: ".hydrahon/*.eco"]
#[end]
```

Now `app::UserTable` exists, with one typed column per field:

```echo
use hydrahon::{Select, Postgres};

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

`$sql->params` holds the `100`. Hand both to your driver; `examples/shop` does it for libmysql.

## Development

```bash
echoc test
echoc run tools/operators.eco -- --check
```

`tools/operators.eco` writes the typed operator overloads in `src/operators.eco`, `src/fn.eco`, `src/assign.eco` and parts of `src/term.eco`. Edit the generator, not those files, then run it without `--check`. `scripts/test-live.sh` checks every rendered statement against real servers in Docker.

MIT licensed.
