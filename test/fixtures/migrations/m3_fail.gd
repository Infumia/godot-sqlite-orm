extends DbMigration
## Changes data, then gives up.

const VERSION := 3


func up(m: DbMigrator) -> void:
    m.execute("UPDATE players SET xp = 0")
    m.fail("not today")
    m.execute("UPDATE players SET xp = 1")
