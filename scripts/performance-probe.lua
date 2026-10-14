-- Deterministic offline census/counters, not a WoW CPU or native memory test.
-- Run from the repository root: luajit scripts/performance-probe.lua
-- For comparisons run this same file from the baseline checkout as well.
package.path = "tests/?.lua;" .. package.path
local Helpers = require("helpers")
local Mock = Helpers.Mock
local UF, CG = Helpers.LoadClickGrid(false)
assert(not UF.Workbench, "runtime probe must leave Workbench unloaded")

local widgetCounts = {}
for _, object in ipairs(Mock.objects) do
	widgetCounts[object.__type] = (widgetCounts[object.__type] or 0) + 1
end
local seen, components, schemaTables = {}, 0, 0
local function Tables(value)
	if type(value) ~= "table" or seen[value] then return end
	seen[value], schemaTables = true, schemaTables + 1
	for _, child in pairs(value) do Tables(child) end
end
local function Component(component)
	components = components + 1
	Tables(component:GetSchema())
	for _, child in ipairs(component.children) do Component(child) end
end
for _, frame in ipairs(CG.frames) do Component(frame.uf) end
print(string.format("ClickGrid compositions=%d components=%d unique schema tables=%d", #CG.frames, components, schemaTables))
local kinds = {}
for kind in pairs(widgetCounts) do kinds[#kinds + 1] = kind end
table.sort(kinds)
for _, kind in ipairs(kinds) do print(string.format("mock objects %s=%d", kind, widgetCounts[kind])) end

local frame = CG.headers.party:GetAttribute("child1").Member
frame.__unit = "party1"
local stack, reflows = frame.uf:GetDecorations(), 0
local reflow = stack.Reflow
stack.Reflow = function(self) reflows = reflows + 1; return reflow(self) end
local death = UF.oUF.elements.UFCG_DeathIndicator
death.update(frame)
reflows = 0
for _ = 1, 100 do death.update(frame) end
print("100 unchanged death updates: reflows=" .. reflows)

local ready = frame.uf:GetReadyCheck()
ready:Set("ready")
ready:Finish()
local paints, tint = 0, ready.tint
ready.tint = function(...) paints = paints + 1; return tint(...) end
reflows = 0
local driver = ready.driver
for _ = 1, 60 do driver:GetScript("OnUpdate")(driver, 1 / 60) end
print(string.format("60 ready-check hold ticks: paints=%d reflows=%d", paints, reflows))

CG.Config:Set("panel.mode", "flat")
local inactive = CG.headers.group1:GetAttribute("child1").Member
local applies, apply = 0, inactive.uf.Apply
inactive.uf.Apply = function(self, ...) applies = applies + 1; return apply(self, ...) end
CG.Config:SetStyle("member", "width", 180)
print("inactive-layout style edit: member applies=" .. applies)

CG.Config:Set("panel.targets", true)
local preview = CG.Preview:New(UIParent)
preview:ShowData({ source = "animated", count = 40, readyCheck = "check" })
local copies, copy = 0, UF.Util.Copy
UF.Util.Copy = function(value, ...)
	if value == UF.Units.SAMPLE then copies = copies + 1 end
	return copy(value, ...)
end
-- Once warmed, neither member nor target feed copies SAMPLE again.
for _ = 1, 10 do preview:Tick(0.1) end
print("40 member/target pairs, 10 warmed ticks: SAMPLE copies=" .. copies)
UF.Util.Copy = copy
preview:Release()
