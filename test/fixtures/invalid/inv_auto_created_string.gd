extends DbModel
## Invalid on purpose: auto created string.

var id: int
var stamp: String


static func _schema(s: DbSchema) -> void:
    s.table("t_stamp")
    s.field("id").primary_key()
    s.field("stamp").auto_created()
