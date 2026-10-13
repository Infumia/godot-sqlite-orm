class_name MgPetRebuilt
extends DbModel
## pets pointing at the rebuilt players table.

var id: int
var owner_id: int
var species: StringName = &"cat"


static func _schema(s: DbSchema) -> void:
    s.table("pets")
    s.field("id").primary_key().auto_increment()
    s.field("owner_id").references(MgPlayerRebuilt).on_delete_cascade()
