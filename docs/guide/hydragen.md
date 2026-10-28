---
description: The hydragen command, every hydrahon attribute, the type mapping, naming, and what it refuses.
---

# hydragen

hydragen reads your module's declarations, finds every struct or class marked `#[hydrahon::table]`, and writes one handle class per table into `.hydrahon/tables.eco`. It doesn't parse Echo itself: it asks the compiler for the declarations (`echoc -p decls`), so what it sees is exactly what the compiler sees.

Installing it is in [Getting started](./index.md#install-it).

## Wiring it into a module

The manifest includes the generated file behind a guard:

```echo title="module.eco"
#[if: !HYDRAHON_NOGEN]
#[sources: ".hydrahon/*.eco"]
#[end]
```

Why the guard? hydragen builds your module to read its declarations. Say you rename a field: the old `tables.eco` still has the old column, and a query somewhere still uses it. That build fails, and you could never regenerate your way out. So hydragen builds with `HYDRAHON_NOGEN` defined, which leaves the old file out. Code that uses the handles may not compile in that build either, and hydragen doesn't care, as long as the declarations came out.

Without the guard, hydragen refuses to run and prints the three lines above.

Commit `.hydrahon/tables.eco`, the way `examples/shop` does. A fresh clone then builds without hydragen installed, and `hydragen check` in CI keeps it honest.

## Commands

```txt
usage: hydragen [generate|check] [options]

  generate         write .hydrahon/tables.eco for this module (the default)
  check            exit 1 when .hydrahon/tables.eco is out of date

  --echoc <path>   the compiler, default $ECHOC or echoc on PATH
  --quiet          say nothing on success
```

Run it from the directory with your `module.eco`. `generate` writes the file only when its content changed, so the compiler's cache stays warm. `check` renders the same text and compares, which is what a CI step wants:

```bash
hydragen check
```

```txt
hydragen: .hydrahon/tables.eco is out of date; run hydragen
```

Exit codes: 0 on success, 1 on a problem or a stale file, 2 on a usage error.

## Attributes

All of them live in the `hydrahon` namespace. Anything else in that namespace is an error, so a typo like `#[hydrahon::colums]` doesn't silently do nothing.

### On the type

#### `#[hydrahon::table: 'users']`

Marks the struct or class as a table and names it. Required, and the name must be a non-empty literal.

#### `#[hydrahon::schema: 'blog']`

The schema the table lives in. Columns and the table then render as `"blog"."posts"`.

#### `#[hydrahon::columns: 'snake']`

How field names become column names: `'snake'` or `'verbatim'`. Without it, a column is named exactly like its field.

### On a field

#### `#[hydrahon::name: 'tbl']`

The column name for this field, as written. It wins over `'snake'`.

#### `#[hydrahon::skip]`

Leaves the field out. Use it for anything that isn't a column, like a cached value or a list of tags you load separately. `static` fields are skipped on their own.

```echo title="src/schema.eco"
namespace app;

#[hydrahon::table: 'articles']
#[hydrahon::schema: 'blog']
#[hydrahon::columns: 'snake']
public struct Article
{
    public int64 $id;
    public int64 $authorId;        // author_id
    #[hydrahon::name: 'headline']
    public string $title;          // headline
    #[hydrahon::skip]
    public array<string> $tags;    // not a column
    public static int32 $loaded;   // static, so not a column either
}
```

## Names

The handle is the struct's name plus `Table`, in the struct's namespace: `app::Article` becomes `app::ArticleTable`.

`'snake'` handles acronyms and digits the way you'd hope:

| Field | Column |
|:--|:--|
| `createdAt` | `created_at` |
| `avatarURL` | `avatar_url` |
| `HTTPCode` | `http_code` |
| `userID` | `user_id` |
| `ipV4Address` | `ip_v4_address` |
| `line2Total` | `line2_total` |

## Types

| Field type | Column term |
|:--|:--|
| `int8`, `int16`, `int32`, `int64`, `uint8`, `uint16`, `uint32` | `Term<int64>` |
| `uint64` | `Term<uint64>` |
| `float32`, `float64` | `Term<float64>` |
| `bool` | `Term<bool>` |
| `string` | `Term<string>` |
| `hydrahon::Decimal`, `Bytes`, `Date`, `DateTime`, `Time` | the same type |
| `T?` | `Term<T?>` of the above |

Anything else (`usize`, arrays, your own structs) has no SQL column type, and hydragen asks you to skip it. [Values and types](./values.md) has what each of these binds as.

## What it refuses

Every problem is reported as `file:line: name: message`, all of them in one go, and nothing is written while there's one:

```txt
error: src/schema.eco:5: app::User: #[hydrahon::columns] is 'snake' or 'verbatim'
error: src/schema.eco:8: app::User::$tags: no SQL column type for this field; mark it #[hydrahon::skip]
hydragen: 2 problem(s) in #[hydrahon::...] declarations
```

The full list:

- `#[hydrahon::table] needs the table name: #[hydrahon::table: 'users']`
- `#[hydrahon::table] belongs on a struct or a class`
- `#[hydrahon::table] without a single column`
- `#[hydrahon::...] needs #[hydrahon::table] on the same type`
- `field attributes need #[hydrahon::table] on the type`
- `#[hydrahon::schema] needs a name`
- `#[hydrahon::columns] is 'snake' or 'verbatim'`
- `#[hydrahon::name] needs a column name`
- `unknown attribute #[hydrahon::...]`
- `no SQL column type for this field; mark it #[hydrahon::skip]`
- `column 'x' is already taken by $y`: two fields map to the same column.
- `the generated handle keeps its table in this name; rename the field or mark it #[hydrahon::skip]`: a field called `hydrahonTable`. The handle needs that name for itself.
- `the generated app::UserTable would clash with the declaration of that name`: you already have a type called that.
