local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Raid target icons", function()
	local ns, frame, uf, marker
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		frame = ns.Units.frames.player
		uf = frame.uf
		marker = uf:GetRaidTarget()
	end)

	it("offers and binds an independently configurable icon on every unit", function()
		for _, unit in ipairs(ns.Units.order) do
			local live = ns.Units.frames[unit]
			assert.is_not_nil(ns.Schema.Find(live.uf:GetSchema(), "raidTarget.anchor"))
			assert.equals(live.uf:GetRaidTarget():GetWidget(), live.RaidTargetIndicator)
			assert.is_true(live:IsElementEnabled("RaidTargetIndicator"))
			assert.is_false(live.RaidTargetIndicator:IsShown(), "hidden until a marker is assigned")
		end
		ns.Config:SetUnitValue("target", "raidTarget.enabled", false)
		assert.is_false(ns.Units.frames.target:IsElementEnabled("RaidTargetIndicator"))
		assert.is_true(frame:IsElementEnabled("RaidTargetIndicator"))
		ns.Config:SetUnitValue("target", "raidTarget.enabled", true)
		assert.is_true(ns.Units.frames.target:IsElementEnabled("RaidTargetIndicator"))
	end)

	it("centres on all eight border anchors without changing frame dimensions", function()
		local width, height = frame:GetSize()
		for _, anchor in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT", "RIGHT", "BOTTOMRIGHT", "BOTTOM", "BOTTOMLEFT", "LEFT" }) do
			ns.Config:SetUnitValue("player", "raidTarget.anchor", anchor)
			assert.same({ "CENTER", frame, anchor, 0, 0 }, marker:GetFrame():GetAnchor("CENTER"))
			assert.equals(width, frame:GetWidth())
			assert.equals(height, frame:GetHeight())
		end
		ns.Config:SetUnitValue("player", "raidTarget.size", 32)
		ns.Config:SetUnitValue("player", "raidTarget.offsetX", -7)
		ns.Config:SetUnitValue("player", "raidTarget.offsetY", 5)
		assert.same({ "CENTER", frame, "LEFT", -7, 5 }, marker:GetFrame():GetAnchor("CENTER"))
		assert.equals(32, marker:GetFrame():GetWidth())
		assert.equals(32, marker:GetFrame():GetHeight())
	end)

	it("keeps portrait corners inside on either side and through portrait style changes", function()
		local portrait = uf:GetPortrait():GetFrame()
		for _, side in ipairs({ "LEFT", "RIGHT" }) do
			ns.Config:SetUnitValue("player", "portrait.position", side)
			for _, mode in ipairs({ "3D", "2D", "class" }) do
				ns.Config:SetUnitValue("player", "portrait.mode", mode)
				for _, corner in ipairs({ "BOTTOMLEFT", "BOTTOMRIGHT" }) do
					ns.Config:SetUnitValue("player", "raidTarget.anchor", "PORTRAIT_" .. corner)
					assert.same({ corner, portrait, corner, 0, 0 }, marker:GetFrame():GetAnchor(corner))
					assert.equals(1, marker:GetFrame():GetNumPoints())
				end
			end
		end
		ns.Config:SetUnitValue("player", "raidTarget.offsetX", -3)
		ns.Config:SetUnitValue("player", "raidTarget.offsetY", 4)
		assert.same({ "BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -3, 4 }, marker:GetFrame():GetAnchor("BOTTOMRIGHT"))
	end)

	it("hides portrait anchors when there is no portrait and restores them when it returns", function()
		ns.Config:SetUnitValue("player", "raidTarget.anchor", "PORTRAIT_BOTTOMRIGHT")
		marker:SetIndex(8)
		ns.Config:SetUnitValue("player", "portrait.enabled", false)
		assert.is_false(marker:GetFrame():IsShown())
		marker:Apply()
		assert.is_false(marker:GetFrame():IsShown(), "a child reapply cannot reveal a missing portrait anchor")
		ns.Config:SetUnitValue("player", "portrait.enabled", true)
		assert.is_true(marker:GetFrame():IsShown())
		assert.is_true(marker:GetWidget():IsShown())
		ns.Config:SetUnitValue("player", "portrait.enabled", false)
		ns.Config:SetUnitValue("player", "raidTarget.anchor", "TOP")
		assert.is_true(marker:GetFrame():IsShown(), "border anchors work without portraits")
	end)

	it("fits small portraits and hides when every row is collapsed", function()
		ns.Config:SetUnitValue("player", "raidTarget.anchor", "PORTRAIT_BOTTOMLEFT")
		ns.Config:SetUnitValue("player", "raidTarget.size", 64)
		ns.Config:SetUnitValue("player", "portrait.size", 12)
		assert.equals(12, marker:GetFrame():GetWidth())
		marker:Apply()
		assert.equals(12, marker:GetFrame():GetHeight())
		ns.Config:SetUnitValue("player", "portrait.size", 100)
		ns.Config:SetUnitValue("player", "castbar.placement", "off")
		ns.Config:SetUnitValue("player", "power.enabled", false)
		ns.Config:SetUnitValue("player", "experience.enabled", false)
		assert.equals(26, marker:GetFrame():GetHeight(), "height also limits the icon")
		ns.Config:SetUnitValue("player", "health.enabled", false)
		assert.is_false(marker:GetFrame():IsShown())
		ns.Config:SetUnitValue("player", "health.enabled", true)
		assert.is_true(marker:GetFrame():IsShown())
	end)

	it("stays above the portrait and the castbar covering health", function()
		ns.Config:SetUnitValue("player", "castbar.placement", "health")
		local level = marker:GetFrame():GetFrameLevel()
		assert.is_true(level > uf:GetPortrait().model:GetFrameLevel())
		assert.is_true(level > uf:GetCastbar():GetFrame():GetFrameLevel())
		assert.equals("OVERLAY", marker:GetWidget().__state.layer)
	end)

	it("uses the embedded oUF element to handle marker changes, removal and unit changes", function()
		-- Real textures return nil for unset optional callback fields.
		rawset(marker:GetWidget(), "__strict", true)
		assert(loadfile("UnitFrames/Libs/oUF/elements/raidtargetindicator.lua"))("oUF", ns)
		local element, handlers = ns.oUF.elements.RaidTargetIndicator, {}
		frame.RegisterEvent = function(_, event, handler, shared)
			handlers[event] = handler
			assert.is_true(shared, "raid marker events carry no unit")
		end
		frame.UnregisterEvent = function(_, event) handlers[event] = nil end
		assert.is_true(element.enable(frame))
		assert.is_not_nil(handlers.RAID_TARGET_UPDATE)
		for index = 1, 8 do
			Mock.raidTargets.player = index
			handlers.RAID_TARGET_UPDATE(frame, "RAID_TARGET_UPDATE")
			assert.equals(index, marker:GetWidget().__state.raidTargetIndex)
			assert.is_true(marker:GetWidget():IsShown())
		end
		Mock.raidTargets.player = nil
		handlers.RAID_TARGET_UPDATE(frame, "RAID_TARGET_UPDATE")
		assert.is_false(marker:GetWidget():IsShown())
		frame.__unit = "target"
		Mock.raidTargets.target = 3
		element.update(frame, "PLAYER_TARGET_CHANGED")
		assert.equals(3, marker:GetWidget().__state.raidTargetIndex)
		assert.is_true(marker:GetWidget():IsShown())
		element.disable(frame)
		assert.is_nil(handlers.RAID_TARGET_UPDATE)
		assert.is_false(marker:GetWidget():IsShown())
	end)

	it("copies player icon settings and releases preview visuals", function()
		ns.Config:SetUnitValue("player", "raidTarget.anchor", "BOTTOMRIGHT")
		ns.Config:SetUnitValue("player", "raidTarget.offsetX", 7)
		ns.Units:CopyPlayerSettings("target")
		local target = ns.Units.frames.target
		assert.same({ "CENTER", target, "BOTTOMRIGHT", 7, 0 }, target.uf:GetRaidTarget():GetFrame():GetAnchor("CENTER"))
		local preview = ns.Units:CreateFrame("target", UIParent)
		local previewMarker = preview:GetRaidTarget()
		previewMarker:SetIndex(8)
		preview:Release()
		assert.is_false(previewMarker:GetFrame():IsShown())
		assert.equals(0, previewMarker:GetFrame():GetNumPoints())
	end)
end)

describe("Raid target Workbench previews", function()
	it("offers every marker and None while saving anchor changes to the live frame", function()
		local ns, workbench = Helpers.LoadWorkbench()
		workbench:Toggle()
		for _, unit in ipairs(ns.Units.order) do
			workbench:Select("unit." .. unit)
			local marker = workbench.handle.parts.uf:GetRaidTarget()
			local opt = ns.Schema.Find(workbench.dataTarget.schema, "raidTarget")
			assert.equals(9, #ns.Schema.GetValues(opt))
			assert.equals(8, marker:GetWidget().__state.raidTargetIndex)
			for index = 1, 8 do
				workbench.dataTarget.set("raidTarget", index)
				assert.equals(index, marker:GetWidget().__state.raidTargetIndex)
				assert.is_true(marker:GetWidget():IsShown())
			end
			workbench.dataTarget.set("raidTarget", 0)
			assert.is_false(marker:GetWidget():IsShown())
			workbench.styleTarget.set("raidTarget.anchor", "BOTTOM")
			assert.equals("BOTTOM", ns.Units.frames[unit].uf:GetRaidTarget().resolved.anchor)
			workbench:SelectSection("raidTarget")
			assert.equals(7, #workbench.inspector.page.rows)
		end
	end)
end)
