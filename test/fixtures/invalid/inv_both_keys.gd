extends DbModel
## Invalid on purpose: both keys.

var a: int
var b: int


static func _schema(s: DbSchema) -> void:
    s.table("t_both")
    s.field("a").primary_key()
    s.primary_key(["a", "b"])
