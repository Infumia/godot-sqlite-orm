class_name DbMigrationRunner
extends RefCounted
## Checks the migration list and runs the migrations a database has not run yet.
## Not part of the public API.

const CREATE_TABLE_SQL: String = (
    "CREATE TABLE \"_migrations\" (\"version\" INTEGER PRIMARY KEY, "
    + "\"applied_at\" INTEGER NOT NULL) STRICT"
)

var _db: Db
var _scripts: Dictionary[int, GDScript] = { }


func _init(db: Db) -> void:
    _db = db


## Reads the VERSION of every script in [param migrations]. Returns the problems found.
func load_scripts(migrations: Array) -> PackedStringArray:
    var errors: PackedStringArray = []
    for item: Variant in migrations:
        if not item is GDScript:
            errors.append("migration list holds %s, not a GDScript" % [item])
            continue
        var script: GDScript = item
        var label: String = script.resource_path.get_file()
        var constants: Dictionary = script.get_script_constant_map()
        if not constants.has("VERSION"):
            errors.append("%s has no VERSION constant" % label)
            continue
        var version: Variant = constants["VERSION"]
        if typeof(version) != TYPE_INT:
            errors.append("%s: VERSION must be an int" % label)
            continue
        var number: int = version
        if number < 1:
            errors.append("%s: VERSION must be 1 or more" % label)
            continue
        if _scripts.has(number):
            errors.append(
                "%s and %s both have VERSION %d"
                % [_scripts[number].resource_path.get_file(), label, number]
            )
            continue
        if not script.can_instantiate() or not script.new() is DbMigration:
            errors.append("%s does not extend DbMigration" % label)
            continue
        _scripts[number] = script
    return errors


## Every listed version, lowest first.
func versions() -> Array[int]:
    var numbers: Array[int] = []
    numbers.assign(_scripts.keys())
    numbers.sort()
    return numbers


## Runs the pending migrations. Foreign keys are off while they run, so tables can be
## rebuilt; each migration must leave no broken references, or it is rolled back.
func run() -> bool:
    var rows: Array[Dictionary] = _db._rows("SELECT version FROM \"_migrations\" ORDER BY version")
    if not _db.last_error().is_empty():
        return false
    var applied: Array[int] = []
    for row: Dictionary in rows:
        applied.append(DbSql.to_int(row["version"]))
    var highest: int = applied.max() if not applied.is_empty() else 0
    for version: int in applied:
        if not _scripts.has(version):
            return _db._fail(
                Db.ErrorKind.MIGRATION,
                (
                    "the database has migration %d, which this build does not know; "
                    + "it was made by a newer version"
                )
                % version,
            )
    var pending: Array[int] = []
    for version: int in versions():
        if version in applied:
            continue
        if version < highest:
            return _db._fail(
                Db.ErrorKind.MIGRATION,
                "migration %d is not applied but %d is; it was added out of order"
                % [version, highest],
            )
        pending.append(version)
    if pending.is_empty():
        return true

    var options: DbOptions = _db.options()
    if options.backup_before_migrations and not options.backup_path.is_empty():
        if not _db.backup():
            return false
    if not _db._run("PRAGMA foreign_keys = OFF"):
        return false
    var ok: bool = true
    for version: int in pending:
        ok = _db.transaction(
            func() -> bool:
                return _apply(version),
        )
        if not ok:
            if _db.last_error_kind() != Db.ErrorKind.MIGRATION:
                _db._last_error = "migration %d: %s" % [version, _db.last_error()]
                _db._last_error_kind = Db.ErrorKind.MIGRATION
            break
    var error: String = _db.last_error()
    var kind: Db.ErrorKind = _db.last_error_kind()
    _db._run("PRAGMA foreign_keys = ON")
    if not ok:
        _db._last_error = error
        _db._last_error_kind = kind
    return ok


func _apply(version: int) -> bool:
    var migration: DbMigration = _scripts[version].new()
    var migrator: DbMigrator = DbMigrator.new(_db, version)
    migration.up(migrator)
    if migrator.failed():
        return false
    var violations: Array[Dictionary] = _db._rows("PRAGMA foreign_key_check")
    if not _db.last_error().is_empty():
        return false
    if not violations.is_empty():
        var first: Dictionary = violations[0]
        return _db._fail(
            Db.ErrorKind.MIGRATION,
            "migration %d leaves %d broken references, first in table '%s' row %s"
            % [version, violations.size(), first.get("table"), first.get("rowid")],
        )
    return _db._run(
        "INSERT INTO \"_migrations\" (version, applied_at) VALUES (?, ?)",
        [version, _db.now()],
    )
