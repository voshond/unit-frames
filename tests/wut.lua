--[[
Finds the wow-ui-testing library and puts it on package.path. Runs
scripts/fetch-wut.sh, which downloads the commit pinned in .wut-version into
.wut/ when it isn't there yet (or uses WUT_DIR, a local library checkout).
Returns the library folder. Run from the repository root:

  local wutDir = dofile("tests/wut.lua")
]]
local log = os.tmpname()
local handle = io.popen("bash scripts/fetch-wut.sh 2>" .. log)
local dir = handle:read("*l")
handle:close()

local messages = io.open(log)
local text = messages and messages:read("*a") or ""
if messages then messages:close() end
os.remove(log)

if not dir or dir == "" then
	io.stderr:write(text)
	error("cannot fetch the wow-ui-testing library (scripts/fetch-wut.sh failed); see DEVELOPMENT.md", 0)
end
for line in text:gmatch("[^\n]+") do
	if not line:find("already in", 1, true) and not line:find("package.path:", 1, true) then
		io.stderr:write(line, "\n")
	end
end

package.path = dir .. "/?.lua;" .. dir .. "/?/init.lua;" .. package.path
return dir
