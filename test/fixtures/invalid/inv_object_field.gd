extends DbModel
## Invalid on purpose: object field.

var id: int
var node: Node


static func _schema(s: DbSchema) -> void:
    s.table("t_object")
    s.field("id").primary_key()
