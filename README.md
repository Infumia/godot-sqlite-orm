# godot-sqlite-orm

A Godot 4 addon for SQLite: models declared in GDScript, tables created from them, a
method-based query builder, relations, and versioned migrations. Foreign keys are always
enforced, every table is `STRICT`, and every value is bound, never pasted into SQL.

Built on [godot-sqlite](https://github.com/2shady4u/godot-sqlite). Developed and tested on
Godot 4.7.

- [Install](#install)
- [Models](#models)
- [Opening a database](#opening-a-database)
- [Rows](#rows)
- [Queries](#queries)
- [Relations](#relations)
- [Generated helpers](#generated-helpers)
- [Transactions](#transactions)
- [Errors](#errors)
- [Migrations](#migrations)
- [Backups and recovery](#backups-and-recovery)
- [Options](#options)
- [Develop](#develop)

## Install

Add both to the project's `ggg.toml`:

```toml
[[dependency]]
name = "godot-sqlite"
asset_store_asset = "tooshady4u/godot-sqlite:v4.9"
strip_components = 0

[[dependency]]
name = "sqlite-orm"
git = "https://github.com/Infumia/godot-sqlite-orm.git"
rev = "<tag>"
```

The addon does not bundle godot-sqlite; the project installs it next to the addon. Nothing
needs enabling in the editor: the classes are available once the files are in `addons/`.

## Models

A model extends `DbModel`. Every typed `var` is a column. A static `_schema` names the table
and adds keys and constraints.

```gdscript
# item.gd
class_name Item
extends DbModel

enum Rarity { COMMON, RARE }

var id: int
var name: String
var damage: int = 0
var rarity: Rarity = Rarity.COMMON
var tags: Array[StringName] = []
var description: Variant  # String or null


static func _schema(s: DbSchema) -> void:
    s.table("items")
    s.field("id").primary_key().auto_increment()
    s.field("name").unique()
    s.field("damage").check(">= 0")
    s.field("description").type(TYPE_STRING)
```

### Columns

| Var type                                | Stored as                        |
| --------------------------------------- | -------------------------------- |
| `int`, enums                            | `INTEGER`                        |
| `float`                                 | `REAL` (an `int` value is fine)  |
| `bool`                                  | `INTEGER` with `CHECK (x IN (0, 1))` |
| `String`, `StringName`                  | `TEXT` (a `StringName` comes back as one) |
| `PackedByteArray`                       | `BLOB`                           |
| `Array`, `Dictionary`, typed or not     | `TEXT`, as Godot's native JSON   |
| `Vector2i`, `Color` and other built-ins | `TEXT`, as Godot's native JSON   |
| anything, with `.converter(...)`        | whatever the converter says      |

- **NULL.** A typed var cannot hold `null`, so its column is `NOT NULL`. A `Variant` var is
  nullable; give it a stored type with `.type(TYPE_X)` (a foreign key takes the type of the
  key it points at). `.not_null()` makes a `Variant` column `NOT NULL` too.
- **Defaults.** A typed column's `DEFAULT` is the var's initial value, so a migration can add
  it to existing rows. `.default(value)` overrides it.
- **Not columns.** Vars whose name starts with `_`, relation vars, and vars passed to
  `s.ignore("name")`.
- **JSON columns** use Godot's native JSON (`JSON.from_native`), so element types survive:
  `Array[StringName]` comes back typed, ints stay ints. Objects are refused.
- **Objects** cannot be columns. Use a relation, or a `DbConverter`.

### Field settings

```gdscript
s.field("id").primary_key().auto_increment()   # int key, filled on insert, never reused
s.field("uid").primary_key().default_uuid()    # String key, a UUID v4 filled on insert
s.field("name").unique()
s.field("level").check(">= 1")                 # SQL that follows the column name
s.field("surname").type(TYPE_STRING).not_null()
s.field("created").auto_created()              # Unix time on insert, if still 0
s.field("updated").auto_updated()              # Unix time on every insert and update
s.field("color").converter(HexColorConverter.new())
s.field("rank").index()
```

### Keys, unique sets and indexes

```gdscript
s.primary_key(["hero_id", "quest_id"])   # a key over several fields
s.unique(["name", "surname"])            # unique together
s.index(["surname", "name"])             # a plain index
```

Unique fields and sets are created as unique indexes named `<table>_<fields>_unique`, and
plain ones as `<table>_<fields>_index`. SQLite cannot add a constraint to an existing table
but it can add an index, so a migration can add or drop them without rebuilding the table.
SQLite treats every `NULL` as distinct in a unique check, so the fields of a unique set
should be `NOT NULL`.

### Converters

```gdscript
class_name HexColorConverter
extends DbConverter


func sql_type() -> String:
    return "TEXT"


func to_sql(value: Variant) -> Variant:
    var color: Color = value
    return color.to_html()


func from_sql(value: Variant) -> Variant:
    var text: String = value
    if not Color.html_is_valid(text):
        return fail("not a color: %s" % text)
    return Color.html(text)
```

`null` never reaches a converter. A value `from_sql` rejects with `fail()` makes the load
fail with `Db.ErrorKind.CONVERSION`.

### Hooks

```gdscript
func _before_save() -> void:  # before insert, update and save
    name = name.strip_edges()


func _after_load() -> void:   # after the columns are read
    _cache = {}
```

## Opening a database

```gdscript
const MODELS: Array = [Item, Character, Hero, Gear]

var db := Db.open("user://saves/game.db", MODELS, Migrations.LIST)
if not db.is_open():
    push_error(db.last_error())
```

`open` always returns a `Db`; check `is_open()`. It compiles the models (an invalid model
fails before any file is touched), opens or creates the file and its folders, checks the
file's integrity, turns on foreign keys, then brings the schema up to date:

- **New file:** the tables come from the models and every listed migration is recorded as
  applied. `db.is_new()` is true: put starting data in then.
- **Existing file:** the migrations it has not run yet run in order.

Use `":memory:"` as the path for a database that lives in memory. `db.close()` closes it;
a transaction still open is rolled back.

## Rows

```gdscript
var sword := Item.new()
sword.name = "Iron Sword"
db.insert(sword)                    # sword.id is filled in

sword.damage = 12
db.update(sword)                    # by primary key; NOT_FOUND when the row is gone
db.save(sword)                      # insert, or update the row with the same key
db.delete(sword)                    # NOT_FOUND when there is no such row

var item := db.find(Item, 1) as Item           # null when there is no such row
var quest := db.find(Quest, [hero.id, &"rats"]) as Quest   # a key over several fields
db.reload(item)                     # read the row again into the same object

db.insert_many([a, b, c])           # one transaction: all or none
db.save_many([a, b, c])
```

Every call returns `true` on success; on failure `db.last_error()` and
`db.last_error_kind()` say why. A failed insert leaves the model as it was: keys and
timestamps are written back only when the statement works.

## Queries

```gdscript
var top: Array = (
    db.select(Character)
    .where("level", ">=", 10)
    .order_by("level", Db.DESC)
    .limit(5)
    .offset(10)
    .all()
)

var ada := db.select(Character).where("name", "=", "Ada").first() as Character
var unarmed: int = db.select(Character).where_null("weapon_id").count()
var any_rare: bool = db.select(Item).where("rarity", "=", Item.Rarity.RARE).exists()
var names: Array = db.select(Character).order_by("name").pluck("name")
```

| Condition                                            | SQL                               |
| ---------------------------------------------------- | --------------------------------- |
| `where(field, op, value)`, `or_where(...)`           | `=`, `!=`, `<>`, `<`, `<=`, `>`, `>=`, `LIKE`, `NOT LIKE`, `GLOB`, `NOT GLOB`, `IS`, `IS NOT` |
| `where(field, "=", null)`                            | `IS NULL` (and `!=` gives `IS NOT NULL`) |
| `where_in(field, list)`, `or_where_in`, `where_not_in` | `IN (...)`; an empty list matches nothing (`not_in`: everything); long lists are split |
| `where_null(field)`, `or_where_null`, `where_not_null` | `IS NULL`, `IS NOT NULL`        |
| `where_between(field, low, high)`                    | `BETWEEN`                         |
| `where_group(callable)`, `or_where_group(callable)`  | conditions in parentheses         |
| `where_raw(sql, args)`                               | your own SQL with `?` marks       |

Conditions join in order: `where` with AND, `or_where` with OR. As in SQL, AND binds tighter:
`.where(a).where(b).or_where(c)` is `(a AND b) OR c`. Use a group for anything else:

```gdscript
db.select(Character).where("level", ">", 5).where_group(
    func(w: DbWhere) -> void: w.where("name", "=", "Ada").or_where("name", "=", "Lin")
)
```

The operators also exist as constants, so a typo is a parse error: `Db.EQ`, `Db.NE`, `Db.LT`,
`Db.LTE`, `Db.GT`, `Db.GTE`, `Db.LIKE`, `Db.NOT_LIKE`, `Db.GLOB`, `Db.NOT_GLOB`, `Db.IS`,
`Db.IS_NOT`.

Values are converted like fields (a `StringName`, an enum, a `bool`), and field names must be
columns of the model, so neither can inject SQL. Without `order_by`, rows come in primary
key order. `count()` ignores `order_by`, `limit` and `offset`. `to_sql()` shows the
statement.

### Bulk changes

```gdscript
db.update_all(Character).set_field("level", 1).where("level", ">", 99).execute()  # rows changed
db.delete_all(Character).where("level", "<", 2).execute()                         # rows deleted
db.delete_all(Character).all_rows().execute()   # no conditions only with all_rows()
```

These write SQL directly: hooks and relations are skipped; `auto_updated()` fields are still
set. They return `-1` on failure.

### Raw SQL

```gdscript
var rows: Array[Dictionary] = db.raw(
    "SELECT c.name, i.name AS weapon FROM characters c JOIN items i ON i.id = c.weapon_id WHERE i.damage > ?",
    [10],
)
db.execute("UPDATE items SET damage = damage + ?", [1])
```

## Relations

### belongs_to

The side that holds the foreign key declares it as a field, and `belongs_to` binds a var to
the row it points at:

```gdscript
class_name Character
extends DbModel

var id: int
var name: String
var weapon_id: Variant  # the column: int or null
var weapon: Item        # the relation: filled only when loaded


static func _schema(s: DbSchema) -> void:
    s.table("characters")
    s.field("id").primary_key().auto_increment()
    s.field("weapon_id").belongs_to("weapon", Item).on_delete_set_null()
```

```sql
weapon_id INTEGER REFERENCES items (id) ON DELETE SET NULL
```

- `.references(Model)` makes a foreign key without a relation var.
- `.to("uuid")` points at another unique field of the target instead of its primary key.
- `.on_delete_cascade()`, `.on_delete_set_null()` (the field must be a `Variant`),
  `.on_delete_restrict()`, `.on_update_cascade()`.
- Every foreign key column gets an index unless another index already starts with it.
- Assigning the relation var sets the key on save: `hero.weapon = sword` then
  `db.update(hero)` writes `sword.id`. An unsaved target is an error. A `null` relation var
  leaves the key alone, since it may only mean "not loaded"; set the key to `null` to clear it.

### has_many and has_one

The other side declares a list (or a single row) of the models that point at it:

```gdscript
class_name Hero
extends DbModel

var id: String
var gear: Array[Gear] = []
var banner: Banner


static func _schema(s: DbSchema) -> void:
    s.table("heroes")
    s.field("id").primary_key().default_uuid()
    s.has_many("gear", Gear, "hero_id").position("slot_index")
    s.has_one("banner", Banner, "hero_id")
```

`Gear.hero_id` must reference `Hero`. `.position("slot_index")` keeps the list order: it is
written on save and sorted by on load. `.order_by("field", true)` sorts by another field
instead. Without either, children come in primary key order.

### Loading

Relations are never loaded on their own. Ask for them, with one query per relation however
many rows there are:

```gdscript
var heroes: Array = db.select(Hero).with("gear.affixes").with("banner").all()
db.load(hero, "gear")                 # one row
db.load_many(heroes, "gear.affixes")  # rows you already have
```

Rows loaded together share related objects: two characters with the same weapon point at
the same `Item`.

### Saving

```gdscript
db.sync_children(hero, "gear")                       # one relation
db.save_tree(hero, ["gear.affixes", "banner"])       # the row and a whole tree
```

`sync_children` makes the rows match the var: every child in it is saved and pointed at the
parent (and given its position), and the parent's other children are deleted.
`save_tree` saves belongs_to targets first, then the row, then its children through
`sync_children`, all in one transaction.

A list that was never loaded is empty, and syncing it would delete every child. So a row
read from the database refuses to sync a relation that was not loaded. Load it first, or
call `hero.mark_loaded("gear")` after filling it by hand. Rows created in code have nothing
to lose and sync freely.

## Generated helpers

Field and relation names in strings fail only when the query runs. The generator writes a
typed helper class for every model, so a renamed field breaks the build instead:

```gdscript
var hero: Hero = HeroDb.find(db, id)

var top: Array[Character] = (
    CharacterDb.query(db)
    .where_level(Db.GTE, 10)
    .where_weapon_id_null()
    .order_by_level(Db.DESC)
    .with_weapon()
    .limit(5)
    .all()
)

var saves: Array[Hero] = HeroDb.query(db).with_gear(GearDb.Rel.AFFIXES).all()
db.update_all(Character).set_field(CharacterDb.Field.LEVEL, 1).all_rows().execute()
db.save_tree(hero, [HeroDb.Rel.GEAR + "." + GearDb.Rel.AFFIXES])
```

For a model `Character`, `CharacterDb` holds:

| Member                                                   | For                                      |
| -------------------------------------------------------- | ---------------------------------------- |
| `Field.LEVEL`, ...                                       | column names, as `StringName`            |
| `Rel.WEAPON`, ...                                        | relation names, for paths                |
| `find(db, key...)`                                       | the row, typed; one parameter per key field, typed like the key |
| `query(db)`                                              | a `CharacterDb.Query`                    |
| `where_<field>(op, value)`, `or_where_<field>(op, value)` | `value` typed like the field (an enum, `StringName`, ...) |
| `where_<field>_in(values)`, `where_<field>_not_in(values)` | int, float, String and StringName fields |
| `where_<field>_between(low, high)`                       | int and float fields                     |
| `where_<field>_null()`, `or_where_<field>_null()`, `where_<field>_not_null()` | nullable fields   |
| `order_by_<field>(descending)`, `pluck_<field>()`        | `pluck` returns a typed array for scalar fields |
| `with_<relation>(nested)`                                | loads a relation; `nested` continues the path |
| `where_group`, `or_where_group`, `where_raw`, `limit`, `offset` | as on `DbQuery`                 |
| `all() -> Array[Character]`, `first() -> Character`, `count()`, `exists()`, `to_sql()` | typed results |
| `db_query()`                                             | the `DbQuery` underneath, for anything else |

### Running it

```
godot --headless --script res://addons/sqlite_orm/generator/generate.gd
godot --headless --script res://addons/sqlite_orm/generator/generate.gd -- --check
```

It finds every `class_name` script that extends `DbModel`, compiles them together (an invalid
model is reported the same way `Db.open` reports it), and writes one file per model. Files
are only rewritten when their content changes; a file the generator made for a model that no
longer exists is removed. The output passes the GDScript formatter and the strict warnings
unchanged. Commit it: the exported game needs it.

`--check` writes nothing and exits with 1 when a helper is missing, stale or orphaned. Put it
in a pre-commit hook or CI, so a forgotten run cannot slip through.

| Project setting                    | Default                          |
| ---------------------------------- | -------------------------------- |
| `sqlite_orm/generator/output_dir`  | `res://sqlite_orm_generated`     |
| `sqlite_orm/generator/exclude`     | `["res://addons"]`: folders whose models are skipped |

A model needs a `class_name` to get a helper, and its generated names must not clash: a field
named `group` would make `where_group`, which the query already has. The generator reports
such clashes instead of writing the file.

## Transactions

```gdscript
var ok := db.transaction(func() -> bool:
    db.insert(shield)
    hero.weapon = shield
    return db.update(hero)
)
```

Everything inside is committed together. If the callable returns `false`, or any statement
inside fails (even one whose result was ignored), all of it is rolled back and
`transaction()` returns `false` with the first error. Transactions nest as savepoints: an
inner one that fails rolls back only its own work and returns `false` to the outer body,
which decides what to do. The body must not `await`.

## Errors

Every call reports failure the same way: `false` (or `null`, `[]`, `-1`), with
`db.last_error()` holding the message and `db.last_error_kind()` one of:

| Kind                                   | When                                                   |
| -------------------------------------- | ------------------------------------------------------ |
| `USAGE`                                | wrong use: unknown field, unsaved row, model not listed |
| `SCHEMA`                               | invalid models, or models that do not match the tables |
| `CONVERSION`                           | a value does not fit its column, or stored data does not fit its field |
| `NOT_FOUND`                            | update, delete or reload of a row that is not there    |
| `UNIQUE`, `FOREIGN_KEY`, `NOT_NULL`, `CHECK`, `CONSTRAINT` | the constraint that failed       |
| `BUSY`                                 | another connection held a lock past the busy timeout   |
| `CORRUPT`                              | the file is damaged or is not a database               |
| `MIGRATION`                            | a migration failed or the list is invalid              |
| `SQL`                                  | any other SQLite error                                 |

A successful call clears the error. With `DbOptions.report_errors` (on by default) the
addon's own errors are also printed with `push_error`; godot-sqlite prints SQL errors itself.

## Migrations

A migration changes an existing database. It sets its own `VERSION`; file names and list
order do not matter.

```gdscript
# migrations/add_character_xp.gd
extends DbMigration

const VERSION := 1


func up(m: DbMigrator) -> void:
    m.add_column_raw("characters", "xp", TYPE_INT, {"not_null": true, "default": 0})
    m.execute("UPDATE characters SET xp = level * 100")
```

List them in one script, so exported builds find them:

```gdscript
# migrations.gd
class_name Migrations

const LIST: Array = [
    preload("migrations/add_character_xp.gd"),
    preload("migrations/rebuild_items.gd"),
]
```

### Steps

| Step                                                         | Does                                         |
| ------------------------------------------------------------ | -------------------------------------------- |
| `execute(sql, args)`, `query(sql, args)`                     | any SQL; `query` returns rows                |
| `add_column_raw(table, column, TYPE_X, {not_null, default, check})` | a column spelled out in full          |
| `add_column(Model, field)`                                   | a column as the model declares it now        |
| `rename_column(table, old, new)`, `drop_column(table, column)` | as in SQLite                               |
| `create_table(Model)`                                        | a model added after the first release        |
| `drop_table(name)`, `rename_table(old, new)`                 |                                              |
| `rebuild_table(Model, {"old": "new"})`                       | change types, constraints or keys: rebuilds the table from the model and copies the rows |
| `add_unique(Model, fields)`, `add_index(Model, fields)`      | the index the model declares                 |
| `drop_unique(Model, fields)`, `drop_index(Model, fields)`, `drop_index_raw(name)` |                   |
| `fail(message)`                                              | stop and roll back                           |

After the first failed step the rest do nothing and the migration is rolled back.

Steps that take a model read the model as it is **now**, and the model must be in the list
passed to `Db.open`. That is fine while the model still has that shape, but a migration
from an old release runs against whatever the model has become. When a migration must keep
working however the models change later, spell it out with the `_raw` steps and `execute`.

### How they run

- Applied versions are kept in a `_migrations` table, with the time each ran.
- A **new database** runs no migration: its tables come from the models, which already
  describe the latest schema, and every listed version is recorded as applied. Starting data
  therefore belongs behind `db.is_new()`, not in a migration.
- On an **existing database**, each version not yet applied runs in version order, in its
  own transaction together with its `_migrations` row.
- Foreign keys are off while migrations run, so a table can be rebuilt. Each migration must
  leave no broken reference: `PRAGMA foreign_key_check` runs before its commit, and a
  violation rolls it back.
- With `DbOptions.backup_path` set, a backup is written before the first pending migration.
- **Refused lists:** two scripts with the same `VERSION`; a missing, non-int or < 1
  `VERSION`; a script that does not extend `DbMigration`.
- **Refused databases:** one with an unapplied version lower than an applied one (it was
  added out of order and would be skipped); one with an applied version this build does not
  list (it was made by a newer build).

### Schema check

With `DbOptions.check_schema` (on in debug builds), `open` compares the models with the real
tables: columns, types, `NOT NULL`, keys, foreign keys and the addon's indexes. Differences
are printed as warnings and listed by `db.schema_problems()`; with `strict_schema` they fail
the open. A difference usually means a migration is missing.

## Backups and recovery

```gdscript
var options := DbOptions.new()
options.backup_path = "user://saves/game.backup.db"
var db := Db.open("user://saves/game.db", MODELS, Migrations.LIST, options)

db.backup()               # to backup_path, or db.backup("user://elsewhere.db")
db.quick_check()          # true when intact
db.integrity_check()      # the problems found, empty when intact
```

A backup is a consistent copy made with SQLite's backup API, checked, and moved over the
previous one, so a failed backup never damages the last good copy.

On open, a file that is not a database or fails `PRAGMA quick_check` counts as corrupt. With
a `backup_path` holding a good copy, the damaged file (and its `-wal`, `-shm`, `-journal`
files) are moved aside with a `.corrupt` suffix and the backup is opened instead;
`db.recovered_from_backup()` is then true, so the game can tell the player. Without a good
backup, `open` fails with `CORRUPT` and leaves the file alone.

### Journal mode and cloud saves

The default journal, `DbOptions.Journal.DELETE`, keeps everything in the database file
itself when no write is in progress: the right choice when the file is copied or synced
(Steam Cloud). `Journal.WAL` writes faster, but recent changes sit in a `-wal` file beside
the database until a checkpoint; `close()` and `checkpoint()` write them back.

## Options

| `DbOptions`                | Default                   |                                          |
| -------------------------- | ------------------------- | ---------------------------------------- |
| `journal`                  | `DELETE`                  | see above                                |
| `busy_timeout_ms`          | `5000`                    | wait for another connection's lock       |
| `check_integrity`          | `true`                    | `PRAGMA quick_check` on open             |
| `backup_path`              | `""`                      | where `backup()` writes; enables restore |
| `restore_from_backup`      | `true`                    | open the backup when the file is corrupt |
| `backup_before_migrations` | `true`                    | needs `backup_path`                      |
| `check_schema`             | debug builds              | compare models with tables on open       |
| `strict_schema`            | `false`                   | fail the open on a difference            |
| `log_queries`              | `false`                   | print every statement with its values    |
| `report_errors`            | `true`                    | `push_error` the addon's own errors      |
| `clock`                    | system time               | a `Callable` returning Unix seconds, for timestamps and tests |

`db.query_executed(sql, args, ok, usec)` is emitted after every statement.

A `Db` must be used from one thread. Open one per thread if you need more.

## Develop

```
ggg sync
test.bat                      # every test, headless; pass GUT options: test.bat -gselect=test_query
format.bat
lint.bat
```

Tests are GUT tests in `test/`, with fixture models in `test/fixtures/`. `tools/check_scripts.gd`
loads every script with the strict warnings of `project.godot`
(`godot --headless --script res://tools/check_scripts.gd`).
