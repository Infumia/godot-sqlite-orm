extends DbModel
## Invalid on purpose: unknown index.

var id: int


static func _schema(s: DbSchema) -> void:
    s.table("t_index")
    s.field("id").primary_key()
    s.index(["nope"])
