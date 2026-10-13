extends DbMigration
## Leaves a pet pointing at a player that does not exist.

const VERSION := 3


func up(m: DbMigrator) -> void:
    m.execute("INSERT INTO pets (owner_id, species) VALUES (999, 'ghost')")
