extends DbModel
## Invalid on purpose: private field.

var id: int
var _secret: int


static func _schema(s: DbSchema) -> void:
    s.table("t_private")
    s.field("id").primary_key()
    s.field("_secret")
