extends DbModel
## Invalid on purpose: relation missing var.

var id: int
var owner_id: Variant


static func _schema(s: DbSchema) -> void:
    s.table("t_rel_missing")
    s.field("id").primary_key()
    s.field("owner_id").belongs_to("owner", FxItem)
