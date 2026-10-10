--[[
Minimal mock of the WoW client API, enough to load UnitFrames and test its
logic offline (LuaJIT, Lua 5.1 semantics like the client).

Widgets are plain tables that keep simple state and record calls. Methods
without an explicit implementation are accepted and recorded, so code can call
them, and tests can inspect obj.__calls.

Secret(v) creates a fake secret value: a table without arithmetic or
comparison metamethods, so doing maths or comparisons on it raises an error,
just like a real secret does. issecretvalue() recognises it.
]]
local Mock = {}

local SecretMT = { __tostring = function() return "<secret>" end }

function Mock.Secret(value)
	return setmetatable({ secretValue = value }, SecretMT)
end

-- Concatenating secrets is allowed in the client and gives a secret string.
SecretMT.__concat = function()
	return Mock.Secret("concat")
end

function Mock.IsSecret(value)
	return type(value) == "table" and getmetatable(value) == SecretMT
end

local function AnySecret(...)
	for i = 1, select("#", ...) do
		if Mock.IsSecret((select(i, ...))) then
			return true
		end
	end
	return false
end

-- Widgets ---------------------------------------------------------------------

local Methods = {}
local ObjectMT = {}

local registry -- all created objects, reset per Mock.Install()

local function NewObject(objectType, parent, name)
	local obj = setmetatable({
		__type = objectType,
		__calls = {},
		__state = {
			shown = true,
			points = {},
			width = 0,
			height = 0,
			level = parent and parent.__state and (parent.__state.level + 1) or 0,
			parent = parent,
			scripts = {},
			events = {},
			name = name,
		},
	}, ObjectMT)
	registry[#registry + 1] = obj
	if name then
		_G[name] = obj
	end
	return obj
end
Mock.NewObject = NewObject

ObjectMT.__index = function(obj, key)
	local impl = Methods[key]
	if impl then
		return impl
	end
	-- Strict objects behave like real frames for unknown keys (nil), e.g. oUF
	-- unit frames where code checks fields like frame.Health.
	if rawget(obj, "__strict") then
		return nil
	end
	-- oUF's prediction calculator is a data field, never a widget method.
	if key == "values" then return nil end
	-- Unknown method: accept and record.
	return function(self, ...)
		self.__calls[#self.__calls + 1] = { key, ... }
	end
end

local function Record(self, name, ...)
	self.__calls[#self.__calls + 1] = { name, ... }
end

function Methods:GetObjectType() return self.__type end
function Methods:IsObjectType(t) return self.__type == t end
function Methods:GetName() return self.__state.name end

function Methods:SetScript(name, fn) self.__state.scripts[name] = fn end
function Methods:GetScript(name) return self.__state.scripts[name] end
function Methods:HookScript(name, fn)
	local previous = self.__state.scripts[name]
	self.__state.scripts[name] = function(...)
		if previous then
			previous(...)
		end
		fn(...)
	end
end
function Methods:RunScript(name, ...)
	local fn = self.__state.scripts[name]
	if fn then
		return fn(self, ...)
	end
end

function Methods:Show() self.__state.shown = true end
function Methods:Hide() self.__state.shown = false end
function Methods:SetShown(shown) self.__state.shown = shown and true or false end
function Methods:IsShown() return self.__state.shown end
function Methods:IsVisible()
	local parent = self:GetParent()
	return self:IsShown() and (not parent or parent:IsVisible())
end

function Methods:SetParent(parent) self.__state.parent = parent end
function Methods:GetParent() return self.__state.parent end

local function Resize(self, width, height)
	local s = self.__state
	local changed = s.width ~= width or s.height ~= height
	s.width, s.height = width, height
	if changed and s.scripts.OnSizeChanged then
		s.scripts.OnSizeChanged(self, width, height)
	end
end
function Methods:SetSize(width, height) Resize(self, width, height) end
function Methods:SetWidth(width) Resize(self, width, self.__state.height) end
function Methods:SetHeight(height) Resize(self, self.__state.width, height) end
function Methods:GetSize() return self.__state.width, self.__state.height end
function Methods:GetWidth() return self.__state.width end
function Methods:GetHeight() return self.__state.height end

function Methods:SetPoint(point, relativeTo, relativePoint, x, y)
	if type(relativeTo) == "number" then
		relativeTo, relativePoint, x, y = nil, point, relativeTo, relativePoint
	end
	local points = self.__state.points
	for i, p in ipairs(points) do
		if p[1] == point then
			table.remove(points, i)
			break
		end
	end
	points[#points + 1] = { point, relativeTo, relativePoint or point, x or 0, y or 0 }
end
function Methods:SetAllPoints(relativeTo)
	self.__state.points = { { "ALL", relativeTo } }
end
function Methods:ClearAllPoints() self.__state.points = {} end
function Methods:GetNumPoints() return #self.__state.points end
function Methods:GetPoint(index)
	local p = self.__state.points[index or 1]
	if p then
		return p[1], p[2], p[3], p[4], p[5]
	end
end
-- Test helper: the anchor entry for a given point name.
function Methods:GetAnchor(point)
	for _, p in ipairs(self.__state.points) do
		if p[1] == point then
			return p
		end
	end
end

function Methods:SetFrameLevel(level) self.__state.level = level end
function Methods:IsProtected() return self.__state.protected == true end
function Methods:SetAttribute(name, value) self.__state.attributes = self.__state.attributes or {}; self.__state.attributes[name] = value end
function Methods:RegisterForClicks(...) Record(self, "RegisterForClicks", ...) end
function Methods:GetChildren() end
function Methods:GetFrameLevel() return self.__state.level end

function Methods:CreateTexture(name, layer)
	local t = NewObject("Texture", self, name)
	t.__state.layer = layer
	return t
end
function Methods:CreateLine(name, layer)
	local line = NewObject("Line", self, name)
	line.__state.layer = layer
	return line
end
function Methods:CreateFontString(name, layer, inherits)
	local fs = NewObject("FontString", self, name)
	fs.__state.layer = layer
	fs.__state.fontObject = inherits
	return fs
end
function Methods:CreateAnimationGroup() return NewObject("AnimationGroup", self) end
function Methods:CreateAnimation(animationType) return NewObject(animationType or "Animation", self) end

-- StatusBar
function Methods:GetStatusBarTexture()
	if not self.__state.fill then
		self.__state.fill = NewObject("Texture", self)
	end
	return self.__state.fill
end
function Methods:SetStatusBarTexture(texture)
	Record(self, "SetStatusBarTexture", texture)
	self.__state.texture = texture
	return true
end
function Methods:SetMinMaxValues(min, max) self.__state.min, self.__state.max = min, max end
function Methods:GetMinMaxValues() return self.__state.min, self.__state.max end
function Methods:SetValue(value, interpolation)
	self.__state.value = value
	self.__state.interpolation = interpolation
end
function Methods:GetValue() return self.__state.value end
function Methods:SetStatusBarColor(r, g, b, a) self.__state.color = { r, g, b, a } end
function Methods:SetOrientation(orientation) self.__state.orientation = orientation end
function Methods:GetOrientation() return self.__state.orientation or "HORIZONTAL" end
function Methods:SetReverseFill(reverse) self.__state.reverseFill = reverse end
function Methods:SetTimerDuration(duration, interpolation, direction)
	self.__state.timer = { duration = duration, interpolation = interpolation, direction = direction }
end

-- Texture
function Methods:SetTexture(texture) self.__state.texture = texture end
function Methods:SetTexCoord(...) self.__state.texCoords = { ... } end
function Methods:GetTexture() return self.__state.texture end
function Methods:SetVertexColor(r, g, b, a) self.__state.vertexColor = { r, g, b, a } end
function Methods:SetColorTexture(r, g, b, a) self.__state.colorTexture = { r, g, b, a } end

-- FontString
function Methods:SetFont(path, size, flags)
	Record(self, "SetFont", path, size, flags)
	if type(path) ~= "string" or path == "" then
		return false
	end
	self.__state.font = { path, size, flags }
	return true
end
-- Like the client: a FontString needs a font before it can show text.
local function RequireFont(fs)
	local s = fs.__state
	if fs.__type == "FontString" and not (s.font or s.fontObject) then
		error("FontString:SetText(): Font not set", 3)
	end
end
function Methods:SetText(text)
	RequireFont(self)
	self.__state.text = text
end
function Methods:SetFontObject(font) self.__state.fontObject = font end
function Methods:SetFormattedText(fmt, ...)
	RequireFont(self)
	if AnySecret(...) then
		self.__state.text = Mock.Secret(fmt)
	else
		self.__state.text = string.format(fmt, ...)
	end
end
function Methods:GetText() return self.__state.text end
function Methods:SetTextColor(r, g, b, a) self.__state.textColor = { r, g, b, a } end
function Methods:GetStringWidth() return 50 end

-- Backdrop (BackdropTemplate)
local borderPieces = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
	"TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }
function Methods:SetBackdrop(info)
	if not info or not (info.edgeFile or info.bgFile) then self:ClearBackdrop(); return end
	self.__state.backdrop = info
	for _, key in ipairs(borderPieces) do
		local texture = rawget(self, key) or self:CreateTexture(nil, "BORDER")
		self[key] = texture
		texture:SetTexture(info.edgeFile)
	end
end
function Methods:GetBackdrop() return self.__state.backdrop end
function Methods:ClearBackdrop()
	self.__state.backdrop = nil
	for _, key in ipairs(borderPieces) do
		local texture = rawget(self, key)
		if texture then texture:SetTexture(nil) end
	end
end
function Methods:SetBackdropColor(r, g, b, a) self.__state.backdropColor = { r, g, b, a } end
function Methods:SetBackdropBorderColor(r, g, b, a)
	self.__state.backdropBorderColor = { r, g, b, a }
	for _, key in ipairs(borderPieces) do
		local texture = rawget(self, key)
		if texture then texture:SetVertexColor(r, g, b, a) end
	end
end

function Methods:SetCooldown(start, duration) self.__state.cooldown = { start = start, duration = duration } end
function Methods:Pause() self.__state.paused = true end

-- Slider
function Methods:GetThumbTexture()
	if not self.__state.thumb then
		self.__state.thumb = NewObject("Texture", self)
	end
	return self.__state.thumb
end

-- DropdownButton (Blizzard menu system): GenerateMenu runs the generator
-- against a fake root description so menu code gets exercised.
function Methods:SetupMenu(generator)
	self.__state.menuGenerator = generator
	self:GenerateMenu()
end
function Methods:GenerateMenu()
	local generator = self.__state.menuGenerator
	if generator then
		local root = NewObject("MenuDescription")
		generator(self, root)
		self.__state.menu = root
	end
end
function Methods:CreateRadio(text, isSelected, setSelected, data)
	local element = NewObject("MenuElement")
	element.__state.text = text
	element.__state.isSelected = isSelected
	element.__state.setSelected = setSelected
	element.__state.data = data
	self.__state.elements = self.__state.elements or {}
	table.insert(self.__state.elements, element)
	isSelected()
	return element
end
function Methods:AddInitializer(initializer)
	self.__state.initializers = self.__state.initializers or {}
	table.insert(self.__state.initializers, initializer)
end

-- Events
function Methods:RegisterEvent(event) self.__state.events[event] = true end
function Methods:RegisterUnitEvent(event) self.__state.events[event] = true end
function Methods:UnregisterEvent(event) self.__state.events[event] = nil end
function Methods:UnregisterAllEvents() self.__state.events = {} end

function Mock.FireEvent(event, ...)
	for _, obj in ipairs(registry) do
		if obj.__state.events[event] and obj.__state.scripts.OnEvent then
			obj.__state.scripts.OnEvent(obj, event, ...)
		end
	end
end

-- AuraContainer (Blizzard_CustomAuraContainer): groups create two buttons up
-- front through their initializeFrame, like the real frame batch does.
function Mock.DecorateAuraContainer(container)
	local s = container.__state
	s.groups, s.groupOrder = {}, {}
	function container:AddAuraGroup(key, filter, options)
		local group = { filter = filter, options = options, frames = {}, enabled = true }
		s.groups[key] = group
		table.insert(s.groupOrder, key)
		for i = 1, 2 do
			local button = NewObject("Button", self)
			button.__state.dispelTextures = {}
			function button:MockUpdateDispelTextures(dispelName)
				if dispelName then self.__state.dispelName = dispelName end
				for texture, opts in pairs(self.__state.dispelTextures) do
					local name = self.__state.dispelName or "Magic"
					local color = opts.customDispelColorMap and opts.customDispelColorMap[name]
						or AuraUtil.GetAuraBorderColor(name)
					texture:SetVertexColor(color:GetRGBA())
					texture:Show()
				end
			end
			function button:AddDispelTypeTexture(texture, opts)
				assert(not self.__state.dispelTextures[texture], "duplicate dispel texture")
				self.__state.dispelTextures[texture] = opts
				self:MockUpdateDispelTextures()
			end
			function button:RemoveDispelTypeTexture(texture)
				assert(self.__state.dispelTextures[texture], "unregistered dispel texture")
				self.__state.dispelTextures[texture] = nil
			end
			-- The engine fills bound texts right away (here, during AddAuraGroup).
			function button:SetApplicationCount(fs) fs:SetText("") end
			function button:SetDurationText(fs, options)
				self.__state.durationText = { fontString = fs, options = options }
				fs:SetText("")
			end
			group.frames[i] = button
			options.initializeFrame(button)
		end
	end
	function container:SetAuraGroupEnabled(key, enabled) s.groups[key].enabled = enabled end
	function container:SetAuraGroupFilterString(key, filter) s.groups[key].filter = filter end
	function container:SetAuraGroupMaxFrameCount(key, max) s.groups[key].max = max end
	function container:SetAuraGroupLayout(key, layout) s.groups[key].layout = layout end
	function container:GetAuraGroupFrameCount(key) return #s.groups[key].frames end
	function container:GetAuraGroupFrame(key, index) return s.groups[key].frames[index] end
	function container:SetUnit(unit)
		assert(type(unit) == "string", "AuraContainer:SetUnit requires a string")
		s.unit = unit
		s.updates = (s.updates or 0) + 1
	end
	function container:GetUnit() return s.unit end
	function container:UpdateAllAuras() s.updates = (s.updates or 0) + 1 end
	function container:SetEnabled(enabled) s.enabled = enabled end
	function container:IsEnabled() return s.enabled == true end
	function container:SetFlowLayoutAnchorPoint(point) s.flowAnchor = point end
	function container:SetFlowLayoutAxis(axis) s.flowAxis = axis end
	function container:SetFlowLayoutGrowthDirection(x, y) s.growth = { x, y } end
	function container:SetFlowLayoutMaximumLineSize(size) s.lineSize = size end
end

-- Other API ---------------------------------------------------------------------

local function NewColor(r, g, b, a)
	local color = { r = r, g = g, b = b, a = a or 1 }
	function color:GetRGB() return self.r, self.g, self.b end
	function color:GetRGBA() return self.r, self.g, self.b, self.a end
	return color
end

local function NewCurve(isColor)
	local curve = { points = {}, isColor = isColor }
	function curve:AddPoint(x, y)
		self.points[#self.points + 1] = { x, y }
		table.sort(self.points, function(a, b) return a[1] < b[1] end)
	end
	function curve:Evaluate(x)
		local points = self.points
		if x <= points[1][1] then
			return points[1][2]
		end
		for i = 2, #points do
			local p0, p1 = points[i - 1], points[i]
			if x <= p1[1] then
				local t = (x - p0[1]) / (p1[1] - p0[1])
				local a, b = p0[2], p1[2]
				if type(a) == "table" then
					return NewColor(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
				end
				return a + (b - a) * t
			end
		end
		return points[#points][2]
	end
	return curve
end

-- The client's string.format accepts secrets (result is a secret string).
local format = string.format
string.format = function(fmt, ...)
	for i = 1, select("#", ...) do
		if Mock.IsSecret((select(i, ...))) then
			return Mock.Secret(fmt)
		end
	end
	return format(fmt, ...)
end

function Mock.Install()
	registry = {}
	Mock.objects = registry
	Mock.time = 100

	_G.LibStub = nil
	_G.UnitFrames = nil
	_G.UnitFramesDB = nil
	_G.UnitFramesWorkbenchDB = nil

	_G.Secret = Mock.Secret
	_G.issecretvalue = Mock.IsSecret

	_G.CreateFrame = function(frameType, name, parent)
		local obj = NewObject(frameType or "Frame", parent, name)
		if frameType == "AuraContainer" then
			Mock.DecorateAuraContainer(obj)
		end
		return obj
	end
	_G.CreateFont = function(name)
		return NewObject("Font", nil, name)
	end
	_G.UIParent = NewObject("Frame", nil, "UIParent")
	_G.UISpecialFrames = {}
	_G.SlashCmdList = {}
	_G.CreateColor = NewColor
	_G.GetTime = function() return Mock.time end
	_G.GetLocale = function() return "enUS" end
	_G.GetRealmName = function() return "TestRealm" end
	_G.GetCurrentRegion = function() return 3 end
	_G.GetCurrentRegionName = function() return "EU" end
	_G.UnitName = function() return "Tester", "TestRealm" end
	_G.UnitNameUnmodified = _G.UnitName
	_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
	_G.UnitRace = function() return "Human", "Human" end
	_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
	_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
	_G.strlenutf8 = function(s) return #s end
	_G.tinsert = table.insert
	_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
	_G.securecallfunction = function(fn, ...) return fn(...) end
	_G.geterrorhandler = function() return error end
	_G.INTERRUPTED = "Interrupted"
	_G.UnitFrame_OnEnter = function() end
	_G.UnitFrame_OnLeave = function() end
	_G.InCombatLockdown = function() return Mock.inCombat == true end
	Mock.inCombat = false
	_G.FAILED = "Failed"

	_G.AnchorUtil = {
		FlowLayoutAxis = { Horizontal = 0, Vertical = 1 },
		FlowDirection = { Left = -1, Right = 1, Up = 1, Down = -1 },
		CreateFlowLayout = function()
			local flow = {}
			function flow:SetLayoutAxis(axis) self.axis = axis end
			function flow:SetAnchorPoint(anchor) self.anchor = anchor end
			function flow:SetGrowthDirection(x, y) self.x, self.y = x, y end
			function flow:SetMaximumLineSize(size) self.lineSize = size end
			-- Sample grids have one group of equally sized cells. Model the
			-- resulting bounds and anchors, including wrapping and empty grids.
			function flow:Apply(container, groups)
				local group = groups[1]
				local elements = group.elements
				if #elements == 0 then container:SetSize(1, 1); return end
				local vertical = self.axis == 1
				local width, height = elements[1]:GetSize()
				local primary = vertical and height or width
				local cross = vertical and width or height
				local spacing, lineSpacing = group.elementSpacing, group.lineSpacing
				local perLine = math.max(1, math.floor((self.lineSize + spacing) / (primary + spacing)))
				for i, button in ipairs(elements) do
					local p, c = (i - 1) % perLine * (primary + spacing), math.floor((i - 1) / perLine) * (cross + lineSpacing)
					button:ClearAllPoints()
					button:SetPoint(self.anchor, container, self.anchor, (vertical and c or p) * self.x, (vertical and p or c) * self.y)
				end
				local p = math.min(perLine, #elements) * (primary + spacing) - spacing
				local c = math.ceil(#elements / perLine) * (cross + lineSpacing) - lineSpacing
				container:SetSize(vertical and c or p, vertical and p or c)
			end
			return flow
		end,
	}
	_G.AuraUtil = {
		GetAuraBorderColor = function(kind)
			local colors = { Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 }, Poison = { 0, 0.6, 0 } }
			return NewColor(unpack(colors[kind] or { 0.8, 0, 0 }))
		end,
	}
	_G.AuraContainerSortMethod = { ExpirationOnly = 1 }
	_G.AuraContainerSortDirection = { Normal = 0 }
	_G.Enum = {
		CustomAuraButtonDispelTypeTextureStyle = { Border = 1, PreserveAsset = 4 },
		StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 },
		UnitDamageAbsorbClampMode = { MissingHealth = 0, MissingHealthWithoutIncomingHeals = 1, MaximumHealth = 2 },
		UnitMaximumHealthMode = { Default = 0, WithAbsorbs = 1 },
		StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 },
		SecondsFormatterAbbreviation = { None = 0, Truncate = 1, OneLetter = 2 },
		SecondsFormatterInterval = { Seconds = 1, Minutes = 2, Hours = 3, Days = 4 },
		SecondsFormatterRounding = { RoundUp = 0, Truncate = 1 },
		SecondsFormatterIntervalWhitespace = { Preserve = 0, Strip = 1, StripIgnoreLocale = 2 },
	}
	_G.C_AddOns = {
		GetAddOnMetadata = function() return "test" end,
		LoadAddOn = function() return true end,
	}
	_G.C_UIFileAsset = { IsKnownFile = function() return true end }
	local defaultAuraCurve = NewCurve(false)
	_G.AuraContainerInbound = {
		GetDefaultAuraDurationFormatter = function()
			return { GetMaxIntervalCurve = function() return defaultAuraCurve end }
		end,
	}
	_G.C_DurationUtil = {
		CreateDuration = function()
			local duration = NewObject("Duration")
			function duration.SetTimeFromStart(self, start, length)
				self.__state.start, self.__state.length = start, length
			end
			return duration
		end,
		CreateDurationTextBinding = function() return NewObject("DurationTextBinding") end,
	}
	_G.C_CurveUtil = {
		CreateCurve = function() return NewCurve(false) end,
		CreateColorCurve = function() return NewCurve(true) end,
		-- Real API: picks a colour from a (possibly secret) boolean without
		-- exposing it. The mock returns secret channels for secret input.
		EvaluateColorFromBoolean = function(value, ifTrue, ifFalse)
			if Mock.IsSecret(value) then
				return NewColor(Mock.Secret(1), Mock.Secret(1), Mock.Secret(1), Mock.Secret(1))
			end
			return value and ifTrue or ifFalse
		end,
	}
	_G.C_StringUtil = {
		CreateSecondsFormatter = function()
			local formatter = NewObject("SecondsFormatter")
			function formatter:Format(seconds)
				if Mock.IsSecret(seconds) then return Mock.Secret("duration") end
				local divisor, suffix = 1, "s"
				if seconds > 129600 then divisor, suffix = 86400, "d"
				elseif seconds > 5400 then divisor, suffix = 3600, "h"
				elseif seconds > 90 then divisor, suffix = 60, "m" end
				return tostring(math.ceil(seconds / divisor)) .. suffix
			end
			return formatter
		end,
		TruncateWhenZero = function(value)
			if Mock.IsSecret(value) then
				return Mock.Secret("truncated")
			end
			return value == 0 and "" or tostring(value)
		end,
	}
	_G.AbbreviateNumbers = function(value)
		if Mock.IsSecret(value) then
			return Mock.Secret("abbreviated")
		end
		return tostring(value)
	end
	_G.C_CVar = { SetCVar = function() return true end }
end

--[[
Extra client UI used by our widgets and the Workbench, plus a unit API that
returns secret values (as with forced combat restrictions).
]]
function Mock.InstallUI()
	local Secret = Mock.Secret
	local function CatchAll(name) return NewObject(name) end

	_G.ColorPickerFrame = CatchAll("ColorPickerFrame")
	_G.GameTooltip = CatchAll("GameTooltip")
	_G.ScrollUtil = {
		InitScrollBoxListWithScrollBar = function() end,
		InitScrollBoxWithScrollBar = function() end,
	}
	_G.ScrollBoxConstants = { UpdateImmediately = true }
	_G.CreateScrollBoxListLinearView = function() return CatchAll("ScrollBoxListLinearView") end
	_G.CreateScrollBoxLinearView = function() return CatchAll("ScrollBoxLinearView") end
	_G.CreateDataProvider = function(items) return { items = items } end
	_G.RAID_CLASS_COLORS = {
		WARRIOR = NewColor(0.78, 0.61, 0.43),
		PALADIN = NewColor(0.96, 0.55, 0.73),
		MAGE = NewColor(0.25, 0.78, 0.92),
	}
	_G.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", PALADIN = "Paladin", MAGE = "Mage" }

	_G.SetPortraitTexture = function(texture) texture.__state.texture = "portrait" end
	_G.UnitExists = function() return true end
	_G.UnitIsPlayer = function() return true end
	_G.UnitIsConnected = function() return true end
	_G.UnitIsTapDenied = function() return false end
	_G.UnitReaction = function() return 2 end
	_G.UnitClassification = function() return "elite" end
	_G.UnitCreatureType = function() return Secret("Beast") end
	_G.UnitName = function() return Secret("name"), Secret("realm") end
	_G.UnitClass = function() return Secret("Warrior"), "WARRIOR", 1 end
	_G.UnitLevel = function() return 30 end
	_G.UnitHealth = function() return Secret(500) end
	_G.UnitHealthMax = function() return Secret(1000) end
	_G.UnitHealthMissing = function() return Secret(500) end
	_G.UnitGetIncomingHeals = function() return Secret(50) end
	_G.UnitGetTotalAbsorbs = function() return Secret(100) end
	_G.UnitGetTotalHealAbsorbs = function() return Secret(0) end
	-- Minimal engine-side scale calculation for the standalone live preview.
	_G.CreateUnitHealPredictionCalculator = function()
		return {
			SetMaximumHealthMode = function(self, mode) self.maximumMode = mode end,
			GetMaximumHealth = function(self)
				return Secret(self.max + (self.maximumMode == Enum.UnitMaximumHealthMode.WithAbsorbs and self.absorb or 0))
			end,
		}
	end
	_G.UnitGetDetailedHealPrediction = function(unit, _, calculator)
		calculator.max = UnitHealthMax(unit).secretValue
		calculator.absorb = UnitGetTotalAbsorbs(unit).secretValue
	end
	local function Percent(_, _, _, curve)
		if curve and curve.isColor then
			return NewColor(Secret(1), Secret(1), Secret(1), Secret(1))
		end
		return Secret(50)
	end
	_G.UnitHealthPercent = function(unit, usePredicted, curve) return Percent(unit, nil, nil, curve) end
	_G.UnitPowerPercent = Percent
	_G.UnitPowerType = function() return 0, "MANA" end
	_G.UnitPower = function() return Secret(300) end
	_G.UnitPowerMax = function() return Secret(600) end
	_G.UnitPowerMissing = function() return Secret(300) end
	_G.UnitXP = function() return 1200 end
	_G.UnitXPMax = function() return 5000 end
	_G.GetXPExhaustion = function() return nil end
	_G.UnitCastingInfo = function()
		return Secret("Fireball"), Secret("Fireball"), Secret(135812), Secret(0), Secret(3000), false, Secret(1), Secret(true)
	end
	_G.UnitChannelInfo = function()
		return Secret("Drain Life"), Secret("Drain Life"), Secret(136169), Secret(0), Secret(5000), false, Secret(true)
	end
	_G.UnitCastingDuration = function() return C_DurationUtil.CreateDuration() end
	_G.UnitChannelDuration = function() return C_DurationUtil.CreateDuration() end
end

return Mock
