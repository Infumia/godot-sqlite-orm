extends DbMigration
## Adds the unique nickname index.

const VERSION := 3


func up(m: DbMigrator) -> void:
    m.add_unique(MgPlayerUnique, ["nickname"])
