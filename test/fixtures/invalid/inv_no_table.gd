extends DbModel
## Invalid on purpose: no table.

var id: int


static func _schema(s: DbSchema) -> void:
    s.field("id").primary_key()
