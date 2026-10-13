class_name DbColumn
extends RefCounted
## A compiled column: how one model var is stored and read back. Not part of the public API.

enum Kind {
    INT,
    FLOAT,
    BOOL,
    STRING,
    STRING_NAME,
    BYTES,
    JSON,
    CUSTOM,
}

const ON_DELETE_SQL: Dictionary[DbField.OnDelete, String] = {
    DbField.OnDelete.NO_ACTION: "",
    DbField.OnDelete.CASCADE: "CASCADE",
    DbField.OnDelete.SET_NULL: "SET NULL",
    DbField.OnDelete.RESTRICT: "RESTRICT",
}

var name: String
## The var's declared type; TYPE_NIL for a Variant var.
var var_type: int = TYPE_NIL
## The type values have once loaded: [member var_type], or the type a Variant var declares.
var value_type: int = TYPE_NIL
var kind: Kind = Kind.INT
var sql_type: String = "INTEGER"
var nullable: bool = false
var primary_key: bool = false
var auto_increment: bool = false
var uuid: bool = false
var auto_created: bool = false
var auto_updated: bool = false
var unique: bool = false
var indexed: bool = false
var check_sql: String = ""
var has_default: bool = false
var default_value: Variant = null
var converter: DbConverter = null
var reference_target: GDScript = null
var reference_table: String = ""
var reference_column: String = ""
var on_delete: DbField.OnDelete = DbField.OnDelete.NO_ACTION
var on_update_cascade: bool = false
## For typed Array and Dictionary vars: element types, as in [method Array.get_typed_builtin].
var element_type: int = TYPE_NIL
var key_type: int = TYPE_NIL
var dictionary_value_type: int = TYPE_NIL
var _error: String = ""


## Picks [member kind] and [member sql_type] from [member value_type]. Returns an error, or "".
func resolve_kind() -> String:
    if converter != null:
        kind = Kind.CUSTOM
        sql_type = converter.sql_type().to_upper()
        if sql_type not in ["INTEGER", "REAL", "TEXT", "BLOB"]:
            return "the converter of '%s' returns sql_type '%s'" % [name, sql_type]
        return ""
    match value_type:
        TYPE_INT:
            kind = Kind.INT
            sql_type = "INTEGER"
        TYPE_FLOAT:
            kind = Kind.FLOAT
            sql_type = "REAL"
        TYPE_BOOL:
            kind = Kind.BOOL
            sql_type = "INTEGER"
        TYPE_STRING:
            kind = Kind.STRING
            sql_type = "TEXT"
        TYPE_STRING_NAME:
            kind = Kind.STRING_NAME
            sql_type = "TEXT"
        TYPE_PACKED_BYTE_ARRAY:
            kind = Kind.BYTES
            sql_type = "BLOB"
        TYPE_NIL:
            return "'%s' is a Variant; give its stored type with .type()" % name
        TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
            return (
                "'%s' has type %s, which cannot be stored; use a relation or a converter"
                % [name, type_string(value_type)]
            )
        _:
            kind = Kind.JSON
            sql_type = "TEXT"
    return ""


## The column definition inside CREATE TABLE. [param single_key] is true when this column is
## the whole primary key.
func definition(single_key: bool) -> String:
    var parts: PackedStringArray = [DbSql.ident(name), sql_type]
    if single_key:
        parts.append("PRIMARY KEY")
        if auto_increment:
            parts.append("AUTOINCREMENT")
    if not nullable:
        parts.append("NOT NULL")
    if has_default:
        var ok: Array[bool] = [true]
        parts.append("DEFAULT " + DbSql.literal(stored_default(), ok))
    if kind == Kind.BOOL:
        parts.append("CHECK (%s IN (0, 1))" % DbSql.ident(name))
    if not check_sql.is_empty():
        parts.append("CHECK (%s %s)" % [DbSql.ident(name), check_sql])
    if reference_target != null:
        parts.append(
            "REFERENCES %s (%s)" % [DbSql.ident(reference_table), DbSql.ident(reference_column)]
        )
        if on_delete != DbField.OnDelete.NO_ACTION:
            parts.append("ON DELETE " + ON_DELETE_SQL[on_delete])
        if on_update_cascade:
            parts.append("ON UPDATE CASCADE")
    return " ".join(parts)


## [member default_value] as stored in SQL.
func stored_default() -> Variant:
    if default_value == null:
        return null
    var stored: Variant = to_sql(default_value)
    take_error()
    return stored


## Whether [method stored_default] can be written as a SQL literal.
func default_is_valid() -> bool:
    if not has_default:
        return true
    var stored: Variant = to_sql(default_value)
    if not take_error().is_empty():
        return false
    var ok: Array[bool] = [true]
    DbSql.literal(stored, ok)
    return ok[0]


## Converts a var value into the value bound in SQL. On failure returns null and sets the
## error that [method take_error] reads.
func to_sql(value: Variant) -> Variant:
    if value == null:
        if nullable:
            return null
        return _fail("'%s' cannot be null" % name)
    match kind:
        Kind.INT:
            if typeof(value) != TYPE_INT:
                return _wrong_type(value)
            return value
        Kind.FLOAT:
            if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
                return _wrong_type(value)
            return DbSql.to_float(value)
        Kind.BOOL:
            if typeof(value) != TYPE_BOOL:
                return _wrong_type(value)
            return 1 if value else 0
        Kind.STRING, Kind.STRING_NAME:
            if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
                return _wrong_type(value)
            return str(value)
        Kind.BYTES:
            if typeof(value) != TYPE_PACKED_BYTE_ARRAY:
                return _wrong_type(value)
            return value
        Kind.JSON:
            if typeof(value) != value_type:
                return _wrong_type(value)
            if _holds_object(value):
                return _fail("'%s' holds an Object, which cannot be stored" % name)
            return JSON.stringify(JSON.from_native(value))
        Kind.CUSTOM:
            var stored: Variant = converter.to_sql(value)
            var error: String = converter.take_error()
            if not error.is_empty():
                return _fail("'%s': %s" % [name, error])
            return stored
    return _fail("'%s' has an unknown kind" % name)


