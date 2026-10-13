class_name Db
extends RefCounted
## A connection to one SQLite database, with typed models, queries and migrations.
##
## [codeblock]
## var db := Db.open("user://game.db", [Item, Character], Migrations.LIST)
## if not db.is_open():
##     push_error(db.last_error())
## [/codeblock]
## Foreign keys are always enforced. A Db must be used from one thread only.

## Emitted after every statement, whether it worked or not.
signal query_executed(sql: String, args: Array, ok: bool, usec: int)

enum ErrorKind {
    NONE,
    ## Wrong use of the API, such as updating a row that was never saved.
    USAGE,
    ## The models are invalid, or do not match the database.
    SCHEMA,
    ## A value cannot be stored in or read from its column.
    CONVERSION,
    ## The row to update or delete does not exist.
    NOT_FOUND,
    UNIQUE,
    FOREIGN_KEY,
    NOT_NULL,
    CHECK,
    ## Another constraint failed.
    CONSTRAINT,
    ## The file is damaged or is not a database.
    CORRUPT,
    ## Another connection holds a lock longer than [member DbOptions.busy_timeout_ms].
    BUSY,
    MIGRATION,
    ## Any other SQLite error.
    SQL,
}

const ASC: bool = false
const DESC: bool = true
const MIGRATIONS_TABLE: String = "_migrations"

var _sqlite: SQLite = null
var _options: DbOptions = DbOptions.new()
var _registry: DbRegistry = DbRegistry.new()
var _path: String = ""
var _is_open: bool = false
var _is_new: bool = false
var _recovered: bool = false
var _last_error: String = ""
var _last_error_kind: ErrorKind = ErrorKind.NONE
## One entry per open transaction level: whether something inside it failed.
var _transaction_failed: Array[bool] = []
## One entry per open transaction level: the first error inside it, kept for the rollback
## report even when later statements succeed and clear [method last_error].
var _transaction_errors: Array[Array] = []
var _schema_problems: PackedStringArray = []


## Opens or creates the database at [param path] (":memory:" for one that lives in memory)
## and brings its schema up to date. [param models] lists every model script;
## [param migrations] lists every [DbMigration] script. Always returns a Db: check
## [method is_open], and [method last_error] when it is not.
static func open(
    path: String,
    models: Array,
    migrations: Array = [],
    options: DbOptions = null,
) -> Db:
    var db: Db = Db.new()
    db._open(path, models, migrations, options if options != null else DbOptions.new())
    return db


static func _kind_of(message: String) -> ErrorKind:
    if message.begins_with("UNIQUE constraint failed"):
        return ErrorKind.UNIQUE
    if message.begins_with("FOREIGN KEY constraint failed"):
        return ErrorKind.FOREIGN_KEY
    if message.begins_with("NOT NULL constraint failed"):
        return ErrorKind.NOT_NULL
    if message.begins_with("CHECK constraint failed"):
        return ErrorKind.CHECK
    if message.contains("constraint failed"):
        return ErrorKind.CONSTRAINT
    if message.begins_with("cannot store"):
        return ErrorKind.CONVERSION
    if message.begins_with("database is locked") or message.contains("database table is locked"):
        return ErrorKind.BUSY
    if message.contains("not a database") or message.contains("malformed"):
        return ErrorKind.CORRUPT
    return ErrorKind.SQL
#endregion


#region State
func is_open() -> bool:
    return _is_open


## Whether [method open] created the database: the tables came from the models and no
## migration ran. Put starting data in when this is true.
func is_new() -> bool:
    return _is_new


## Whether [method open] found the database corrupt and opened the backup instead.
func recovered_from_backup() -> bool:
    return _recovered


func path() -> String:
    return _path


func options() -> DbOptions:
    return _options


## The message of the last failure, or "" when the last call worked.
func last_error() -> String:
    return _last_error


func last_error_kind() -> ErrorKind:
    return _last_error_kind


