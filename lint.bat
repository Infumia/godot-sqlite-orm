@echo off
rem private-access is off: the addon's classes share "_" members as an internal API that
rem stays out of the public one, and the tests read them.

gdscript-formatter lint . ^
  --exclude ./addons/gut/ ^
  --exclude ./addons/godot-sqlite/ ^
  --disable private-access ^
  --max-line-length 100 ^
  --pretty
