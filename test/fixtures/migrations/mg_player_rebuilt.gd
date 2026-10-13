class_name MgPlayerRebuilt
extends DbModel
## players rebuilt: nickname becomes display (unique), xp becomes a float, a new level.

var id: int
var display: String
var xp: float = 0.0
var title: Variant
var level: int = 1


static func _schema(s: DbSchema) -> void:
    s.table("players")
    s.field("id").primary_key().auto_increment()
    s.field("display").unique()
    s.field("title").type(TYPE_STRING)
