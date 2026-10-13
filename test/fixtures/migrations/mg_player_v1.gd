class_name MgPlayerV1
extends DbModel
## players, first release.

var id: int
var name: String


static func _schema(s: DbSchema) -> void:
    s.table("players")
    s.field("id").primary_key().auto_increment()
