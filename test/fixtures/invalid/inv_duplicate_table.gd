extends DbModel
## Invalid on purpose: duplicate table.

var id: int


static func _schema(s: DbSchema) -> void:
    s.table("items")
    s.field("id").primary_key()
