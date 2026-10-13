class_name MgPlayerV2
extends DbModel
## players after migration 1: xp and an optional title.

var id: int
var name: String
var xp: int = 0
var title: Variant


static func _schema(s: DbSchema) -> void:
    s.table("players")
    s.field("id").primary_key().auto_increment()
    s.field("title").type(TYPE_STRING)
