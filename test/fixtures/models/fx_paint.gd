class_name FxPaint
extends DbModel
## A custom converter field and a JSON-stored Color.

var id: int
var color: Color = Color.WHITE
var shade: Color = Color.BLACK
var accent: Variant


static func _schema(s: DbSchema) -> void:
    s.table("paints")
    s.field("id").primary_key().auto_increment()
    s.field("color").converter(FxHexColorConverter.new())
    s.field("accent").converter(FxHexColorConverter.new())
