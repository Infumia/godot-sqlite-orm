extends DbMigration
## Renames name to nickname and creates the pets table from MgPetV3.

const VERSION := 2


func up(m: DbMigrator) -> void:
    m.rename_column("players", "name", "nickname")
    m.create_table(MgPetV3)
