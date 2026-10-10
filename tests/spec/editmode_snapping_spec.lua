local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Edit Mode snapping", function()
	local ns, lem, manager, frame, selection, oldManager, oldMagnetism
	local function Geometry(frame, left, bottom, width, height, scale)
		scale = scale or 1
		frame.GetRect = function() return left, bottom, width, height end
		frame.GetEffectiveScale = function() return scale end
		frame.IsVisible = function(self) return self:IsShown() end
	end

	before_each(function()
		oldManager, oldMagnetism = EditModeManagerFrame, EditModeMagnetismManager
		ns = Helpers.LoadAddon(true)
		Geometry(UIParent, 0, 0, 1000, 800)
		lem = LibStub:NewLibrary("LibEditMode", 999)
		lem.SettingType = { Slider = 1, Checkbox = 2, Dropdown = 3 }
		lem.frameSelections, lem.callbacks = {}, {}
		lem.editing, lem.layout = true, "Healer"
		function lem:IsInEditMode() return self.editing end
		function lem:GetActiveLayoutName() return self.layout end
		function lem:RegisterCallback(event, fn) self.callbacks[event] = fn end
		function lem:AddFrame(frame, callback)
			local selection = CreateFrame("Frame", nil, frame)
			self.frameSelections[frame] = selection
			selection:SetScript("OnDragStart", function() frame.__state.moving = true end)
			selection:SetScript("OnDragStop", function()
				frame.__state.moving = false
				callback(frame, self.layout, "CENTER", 123, 456) -- library's initial, unsnapped save
			end)
		end
		function lem:AddFrameSettings() end
		function lem:AddFrameSettingsButtons() end
		EditModeManagerFrame = { enabled = true, IsSnapEnabled = function(self) return self.enabled end }
		manager = { magneticFrames = {}, magneticGridLines = { vertical = {}, horizontal = {} } }
		function manager:GetMagneticFrameInfos(source)
			assert.is_false(self == manager, "calculations use a private view")
			manager.lastView, manager.lastSource = self, source
			return manager.infos
		end
		EditModeMagnetismManager = manager
		assert(loadfile("UnitFrames/Integration/EditMode.lua"))("UnitFrames", ns)
		ns.oUF:RunFactories()
		frame = ns.Units.frames.player
		selection = lem.frameSelections[frame]
		Geometry(frame, 263, 185, 100, 40)
		for _, unit in ipairs({ "target", "targettarget", "focus" }) do ns.Units.frames[unit]:Hide() end
	end)

	after_each(function()
		EditModeManagerFrame, EditModeMagnetismManager = oldManager, oldMagnetism
	end)

	it("hooks the library's drag scripts and saves a two-axis grid snap in the active layout", function()
		manager.infos = {
			{ frame = UIParent, point = "LEFT", relativePoint = "LEFT", offset = 270, isHorizontal = true },
			{ frame = UIParent, point = "BOTTOM", relativePoint = "BOTTOM", offset = 190, isHorizontal = false },
		}
		selection:RunScript("OnDragStart")
		assert.is_true(frame.__state.moving)
		assert.is_true(ns.EditMode.snapGuides:IsShown())
		assert.equals(2, #ns.EditMode.snapGuideLines)
		selection:RunScript("OnDragStop")
		assert.is_false(frame.__state.moving)
		assert.is_false(ns.EditMode.snapGuides:IsShown())
		assert.same({ "CENTER", UIParent, "CENTER", -180, -190 }, frame:GetAnchor("CENTER"))
		assert.same({ point = "CENTER", x = -180, y = -190 }, ns.Config:GetPosition("Healer", "player"))
		assert.is_nil(ns.Config:GetPosition("DPS", "player"))
	end)

	it("combines visible addon and Blizzard selection bounds without changing Blizzard's registrations", function()
		local target = ns.Units.frames.target
		target:Show()
		Geometry(target, 365, 185, 100, 40)
		local blizzard = CreateFrame("Frame")
		blizzard.Selection = CreateFrame("Frame", nil, blizzard)
		Geometry(blizzard.Selection, 100, 100, 100, 30)
		manager.magneticFrames[blizzard] = true
		ns.EditMode:GetSnap("player")
		local count = 0
		for geometry in pairs(manager.lastView.magneticFrames) do
			count = count + 1
			assert.is_true(geometry.left == 365 or geometry.left == 100)
		end
		assert.equals(2, count, "only visible candidates, excluding the dragged frame")
		assert.same({ [blizzard] = true }, manager.magneticFrames)
		assert.equals(manager.magneticGridLines, manager.lastView.magneticGridLines)
	end)

	it("aligns frame edges and corners while keeping the resulting anchor on UIParent", function()
		local other = ns.Units.frames.target
		other:Show()
		Geometry(other, 365, 185, 100, 40)
		manager.GetMagneticFrameInfos = function(view)
			for geometry in pairs(view.magneticFrames) do
				return { { frame = geometry, point = "TOPRIGHT", relativePoint = "TOPLEFT", offset = 0,
					isHorizontal = true, isCornerSnap = true } }
			end
		end
		assert.is_true(ns.EditMode:SnapFrame("player"))
		assert.same({ "CENTER", UIParent, "CENTER", -185, -195 }, frame:GetAnchor("CENTER"))
		assert.equals(1, frame:GetNumPoints())
		ns.EditMode:ApplyPosition("player") -- saved positions reapply independently
		-- The active layout is normally supplied by LibEditMode's layout callback.
		ns.EditMode.layout = "Healer"
		ns.EditMode:ApplyPosition("player")
		assert.same({ "CENTER", UIParent, "CENTER", -185, -195 }, frame:GetAnchor("CENTER"))
	end)

	it("converts snapping offsets correctly for scaled frames and UI scale", function()
		UIParent.GetEffectiveScale = function() return 0.8 end
		Geometry(frame, 126.5, 92.5, 50, 20, 1.6) -- UIParent rect: 253,185,100,40
		manager.infos = { { frame = UIParent, point = "LEFT", relativePoint = "LEFT", offset = 260, isHorizontal = true } }
		ns.EditMode:SnapFrame("player")
		assert.same({ "CENTER", UIParent, "CENTER", -95, -97.5 }, frame:GetAnchor("CENTER"))
	end)

	it("leaves free dragging untouched when snapping is disabled or nothing is in range", function()
		EditModeManagerFrame.enabled = false
		selection:RunScript("OnDragStart")
		selection:RunScript("OnDragStop")
		assert.same({ point = "CENTER", x = 123, y = 456 }, ns.Config:GetPosition("Healer", "player"))
		assert.is_nil(manager.lastView)
		EditModeManagerFrame.enabled = true
		manager.infos = nil
		assert.is_false(ns.EditMode:SnapFrame("player"))
	end)

	it("hides guides when snapping is disabled, edit mode exits or combat interrupts a drag", function()
		manager.infos = { { frame = UIParent, point = "LEFT", relativePoint = "LEFT", offset = 270, isHorizontal = true } }
		selection:RunScript("OnDragStart")
		assert.is_true(ns.EditMode.snapGuides:IsShown())
		EditModeManagerFrame.enabled = false
		selection:RunScript("OnUpdate", 0.1)
		assert.is_false(ns.EditMode.snapGuides:IsShown())
		EditModeManagerFrame.enabled = true
		selection:RunScript("OnUpdate", 0.1)
		assert.is_true(ns.EditMode.snapGuides:IsShown())
		lem.editing = false
		lem.callbacks.exit()
		assert.is_false(ns.EditMode.snapGuides:IsShown())
		assert.is_false(ns.EditMode:SnapFrame("player"))
		lem.editing = true
		Mock.inCombat = true
		selection:RunScript("OnEvent", "PLAYER_REGEN_DISABLED")
		assert.is_false(ns.EditMode.snapGuides:IsShown())
		assert.is_false(ns.EditMode:SnapFrame("player"))
		Mock.inCombat = false
	end)

	it("ignores incomplete or secret geometry without arithmetic on secrets", function()
		frame.GetRect = function() return Mock.Secret(200), 185, 100, 40 end
		assert.is_false(ns.EditMode:SnapFrame("player"))
		frame.GetRect = function() return nil end
		assert.is_false(ns.EditMode:SnapFrame("player"))
		Geometry(frame, 263, 185, 100, 40)
		UIParent.GetEffectiveScale = function() return Mock.Secret(1) end
		assert.is_false(ns.EditMode:SnapFrame("player"))
	end)

	it("keeps ordinary dragging functional if native snapping APIs are unavailable", function()
		EditModeMagnetismManager = nil
		selection:RunScript("OnDragStart")
		selection:RunScript("OnDragStop")
		assert.same({ point = "CENTER", x = 123, y = 456 }, ns.Config:GetPosition("Healer", "player"))
		assert.is_false(ns.EditMode:SnapFrame("player"))
	end)
end)
