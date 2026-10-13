extends DbModel
## Invalid on purpose: on delete alone.

var id: int
var other: int


static func _schema(s: DbSchema) -> void:
    s.table("t_on_delete")
    s.field("id").primary_key()
    s.field("other").on_delete_cascade()
