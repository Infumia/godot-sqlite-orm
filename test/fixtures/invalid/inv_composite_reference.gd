extends DbModel
## Invalid on purpose: composite reference.

var id: int
var quest: String


static func _schema(s: DbSchema) -> void:
    s.table("t_composite_ref")
    s.field("id").primary_key()
    s.field("quest").references(FxQuest)