## Differences between the models and the tables, found by [member DbOptions.check_schema].
func schema_problems() -> PackedStringArray:
    return _schema_problems


## Whether a transaction is open.
func in_transaction() -> bool:
    return not _transaction_failed.is_empty()


## The current Unix time from [member DbOptions.clock].
func now() -> int:
    var time: Variant = _options.clock.call()
    return DbSql.to_int(time)


## Closes the database. A transaction still open is rolled back.
func close() -> void:
    if not _is_open:
        return
    if in_transaction():
        _run("ROLLBACK")
        _transaction_failed.clear()
        _transaction_errors.clear()
    if _options.journal == DbOptions.Journal.WAL and _path != ":memory:":
        _run("PRAGMA wal_checkpoint(TRUNCATE)")
    _run("PRAGMA optimize")
    _close_sqlite()
#endregion


#region Rows
## Inserts [param model] as a new row. An auto-increment key left at 0 and an empty UUID
## key are filled in.
func insert(model: DbModel) -> bool:
    _clear_error()
    var table: DbTable = _table_of(model)
    if table == null:
        return false
    return _insert(table, model)


## Inserts every model of [param models] in one transaction; all or none are inserted.
func insert_many(models: Array) -> bool:
    _clear_error()
    return transaction(
        func() -> bool:
            return _each_model(models, insert, "insert_many"),
    )


## Writes [param model]'s fields to its row, found by primary key. Fails with
## [constant ErrorKind.NOT_FOUND] when there is no such row.
func update(model: DbModel) -> bool:
    _clear_error()
    var table: DbTable = _table_of(model)
    if table == null:
        return false
    return _update(table, model)


## Inserts [param model], or updates its row when one with the same key exists.
func save(model: DbModel) -> bool:
    _clear_error()
    var table: DbTable = _table_of(model)
    if table == null:
        return false
    return _save(table, model)


## [method save] for every model of [param models], in one transaction.
func save_many(models: Array) -> bool:
    _clear_error()
    return transaction(
        func() -> bool:
            return _each_model(models, save, "save_many"),
    )


## Deletes [param model]'s row. Rows pointing at it follow their on_delete rule. Fails with
## [constant ErrorKind.NOT_FOUND] when there is no such row.
func delete(model: DbModel) -> bool:
    _clear_error()
    var table: DbTable = _table_of(model)
    if table == null:
        return false
    if table.is_unsaved(model):
        return _fail(ErrorKind.USAGE, "%s has no key yet, so it has no row" % table.model_name)
    var key_values: Array = _key_values(table, model)
    if key_values.is_empty() and not _last_error.is_empty():
        return false
    var sql: String = "DELETE FROM %s WHERE %s" % [DbSql.ident(table.name), _key_where(table)]
    if not _run(sql, key_values):
        return false
    if _changes() == 0:
        return _fail(
            ErrorKind.NOT_FOUND,
            "%s %s has no row" % [table.model_name, [table.key_of(model)]],
        )
    model._db_persisted = false
    return true


## The row of [param model] with primary key [param key], or null. A key over several fields
## is an Array in field order. Null with an empty [method last_error] means no such row.
func find(model: GDScript, key: Variant) -> DbModel:
    _clear_error()
    var table: DbTable = _table_of_script(model)
    if table == null:
        return null
    var keys: Array = key if table.primary_key.size() > 1 and key is Array else [key]
    if keys.size() != table.primary_key.size():
        _fail(
            ErrorKind.USAGE,
            "%s needs %d key values" % [table.model_name, table.primary_key.size()],
        )
        return null
    var query: DbQuery = select(model)
    for i: int in keys.size():
        query.where(table.primary_key[i], "=", keys[i])
    return query.first()


