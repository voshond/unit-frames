local _, ns = ...
local Skin, Media = ns.Skin, ns.Media

--[[
Dropdown on Blizzard's menu system (DropdownButton + MenuUtil).
opts:
  label, tooltip
  values     array of { value, label } or a function returning one
  preview    "font" | "statusbar" | "border" | "background": render a preview per entry
  onChange(value)
]]
local Dropdown = ns.Widget:Extend("Dropdown")

local MAX_MENU_HEIGHT = 320

local previewers = {
	font = function(button, value)
		button.fontString:SetFont(Media:Fetch("font", value), 13, "")
	end,
	statusbar = function(button, value)
		local texture = button:AttachTexture()
		texture:SetDrawLayer("BACKGROUND")
		texture:SetPoint("TOPLEFT", 18, -1)
		texture:SetPoint("BOTTOMRIGHT", -2, 1)
		texture:SetTexture(Media:Fetch("statusbar", value))
		texture:SetVertexColor(0.35, 0.55, 0.9, 0.8)
	end,
	background = function(button, value)
		local texture = button:AttachTexture()
		texture:SetDrawLayer("BACKGROUND")
		texture:SetPoint("TOPLEFT", 18, -1)
		texture:SetPoint("BOTTOMRIGHT", -2, 1)
		texture:SetTexture(Media:Fetch("background", value))
	end,
}

function Dropdown:OnCreate(parent, opts)
	local frame = CreateFrame("Frame", nil, parent)
	self.frame = frame
	frame:SetHeight(44)

	self.label = Skin.FontString(frame)
	self.label:SetPoint("TOPLEFT")
	self.label:SetJustifyH("LEFT")
	self.label:SetText(opts.label or "")

	local dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
	dropdown:SetPoint("BOTTOMLEFT")
	dropdown:SetPoint("BOTTOMRIGHT")
	self.dropdown = dropdown

	dropdown:SetupMenu(function(_, root)
		root:SetScrollMode(MAX_MENU_HEIGHT)
		local preview = previewers[opts.preview]
		for _, entry in ipairs(self:GetValues()) do
			local value = entry[1]
			local radio = root:CreateRadio(entry[2], function()
				return self.value == value
			end, function()
				self:Select(value)
			end, value)
			if preview then
				radio:AddInitializer(function(button)
					preview(button, value)
				end)
			end
		end
	end)
	ns.Widget.AttachTooltip(frame, opts.label, opts.tooltip)
	frame:EnableMouse(true)
end

function Dropdown:GetValues()
	local values = self.opts.values
	if type(values) == "function" then
		return values()
	end
	return values or {}
end

function Dropdown:Select(value)
	self:SetValue(value)
	if self.opts.onChange then
		self.opts.onChange(value)
	end
end

function Dropdown:SetValue(value)
	self.value = value
	self.dropdown:SetDefaultText(tostring(value))
	self.dropdown:GenerateMenu()
end

function Dropdown:GetValue()
	return self.value
end

function Dropdown:SetLabelColor(r, g, b)
	self.label:SetTextColor(r, g, b)
end

-- Value list for a LibSharedMedia type, as used by schema media options.
function Dropdown.MediaValues(kind)
	return function()
		local values = {}
		for _, key in ipairs(Media:List(kind)) do
			values[#values + 1] = { key, key }
		end
		return values
	end
end
