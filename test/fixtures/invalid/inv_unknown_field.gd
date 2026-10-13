extends DbModel
## Invalid on purpose: unknown field.

var id: int


static func _schema(s: DbSchema) -> void:
    s.table("t_unknown")
    s.field("id").primary_key()
    s.field("missing")
