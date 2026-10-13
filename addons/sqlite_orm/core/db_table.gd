class_name DbTable
extends RefCounted
## A compiled model: its table, columns, keys, indexes and relations. Not part of the public API.

var model_script: GDScript
var name: String
var columns: Array[DbColumn] = []
var by_name: Dictionary[String, DbColumn] = { }
var primary_key: Array[String] = []
## The single auto-increment key column, or null.
var auto_key: DbColumn = null
var indexes: Array[IndexDef] = []
var relations: Dictionary[String, DbRelation] = { }
var model_name: String


func column(column_name: String) -> DbColumn:
    return by_name.get(column_name)


func has_column(column_name: String) -> bool:
    return by_name.has(column_name)


func column_names() -> Array[String]:
    var names: Array[String] = []
    for item: DbColumn in columns:
        names.append(item.name)
    return names


## CREATE TABLE for this table, or under [param table_name] when given (used to rebuild a table).
func create_sql(table_name: String = "") -> String:
    var single_key: bool = primary_key.size() == 1
    var lines: PackedStringArray = []
    for item: DbColumn in columns:
        lines.append(item.definition(single_key and item.primary_key))
    if not single_key:
        lines.append("PRIMARY KEY (%s)" % DbSql.idents(primary_key))
    var target: String = name if table_name.is_empty() else table_name
    return "CREATE TABLE %s (\n    %s\n) STRICT" % [DbSql.ident(target), ",\n    ".join(lines)]


func index_sql() -> PackedStringArray:
    var statements: PackedStringArray = []
    for index: IndexDef in indexes:
        statements.append(index.create_sql(name))
    return statements


func find_index(index_columns: Array[String], unique: bool) -> IndexDef:
    for index: IndexDef in indexes:
        if index.unique == unique and index.columns == index_columns:
            return index
    return null


## The primary key value of [param model]: the value itself for a single key, an Array for
## a key over several columns.
func key_of(model: Object) -> Variant:
    if primary_key.size() == 1:
        return model.get(primary_key[0])
    var values: Array = []
    for key: String in primary_key:
        values.append(model.get(key))
    return values


## Whether [param model] has no key yet: an auto-increment key at 0, or an empty UUID key.
func is_unsaved(model: Object) -> bool:
    if auto_key != null:
        var id: Variant = model.get(auto_key.name)
        return typeof(id) == TYPE_INT and id == 0
    if primary_key.size() == 1:
        var key_column: DbColumn = by_name[primary_key[0]]
        if key_column.uuid:
            return str(model.get(key_column.name)).is_empty()
    return false


## One index the table needs, named after its table and columns.
class IndexDef:
    extends RefCounted

    var name: String
    var columns: Array[String]
    var unique: bool


    func _init(
        table: String,
        index_columns: Array[String],
        is_unique: bool,
        suffix: String,
    ) -> void:
        columns = index_columns
        unique = is_unique
        name = "%s_%s_%s" % [table, "_".join(index_columns), suffix]


    func create_sql(table: String) -> String:
        return "CREATE %sINDEX IF NOT EXISTS %s ON %s (%s)" % [
            "UNIQUE " if unique else "",
            DbSql.ident(name),
            DbSql.ident(table),
            DbSql.idents(columns),
        ]
