--[[
Stand-in for the embedded oUF in offline tests (the real one needs the full
client). Records what our code asks of oUF: styles, elements, tags, element
enable/disable, so the binding layer can be tested.

Spawned frames are strict mock objects (unknown fields are nil like on real
frames) and get oUF's frame methods.
]]
return function(Mock)
	local oUF = {
		styles = {},
		elements = {},
		factories = {},
		initCallbacks = {},
		headers = {},
		Tags = { Methods = {}, Events = {}, SharedEvents = {} },
	}

	-- Elements oUF ships with, which the style can enable by setting frame[name].
	local BUILTIN = { Health = true, Power = true, Portrait = true, RaidTargetIndicator = true,
		GroupRoleIndicator = true, LeaderIndicator = true, AssistantIndicator = true, ReadyCheckIndicator = true,
		ResurrectIndicator = true, SummonIndicator = true, PhaseIndicator = true, ThreatIndicator = true, PrivateAuras = true }

	function oUF:RegisterStyle(name, func)
		self.styles[name] = func
	end

	function oUF:SetActiveStyle(name)
		self.activeStyle = name
	end
	function oUF:GetActiveStyle() return self.activeStyle end
	function oUF:RegisterInitCallback(func) self.initCallbacks[#self.initCallbacks + 1] = func end

	function oUF:AddElement(name, update, enable, disable)
		self.elements[name] = { update = update, enable = enable, disable = disable }
	end

	function oUF:Factory(func)
		self.factories[#self.factories + 1] = func
	end

	-- Test helper: what PLAYER_LOGIN does in the client.
	function oUF:RunFactories()
		for _, func in ipairs(self.factories) do
			func(self)
		end
	end

	local function IsKnown(name)
		return BUILTIN[name] or oUF.elements[name] ~= nil
	end

	local function CreateUnit(unit, name, parent, attributes, style)
		local frame = Mock.NewObject("Button", parent or UIParent, name)
		rawset(frame, "__strict", true)
		frame.__state.protected = true
		frame.__unit = unit
		frame.enabledElements = {}
		frame.tags = {}
		frame.calls = {}
		for key, value in pairs(attributes or {}) do frame:SetAttribute(key, value) end

		function frame:EnableElement(element)
			if IsKnown(element) and self[element] then
				self.enabledElements[element] = true
				table.insert(self.calls, "enable " .. element)
			end
		end
		function frame:DisableElement(element)
			self.enabledElements[element] = nil
			table.insert(self.calls, "disable " .. element)
		end
		function frame:IsElementEnabled(element)
			return self.enabledElements[element] == true
		end
		function frame:Tag(fs, tagString)
			self.tags[fs] = tagString
		end
		function frame:Untag(fs)
			self.tags[fs] = nil
		end
		function frame:UpdateTags()
			table.insert(self.calls, "UpdateTags")
		end
		function frame:UpdateAllElements(event)
			table.insert(self.calls, "UpdateAllElements " .. event)
		end

		oUF.styles[style or oUF.activeStyle](frame, unit)
		-- Like oUF: after the style, enable every element whose widget exists.
		for element in pairs(BUILTIN) do
			frame:EnableElement(element)
		end
		for element in pairs(oUF.elements) do
			frame:EnableElement(element)
		end
		for _, callback in ipairs(oUF.initCallbacks) do callback(frame) end
		_G.ClickCastFrames = _G.ClickCastFrames or {}
		_G.ClickCastFrames[frame] = true
		return frame
	end

	function oUF:Spawn(unit, name) return CreateUnit(unit, name) end

	-- Header capacity and inherited unit assignment stand-in. Real secure
	-- layout/initialization is separately exercised with embedded source.
	function oUF:SpawnHeader(name, template, attributes)
		assert(not InCombatLockdown(), "Secure headers cannot be created in combat")
		local header = Mock.NewObject("Frame", UIParent, name)
		header.__strict, header.__state.protected = true, true
		header.style = self.activeStyle
		for key, value in pairs(attributes) do header:SetAttribute(key, value) end
		function header:Show()
			self.__state.shown = true
			if self:GetAttribute("startingIndex") < 0 and not self:GetAttribute("child1") then
				local capacity = self:GetAttribute("unitsPerColumn") * self:GetAttribute("maxColumns")
				for i = 1, capacity do
					local cell = Mock.NewObject("Button", self, name .. "UnitButton" .. i)
					cell.__state.protected = true
					cell:SetAttribute("oUF-onlyProcessChildren", true)
					self:SetAttribute("child" .. i, cell)
					cell.Member = CreateUnit("raid", cell:GetName() .. "Member", cell, { ["useparent-unit"] = true }, self.style)
					cell.Target = CreateUnit("raidtarget", cell:GetName() .. "Target", cell,
						{ ["useparent-unit"] = true, unitsuffix = "target", ["ufcg-target"] = true }, self.style)
				end
			end
		end
		function header:SetVisibility(condition) self.visibility = condition end
		function header:Assign(index, unit)
			local cell = self:GetAttribute("child" .. index)
			cell:SetAttribute("unit", unit)
			cell.Member.__unit, cell.Target.__unit = unit, unit and unit .. "target" or nil
		end
		header:Hide()
		self.headers[#self.headers + 1] = header
		return header
	end

	return oUF
end
