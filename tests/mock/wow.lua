--[[
The wow-ui-testing client mock (wowmock, held to the library's API snapshot),
extended with what UnitFrames needs: its saved variables and the addon handle
are cleared on every Mock.Install(). tests/mock/ouf.lua is the oUF stand-in.
]]
local Mock = require("wowmock")

Mock.Extend("UnitFrames", {
	globals = { "UnitFrames", "UnitFramesDB", "UnitFramesWorkbenchDB" },
})

return Mock
