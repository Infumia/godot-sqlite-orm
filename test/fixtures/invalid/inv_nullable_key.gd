extends DbModel
## Invalid on purpose: nullable key.

var id: Variant


static func _schema(s: DbSchema) -> void:
    s.table("t_nullable_key")
    s.field("id").primary_key().type(TYPE_INT)
