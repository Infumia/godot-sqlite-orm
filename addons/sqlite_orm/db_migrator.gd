class_name DbMigrator
extends RefCounted
## The steps a [DbMigration] can take. Every step returns false when it fails; after the
## first failure the rest do nothing and the migration is rolled back.
##
## Steps that take a model read its current definition. When a migration must not change if
## the model changes later, spell the change out with the "_raw" steps or [method execute].

var _db: Db
var _version: int
var _failed: bool = false


func _init(db: Db, version: int) -> void:
    _db = db
    _version = version


## Whether a step failed.
func failed() -> bool:
    return _failed


## Stops the migration with [param message]; it is rolled back.
func fail(message: String) -> bool:
    return _stop(message)


## Runs [param sql] with [param args] bound to its "?" marks.
func execute(sql: String, args: Array = []) -> bool:
    if _failed:
        return false
    return _check(_db._run(sql, args))


## Runs a query and returns its rows, for migrations that move data.
func query(sql: String, args: Array = []) -> Array[Dictionary]:
    if _failed:
        return []
    var rows: Array[Dictionary] = _db._rows(sql, args)
    _check(_db.last_error().is_empty())
    return rows


## Creates [param model]'s table and indexes, for a model added after the first release.
func create_table(model: GDScript) -> bool:
    var table: DbTable = _table(model)
    if table == null:
        return false
    if not execute(table.create_sql()):
        return false
    for statement: String in table.index_sql():
        if not execute(statement):
            return false
    return true


func drop_table(table_name: String) -> bool:
    return execute("DROP TABLE %s" % DbSql.ident(table_name))


func rename_table(old_name: String, new_name: String) -> bool:
    return execute("ALTER TABLE %s RENAME TO %s" % [DbSql.ident(old_name), DbSql.ident(new_name)])


## Adds the column of [param model]'s [param field] as the model declares it now. A NOT NULL
## column needs a default, which typed fields have. A unique field gets its index too.
func add_column(model: GDScript, field: String) -> bool:
    var table: DbTable = _table(model)
    if table == null:
        return false
    var column: DbColumn = table.column(field)
    if column == null:
        return _stop("%s has no field '%s'" % [table.model_name, field])
    if column.primary_key:
        return _stop("add_column() cannot add a primary key; use rebuild_table()")
    var sql: String = "ALTER TABLE %s ADD COLUMN %s" % [
        DbSql.ident(table.name),
        column.definition(false),
    ]
    if not execute(sql):
        return false
    for index: DbTable.IndexDef in table.indexes:
        if field in index.columns and _columns_exist(table.name, index.columns):
            if not execute(index.create_sql(table.name)):
                return false
    return true


## Adds a column spelled out in full. [param options] may hold "not_null" (bool),
## "default" (a value) and "check" (SQL, as in [method DbField.check]).
func add_column_raw(
    table_name: String,
    column_name: String,
    variant_type: int,
    options: Dictionary = { },
) -> bool:
    var column: DbColumn = DbColumn.new()
    column.name = column_name
    column.value_type = variant_type
    column.var_type = variant_type
    var error: String = column.resolve_kind()
    if not error.is_empty():
        return _stop(error)
    column.nullable = not options.get("not_null", false)
    if options.has("default"):
        column.has_default = true
        column.default_value = options["default"]
        if not column.default_is_valid():
            return _stop("the default of '%s' cannot be stored" % column_name)
    column.check_sql = str(options.get("check", ""))
    return execute(
        "ALTER TABLE %s ADD COLUMN %s" % [DbSql.ident(table_name), column.definition(false)]
    )


func rename_column(table_name: String, old_name: String, new_name: String) -> bool:
    return execute(
        "ALTER TABLE %s RENAME COLUMN %s TO %s"
        % [DbSql.ident(table_name), DbSql.ident(old_name), DbSql.ident(new_name)]
    )


## Drops a column. SQLite refuses when the column is a key, unique, indexed or referenced;
## use [method rebuild_table] then.
func drop_column(table_name: String, column_name: String) -> bool:
    return execute(
        "ALTER TABLE %s DROP COLUMN %s" % [DbSql.ident(table_name), DbSql.ident(column_name)]
    )