## Reads [param model]'s row again into the same object. Relations are not reloaded.
func reload(model: DbModel) -> bool:
    _clear_error()
    var table: DbTable = _table_of(model)
    if table == null:
        return false
    if table.is_unsaved(model):
        return _fail(ErrorKind.USAGE, "%s has no key yet, so it has no row" % table.model_name)
    var key: Variant = table.key_of(model)
    var fresh: DbModel = find(table.model_script, key)
    if fresh == null:
        if _last_error.is_empty():
            _fail(ErrorKind.NOT_FOUND, "%s %s has no row" % [table.model_name, [key]])
        return false
    for column: DbColumn in table.columns:
        model.set(column.name, fresh.get(column.name))
    model._db_persisted = true
    model._after_load()
    return true
#endregion


#region Queries
## A query for rows of [param model]. See [DbQuery].
func select(model: GDScript) -> DbQuery:
    return DbQuery.new(self, _table_of_script(model))


## Updates every row of [param model] that matches the conditions. See [DbUpdate].
func update_all(model: GDScript) -> DbUpdate:
    return DbUpdate.new(self, _table_of_script(model))


## Deletes every row of [param model] that matches the conditions. See [DbDelete].
func delete_all(model: GDScript) -> DbDelete:
    return DbDelete.new(self, _table_of_script(model))


## Runs [param sql] with [param args] bound to its "?" marks and returns the rows as
## Dictionaries. Returns an empty Array on failure; check [method last_error].
func raw(sql: String, args: Array = []) -> Array[Dictionary]:
    _clear_error()
    return _rows(sql, args)


## Runs [param sql] with [param args] bound to its "?" marks.
func execute(sql: String, args: Array = []) -> bool:
    _clear_error()
    return _run(sql, args)
#endregion


#region Transactions
## Runs [param body] in a transaction. If [param body] returns false or any statement in it
## fails, everything it did is rolled back and this returns false. Transactions nest: an
## inner one that fails rolls back only its own work, and the outer body decides what to do.
func transaction(body: Callable) -> bool:
    if not _is_open:
        return _fail(ErrorKind.USAGE, "the database is not open")
    var depth: int = _transaction_failed.size()
    var savepoint: String = DbSql.ident("sqlite_orm_%d" % depth)
    if not _run("BEGIN IMMEDIATE" if depth == 0 else "SAVEPOINT " + savepoint):
        return false
    _transaction_failed.append(false)
    _transaction_errors.append([])
    var result: Variant = body.call()
    if _transaction_failed.size() != depth + 1:
        return _fail(ErrorKind.USAGE, "the database was closed inside a transaction")
    var failed: bool = _transaction_failed.pop_back()
    var first_error: Array = _transaction_errors.pop_back()
    if typeof(result) == TYPE_BOOL and result == false:
        failed = true
    if failed:
        var error: String = _last_error
        var kind: ErrorKind = _last_error_kind
        if not first_error.is_empty():
            error = first_error[0]
            kind = first_error[1]
        if depth == 0:
            _run("ROLLBACK")
        else:
            _run("ROLLBACK TO " + savepoint)
            _run("RELEASE " + savepoint)
        if error.is_empty():
            error = "the transaction body returned false"
            kind = ErrorKind.USAGE
        _last_error = error
        _last_error_kind = kind
        return false
    if depth == 0:
        if not _run("COMMIT"):
            var error: String = _last_error
            _run("ROLLBACK")
            _last_error = error
            return false
        return true
    return _run("RELEASE " + savepoint)
#endregion


#region Relations
## Fills the relation vars named by [param relation_path] on [param model]. A path such as
## "inventory.affixes" loads the inventory, then every item's affixes.
func load(model: DbModel, relation_path: String) -> bool:
    _clear_error()
    return DbRelationIO.load_paths(self, [model], [relation_path])


## [method load] for many models at once, with one query per relation.
func load_many(models: Array, relation_path: String) -> bool:
    _clear_error()
    return DbRelationIO.load_paths(self, models, [relation_path])


