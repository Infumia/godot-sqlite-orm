extends DbModel
## Invalid on purpose: reference outside.

var id: int
var guild_id: int


static func _schema(s: DbSchema) -> void:
    s.table("t_outside")
    s.field("id").primary_key()
    s.field("guild_id").references(FxGuild)