## Converts a stored value back into the var's type. On failure returns null and sets the
## error that [method take_error] reads.
func from_sql(value: Variant) -> Variant:
    if value == null:
        if nullable:
            return null
        return _fail("'%s' is NULL in the database but the field cannot hold null" % name)
    match kind:
        Kind.INT:
            if typeof(value) != TYPE_INT:
                return _bad_stored(value)
            return value
        Kind.FLOAT:
            if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
                return _bad_stored(value)
            return DbSql.to_float(value)
        Kind.BOOL:
            if typeof(value) != TYPE_INT:
                return _bad_stored(value)
            return value != 0
        Kind.STRING:
            if typeof(value) != TYPE_STRING:
                return _bad_stored(value)
            return value
        Kind.STRING_NAME:
            if typeof(value) != TYPE_STRING:
                return _bad_stored(value)
            return StringName(str(value))
        Kind.BYTES:
            if typeof(value) != TYPE_PACKED_BYTE_ARRAY:
                return _bad_stored(value)
            return value
        Kind.JSON:
            if typeof(value) != TYPE_STRING:
                return _bad_stored(value)
            return _decode_json(str(value))
        Kind.CUSTOM:
            var loaded: Variant = converter.from_sql(value)
            var error: String = converter.take_error()
            if not error.is_empty():
                return _fail("'%s': %s" % [name, error])
            if var_type != TYPE_NIL and typeof(loaded) != var_type and loaded != null:
                return _fail(
                    "the converter of '%s' returned %s, not %s"
                    % [name, type_string(typeof(loaded)), type_string(var_type)]
                )
            return loaded
    return _fail("'%s' has an unknown kind" % name)


## The last conversion error, cleared by reading it.
func take_error() -> String:
    var error: String = _error
    _error = ""
    return error


func _decode_json(text: String) -> Variant:
    var json: JSON = JSON.new()
    if json.parse(text) != OK:
        return _fail("'%s' holds invalid JSON: %s" % [name, json.get_error_message()])
    var native: Variant = JSON.to_native(json.data)
    if value_type == TYPE_ARRAY:
        return _typed_array(native)
    if value_type == TYPE_DICTIONARY:
        return _typed_dictionary(native)
    if typeof(native) != value_type:
        return _fail(
            "'%s' holds %s in the database, not %s"
            % [name, type_string(typeof(native)), type_string(value_type)]
        )
    return native


func _typed_array(native: Variant) -> Variant:
    if typeof(native) != TYPE_ARRAY:
        return _fail(
            "'%s' holds %s in the database, not Array" % [name, type_string(typeof(native))]
        )
    var items: Array = native
    if element_type == TYPE_NIL:
        return Array(items)
    var checked: Array = []
    for item: Variant in items:
        var converted: Variant = _element(item, element_type)
        if not _error.is_empty():
            return null
        checked.append(converted)
    return Array(checked, element_type, &"", null)


func _typed_dictionary(native: Variant) -> Variant:
    if typeof(native) != TYPE_DICTIONARY:
        return _fail(
            "'%s' holds %s in the database, not Dictionary" % [name, type_string(typeof(native))]
        )
    var source: Dictionary = native
    if key_type == TYPE_NIL and dictionary_value_type == TYPE_NIL:
        return Dictionary(source)
    var checked: Dictionary = { }
    for key: Variant in source:
        var typed_key: Variant = _element(key, key_type)
        if not _error.is_empty():
            return null
        var typed_value: Variant = _element(source[key], dictionary_value_type)
        if not _error.is_empty():
            return null
        checked[typed_key] = typed_value
    return Dictionary(checked, key_type, &"", null, dictionary_value_type, &"", null)


## Checks one element of a typed container. Ints are accepted where floats are expected.
func _element(item: Variant, expected: int) -> Variant:
    if expected == TYPE_NIL or typeof(item) == expected:
        return item
    if expected == TYPE_FLOAT and typeof(item) == TYPE_INT:
        return DbSql.to_float(item)
    if expected == TYPE_STRING_NAME and typeof(item) == TYPE_STRING:
        return StringName(str(item))
    return _fail(
        "'%s' holds a %s where %s is expected"
        % [name, type_string(typeof(item)), type_string(expected)]
    )


func _holds_object(value: Variant) -> bool:
    match typeof(value):
        TYPE_OBJECT:
            return true
        TYPE_ARRAY:
            var items: Array = value
            for item: Variant in items:
                if _holds_object(item):
                    return true
        TYPE_DICTIONARY:
            var dictionary: Dictionary = value
            for key: Variant in dictionary:
                if _holds_object(key) or _holds_object(dictionary[key]):
                    return true
    return false


func _wrong_type(value: Variant) -> Variant:
    return _fail(
        "'%s' expects %s, got %s" % [name, type_string(value_type), type_string(typeof(value))]
    )


func _bad_stored(value: Variant) -> Variant:
    return _fail(
        "'%s' holds %s in the database, not %s" % [name, type_string(typeof(value)), sql_type]
    )


func _fail(message: String) -> Variant:
    _error = message
    return null
