extends DbModel
## Invalid on purpose: untyped variant.

var id: int
var data: Variant


static func _schema(s: DbSchema) -> void:
    s.table("t_variant")
    s.field("id").primary_key()
