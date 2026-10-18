local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Dead & ghost look", function()
	local ns, frame, uf, element, unitIsDeadOrGhost
	local GHOST, STRENGTH = { 0.6, 0.72, 0.82 }, 0.85

	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		frame = ns.Units.frames.player
		uf = frame.uf
		element = ns.oUF.elements.UF_Dead
		unitIsDeadOrGhost = UnitIsDeadOrGhost
	end)

	after_each(function()
		_G.UnitIsDeadOrGhost = unitIsDeadOrGhost
	end)

	local function Blend(base, t)
		return { base[1] + (GHOST[1] - base[1]) * t, base[2] + (GHOST[2] - base[2]) * t,
			base[3] + (GHOST[3] - base[3]) * t, base[4] or 1 }
	end

	local function Set(path, value) ns.Config:SetUnitValue("player", path, value) end
	local function Health() return uf:GetRow("health"):GetBar() end
	local function Update() element.update(frame, "UNIT_HEALTH", "player") end

	local function AssertGhost(target)
		local bar = Health()
		assert.is_true(uf:IsDead())
		assert.is_true(bar.ghostFill:IsShown(), "the ghost paint covers the whole health bar")
		assert.same(Blend({ 1, 1, 1 }, STRENGTH), bar.ghostFill.__state.vertexColor)
		assert.same({ GHOST[1], GHOST[2], GHOST[3], STRENGTH }, { bar:GetTint() })
		assert.same({ GHOST[1], GHOST[2], GHOST[3], STRENGTH }, { uf:GetRow("power"):GetBar():GetTint() })
		assert.equals(bar.bar, select(2, bar.ghostFill:GetPoint()))
		local power = uf:GetRow("power"):GetBar()
		assert.is_true(power.ghostFill:IsShown(), "the power colour no longer shows through")
		assert.equals(power.bar:GetStatusBarTexture(), select(2, power.ghostFill:GetPoint()), "and keeps its fill length")
		assert.same(Blend({ 1, 1, 1 }, STRENGTH), power.ghostFill.__state.vertexColor)
		local portrait = uf:GetPart("portrait")
		assert.equals(STRENGTH, portrait.model.__state.desaturation)
		assert.is_true(portrait.texture.__state.desaturated)
		local text = uf:GetRow("health"):GetText("left")
		assert.same(Blend(text.resolved.color, STRENGTH), text:GetFrame().__state.textColor)
		assert.same(Blend(uf.resolved.border.color, STRENGTH), uf.border.__state.backdropBorderColor, target)
	end

	local function AssertLookOff()
		local bar = Health()
		assert.is_false(bar.ghostFill:IsShown())
		assert.is_nil(bar:GetTint())
		assert.is_false(uf:GetRow("power"):GetBar().ghostFill:IsShown())
		assert.equals(0, uf:GetPart("portrait").model.__state.desaturation)
		assert.is_false(uf:GetPart("portrait").texture.__state.desaturated)
		local text = uf:GetRow("health"):GetText("left")
		assert.same({ ns.Util.UnpackColor(text.resolved.color) }, text:GetFrame().__state.textColor)
		assert.same({ ns.Util.UnpackColor(uf.resolved.border.color) }, uf.border.__state.backdropBorderColor)
	end

	local function AssertAlive()
		assert.is_false(uf:IsDead())
		AssertLookOff()
	end

	local function Rounded(...)
		local values = { ... }
		for i, value in ipairs(values) do values[i] = math.floor(value * 1000 + 0.5) / 1000 end
		return values
	end

	it("is a default-enabled frame state on every unit", function()
		for _, unit in ipairs(ns.Units.order) do
			local other = ns.Units.frames[unit]
			assert.is_true(other.uf.resolved.dead.enabled, unit)
			assert.is_true(other:IsElementEnabled("UF_Dead"), unit)
		end
		assert.is_nil(ns.Config:GetUnitConfig("player").dead)
	end)

	it("turns a dead unit's frame ghostly and restores it when alive", function()
		Mock.dead.player = true
		Update()
		AssertGhost("dead")
		Mock.dead.player = nil
		Update()
		AssertAlive()
	end)

	it("covers a ghost's single health point", function()
		Mock.ghosts.player = true
		Update()
		AssertGhost("ghost")
	end)

	it("redraws on the player's death events, which carry no unit", function()
		local handlers = {}
		frame.RegisterEvent = function(_, event, handler, shared) handlers[event] = { handler, shared } end
		frame.UnregisterEvent = function(_, event) handlers[event] = nil end
		assert.is_true(element.enable(frame))
		for _, event in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
			assert.is_true(handlers[event][2], event .. " is unitless")
		end
		for _, event in ipairs({ "UNIT_HEALTH", "UNIT_FLAGS", "UNIT_CONNECTION" }) do
			assert.is_nil(handlers[event][2], event)
		end
		Mock.ghosts.player = true
		handlers.PLAYER_ALIVE[1](frame, "PLAYER_ALIVE")
		assert.is_true(uf:IsDead(), "releasing makes a ghost")
		handlers.UNIT_HEALTH[1](frame, "UNIT_HEALTH", "party1")
		assert.is_true(uf:IsDead(), "another unit's event leaves it alone")
		Mock.ghosts.player = nil
		handlers.PLAYER_UNGHOST[1](frame, "PLAYER_UNGHOST")
		AssertAlive()
	end)

	it("counts an opaque state as alive", function()
		_G.UnitIsDeadOrGhost = function() return Mock.Secret(true) end
		Update()
		AssertAlive()
	end)

	it("follows its settings and switches off with the element", function()
		Mock.dead.player = true
		Update()
		Set("dead.bars", false)
		assert.is_false(Health().ghostFill:IsShown())
		assert.is_nil(Health():GetTint())
		assert.is_true(uf:GetPart("portrait").texture.__state.desaturated, "other targets stay")
		Set("dead.bars", true)
		Set("dead.color", { 0.2, 0.2, 0.9, 1 })
		assert.same({ 0.2, 0.2, 0.9, STRENGTH }, { Health():GetTint() })
		Set("dead.color", nil)
		element.disable(frame)
		assert.is_false(uf:IsDead(), "disabling the element resets the state")
		Update()
		Set("dead.enabled", false)
		assert.is_false(frame:IsElementEnabled("UF_Dead"))
		AssertLookOff()
		Set("dead.enabled", true)
		assert.is_true(frame:IsElementEnabled("UF_Dead"))
		Update()
		AssertGhost("enabled again")
	end)

	it("survives restyling", function()
		Mock.dead.player = true
		Update()
		ns.Units:Refresh("player")
		Set("health.bar.texture", "Blizzard")
		AssertGhost("restyled")
	end)

	it("lets a ready check tint draw over it and returns to the ghost colour", function()
		Mock.dead.player = true
		Update()
		local readyCheck = uf:GetReadyCheck()
		readyCheck:Set("ready")
		local ready = uf.resolved.readyCheck.readyColor
		assert.same(Rounded(ready[1], ready[2], ready[3], 1), Rounded(Health():GetTint()))
		readyCheck:Set(nil)
		AssertGhost("after the check")
	end)

	it("previews through the dead sample and polled live units, like the oUF frame #workbench", function()
		local preview = ns.Units:CreateFromDefinition(ns.Units:GetDefinition("player"), UIParent)
		local sample = ns.Units:GetSample("player")
		sample.status = "dead"
		ns.Units:ShowSample(preview, sample)
		assert.is_true(preview:IsDead())
		assert.is_true(preview:GetRow("health"):GetBar().ghostFill:IsShown())
		sample.status = nil
		ns.Units:ShowSample(preview, sample)
		assert.is_false(preview:IsDead())
		Mock.ghosts.party1 = true
		ns.Units:ShowLive(preview, "party1", {})
		assert.is_true(preview:IsDead())
		Mock.ghosts.party1 = nil
		ns.Units:ShowLive(preview, "party1", {})
		assert.is_false(preview:IsDead())
	end)
end)
