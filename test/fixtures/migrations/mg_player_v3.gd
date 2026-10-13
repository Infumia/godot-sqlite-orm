class_name MgPlayerV3
extends DbModel
## players after migration 2: name renamed to nickname.

var id: int
var nickname: String
var xp: int = 0
var title: Variant
var pets: Array[MgPetV3] = []


static func _schema(s: DbSchema) -> void:
    s.table("players")
    s.field("id").primary_key().auto_increment()
    s.field("title").type(TYPE_STRING)
    s.has_many("pets", MgPetV3, "owner_id")
