extends DbModel
## Invalid on purpose: a has_many position field that is not an int.

const Child = preload("res://test/fixtures/invalid/inv_position_child.gd")

var id: int
var children: Array[Child] = []


static func _schema(s: DbSchema) -> void:
    s.table("t_position_parent")
    s.field("id").primary_key()
    s.has_many("children", Child, "parent_id").position("label")
