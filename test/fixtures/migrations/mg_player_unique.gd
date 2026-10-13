class_name MgPlayerUnique
extends DbModel
## players with a unique nickname, added by a migration.

var id: int
var nickname: String
var xp: int = 0
var title: Variant


static func _schema(s: DbSchema) -> void:
    s.table("players")
    s.field("id").primary_key().auto_increment()
    s.field("title").type(TYPE_STRING)
    s.unique(["nickname"])
