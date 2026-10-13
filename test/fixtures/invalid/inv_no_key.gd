extends DbModel
## Invalid on purpose: no key.

var id: int


static func _schema(s: DbSchema) -> void:
    s.table("t_no_key")
