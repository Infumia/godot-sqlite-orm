class_name FxQuest
extends DbModel
## A quest's progress, keyed by hero and quest together.

enum Status {
    ACTIVE,
    DONE,
    CLAIMED,
}

var hero_id: String
var quest_id: StringName
var status: Status = Status.ACTIVE
var counts: Dictionary[String, int] = { }


static func _schema(s: DbSchema) -> void:
    s.table("quests")
    s.primary_key(["hero_id", "quest_id"])
    s.field("hero_id").references(FxHero).on_delete_cascade()
