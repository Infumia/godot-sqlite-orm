class_name FxMember
extends DbModel
## A guild member; the guild cannot be deleted while it has members.

var id: int
var guild_id: int
var guild: FxGuild


static func _schema(s: DbSchema) -> void:
    s.table("members")
    s.field("id").primary_key().auto_increment()
    s.field("guild_id").belongs_to("guild", FxGuild).on_delete_restrict()