## Makes the rows of the has_many or has_one relation [param relation] match
## [param parent]'s var: saves every child in it, pointing it at [param parent], and deletes
## the parent's other children. A loaded parent must have the relation loaded (see
## [method DbModel.is_loaded]), so a list that was never loaded does not wipe the rows.
func sync_children(parent: DbModel, relation: String) -> bool:
    _clear_error()
    return transaction(
        func() -> bool:
            return DbRelationIO.sync_children(self, parent, relation, { }),
    )


## Saves [param model] and the relations named by [param relation_paths], in one
## transaction: belongs_to targets first, then the row, then has_many and has_one children
## with [method sync_children]. Paths nest like "inventory.affixes".
func save_tree(model: DbModel, relation_paths: Array = []) -> bool:
    _clear_error()
    return transaction(
        func() -> bool:
            return DbRelationIO.save_tree(self, model, relation_paths),
    )
#endregion


#region Maintenance
## Writes a consistent copy of the database to [param target], or to
## [member DbOptions.backup_path]. The copy is written beside the target and then moved
## over it, so a failed backup never damages the previous one.
func backup(target: String = "") -> bool:
    _clear_error()
    if not _is_open:
        return _fail(ErrorKind.USAGE, "the database is not open")
    var destination: String = target if not target.is_empty() else _options.backup_path
    if destination.is_empty():
        return _fail(ErrorKind.USAGE, "backup() needs a target or DbOptions.backup_path")
    if in_transaction():
        return _fail(ErrorKind.USAGE, "backup() cannot run inside a transaction")
    var temporary: String = destination + ".tmp"
    DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
    if FileAccess.file_exists(temporary):
        DirAccess.remove_absolute(temporary)
    if not _sqlite.backup_to(temporary):
        return _fail(ErrorKind.SQL, "backup failed: " + _sqlite.error_message)
    if not _is_valid_database(temporary):
        DirAccess.remove_absolute(temporary)
        return _fail(ErrorKind.CORRUPT, "the backup copy failed its integrity check")
    var error: Error = DirAccess.rename_absolute(temporary, destination)
    if error != OK:
        return _fail(ErrorKind.SQL, "cannot move the backup into place: %s" % error_string(error))
    return true


## Runs PRAGMA quick_check. True when the database is intact.
func quick_check() -> bool:
    _clear_error()
    var rows: Array[Dictionary] = _rows("PRAGMA quick_check")
    return rows.size() == 1 and str(rows[0].get("quick_check")) == "ok"


## Runs PRAGMA integrity_check and returns the problems; empty when the database is intact.
func integrity_check() -> PackedStringArray:
    _clear_error()
    var problems: PackedStringArray = []
    for row: Dictionary in _rows("PRAGMA integrity_check"):
        var line: String = str(row.get("integrity_check"))
        if line != "ok":
            problems.append(line)
    return problems


## Writes the "-wal" file into the database file. Only does something in WAL mode.
func checkpoint() -> bool:
    _clear_error()
    if _options.journal != DbOptions.Journal.WAL:
        return true
    return _run("PRAGMA wal_checkpoint(TRUNCATE)")
#endregion


#region Internal: used by queries, relations and migrations
func _run(sql: String, args: Array = []) -> bool:
    if not _is_open:
        return _fail(ErrorKind.USAGE, "the database is not open")
    var started: int = Time.get_ticks_usec()
    var ok: bool = _sqlite.query(sql) if args.is_empty() else _sqlite.query_with_bindings(sql, args)
    var elapsed: int = Time.get_ticks_usec() - started
    if _options.log_queries:
        print(
            "[sqlite_orm] %s %s%s"
            % [sql, args if not args.is_empty() else "", "" if ok else " FAILED"]
        )
    query_executed.emit(sql, args, ok, elapsed)
    if not ok:
        var message: String = _sqlite.error_message
        _fail(_kind_of(message), "%s\n  in: %s" % [message, sql], true)
    return ok


