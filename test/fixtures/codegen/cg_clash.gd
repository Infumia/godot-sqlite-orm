class_name CgClash
extends DbModel
## Its "group" field would generate where_group, which the query already has.

var id: int
var group: int


static func _schema(s: DbSchema) -> void:
    s.table("cg_clash")
    s.field("id").primary_key()
