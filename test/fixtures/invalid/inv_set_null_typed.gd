extends DbModel
## Invalid on purpose: set null typed.

var id: int
var item_id: int


static func _schema(s: DbSchema) -> void:
    s.table("t_set_null")
    s.field("id").primary_key()
    s.field("item_id").references(FxItem).on_delete_set_null()
