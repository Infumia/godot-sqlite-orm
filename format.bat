@echo off

gdscript-formatter . ^
  --exclude ./addons/gut/ ^
  --exclude ./addons/godot-sqlite/ ^
  --use-spaces ^
  --indent-size 4 ^
  --continuation-indent-level 1 ^
  --max-line-length 100 ^
  --quote-style double ^
  --reorder-code
