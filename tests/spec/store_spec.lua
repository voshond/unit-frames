local Helpers = require("helpers")

describe("Settings stores", function()
	local ns, events
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		events = {}
		ns.Events.RegisterCallback(events, "UnitConfigChanged", function(_, unit, path)
			events[#events + 1] = { unit = unit, path = path }
		end)
	end)

	it("edits unit styles in place and notifies once per write", function()
		local saved = ns.Config:GetUnitConfig("target")
		local store = ns.Config:UnitStore("target")
		assert.is_true(store:Set("width", 250))
		assert.equals(250, saved.width)
		assert.is_true(store:Replace({ spacing = 3 }))
		assert.equals(saved, ns.Config:GetUnitConfig("target"))
		assert.same({ spacing = 3 }, saved)
		assert.is_true(store:Reset())
		assert.same({}, saved)
		assert.same({ { unit = "target", path = "width" }, { unit = "target" }, { unit = "target" } }, events)
		assert.equals(1, ns.Units.frames.target.uf.resolved.spacing)
	end)

	it("copies player settings through one replacement", function()
		ns.Config:SetUnitValue("player", "width", 280)
		events[1] = nil
		assert.is_true(ns.Units:CopyPlayerSettings("focus"))
		assert.equals(280, ns.Config:GetUnitConfig("focus").width)
		assert.same({ { unit = "focus" } }, events)
	end)

	it("rejects invalid candidates without writing or notifying", function()
		local saved, changes = {}, 0
		local store = ns.Store:New({
			schema = { { key = "size", type = "range", min = 1, max = 10, default = 5 } },
			read = function() return saved end,
			write = function(candidate) saved = candidate end,
			validate = true,
			check = function(candidate) return candidate.size ~= 7, "seven is reserved" end,
			changed = function() changes = changes + 1 end,
		})
		local ok, reason = store:Set("size", 20)
		assert.is_false(ok)
		assert.is_not_nil(reason:find("out of range", 1, true))
		ok, reason = store:Set("size", 7)
		assert.is_false(ok)
		assert.equals("seven is reserved", reason)
		assert.same({}, saved)
		assert.equals(0, changes)
		local target = store:Target(function(message) reason = "reported: " .. message end)
		target.set("size", 20)
		assert.is_not_nil(reason:find("reported:", 1, true))
		target.set("size", 3)
		assert.equals(3, target.get("size"))
		assert.equals(3, target.resolved().size)
		assert.equals(1, changes)
	end)
end)
