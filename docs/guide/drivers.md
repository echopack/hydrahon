---
description: What an Sql holds, the Binder interface, and a complete adapter for libmysql.
---

# Running statements

hydrahon stops at a string and a list of values. It never opens a connection, never sends a byte, and doesn't know which driver you use. That's the line: hydrahon decides what the SQL says, the driver decides how it gets there.

So you need a small adapter between the two, written once per driver. This page builds the one `examples/shop` uses for libmysql.

## What you hand over

`sql()` gives you a [](api:hydrahon::Sql): the text, in the dialect's placeholder style, and the [](api:hydrahon::Params) for it, in placeholder order:

```echo
$q = Select(from: $u)->where($u->email == 'mario@x.ch' && $u->views > 10);
hydrahon::Sql $sql = guard $q->sql<Mysql>();
echo $sql->text;
// MySQL: SELECT * FROM `users` WHERE `users`.`email` = ?
//     AND `users`.`views` > ?
echo $sql->params->count();  // 2
```

Each parameter is a [](api:hydrahon::Value): an enum with one case per kind, from `none` (NULL) through `int`, `text` and `decimal` to `datetime`. Your driver has its own value type, so the job is to translate one into the other.

## The Binder

You could `foreach` over `$sql->params` and `match` every case yourself. [](api:hydrahon::Binder) is that match, written once: one method per kind, and `$sql->bind($binder)` calls them in placeholder order.

For libmysql, every method appends to a `mysql::Params`:

```echo title="src/binder.eco"
namespace shop;

public struct MysqlBinder : hydrahon::Binder
{
    public mysql::Params $params = mysql::Params();

    public function none() : void
    {
        $this->params[] = mysql::Value::none();
    }

    public function int(int64 $v) : void
    {
        $this->params[] = mysql::Value::int($v);
    }

    public function text(const string& $v) : void
    {
        $this->params[] = mysql::Value::text($v);
    }

    public function decimal(const hydrahon::Decimal& $v) : void
    {
        $this->params[] = mysql::Value::decimal($v->text);
    }

    public function datetime(const hydrahon::DateTime& $v) : void
    {
        $this->params[] = mysql::Value::datetime(mysql::DateTime($v->year, $v->month, $v->day, $v->hour, $v->minute, $v->second, $v->micro));
    }

    // ... bool, uint, float, bytes, date, time
}
```

Mostly one line each. Two of them are worth a second look:

- `bool`. MySQL has no real boolean, so the shop's binder sends `0` or `1` as an int.
- `decimal`. A [](api:hydrahon::Decimal) is text on purpose, so it goes over as the driver's decimal, never through a float.

## Running it

Rendering can fail, and so can the query. Two different errors, so the adapter gets an enum that says which one it was:

```echo title="src/binder.eco"
public enum Failure
{
    case render(hydrahon::Error $e);
    case db(mysql::Error $e);
}
```

Then one function per way of running a statement. This is the one for statements that return rows. Its twin, `exec`, is the same with `$db->exec` and a `mysql::Outcome`:

```echo title="src/binder.eco"
public function query<S>(mysql::Connection $db, const S& $statement) : result<mysql::ResultSet, Failure>
{
    hydrahon::Sql $sql = guard $statement->sql<hydrahon::Mysql>() else ($e) {
        return .error(.render($e));
    }
    MysqlBinder $b = MysqlBinder();
    $sql->bind($b);
    mysql::ResultSet $rs = guard $db->query($sql->text, $b->params) else ($e) {
        return .error(.db($e));
    }
    return .ok($rs);
}
```

`S` is any statement. They all have `sql<D>()`, so one generic function covers Select, Insert, Update and Delete alike.

And now it's just a call:

```echo title="shop.eco"
$c = shop::CustomerTable();
mysql::ResultSet $rs = guard shop::query($db, Select(from: $c)->where($c->visits > 1));
foreach ($rs as $row) {
    echo "{$row['name']}: {$row['visits']} visits";
}
```

The whole example, with the connection, the upsert and a report with joins, is `examples/shop`:

```bash
cd examples/shop
hydragen
MYSQL_URL=mysql://root@127.0.0.1/test echoc run
```

## Other drivers

Same shape every time: a `Binder` that fills the driver's parameter list, a `query` and an `exec`. For Postgres, render with `sql<hydrahon::Postgres>()` and the text already has `$1`, `$2`, in the order `bind` calls you. For SQLite, the text has `?`, and binding goes by position.
