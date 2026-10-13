extends DbModel
## Invalid on purpose: node array.

var id: int
var nodes: Array[Node] = []


static func _schema(s: DbSchema) -> void:
    s.table("t_nodes")
    s.field("id").primary_key()
