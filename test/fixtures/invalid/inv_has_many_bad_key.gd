extends DbModel
## Invalid on purpose: has many bad key.

var id: int
var items: Array[FxItem] = []


static func _schema(s: DbSchema) -> void:
    s.table("t_has_many")
    s.field("id").primary_key()
    s.has_many("items", FxItem, "damage")
