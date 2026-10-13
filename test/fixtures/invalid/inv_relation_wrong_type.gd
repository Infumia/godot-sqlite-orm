extends DbModel
## Invalid on purpose: relation wrong type.

var id: int
var owner_id: Variant
var owner: FxCharacter


static func _schema(s: DbSchema) -> void:
    s.table("t_rel_type")
    s.field("id").primary_key()
    s.field("owner_id").belongs_to("owner", FxItem)
