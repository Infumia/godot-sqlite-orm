extends DbMigration
## Adds xp and an optional title, spelled out, then fills xp from the name.

const VERSION := 1


func up(m: DbMigrator) -> void:
    m.add_column_raw("players", "xp", TYPE_INT, { "not_null": true, "default": 0 })
    m.add_column_raw("players", "title", TYPE_STRING)
    m.execute("UPDATE players SET xp = length(name) * 10")
