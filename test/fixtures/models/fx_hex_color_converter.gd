class_name FxHexColorConverter
extends DbConverter
## Stores a Color as "rrggbbaa" text.


func sql_type() -> String:
    return "TEXT"


func to_sql(value: Variant) -> Variant:
    var color: Color = value
    return color.to_html()


func from_sql(value: Variant) -> Variant:
    var text: String = str(value)
    if not Color.html_is_valid(text):
        return fail("'%s' is not a color" % text)
    return Color.html(text)