## Rebuilds [param model]'s table from its current definition and copies the rows over: the
## way to change a column's type, constraints or key, which SQLite cannot alter in place.
## Columns keep their data by name; [param renames] maps old names to new ones. A new
## column without a source takes its default. Indexes are created again.
func rebuild_table(model: GDScript, renames: Dictionary = { }) -> bool:
    var table: DbTable = _table(model)
    if table == null:
        return false
    var old_columns: Array[String] = _column_names(table.name)
    if _failed:
        return false
    if old_columns.is_empty():
        return _stop("table '%s' does not exist" % table.name)
    for old_name: Variant in renames:
        if str(old_name) not in old_columns:
            return _stop("rebuild_table(): '%s' has no column '%s'" % [table.name, old_name])
        if not table.has_column(str(renames[old_name])):
            return _stop(
                "rebuild_table(): %s has no field '%s'" % [table.model_name, renames[old_name]]
            )
    var sources: Dictionary = { }
    for old_name: String in old_columns:
        var new_name: String = str(renames.get(old_name, old_name))
        if table.has_column(new_name):
            sources[new_name] = old_name
    var targets: Array[String] = []
    var selects: Array[String] = []
    for column: DbColumn in table.columns:
        if sources.has(column.name):
            targets.append(column.name)
            selects.append(sources[column.name])
        elif not column.nullable and not column.has_default:
            return _stop(
                "rebuild_table(): '%s' is new and NOT NULL but has no default" % column.name
            )
    var temporary: String = "_sqlite_orm_new_" + table.name
    if not execute(table.create_sql(temporary)):
        return false
    if not targets.is_empty():
        var copy: String = "INSERT INTO %s (%s) SELECT %s FROM %s" % [
            DbSql.ident(temporary),
            DbSql.idents(targets),
            DbSql.idents(selects),
            DbSql.ident(table.name),
        ]
        if not execute(copy):
            return false
    if not drop_table(table.name) or not rename_table(temporary, table.name):
        return false
    for statement: String in table.index_sql():
        if not execute(statement):
            return false
    return true


## Adds the unique index over [param fields] that [param model] declares. Fails when rows
## already break it.
func add_unique(model: GDScript, fields: Array[String]) -> bool:
    return _add_index(model, fields, true)


## Adds the index over [param fields] that [param model] declares.
func add_index(model: GDScript, fields: Array[String]) -> bool:
    return _add_index(model, fields, false)


## Drops the unique index over [param fields] of [param model]'s table.
func drop_unique(model: GDScript, fields: Array[String]) -> bool:
    return _drop_index(model, fields, true)


## Drops the index over [param fields] of [param model]'s table.
func drop_index(model: GDScript, fields: Array[String]) -> bool:
    return _drop_index(model, fields, false)


## Drops an index by name.
func drop_index_raw(index_name: String) -> bool:
    return execute("DROP INDEX IF EXISTS %s" % DbSql.ident(index_name))


func _add_index(model: GDScript, fields: Array[String], unique: bool) -> bool:
    var table: DbTable = _table(model)
    if table == null:
        return false
    var index: DbTable.IndexDef = table.find_index(fields, unique)
    if index == null:
        return _stop(
            "%s declares no %s over %s"
            % [table.model_name, "unique" if unique else "index", fields]
        )
    return execute(index.create_sql(table.name))


func _drop_index(model: GDScript, fields: Array[String], unique: bool) -> bool:
    var table: DbTable = _table(model)
    if table == null:
        return false
    var index: DbTable.IndexDef = DbTable.IndexDef.new(
        table.name,
        fields,
        unique,
        "unique" if unique else "index",
    )
    return drop_index_raw(index.name)


func _table(model: GDScript) -> DbTable:
    if _failed:
        return null
    var table: DbTable = _db._registry.table_for_script(model)
    if table == null:
        _stop("%s is not in the model list" % DbRegistry._script_name(model))
    return table


func _column_names(table_name: String) -> Array[String]:
    var names: Array[String] = []
    for row: Dictionary in query("PRAGMA table_xinfo(%s)" % DbSql.ident(table_name)):
        names.append(str(row["name"]))
    return names


func _columns_exist(table_name: String, columns: Array[String]) -> bool:
    var existing: Array[String] = _column_names(table_name)
    for column: String in columns:
        if column not in existing:
            return false
    return true


func _check(ok: bool) -> bool:
    if not ok:
        _failed = true
    return ok


func _stop(message: String) -> bool:
    _failed = true
    _db._fail(Db.ErrorKind.MIGRATION, "migration %d: %s" % [_version, message])
    return false
