extends DbModel
## Invalid on purpose: reference not unique.

var id: int
var item_damage: int


static func _schema(s: DbSchema) -> void:
    s.table("t_not_unique")
    s.field("id").primary_key()
    s.field("item_damage").references(FxItem, "damage")
