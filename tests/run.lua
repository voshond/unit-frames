--[[
Runs the specs with the wow-ui-testing runner (wowtest), configured by
tests/wut.config.lua. Run from the repository root:

  luajit tests/run.lua                  all specs
  luajit tests/run.lua units            spec paths containing "units" (folder or file)
  luajit tests/run.lua units/           exactly the tests/spec/units/ folder
  luajit tests/run.lua shields_spec.lua exactly that spec file
  luajit tests/run.lua -t "full health" only tests whose full name contains the text
  luajit tests/run.lua --tag shields    only tests tagged #shields (in a describe or it name)
  luajit tests/run.lua -j               spec files in parallel, one process per CPU (-j 4: four)
  luajit tests/run.lua --times          also report how long each spec file took

Path filters are combined with "or"; -t and --tag narrow further. Every run
also syntax-checks every addon Lua file. A run that selects no tests fails.
]]
local wutDir = dofile("tests/wut.lua")
arg[0] = wutDir .. "/wowtest/cli.lua"
dofile(arg[0])
