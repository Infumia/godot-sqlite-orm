class_name DbConverter
extends RefCounted
## Stores a field type the addon does not handle by itself, or stores a type differently.
##
## Extend it and set it on a field with [method DbField.converter]:
## [codeblock]
## class_name ColorHexConverter
## extends DbConverter
##
## func sql_type() -> String:
##     return "TEXT"
##
## func to_sql(value: Variant) -> Variant:
##     var color: Color = value
##     return color.to_html()
##
## func from_sql(value: Variant) -> Variant:
##     if not Color.html_is_valid(value):
##         return fail("not a color: %s" % value)
##     return Color.html(value)
## [/codeblock]
## [code]null[/code] never reaches a converter: a nullable field stores and loads it as is.

var _error: String = ""


## The SQLite column type: "INTEGER", "REAL", "TEXT" or "BLOB".
func sql_type() -> String:
    return "TEXT"


## Turns a field value into a value SQLite stores in [method sql_type].
func to_sql(value: Variant) -> Variant:
    return value


## Turns a stored value back into the field's type.
func from_sql(value: Variant) -> Variant:
    return value


## Call from [method to_sql] or [method from_sql] to reject a value; returns null.
func fail(message: String) -> Variant:
    _error = message
    return null


## The error from the last call, cleared by reading it. Used by the addon.
func take_error() -> String:
    var error: String = _error
    _error = ""
    return error
