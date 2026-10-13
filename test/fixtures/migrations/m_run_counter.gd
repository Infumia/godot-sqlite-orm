extends DbMigration
## Would break a new database if it ran: it drops a table the models need.

const VERSION := 1


func up(m: DbMigrator) -> void:
    m.drop_table("players")
