extends DbModel
## Invalid on purpose: type mismatch.

var id: int
var n: int


static func _schema(s: DbSchema) -> void:
    s.table("t_mismatch")
    s.field("id").primary_key()
    s.field("n").type(TYPE_STRING)
