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
		Tags = { Methods = {}, Events = {}, SharedEvents = {} },
	}

	-- Elements oUF ships with, which the style can enable by setting frame[name].
	local BUILTIN = { Health = true, Power = true, Portrait = true, RaidTargetIndicator = true }

	function oUF:RegisterStyle(name, func)
		self.styles[name] = func
	end

	function oUF:SetActiveStyle(name)
		self.activeStyle = name
	end

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

	function oUF:Spawn(unit, name)
		local frame = Mock.NewObject("Button", UIParent, name)
		rawset(frame, "__strict", true)
		frame.__state.protected = true
		frame.__unit = unit
		frame.enabledElements = {}
		frame.tags = {}
		frame.calls = {}

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

		self.styles[self.activeStyle](frame, unit)
		-- Like oUF: after the style, enable every element whose widget exists.
		for element in pairs(BUILTIN) do
			frame:EnableElement(element)
		end
		for element in pairs(self.elements) do
			frame:EnableElement(element)
		end
		return frame
	end

	return oUF
end
