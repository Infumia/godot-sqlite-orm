class_name FxItem
extends DbModel
## A weapon or other item with every built-in column type.

enum Rarity {
    COMMON,
    RARE,
    LEGENDARY,
}

var id: int
var name: String
var damage: int = 0
var weight: float = 1.5
var rarity: Rarity = Rarity.COMMON
var tradable: bool = true
var kind: StringName = &"weapon"
var icon: PackedByteArray = PackedByteArray()
var tags: Array[StringName] = []
var rolls: Array[float] = []
var stats: Dictionary[String, int] = { }
var notes: Array = []
var extra: Dictionary = { }
var grid_cell: Vector2i = Vector2i.ZERO
var created: int = 0
var updated: int = 0
var description: Variant = null
var transient: String = ""
var _cache: int = 0


static func _schema(s: DbSchema) -> void:
    s.table("items")
    s.field("id").primary_key().auto_increment()
    s.field("name").unique()
    s.field("damage").check(">= 0")
    s.field("created").auto_created()
    s.field("updated").auto_updated()
    s.field("description").type(TYPE_STRING)
    s.ignore("transient")
