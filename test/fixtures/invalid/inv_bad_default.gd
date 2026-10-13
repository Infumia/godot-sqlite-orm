extends DbModel
## Invalid on purpose: bad default.

var id: int
var ratio: float


static func _schema(s: DbSchema) -> void:
    s.table("t_bad_default")
    s.field("id").primary_key()
    s.field("ratio").default(NAN)
