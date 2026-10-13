class_name MgPetV3
extends DbModel
## pets, added by migration 2.

var id: int
var owner_id: int
var species: StringName = &"cat"


static func _schema(s: DbSchema) -> void:
    s.table("pets")
    s.field("id").primary_key().auto_increment()
    s.field("owner_id").references(MgPlayerV3).on_delete_cascade()
