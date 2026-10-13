class_name DbSql
extends RefCounted
## SQL text helpers shared by the addon. Not part of the public API.

## The most values bound in one IN list. Longer lists are split into chunks of this size,
## well under SQLite's limit on host parameters per statement.
const MAX_BINDINGS: int = 500


## Quotes an identifier (table, column, index name) so any name is safe in SQL.
static func ident(name: String) -> String:
    return "\"" + name.replace("\"", "\"\"") + "\""


static func idents(names: Array[String]) -> String:
    var quoted: PackedStringArray = []
    for name: String in names:
        quoted.append(ident(name))
    return ", ".join(quoted)


## The SQL for one bound value: "?", except for an empty PackedByteArray, which godot-sqlite
## would bind as NULL and which is written as the literal X'' instead.
static func mark(value: Variant) -> String:
    if typeof(value) == TYPE_PACKED_BYTE_ARRAY:
        var bytes: PackedByteArray = value
        if bytes.is_empty():
            return "X''"
    return "?"


## Appends [param value] to [param args] unless [method mark] writes it inline.
static func bind(value: Variant, args: Array) -> String:
    var text: String = mark(value)
    if text == "?":
        args.append(value)
    return text


## "?, ?, ?" for [param count] values.
static func placeholders(count: int) -> String:
    var marks: PackedStringArray = []
    for i: int in count:
        marks.append("?")
    return ", ".join(marks)


## A SQL literal for a DEFAULT clause. Only scalar values that SQLite stores are accepted;
## [param ok] gets false for anything else.
static func literal(value: Variant, ok: Array[bool]) -> String:
    ok[0] = true
    match typeof(value):
        TYPE_NIL:
            return "NULL"
        TYPE_BOOL:
            return "1" if value else "0"
        TYPE_INT:
            return str(value)
        TYPE_FLOAT:
            var number: float = value
            if is_nan(number) or is_inf(number):
                ok[0] = false
                return ""
            return var_to_str(number)
        TYPE_STRING, TYPE_STRING_NAME:
            var text: String = str(value)
            return "'" + text.replace("'", "''") + "'"
        TYPE_PACKED_BYTE_ARRAY:
            var bytes: PackedByteArray = value
            return "X'" + bytes.hex_encode() + "'"
    ok[0] = false
    return ""


## [param value] as an int: SQLite results and model fields arrive as Variants.
static func to_int(value: Variant) -> int:
    match typeof(value):
        TYPE_INT:
            return value
        TYPE_FLOAT:
            var number: float = value
            return int(number)
        TYPE_BOOL:
            var flag: bool = value
            return 1 if flag else 0
    return 0


## [param value] as a float; ints are widened.
static func to_float(value: Variant) -> float:
    match typeof(value):
        TYPE_FLOAT:
            return value
        TYPE_INT:
            var number: int = value
            return float(number)
    return 0.0


## A random version 4 UUID, lowercase with dashes.
static func uuid_v4() -> String:
    var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
    bytes[6] = (bytes[6] & 0x0f) | 0x40
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    var hex: String = bytes.hex_encode()
    return "%s-%s-%s-%s-%s" % [
        hex.substr(0, 8),
        hex.substr(8, 4),
        hex.substr(12, 4),
        hex.substr(16, 4),
        hex.substr(20, 12),
    ]


## Splits [param values] into arrays of at most [constant MAX_BINDINGS] items.
static func chunks(values: Array, size: int = MAX_BINDINGS) -> Array[Array]:
    var result: Array[Array] = []
    var start: int = 0
    while start < values.size():
        result.append(values.slice(start, start + size))
        start += size
    return result
