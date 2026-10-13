class_name FxPerson
extends DbModel
## Unique fields alone and together, and a plain index.

var id: int
var name: String
var surname: Variant
var government_id: String


static func _schema(s: DbSchema) -> void:
    s.table("people")
    s.field("id").primary_key().auto_increment()
    s.field("surname").type(TYPE_STRING)
    s.field("government_id").unique()
    s.unique(["name", "surname"])
    s.index(["surname", "name"])
