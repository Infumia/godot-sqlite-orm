extends DbModel
## The child of inv_position_parent.gd; its "label" is a String.

var id: int
var parent_id: int
var label: String


static func _schema(s: DbSchema) -> void:
    s.table("t_position_child")
    s.field("id").primary_key()
    var parent: GDScript = load("res://test/fixtures/invalid/inv_position_parent.gd")
    s.field("parent_id").references(parent)
