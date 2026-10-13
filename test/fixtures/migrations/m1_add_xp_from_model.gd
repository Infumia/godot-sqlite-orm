extends DbMigration
## Adds xp and title as MgPlayerV2 declares them.

const VERSION := 1


func up(m: DbMigrator) -> void:
    m.add_column(MgPlayerV2, "xp")
    m.add_column(MgPlayerV2, "title")
    m.execute("UPDATE players SET xp = length(name) * 10")
