class_name DbTestCase
extends GutTest
## Shared helpers for the addon's tests: databases in memory or in a scratch folder that is
## removed after each test.

const SCRATCH_ROOT: String = "user://sqlite_orm_tests"

var _scratch: String = ""
var _opened: Array[Db] = []
var _clock_time: int = 1_000


## Every fixture model.
static func all_models() -> Array:
    return [
        FxItem,
        FxCharacter,
        FxHero,
        FxGear,
        FxAffix,
        FxQuest,
        FxEquipped,
        FxBanner,
        FxPerson,
        FxGuild,
        FxMember,
        FxPaint,
        FxTick,
    ]


func before_each() -> void:
    _scratch = "%s/%d_%d" % [SCRATCH_ROOT, Time.get_ticks_usec(), randi()]
    DirAccess.make_dir_recursive_absolute(_scratch)
    _clock_time = 1_000


func after_each() -> void:
    for db: Db in _opened:
        db.close()
    _opened.clear()
    _remove_tree(_scratch)


## Options for tests: errors are not pushed (tests read last_error instead), the schema is
## checked strictly, and time comes from [method advance_clock].
func make_options() -> DbOptions:
    var options: DbOptions = DbOptions.new()
    options.report_errors = false
    options.check_schema = true
    options.strict_schema = true
    options.clock = func() -> int:
        return _clock_time
    return options


func advance_clock(seconds: int) -> void:
    _clock_time += seconds


func clock_time() -> int:
    return _clock_time


func open_memory(models: Array = [], migrations: Array = [], options: DbOptions = null) -> Db:
    var db: Db = Db.open(
        ":memory:",
        models if not models.is_empty() else all_models(),
        migrations,
        options if options != null else make_options(),
    )
    _opened.append(db)
    return db


func open_file(
    file_name: String,
    models: Array = [],
    migrations: Array = [],
    options: DbOptions = null,
) -> Db:
    var db: Db = Db.open(
        scratch_path(file_name),
        models if not models.is_empty() else all_models(),
        migrations,
        options if options != null else make_options(),
    )
    _opened.append(db)
    return db


## A path inside this test's scratch folder.
func scratch_path(file_name: String) -> String:
    return _scratch.path_join(file_name)


## Asserts that [param db] opened, printing its error when it did not.
func assert_open(db: Db) -> void:
    assert_true(db.is_open(), "database should open: " + db.last_error())


func assert_ok(ok: bool, db: Db, text: String = "") -> void:
    assert_true(ok, "%s %s" % [text, db.last_error()])


func assert_failed(ok: bool, db: Db, kind: Db.ErrorKind, contains: String = "") -> void:
    assert_false(ok, "the call should fail")
    assert_eq(db.last_error_kind(), kind, "error kind, message: " + db.last_error())
    if not contains.is_empty():
        assert_string_contains(db.last_error(), contains)


## Marks the engine errors godot-sqlite printed for a failing statement as expected.
func expect_engine_errors(text: String = "") -> void:
    for error: Variant in get_errors():
        var tracked: Object = error
        if (
            text.is_empty() or str(tracked.get("code")).contains(text)
            or str(tracked.get("rationale")).contains(text)
        ):
            tracked.set("handled", true)


## Counts statements run on [param db] while [param body] runs.
func count_queries(db: Db, body: Callable) -> int:
    var counter: Array[int] = [0]
    var listener: Callable = func(_sql: String, _args: Array, _ok: bool, _usec: int) -> void:
        counter[0] += 1
    db.query_executed.connect(listener)
    body.call()
    db.query_executed.disconnect(listener)
    return counter[0]


func make_item(item_name: String, damage: int = 1) -> FxItem:
    var item: FxItem = FxItem.new()
    item.name = item_name
    item.damage = damage
    return item


func make_character(character_name: String, level: int = 1) -> FxCharacter:
    var character: FxCharacter = FxCharacter.new()
    character.name = character_name
    character.level = level
    return character


func make_hero(hero_name: String) -> FxHero:
    var hero: FxHero = FxHero.new()
    hero.display_name = hero_name
    return hero


func make_gear(base: StringName, affix_values: Array = []) -> FxGear:
    var gear: FxGear = FxGear.new()
    gear.base_id = base
    for value: Variant in affix_values:
        var affix: FxAffix = FxAffix.new()
        affix.affix_id = &"power"
        affix.value = DbSql.to_float(value)
        gear.affixes.append(affix)
    return gear


func _remove_tree(path: String) -> void:
    if path.is_empty() or not DirAccess.dir_exists_absolute(path):
        return
    for file: String in DirAccess.get_files_at(path):
        DirAccess.remove_absolute(path.path_join(file))
    for folder: String in DirAccess.get_directories_at(path):
        _remove_tree(path.path_join(folder))
    DirAccess.remove_absolute(path)
