class_name FxGuild
extends DbModel
## A guild that cannot be deleted while members point at it (RESTRICT).

var id: int
var name: String


static func _schema(s: DbSchema) -> void:
    s.table("guilds")
    s.field("id").primary_key().auto_increment()
