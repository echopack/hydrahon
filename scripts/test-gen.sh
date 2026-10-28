#!/usr/bin/env bash
# Run hydragen end to end: build it, point it at a scratch module, and check that what it writes
# compiles and renders the SQL the schema asks for. Also walks the ways it refuses to run.
#
#   scripts/test-gen.sh
#   ECHOC=/path/to/echoc scripts/test-gen.sh

set -uo pipefail

cd "$(dirname "$0")/.."
root="$(pwd)"
ECHOC="${ECHOC:-echoc}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0

fail() {
    echo "FAIL $1"
    failed=$((failed + 1))
}

# $1 what, $2 expected exit code, $3 text the output must contain, then the command
expect() {
    local what="$1" code="$2" needle="$3"
    shift 3
    out="$("$@" 2>&1)"
    got=$?
    if [ "$got" -ne "$code" ]; then
        fail "$what: exit $got, wanted $code"
        echo "$out" | head -5
        return
    fi
    if [[ "$out" != *"$needle"* ]]; then
        fail "$what: output lacks '$needle'"
        echo "$out" | head -5
        return
    fi
    echo "ok   $what"
}

# $1 the directory, then the command to run in it
in_dir() {
    (cd "$1" && shift && "$@")
}

echo "building hydragen"
if [ ! -d cli/vendor ] && ! in_dir cli epm install >"$work/build.log" 2>&1; then
    cat "$work/build.log"
    exit 1
fi
if ! in_dir cli "$ECHOC" build >"$work/build.log" 2>&1; then
    cat "$work/build.log"
    exit 1
fi
gen="$root/cli/ecobuild/hydragen"

mkdir -p "$work/empty" "$work/unwired/src" "$work/app/src"
expect "no module.eco" 1 "no module.eco here" in_dir "$work/empty" "$gen" --echoc "$ECHOC"

cat >"$work/unwired/module.eco" <<EOF
#[module: "unwired"]
#[version: "0.1.0"]
#[sources: "src/*.eco"]
EOF
echo 'namespace unwired;' >"$work/unwired/src/a.eco"
expect "manifest without the wiring" 1 '#[if: !HYDRAHON_NOGEN]' in_dir "$work/unwired" "$gen" --echoc "$ECHOC"

cat >"$work/app/module.eco" <<EOF
#[module: "app"]
#[version: "0.1.0"]
#[depends: "$root"]
#[sources: "src/*.eco"]

#[if: !HYDRAHON_NOGEN]
#[sources: ".hydrahon/*.eco"]
#[end]

#[target: exe { name: "app", entry: "main.eco" }] {
    #[sources: "main.eco"]
}
EOF
cat >"$work/app/src/schema.eco" <<'EOF'
namespace app;

#[hydrahon::table: 'people']
#[hydrahon::columns: 'snake']
public struct Person
{
    public int32 $id;
    public string $fullName;
    public string? $email;
    public uint64 $balance;
    public float32 $score;
    public bool? $active;
    public hydrahon::Decimal $limit;
    public hydrahon::Bytes? $avatar;
    public hydrahon::Date $born;
    public hydrahon::DateTime? $seenAt;
    public hydrahon::Time $wakes;
    #[hydrahon::name: 'tbl']
    public int64 $table;
    #[hydrahon::skip]
    public array<string> $tags;
    public static int32 $made = 0;
}

namespace app::audit;

#[hydrahon::table: 'odd */ log']
#[hydrahon::schema: 'audit']
public class Entry
{
    public int64 $id;
    public string $all;
}
EOF
cat >"$work/app/main.eco" <<'EOF'
$p = app::PersonTable(alias: 'p');
$q = hydrahon::Select(from: $p)
    ->fields([$p->fullName, $p->table, $p->all()])
    ->where($p->email->isNotNull() && $p->balance > 10 && $p->active == true && $p->born < hydrahon::Date(2000, 1, 1))
    ->order([$p->seenAt->desc()]);
$s = guard $q->sql<hydrahon::Postgres>();
echo $s->text;
$e = app::audit::EntryTable();
$i = hydrahon::Insert(into: $e)->row([$e->id => 1, $e->all => 'x']);
$t = guard $i->sql<hydrahon::Mysql>();
echo $t->text;
EOF

expect "generate" 0 "wrote     .hydrahon/tables.eco" in_dir "$work/app" "$gen" --echoc "$ECHOC"
expect "check after generate" 0 "current   .hydrahon/tables.eco" in_dir "$work/app" "$gen" check --echoc "$ECHOC"
expect "quiet says nothing" 0 "" bash -c "cd '$work/app' && test -z \"\$('$gen' --quiet --echoc '$ECHOC')\""
expect "generated code runs" 0 'SELECT "p"."full_name", "p"."tbl", "p".* FROM "people" AS "p" WHERE "p"."email" IS NOT NULL AND "p"."balance" > $1 AND "p"."active" = $2 AND "p"."born" < $3 ORDER BY "p"."seen_at" DESC' in_dir "$work/app" "$ECHOC" run
expect "schema and odd names" 0 'INSERT INTO `audit`.`odd */ log` (`id`, `all`) VALUES (?, ?)' in_dir "$work/app" "$ECHOC" run

# a field added to the schema makes the file stale until it is regenerated
sed -i.bak 's/public string \$all;/public string $all;\n    public int64 $level;/' "$work/app/src/schema.eco"
expect "check notices a change" 1 "out of date" in_dir "$work/app" "$gen" check --echoc "$ECHOC"
expect "regenerate" 0 "wrote" in_dir "$work/app" "$gen" --echoc "$ECHOC"
expect "check after regenerate" 0 "current" in_dir "$work/app" "$gen" check --echoc "$ECHOC"

# a broken generated file never stops the next run
echo 'this is not echo' >"$work/app/.hydrahon/tables.eco"
expect "regenerate over a broken file" 0 "wrote" in_dir "$work/app" "$gen" --echoc "$ECHOC"

# problems are reported with their place, and nothing is written
cp "$work/app/.hydrahon/tables.eco" "$work/before.eco"
cat >>"$work/app/src/schema.eco" <<'EOF'

#[hydrahon::table: 'bad']
#[hydrahon::colums: 'snake']
public struct Bad
{
    public int64 $hydrahonTable;
}
EOF
expect "problems" 1 "unknown attribute #[hydrahon::colums]" in_dir "$work/app" "$gen" --echoc "$ECHOC"
expect "problems name the reserved field" 1 "Bad::\$hydrahonTable: the generated handle keeps its table in this name" in_dir "$work/app" "$gen" --echoc "$ECHOC"
if ! cmp -s "$work/before.eco" "$work/app/.hydrahon/tables.eco"; then
    fail "a failed run changed the generated file"
fi

expect "usage" 2 "usage: hydragen" "$gen" --nope
expect "help" 0 "usage: hydragen" "$gen" --help
expect "missing compiler" 1 "could not run" in_dir "$work/app" "$gen" --echoc /nonexistent/echoc

if [ "$failed" -gt 0 ]; then
    echo "$failed failure(s)"
    exit 1
fi
echo "hydragen works end to end"
