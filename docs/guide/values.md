---
description: The ten value kinds, Decimal, Bytes, Date, DateTime and Time, and how literals become parameters.
---

# Values and types

Every column is one of ten kinds, and every value you put in a statement becomes a bound parameter of one of them.

| Kind | Echo type | Binds as |
|:--|:--|:--|
| integer | `int64` | `Value::int` |
| unsigned | `uint64` | `Value::uint` |
| float | `float64` | `Value::float` |
| decimal | `hydrahon::Decimal` | `Value::decimal` |
| boolean | `bool` | `Value::bool` |
| text | `string` | `Value::text` |
| binary | `hydrahon::Bytes` | `Value::bytes` |
| date | `hydrahon::Date` | `Value::date` |
| date and time | `hydrahon::DateTime` | `Value::datetime` |
| time | `hydrahon::Time` | `Value::time` |

Each kind also comes nullable, `T?`, and a NULL binds as `Value::none`. Smaller integers and floats are widened on the way in: an `int32` field is a `Term<int64>` column, and an `int32` value goes where an `int64` is expected. [hydragen](./hydragen.md#types) has the field-to-column mapping.

The five structs below are hydrahon's own. They're plain data on purpose: hydrahon only carries them to your [Binder](./drivers.md), it never computes with them.

## Decimal

An exact decimal number, kept as its text:

```echo
$p = app::PostTable();
$q = Insert(into: $p)->row([$p->userId => 7, $p->title => 'Hello', $p->price => hydrahon::Decimal('19.90')]);
// MySQL: INSERT INTO `blog`.`posts` (`user_id`, `title`, `price`)
//     VALUES (?, ?, ?)
```

Why text and not a float? Because `19.90` isn't a float. As a `float64`, it's `19.899999999999998578915`, and a price column is exactly where you don't want that. The server parses the text into its own `DECIMAL`, and nothing is rounded on the way.

hydrahon doesn't check the text. `Decimal('banana')` goes to the server, and the server says no.

## Bytes

Binary data. It's a `string` underneath, because that's where Echo keeps bytes, but wrapping it tells the binder this is a blob, not text:

```echo
string $raw = 'whatever came out of a file, a hash, an image';
hydrahon::Bytes $blob = hydrahon::Bytes($raw);
```

Echo string literals have to be valid UTF-8, so real binary data comes from somewhere at runtime anyway.

## Date

A calendar date: `hydrahon::Date(2024, 1, 31)`. Fields `year`, `month` and `day`, no validation.

## DateTime

A date and a wall clock time, to the microsecond, without a timezone. The constructor takes the parts largest first, and you leave out what you don't need:

```echo
$midnight = hydrahon::DateTime(2024, 1, 31);
$noon = hydrahon::DateTime(2024, 1, 31, 12);
$exact = hydrahon::DateTime(2024, 1, 31, 12, 30, 15, 250000);
```

From a unix timestamp, in UTC:

```echo
$then = hydrahon::DateTime(unix: 1700000000);
```

That's 2023-11-14 22:13:20. Negative timestamps work, for the dates before 1970.

No timezone means none at all. A `DateTime` is the digits that end up in the column, and what they mean is between you and your database.

## Time

A time of day, or a span. Spans can be negative and can run past 24 hours, which MySQL's `TIME` allows up to 838:59:59:

```echo
$lunch = hydrahon::Time($hours: 12, $minute: 30);
$overtime = hydrahon::Time($hours: 26, $minute: 15);
$back = hydrahon::Time($negative: true, $hours: 1);
```

## Value

[](api:hydrahon::Value) is the enum every parameter ends up as. You rarely write one: every literal converts on its own, which is how `[$u->name => 'Mario']` and `raw<bool>('a = ?', [7])` work. The conversions cover `bool`, `int32`, `int64`, `uint32`, `uint64`, `float64`, `string` and the five structs above, and the nullable version of each, except the 32-bit integers.
