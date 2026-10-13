class_name FxTick
extends DbModel
## A table with nothing but its key, inserted with DEFAULT VALUES.

var id: int


static func _schema(s: DbSchema) -> void:
    s.table("ticks")
    s.field("id").primary_key().auto_increment()
