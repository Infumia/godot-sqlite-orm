extends DbModel
## Invalid on purpose: auto increment string.

var id: String


static func _schema(s: DbSchema) -> void:
    s.table("t_auto_str")
    s.field("id").primary_key().auto_increment()
