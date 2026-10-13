extends DbModel
## Invalid on purpose: relation on column.

var id: int
var damage: int
var owner_id: Variant


static func _schema(s: DbSchema) -> void:
    s.table("t_rel_col")
    s.field("id").primary_key()
    s.field("owner_id").belongs_to("damage", FxItem)
