class_name DbDelete
extends RefCounted
## Deletes every row that matches. Made by [method Db.delete_all].
## [codeblock]
## db.delete_all(Character).where("level", "<", 2).execute()
## [/codeblock]
## Rows pointing at deleted rows follow their on_delete rule. Without conditions it refuses
## to run, unless [method all_rows] says that is meant.

var _db: Db
var _table: DbTable
var _where: DbWhere
var _all_rows: bool = false
var _error: String = ""


func _init(db: Db, table: DbTable) -> void:
    _db = db
    _table = table
    _where = DbWhere.new(table)
    if table == null:
        _error = db.last_error()


## Allows running without conditions, deleting every row.
func all_rows() -> DbDelete:
    _all_rows = true
    return self


func where(field: String, operator: String, value: Variant) -> DbDelete:
    _where.where(field, operator, value)
    return self


func or_where(field: String, operator: String, value: Variant) -> DbDelete:
    _where.or_where(field, operator, value)
    return self


func where_in(field: String, values: Array) -> DbDelete:
    _where.where_in(field, values)
    return self


func or_where_in(field: String, values: Array) -> DbDelete:
    _where.or_where_in(field, values)
    return self


func where_not_in(field: String, values: Array) -> DbDelete:
    _where.where_not_in(field, values)
    return self


func where_null(field: String) -> DbDelete:
    _where.where_null(field)
    return self


func or_where_null(field: String) -> DbDelete:
    _where.or_where_null(field)
    return self


func where_not_null(field: String) -> DbDelete:
    _where.where_not_null(field)
    return self


func where_between(field: String, low: Variant, high: Variant) -> DbDelete:
    _where.where_between(field, low, high)
    return self


func where_group(body: Callable) -> DbDelete:
    _where.where_group(body)
    return self


func or_where_group(body: Callable) -> DbDelete:
    _where.or_where_group(body)
    return self


func where_raw(sql: String, args: Array = []) -> DbDelete:
    _where.where_raw(sql, args)
    return self


## Runs the delete. Returns how many rows were deleted, or -1 on failure.
func execute() -> int:
    _db._clear_error()
    if not _error.is_empty():
        _db._fail(Db.ErrorKind.USAGE, _error)
        return -1
    if not _where.error().is_empty():
        _db._fail(Db.ErrorKind.USAGE, _where.error())
        return -1
    if _where.is_empty() and not _all_rows:
        _db._fail(Db.ErrorKind.USAGE, "delete_all() without conditions needs all_rows()")
        return -1
    var sql: String = "DELETE FROM %s" % DbSql.ident(_table.name)
    if not _where.is_empty():
        sql += " WHERE " + _where.sql()
    if not _db._run(sql, _where.args()):
        return -1
    return _db._changes()
