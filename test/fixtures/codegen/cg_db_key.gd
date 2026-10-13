class_name CgDbKey
extends DbModel
## A key field named "db" would clash with find()'s parameter.

var db: int


static func _schema(s: DbSchema) -> void:
    s.table("cg_db_key")
    s.field("db").primary_key()