func _rows(sql: String, args: Array = []) -> Array[Dictionary]:
    var rows: Array[Dictionary] = []
    if not _run(sql, args):
        return rows
    for row: Variant in _sqlite.query_result:
        var dictionary: Dictionary = row
        var keyed: Dictionary = { }
        for key: Variant in dictionary:
            keyed[str(key)] = dictionary[key]
        rows.append(keyed)
    return rows


func _each_model(models: Array, action: Callable, caller: String) -> bool:
    for item: Variant in models:
        if not item is DbModel:
            return _fail(ErrorKind.USAGE, "%s() got %s, not a DbModel" % [caller, item])
        var model: DbModel = item
        var ok: bool = action.call(model)
        if not ok:
            return false
    return true


func _changes() -> int:
    if not _sqlite.query("SELECT changes() AS n"):
        return -1
    var rows: Array = _sqlite.query_result
    var row: Dictionary = rows[0]
    return DbSql.to_int(row["n"])


func _fail(kind: ErrorKind, message: String, from_sqlite: bool = false) -> bool:
    _last_error = message
    _last_error_kind = kind
    if not _transaction_failed.is_empty():
        _transaction_failed[-1] = true
        if _transaction_errors[-1].is_empty():
            _transaction_errors[-1] = [message, kind]
    if _options.report_errors and not from_sqlite:
        push_error("sqlite_orm: " + message)
    return false


func _clear_error() -> void:
    _last_error = ""
    _last_error_kind = ErrorKind.NONE


func _table_of(model: Object) -> DbTable:
    if model == null:
        _fail(ErrorKind.USAGE, "the model is null")
        return null
    var table: DbTable = _registry.table_for(model)
    if table == null:
        _fail(ErrorKind.USAGE, "%s is not in this database's model list" % [model])
    return table


func _table_of_script(script: GDScript) -> DbTable:
    if script == null:
        _fail(ErrorKind.USAGE, "the model script is null")
        return null
    var table: DbTable = _registry.table_for_script(script)
    if table == null:
        _fail(
            ErrorKind.USAGE,
            "%s is not in this database's model list" % DbRegistry._script_name(script),
        )
    return table


## Builds a model from a row. Returns null and records the error when a value does not convert.
func _model_from_row(table: DbTable, row: Dictionary) -> DbModel:
    var model: DbModel = table.model_script.new()
    for column: DbColumn in table.columns:
        var value: Variant = column.from_sql(row.get(column.name))
        var error: String = column.take_error()
        if not error.is_empty():
            _fail(ErrorKind.CONVERSION, "%s: %s" % [table.model_name, error])
            return null
        model.set(column.name, value)
    model._db_persisted = true
    model._db_read = true
    model._after_load()
    return model


## The SQL value of every key field of [param model]. Empty on a conversion error.
func _key_values(table: DbTable, model: Object) -> Array:
    var values: Array = []
    for key: String in table.primary_key:
        var column: DbColumn = table.column(key)
        var value: Variant = column.to_sql(model.get(key))
        var error: String = column.take_error()
        if not error.is_empty():
            _fail(ErrorKind.CONVERSION, "%s: %s" % [table.model_name, error])
            return []
        values.append(value)
    return values


func _key_where(table: DbTable) -> String:
    var parts: PackedStringArray = []
    for key: String in table.primary_key:
        parts.append("%s = ?" % DbSql.ident(key))
    return " AND ".join(parts)


