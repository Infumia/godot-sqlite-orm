class_name FxHero
extends DbModel
## A save slot keyed by UUID, with gear, quests and equipped slots as children.

var id: String
var display_name: String
var class_id: StringName = &"knight"
var level: int = 1
var gold: float = 0.0
var created_unix: int = 0
var saved_unix: int = 0
var best_times: Array[float] = []
var tutorial_seen: Array[StringName] = []
var key_bindings: Dictionary[String, int] = { }
var window_position: Vector2i = Vector2i.ZERO
var gear: Array[FxGear] = []
var quests: Array[FxQuest] = []
var equipped: Array[FxEquipped] = []
var banner: FxBanner


static func _schema(s: DbSchema) -> void:
    s.table("heroes")
    s.field("id").primary_key().default_uuid()
    s.field("display_name").check("<> ''")
    s.field("created_unix").auto_created()
    s.field("saved_unix").auto_updated()
    s.has_many("gear", FxGear, "hero_id").position("slot_index")
    s.has_many("quests", FxQuest, "hero_id").order_by("quest_id", true)
    s.has_many("equipped", FxEquipped, "hero_id")
    s.has_one("banner", FxBanner, "hero_id")
