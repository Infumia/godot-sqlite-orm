extends DbMigration
## Rebuilds players from MgPlayerRebuilt, keeping nickname as display.

const VERSION := 3


func up(m: DbMigrator) -> void:
    m.rebuild_table(MgPlayerRebuilt, { "nickname": "display" })