func _insert(table: DbTable, model: DbModel) -> bool:
    model._before_save()
    if not DbRelationIO.copy_belongs_to_keys(self, table, model):
        return false
    var overrides: Dictionary = _automatic_values(table, model, true)
    var names: Array[String] = []
    var marks: PackedStringArray = []
    var values: Array = []
    for column: DbColumn in table.columns:
        if column == table.auto_key and DbSql.to_int(model.get(column.name)) == 0:
            continue
        var value: Variant = _stored(
            table,
            column,
            overrides.get(column.name, model.get(column.name)),
        )
        if not _last_error.is_empty():
            return false
        names.append(column.name)
        marks.append(DbSql.bind(value, values))
    var sql: String = "INSERT INTO %s DEFAULT VALUES" % DbSql.ident(table.name)
    if not names.is_empty():
        sql = "INSERT INTO %s (%s) VALUES (%s)" % [
            DbSql.ident(table.name),
            DbSql.idents(names),
            ", ".join(marks),
        ]
    if not _run(sql, values):
        return false
    for key: String in overrides:
        model.set(key, overrides[key])
    if table.auto_key != null and DbSql.to_int(model.get(table.auto_key.name)) == 0:
        model.set(table.auto_key.name, _sqlite.last_insert_rowid)
    model._db_persisted = true
    return true


func _update(table: DbTable, model: DbModel) -> bool:
    if table.is_unsaved(model):
        return _fail(ErrorKind.USAGE, "%s has no key yet; insert it first" % table.model_name)
    model._before_save()
    if not DbRelationIO.copy_belongs_to_keys(self, table, model):
        return false
    var overrides: Dictionary = _automatic_values(table, model, false)
    var assignments: PackedStringArray = []
    var values: Array = []
    for column: DbColumn in table.columns:
        if column.primary_key:
            continue
        var value: Variant = _stored(
            table,
            column,
            overrides.get(column.name, model.get(column.name)),
        )
        if not _last_error.is_empty():
            return false
        assignments.append("%s = %s" % [DbSql.ident(column.name), DbSql.bind(value, values)])
    var key_values: Array = _key_values(table, model)
    if key_values.is_empty():
        return false
    var sql: String
    if assignments.is_empty():
        sql = "UPDATE %s SET %s = %s WHERE %s" % [
            DbSql.ident(table.name),
            DbSql.ident(table.primary_key[0]),
            DbSql.ident(table.primary_key[0]),
            _key_where(table),
        ]
    else:
        sql = "UPDATE %s SET %s WHERE %s" % [
            DbSql.ident(table.name),
            ", ".join(assignments),
            _key_where(table),
        ]
    values.append_array(key_values)
    if not _run(sql, values):
        return false
    if _changes() == 0:
        return _fail(
            ErrorKind.NOT_FOUND,
            "%s %s has no row" % [table.model_name, [table.key_of(model)]],
        )
    for key: String in overrides:
        model.set(key, overrides[key])
    model._db_persisted = true
    return true


func _save(table: DbTable, model: DbModel) -> bool:
    if table.is_unsaved(model):
        return _insert(table, model)
    model._before_save()
    if not DbRelationIO.copy_belongs_to_keys(self, table, model):
        return false
    var overrides: Dictionary = _automatic_values(table, model, true)
    var names: Array[String] = []
    var marks: PackedStringArray = []
    var values: Array = []
    var assignments: PackedStringArray = []
    for column: DbColumn in table.columns:
        var value: Variant = _stored(
            table,
            column,
            overrides.get(column.name, model.get(column.name)),
        )
        if not _last_error.is_empty():
            return false
        names.append(column.name)
        marks.append(DbSql.bind(value, values))
        if not column.primary_key and not column.auto_created:
            assignments.append(
                "%s = excluded.%s" % [DbSql.ident(column.name), DbSql.ident(column.name)]
            )
    var returning: Array[String] = []
    for column: DbColumn in table.columns:
        if column.auto_created:
            returning.append(column.name)
    var sql: String = "INSERT INTO %s (%s) VALUES (%s) ON CONFLICT (%s) DO %s" % [
        DbSql.ident(table.name),
        DbSql.idents(names),
        ", ".join(marks),
        DbSql.idents(table.primary_key),
        "NOTHING" if assignments.is_empty() else "UPDATE SET " + ", ".join(assignments),
    ]
    if not returning.is_empty() and not assignments.is_empty():
        sql += " RETURNING " + DbSql.idents(returning)
    if not _run(sql, values):
        return false
    for key: String in overrides:
        model.set(key, overrides[key])
    if not returning.is_empty() and not assignments.is_empty():
        var rows: Array = _sqlite.query_result
        if rows.size() == 1:
            var row: Dictionary = rows[0]
            for key: String in returning:
                model.set(key, row[key])
    model._db_persisted = true
    return true


