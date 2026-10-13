extends DbModel
## A model without class_name gets no helper.

var id: int


static func _schema(s: DbSchema) -> void:
    s.table("cg_unnamed")
    s.field("id").primary_key()
