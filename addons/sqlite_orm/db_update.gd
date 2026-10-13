class_name DbUpdate
extends RefCounted
## Changes fields on every row that matches. Made by [method Db.update_all].
## [codeblock]
## db.update_all(Character).set_field("level", 1).where("level", ">", 99).execute()
## [/codeblock]
## It writes SQL directly: model hooks and relations are skipped. auto_updated() fields are
## set to the current time unless set here. Without conditions it refuses to run, unless
## [method all_rows] says that is meant.

var _db: Db
var _table: DbTable
var _where: DbWhere
var _assignments: Dictionary = { }
var _all_rows: bool = false
var _error: String = ""


func _init(db: Db, table: DbTable) -> void:
    _db = db
    _table = table
    _where = DbWhere.new(table)
    if table == null:
        _error = db.last_error()


## Sets [param field] to [param value] on every matching row.
func set_field(field: String, value: Variant) -> DbUpdate:
    if _table == null:
        return self
    var column: DbColumn = _table.column(field)
    if column == null:
        _set_error("%s has no field '%s'" % [_table.model_name, field])
        return self
    var stored: Variant = column.to_sql(value)
    var error: String = column.take_error()
    if not error.is_empty():
        _set_error(error)
        return self
    _assignments[field] = stored
    return self


## Allows running without conditions, changing every row.
func all_rows() -> DbUpdate:
    _all_rows = true
    return self


func where(field: String, operator: String, value: Variant) -> DbUpdate:
    _where.where(field, operator, value)
    return self


func or_where(field: String, operator: String, value: Variant) -> DbUpdate:
    _where.or_where(field, operator, value)
    return self


func where_in(field: String, values: Array) -> DbUpdate:
    _where.where_in(field, values)
    return self


func where_not_in(field: String, values: Array) -> DbUpdate:
    _where.where_not_in(field, values)
    return self


func where_null(field: String) -> DbUpdate:
    _where.where_null(field)
    return self


func where_not_null(field: String) -> DbUpdate:
    _where.where_not_null(field)
    return self


func where_between(field: String, low: Variant, high: Variant) -> DbUpdate:
    _where.where_between(field, low, high)
    return self


func where_group(body: Callable) -> DbUpdate:
    _where.where_group(body)
    return self


func or_where_group(body: Callable) -> DbUpdate:
    _where.or_where_group(body)
    return self


func where_raw(sql: String, args: Array = []) -> DbUpdate:
    _where.where_raw(sql, args)
    return self


## Runs the update. Returns how many rows changed, or -1 on failure.
func execute() -> int:
    _db._clear_error()
    if not _error.is_empty():
        _db._fail(Db.ErrorKind.USAGE, _error)
        return -1
    if not _where.error().is_empty():
        _db._fail(Db.ErrorKind.USAGE, _where.error())
        return -1
    if _assignments.is_empty():
        _db._fail(Db.ErrorKind.USAGE, "update_all() has nothing to set")
        return -1
    if _where.is_empty() and not _all_rows:
        _db._fail(Db.ErrorKind.USAGE, "update_all() without conditions needs all_rows()")
        return -1
    var values: Dictionary = _assignments.duplicate()
    for column: DbColumn in _table.columns:
        if column.auto_updated and not values.has(column.name):
            values[column.name] = _db.now()
    var parts: PackedStringArray = []
    var args: Array = []
    for field: String in values:
        parts.append("%s = %s" % [DbSql.ident(field), DbSql.bind(values[field], args)])
    var sql: String = "UPDATE %s SET %s" % [DbSql.ident(_table.name), ", ".join(parts)]
    if not _where.is_empty():
        sql += " WHERE " + _where.sql()
        args.append_array(_where.args())
    if not _db._run(sql, args):
        return -1
    return _db._changes()


func _set_error(message: String) -> void:
    if _error.is_empty():
        _error = message