## The values the addon fills in on write: UUIDs and timestamps. Written back to the model
## only after the statement works.
func _automatic_values(table: DbTable, model: DbModel, inserting: bool) -> Dictionary:
    var values: Dictionary = { }
    var time: int = now()
    for column: DbColumn in table.columns:
        var current: Variant = model.get(column.name)
        if column.uuid and inserting and str(current).is_empty():
            var id: String = DbSql.uuid_v4()
            values[column.name] = StringName(id) if column.value_type == TYPE_STRING_NAME else id
        if column.auto_created and inserting and typeof(current) == TYPE_INT and current == 0:
            values[column.name] = time
        if column.auto_updated:
            values[column.name] = time
    return values


func _stored(table: DbTable, column: DbColumn, value: Variant) -> Variant:
    var stored: Variant = column.to_sql(value)
    var error: String = column.take_error()
    if not error.is_empty():
        _fail(ErrorKind.CONVERSION, "%s: %s" % [table.model_name, error])
        return null
    return stored
#endregion


#region Internal: opening
func _open(path: String, models: Array, migrations: Array, options: DbOptions) -> void:
    _options = options
    _path = path
    var errors: PackedStringArray = _registry.compile(models)
    if not errors.is_empty():
        _fail(ErrorKind.SCHEMA, "the models are invalid:\n  " + "\n  ".join(errors))
        return
    var runner: DbMigrationRunner = DbMigrationRunner.new(self)
    errors = runner.load_scripts(migrations)
    if not errors.is_empty():
        _fail(ErrorKind.MIGRATION, "the migrations are invalid:\n  " + "\n  ".join(errors))
        return
    if not _open_file():
        return
    if not _configure() or not _prepare_schema(runner):
        _close_sqlite()
        return
    if _options.check_schema:
        _schema_problems = DbSchemaCheck.new(self).run()
        if not _schema_problems.is_empty():
            var message: String = "the models do not match the database:\n  " + "\n  ".join(
                _schema_problems
            )
            if _options.strict_schema:
                _fail(ErrorKind.SCHEMA, message)
                _close_sqlite()
                return
            push_warning("sqlite_orm: " + message)
    _clear_error()


func _open_file() -> bool:
    var in_memory: bool = _path == ":memory:"
    if not in_memory:
        DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
    if _try_open():
        return true
    var reason: String = _last_error
    var reason_kind: ErrorKind = _last_error_kind
    var can_restore: bool = (
        not in_memory and _options.restore_from_backup and not _options.backup_path.is_empty()
    )
    if can_restore and _restore_backup() and _try_open():
        _recovered = true
        push_warning("sqlite_orm: %s was damaged (%s); opened the backup instead" % [_path, reason])
        return true
    _fail(reason_kind if reason_kind != ErrorKind.NONE else ErrorKind.CORRUPT, reason)
    return false


func _try_open() -> bool:
    _close_sqlite()
    _sqlite = SQLite.new()
    _sqlite.verbosity_level = SQLite.QUIET
    _sqlite.default_extension = ""
    _sqlite.path = _path
    _sqlite.foreign_keys = true
    if not _sqlite.open_db():
        _fail(ErrorKind.CORRUPT, "cannot open %s: %s" % [_path, _sqlite.error_message], true)
        _sqlite = null
        return false
    _is_open = true
    if not _run("SELECT count(*) AS n FROM sqlite_master"):
        _last_error_kind = ErrorKind.CORRUPT
        _close_sqlite()
        return false
    if _options.check_integrity and _path != ":memory:" and not quick_check():
        if _last_error.is_empty():
            _fail(ErrorKind.CORRUPT, "%s failed its integrity check" % _path, true)
        _last_error_kind = ErrorKind.CORRUPT
        _close_sqlite()
        return false
    return true


