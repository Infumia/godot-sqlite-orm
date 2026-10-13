@echo off
rem Runs every GUT test headless. Pass GUT options through, e.g. test.bat -gselect=test_query

ggg run -- --headless --import >nul 2>&1
ggg run -- --headless -s addons/gut/gut_cmdln.gd %*
