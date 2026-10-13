class_name DbWhere
extends RefCounted
## Conditions of a query. [DbQuery], [DbUpdate] and [DbDelete] use one, and
## [method where_group] passes one to its callable for conditions in parentheses.
##
## Conditions join in the order they are added: [code]where[/code] adds with AND,
## [code]or_where[/code] with OR. As in SQL, AND binds tighter than OR, so
## [code]a.where(x).where(y).or_where(z)[/code] means (x AND y) OR z. Values are always bound,
## never pasted into the SQL, and field names must be columns of the model.

const OPERATORS: Array[String] = [
    "=",
    "!=",
    "<>",
    "<",
    "<=",
    ">",
    ">=",
    "LIKE",
    "NOT LIKE",
    "GLOB",
    "NOT GLOB",
    "IS",
    "IS NOT",
]

var _table: DbTable
var _parts: PackedStringArray = []
var _args: Array = []
var _error: String = ""


func _init(table: DbTable) -> void:
    _table = table


## [param field] compared to [param value] with [param operator], one of [constant OPERATORS].
## Comparing to null with "=" or "!=" becomes IS NULL or IS NOT NULL.
func where(field: String, operator: String, value: Variant) -> DbWhere:
    _compare("AND", field, operator, value)
    return self


func or_where(field: String, operator: String, value: Variant) -> DbWhere:
    _compare("OR", field, operator, value)
    return self


## [param field] equals one of [param values]. An empty list matches nothing.
func where_in(field: String, values: Array) -> DbWhere:
    _in("AND", field, values, false)
    return self


func or_where_in(field: String, values: Array) -> DbWhere:
    _in("OR", field, values, false)
    return self


## [param field] equals none of [param values]. An empty list matches everything.
func where_not_in(field: String, values: Array) -> DbWhere:
    _in("AND", field, values, true)
    return self


func where_null(field: String) -> DbWhere:
    _null("AND", field, true)
    return self


func or_where_null(field: String) -> DbWhere:
    _null("OR", field, true)
    return self


func where_not_null(field: String) -> DbWhere:
    _null("AND", field, false)
    return self


## [param low] <= [param field] <= [param high].
func where_between(field: String, low: Variant, high: Variant) -> DbWhere:
    var column: DbColumn = _column(field)
    if column != null:
        var low_value: Variant = _value(column, low)
        var high_value: Variant = _value(column, high)
        _add("AND", "%s BETWEEN ? AND ?" % DbSql.ident(field), [low_value, high_value])
    return self


## Conditions in parentheses: [param body] receives a [DbWhere] to fill.
## [codeblock]
## db.select(Character).where("level", ">", 5).where_group(
##     func(w: DbWhere) -> void: w.where("name", "=", "Ada").or_where("name", "=", "Lin")
## )
## [/codeblock]
func where_group(body: Callable) -> DbWhere:
    _group("AND", body)
    return self


func or_where_group(body: Callable) -> DbWhere:
    _group("OR", body)
    return self


## A condition written in SQL, with "?" marks for [param args]. Field names in it are not
## checked, so never build [param sql] from player input.
func where_raw(sql: String, args: Array = []) -> DbWhere:
    _add("AND", "(%s)" % sql, args)
    return self


func is_empty() -> bool:
    return _parts.is_empty()


## The conditions as SQL, without the WHERE keyword; "" when there are none.
func sql() -> String:
    return " ".join(_parts)


func args() -> Array:
    return _args


## The first problem found while adding conditions, such as an unknown field.
func error() -> String:
    return _error


func _compare(joiner: String, field: String, operator: String, value: Variant) -> void:
    var column: DbColumn = _column(field)
    if column == null:
        return
    var op: String = " ".join(operator.strip_edges().to_upper().split(" ", false))
    if op not in OPERATORS:
        _set_error("unknown operator '%s'" % operator)
        return
    if value == null:
        match op:
            "=", "IS":
                _add(joiner, "%s IS NULL" % DbSql.ident(field), [])
            "!=", "<>", "IS NOT":
                _add(joiner, "%s IS NOT NULL" % DbSql.ident(field), [])
            _:
                _set_error("'%s' cannot compare '%s' with null" % [op, field])
        return
    var bound: Variant
    if op.ends_with("LIKE") or op.ends_with("GLOB"):
        if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
            _set_error("'%s' needs a String pattern for '%s'" % [op, field])
            return
        bound = str(value)
    else:
        bound = _value(column, value)
        if not _error.is_empty():
            return
    var args: Array = []
    _add(joiner, "%s %s %s" % [DbSql.ident(field), op, DbSql.bind(bound, args)], args)


func _in(joiner: String, field: String, values: Array, negate: bool) -> void:
    var column: DbColumn = _column(field)
    if column == null:
        return
    if values.is_empty():
        _add(joiner, "1" if negate else "0", [])
        return
    var bound: Array = []
    for value: Variant in values:
        if value == null:
            _set_error("the list for '%s' holds null; use where_null()" % field)
            return
        bound.append(_value(column, value))
        if not _error.is_empty():
            return
    var parts: PackedStringArray = []
    for chunk: Array in DbSql.chunks(bound):
        parts.append(
            "%s %sIN (%s)"
            % [DbSql.ident(field), "NOT " if negate else "", DbSql.placeholders(chunk.size())]
        )
    _add(joiner, "(%s)" % (" AND " if negate else " OR ").join(parts), bound)


func _null(joiner: String, field: String, is_null: bool) -> void:
    if _column(field) != null:
        _add(joiner, "%s IS %sNULL" % [DbSql.ident(field), "" if is_null else "NOT "], [])


func _group(joiner: String, body: Callable) -> void:
    var inner: DbWhere = DbWhere.new(_table)
    body.call(inner)
    if not inner.error().is_empty():
        _set_error(inner.error())
        return
    if not inner.is_empty():
        _add(joiner, "(%s)" % inner.sql(), inner.args())


func _add(joiner: String, sql_part: String, values: Array) -> void:
    if _parts.is_empty():
        _parts.append(sql_part)
    else:
        _parts.append(joiner + " " + sql_part)
    _args.append_array(values)


func _column(field: String) -> DbColumn:
    if _table == null:
        _set_error("the query has no model")
        return null
    var column: DbColumn = _table.column(field)
    if column == null:
        _set_error("%s has no field '%s'" % [_table.model_name, field])
    return column


func _value(column: DbColumn, value: Variant) -> Variant:
    var stored: Variant = column.to_sql(value)
    var error: String = column.take_error()
    if not error.is_empty():
        _set_error(error)
    return stored


func _set_error(message: String) -> void:
    if _error.is_empty():
        _error = message