func _close_sqlite() -> void:
    if _sqlite != null and _is_open:
        _sqlite.close_db()
    _sqlite = null
    _is_open = false


func _restore_backup() -> bool:
    var backup_path: String = _options.backup_path
    if not FileAccess.file_exists(backup_path) or not _is_valid_database(backup_path):
        return false
    _close_sqlite()
    for suffix: String in ["", "-wal", "-shm", "-journal"]:
        var file: String = _path + suffix
        if FileAccess.file_exists(file):
            var aside: String = file + ".corrupt"
            if FileAccess.file_exists(aside):
                DirAccess.remove_absolute(aside)
            if DirAccess.rename_absolute(file, aside) != OK:
                return false
    return DirAccess.copy_absolute(backup_path, _path) == OK


func _is_valid_database(file: String) -> bool:
    var probe: SQLite = SQLite.new()
    probe.verbosity_level = SQLite.QUIET
    probe.default_extension = ""
    probe.path = file
    probe.read_only = true
    if not probe.open_db():
        return false
    var ok: bool = probe.query("PRAGMA quick_check")
    if ok:
        var rows: Array = probe.query_result
        var row: Dictionary = rows[0] if rows.size() == 1 else { }
        ok = str(row.get("quick_check")) == "ok"
    probe.close_db()
    return ok


func _configure() -> bool:
    if _path != ":memory:":
        var mode: String = "WAL" if _options.journal == DbOptions.Journal.WAL else "DELETE"
        var rows: Array[Dictionary] = _rows("PRAGMA journal_mode = " + mode)
        if rows.is_empty() or str(rows[0].get("journal_mode")).to_upper() != mode:
            if _last_error.is_empty():
                _fail(ErrorKind.SQL, "cannot set journal_mode to " + mode)
            return false
        var synchronous: String = "NORMAL" if mode == "WAL" else "FULL"
        if not _run("PRAGMA synchronous = " + synchronous):
            return false
    if not _run("PRAGMA busy_timeout = %d" % maxi(0, _options.busy_timeout_ms)):
        return false
    if not _run("PRAGMA foreign_keys = ON"):
        return false
    var check: Array[Dictionary] = _rows("PRAGMA foreign_keys")
    if check.is_empty() or DbSql.to_int(check[0].get("foreign_keys")) != 1:
        return _fail(ErrorKind.SQL, "foreign keys cannot be turned on")
    return true


func _prepare_schema(runner: DbMigrationRunner) -> bool:
    var rows: Array[Dictionary] = _rows(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
    )
    if not _last_error.is_empty():
        return false
    var existing: Array[String] = []
    for row: Dictionary in rows:
        existing.append(str(row["name"]))
    if existing.is_empty():
        _is_new = true
        return transaction(
            func() -> bool:
                return _create_all(runner),
        )
    if MIGRATIONS_TABLE not in existing:
        return _fail(
            ErrorKind.SCHEMA,
            "%s has tables but no %s table; it was not made by sqlite_orm"
            % [_path, MIGRATIONS_TABLE],
        )
    return runner.run()


func _create_all(runner: DbMigrationRunner) -> bool:
    if not _run(DbMigrationRunner.CREATE_TABLE_SQL):
        return false
    for table: DbTable in _registry.ordered:
        if not _run(table.create_sql()):
            return false
        for statement: String in table.index_sql():
            if not _run(statement):
                return false
    var time: int = now()
    for version: int in runner.versions():
        var sql: String = "INSERT INTO %s (version, applied_at) VALUES (?, ?)" % DbSql.ident(
            MIGRATIONS_TABLE
        )
        if not _run(sql, [version, time]):
            return false
    return true
