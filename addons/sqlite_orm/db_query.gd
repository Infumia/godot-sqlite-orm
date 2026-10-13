class_name DbQuery
extends RefCounted
## Reads rows of one model. Made by [method Db.select]; every builder method returns the
## query, and [method all], [method first], [method count], [method exists] or [method pluck]
## run it. Conditions work as in [DbWhere].
## [codeblock]
## var top: Array = (
##     db.select(Character).where("level", ">=", 10).order_by("level", Db.DESC).limit(5).all()
## )
## [/codeblock]
## On failure the terminal methods return an empty result and [method Db.last_error] says why.

var _db: Db
var _table: DbTable
var _where: DbWhere
var _order: PackedStringArray = []
var _limit: int = -1
var _offset: int = 0
var _with: Array[String] = []
var _error: String = ""


func _init(db: Db, table: DbTable) -> void:
    _db = db
    _table = table
    _where = DbWhere.new(table)
    if table == null:
        _error = db.last_error()


func where(field: String, operator: String, value: Variant) -> DbQuery:
    _where.where(field, operator, value)
    return self


func or_where(field: String, operator: String, value: Variant) -> DbQuery:
    _where.or_where(field, operator, value)
    return self


func where_in(field: String, values: Array) -> DbQuery:
    _where.where_in(field, values)
    return self


func or_where_in(field: String, values: Array) -> DbQuery:
    _where.or_where_in(field, values)
    return self


func where_not_in(field: String, values: Array) -> DbQuery:
    _where.where_not_in(field, values)
    return self


func where_null(field: String) -> DbQuery:
    _where.where_null(field)
    return self


func or_where_null(field: String) -> DbQuery:
    _where.or_where_null(field)
    return self


func where_not_null(field: String) -> DbQuery:
    _where.where_not_null(field)
    return self


func where_between(field: String, low: Variant, high: Variant) -> DbQuery:
    _where.where_between(field, low, high)
    return self


func where_group(body: Callable) -> DbQuery:
    _where.where_group(body)
    return self


func or_where_group(body: Callable) -> DbQuery:
    _where.or_where_group(body)
    return self


func where_raw(sql: String, args: Array = []) -> DbQuery:
    _where.where_raw(sql, args)
    return self


## Sorts by [param field]; call again to break ties with another field. Without any
## order_by, rows come in primary key order.
func order_by(field: String, descending: bool = false) -> DbQuery:
    if _table != null and not _table.has_column(field):
        _set_error("%s has no field '%s'" % [_table.model_name, field])
    else:
        _order.append("%s %s" % [DbSql.ident(field), "DESC" if descending else "ASC"])
    return self


## Returns at most [param count] rows.
func limit(count: int) -> DbQuery:
    if count < 0:
        _set_error("limit() needs a count of 0 or more")
    _limit = count
    return self


## Skips the first [param count] rows.
func offset(count: int) -> DbQuery:
    if count < 0:
        _set_error("offset() needs a count of 0 or more")
    _offset = count
    return self


## Also loads the relation [param relation_path] of every row found, with one query per
## relation. Paths nest: "inventory.affixes".
func with(relation_path: String) -> DbQuery:
    _with.append(relation_path)
    return self


## Every matching row, as models.
func all() -> Array:
    var models: Array = []
    if not _start():
        return models
    var rows: Array[Dictionary] = _db._rows(_select_sql(_column_list()), _select_args())
    if not _db.last_error().is_empty():
        return models
    for row: Dictionary in rows:
        var model: DbModel = _db._model_from_row(_table, row)
        if model == null:
            return []
        models.append(model)
    if not _with.is_empty() and not models.is_empty():
        if not DbRelationIO.load_paths(_db, models, _with):
            return []
    return models


## The first matching row, or null. Null with an empty [method Db.last_error] means no match.
func first() -> DbModel:
    var previous_limit: int = _limit
    _limit = 1
    var models: Array = all()
    _limit = previous_limit
    if models.is_empty():
        return null
    var model: DbModel = models[0]
    return model


## How many rows match. Ignores order_by, limit and offset. -1 on failure.
func count() -> int:
    if not _start():
        return -1
    var sql: String = "SELECT count(*) AS n FROM %s" % DbSql.ident(_table.name)
    if not _where.is_empty():
        sql += " WHERE " + _where.sql()
    var rows: Array[Dictionary] = _db._rows(sql, _where.args())
    if rows.is_empty():
        return -1
    return DbSql.to_int(rows[0]["n"])


## Whether any row matches.
func exists() -> bool:
    if not _start():
        return false
    var sql: String = "SELECT EXISTS (SELECT 1 FROM %s%s) AS found" % [
        DbSql.ident(_table.name),
        "" if _where.is_empty() else " WHERE " + _where.sql(),
    ]
    var rows: Array[Dictionary] = _db._rows(sql, _where.args())
    return not rows.is_empty() and DbSql.to_int(rows[0]["found"]) == 1


## The values of one field from every matching row, converted to the field's type.
func pluck(field: String) -> Array:
    var values: Array = []
    if not _start():
        return values
    var column: DbColumn = _table.column(field)
    if column == null:
        _db._fail(Db.ErrorKind.USAGE, "%s has no field '%s'" % [_table.model_name, field])
        return values
    var rows: Array[Dictionary] = _db._rows(_select_sql(DbSql.ident(field)), _select_args())
    for row: Dictionary in rows:
        var value: Variant = column.from_sql(row.get(field))
        var error: String = column.take_error()
        if not error.is_empty():
            _db._fail(Db.ErrorKind.CONVERSION, "%s: %s" % [_table.model_name, error])
            return []
        values.append(value)
    return values


## The SQL this query runs, for debugging.
func to_sql() -> String:
    if _table == null:
        return ""
    return _select_sql(_column_list())


func _start() -> bool:
    _db._clear_error()
    if not _error.is_empty():
        return _db._fail(Db.ErrorKind.USAGE, _error)
    if not _where.error().is_empty():
        return _db._fail(Db.ErrorKind.USAGE, _where.error())
    return true


func _column_list() -> String:
    return DbSql.idents(_table.column_names())


func _select_sql(columns: String) -> String:
    var sql: String = "SELECT %s FROM %s" % [columns, DbSql.ident(_table.name)]
    if not _where.is_empty():
        sql += " WHERE " + _where.sql()
    if _order.is_empty():
        sql += " ORDER BY " + DbSql.idents(_table.primary_key)
    else:
        sql += " ORDER BY " + ", ".join(_order)
    if _limit >= 0 or _offset > 0:
        sql += " LIMIT ? OFFSET ?"
    return sql


func _select_args() -> Array:
    var values: Array = _where.args().duplicate()
    if _limit >= 0 or _offset > 0:
        values.append(_limit)
        values.append(_offset)
    return values


func _set_error(message: String) -> void:
    if _error.is_empty():
        _error = message
