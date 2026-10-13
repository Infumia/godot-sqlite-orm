extends DbModel
## Invalid on purpose: uuid int.

var id: int


static func _schema(s: DbSchema) -> void:
    s.table("t_uuid_int")
    s.field("id").primary_key().default_uuid()
