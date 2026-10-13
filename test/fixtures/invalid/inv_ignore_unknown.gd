extends DbModel
## Invalid on purpose: ignore unknown.

var id: int


static func _schema(s: DbSchema) -> void:
    s.table("t_ignore")
    s.field("id").primary_key()
    s.ignore("nope")
