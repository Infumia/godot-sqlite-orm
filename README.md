# godot-sqlite-orm

A Godot 4 addon for SQLite: models declared in GDScript,
tables created from them, a method-based query builder, and versioned migrations.
Foreign keys are always enforced.

Built on [godot-sqlite](https://github.com/2shady4u/godot-sqlite).

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

## Usage

> **Status:** in development. The examples below show the target API.

### Models

A model is a script that extends `DbModel`. Its typed `var`s are the table's columns;
`_schema` adds the table name and the constraints.

```gdscript
# item.gd
class_name Item
extends DbModel

var id: int
var name: String
var damage: int = 0


static func _schema(s: SchemaBuilder) -> void:
	s.table("items")
	s.field("id").primary_key().auto_increment()
	s.field("name").not_null().unique()
```

```gdscript
# character.gd
class_name Character
extends DbModel

var id: int
var name: String
var level: int = 1
var weapon_id: Variant  # the column: int or null
var weapon: Item  # the relation: filled only when loaded


static func _schema(s: SchemaBuilder) -> void:
	s.table("characters")
	s.field("id").primary_key().auto_increment()
	s.field("name").not_null()
	s.field("level").not_null().check(">= 1")
	s.field("weapon_id").belongs_to("weapon", Item).on_delete_set_null()
```

Column types come from the `var` types: `int` → `INTEGER`, `float` → `REAL`,
`String` → `TEXT`, `bool` → `INTEGER` (0/1), `PackedByteArray` → `BLOB`.
Columns allow `NULL` unless marked `.not_null()`. A typed `int` cannot hold `null`, so a
column that can be `NULL` is declared as `Variant`; its type then comes from `_schema`
(`.type(TYPE_INT)`, or the target field for a foreign key).

### Unique constraints and indexes

`.unique()` on a field makes that one column unique. `s.unique([...])` makes several
columns unique together, and `s.index([...])` adds a plain index:

```gdscript
# person.gd
class_name Person
extends DbModel

var id: int
var name: String
var surname: String
var government_id: String


static func _schema(s: SchemaBuilder) -> void:
	s.table("people")
	s.field("id").primary_key().auto_increment()  # a primary key is already unique
	s.field("name").not_null()
	s.field("surname").not_null()
	s.field("government_id").not_null().unique()
	s.unique(["name", "surname"])  # a second "Ada Lovelace" is rejected
	s.index(["surname", "name"])
```

```sql
CREATE UNIQUE INDEX people_name_surname_unique ON people(name, surname);
CREATE INDEX people_surname_name_index ON people(surname, name);
```

- Both are created as indexes, not as constraints inside `CREATE TABLE`. SQLite cannot add
  a constraint to an existing table, but it can add an index, so a migration can add or
  drop them without rebuilding the table.
- SQLite treats every `NULL` as different from every other value in a unique check: two
  rows with `name = "Ada"` and `surname = NULL` are both allowed. Mark the columns of a
  multi-column unique `.not_null()`.

### Opening a database

```gdscript
var db := Db.open("user://game.db", [Item, Character], Migrations.LIST)
```

`open` turns on `PRAGMA foreign_keys`, sets WAL mode, then brings the schema up to date:
on a new database it creates the tables from the models; on an existing one it runs
the migrations that have not run yet (see [Migrations](#migrations)).

### Insert, update, delete

```gdscript
var sword := Item.new()
sword.name = "Iron Sword"
sword.damage = 12
db.insert(sword)  # sword.id is set from the new row

var hero := Character.new()
hero.name = "Aria"
hero.weapon = sword  # or hero.weapon_id = sword.id
db.insert(hero)

hero.level += 1
db.update(hero)  # by primary key

var found := db.find(Character, hero.id) as Character  # null when there is no such row

db.delete(sword)  # the row's weapon_id becomes null (ON DELETE SET NULL)
```

### Queries

Values are always sent as bound parameters, never pasted into the SQL.

```gdscript
# Array of Character
var top: Array = (
	db.select(Character)
	.where("level", ">=", 10)
	.order_by("level", Db.DESC)
	.limit(5)
	.all()
)

var aria := db.select(Character).where("name", "=", "Aria").first() as Character

var unarmed := db.select(Character).where_null("weapon_id").count()

var party: Array = db.select(Character).where_in("id", [1, 4, 7]).all()

# Several conditions are joined with AND; or_where starts an OR
var picked: Array = (
	db.select(Character)
	.where("level", ">", 20)
	.or_where("name", "LIKE", "A%")
	.all()
)

# Bulk update and delete
db.update_all(Character).set("level", 1).where("level", ">", 99).execute()
db.delete_all(Character).where("level", "<", 2).execute()

# Raw SQL when the builder is not enough; rows come back as Dictionaries
var rows: Array = db.raw(
	"SELECT c.name, i.name AS weapon FROM characters c JOIN items i ON i.id = c.weapon_id WHERE i.damage > ?",
	[10],
)
```

### Relations

A foreign key is a column declared with `s.field` like any other, plus `.references()`:

```gdscript
s.field("owner_id").references(Player).on_delete_cascade()
# owner_id INTEGER REFERENCES players(id) ON DELETE CASCADE
```

`.belongs_to()` does the same and also binds a relation `var` that holds the target row:

```gdscript
s.field("weapon_id").belongs_to("weapon", Item).on_delete_set_null()
# weapon_id INTEGER REFERENCES items(id) ON DELETE SET NULL
```

| Part        | Comes from                     | Change with                       |
| ----------- | ------------------------------ | --------------------------------- |
| Target      | `Item`'s table and primary key | `.to("field")`                    |
| Column type | the target field's type        | —                                 |
| `ON DELETE` | `.on_delete_*()`               | `set_null`, `cascade`, `restrict` |

```gdscript
s.field("equipped_item_id").belongs_to("equipped", Item).to("uuid").on_delete_cascade()
# equipped_item_id TEXT REFERENCES items(uuid) ON DELETE CASCADE
```

- The model needs a `var` for the column (`weapon_id`) and, for `belongs_to`, a typed
  `var` for the relation (`weapon: Item`). The relation is not a column and is never written.
- Foreign key columns get an index, since SQLite does not index them by itself.
- `Db.open` reports an error when one of these `var`s is missing.

Relations are never loaded on their own; ask for them:

```gdscript
# One extra query for all the weapons, not one per character
var armed: Array = db.select(Character).with("weapon").all()

db.load(hero, "weapon")  # fills hero.weapon for one row

hero.weapon = sword
db.update(hero)  # weapon_id is taken from sword.id; an unsaved sword is an error
```

### Transactions

Everything inside the callable is committed together. If it returns `false` or a
statement fails, all of it is rolled back.

```gdscript
var ok := db.transaction(func() -> bool:
	db.insert(shield)
	hero.weapon_id = shield.id
	return db.update(hero)
)
```

## Migrations

A migration changes an existing database. Each one sets its own `VERSION`; the file name
and the order in the list do not matter.

```gdscript
# add_character_xp.gd
extends DbMigration

const VERSION := 1


func up(m: Migrator) -> void:
	m.add_column(Character, "xp")  # type and default come from the model
	m.execute("UPDATE characters SET xp = level * 100")
```

```gdscript
# rename_item_damage.gd
extends DbMigration

const VERSION := 2


func up(m: Migrator) -> void:
	# SQLite cannot change a column's type or constraints in place, so the table is
	# rebuilt from the model and the rows are copied over: old column -> new column.
	m.rebuild_table(Item, {"damage": "attack"})
```

```gdscript
# add_settings_volume.gd
extends DbMigration

const VERSION := 3


func up(m: Migrator) -> void:
	# Spell the column out when the migration must not change if the model changes later.
	m.add_column_raw("settings", "volume", TYPE_FLOAT, {"default": 1.0, "not_null": true})
```

```gdscript
# unique_person_name.gd
extends DbMigration

const VERSION := 4


func up(m: Migrator) -> void:
	m.add_unique(Person, ["name", "surname"])  # fails if duplicates already exist
	m.drop_index(Person, ["surname", "name"])
```

All migrations are listed in one script, so they are found in exported builds too:

```gdscript
# migrations.gd
class_name Migrations

const LIST := [
	preload("migrations/add_character_xp.gd"),
	preload("migrations/rename_item_damage.gd"),
	preload("migrations/add_settings_volume.gd"),
	preload("migrations/unique_person_name.gd"),
]
```

How `Db.open` uses them:

- Applied versions are kept in a `_migrations` table.
- **New database:** the tables are created from the models, and every listed version is
  recorded as applied without running. The models already describe the latest schema.
- **Existing database:** each version not yet applied runs in version order, in its own
  transaction together with its `_migrations` row. A failure rolls that step back and stops.
- Two migrations with the same `VERSION`, or a missing `VERSION`, is an error.
- An unapplied version lower than the highest applied one is an error (it was added out
  of order and would otherwise be skipped silently).
- In debug builds, `open` compares the models with the real tables and warns when they
  differ, which usually means a migration is missing.

Starting data belongs in a seed step, not in a migration, because migrations do not run
on a new database:

```gdscript
if db.is_new():
	db.insert(starter_sword)
```

## Develop

```
ggg sync
ggg edit
```

Tests are GUT tests in `test/`. The design is in `docs/design.md`.
