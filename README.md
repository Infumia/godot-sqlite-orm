# godot-sqlite-orm

A Godot 4 addon for SQLite: models declared in GDScript,
tables created from them, a method-based query builder, and versioned migrations.
Foreign keys are always enforced.

Built on [godot-sqlite](https://github.com/2shady4u/godot-sqlite).

## Use in a game

Add both to the game's `ggg.toml`:

```toml
[[dependency]]
name = "godot-sqlite"
asset_store_asset = "tooshady4u/godot-sqlite:v4.9"
strip_components = 0

[[dependency]]
name = "sqlite-orm"
git = "https://github.com/Infumia/godot-sqlite-orm.git"
rev = "<tag>"
```

## Develop

```
ggg sync
ggg edit
```

Tests are GUT tests in `test/`. The design is in `docs/design.md`.
