local _, ob = ...
local UF = UnitFrames
local Skin = UF.Skin
local C, COLORS = Skin.colors, ob.COLORS

--[[
The guide's frame: a dimmed full-screen backdrop (Escape closes it), the
window with its step rail on the left, the step's title, a page area and the
footer (Back, step count, the primary action). Pages fade and slide in.
]]
local Shell = UF.Object:Extend("OnboardingShell")
ob.Shell = Shell

Shell.WIDTH, Shell.HEIGHT, Shell.RAIL = 1060, 660, 230
Shell.PAGE_WIDTH, Shell.PAGE_HEIGHT = 770, 470
local NODE_GAP, TRANSITION, SLIDE = 64, 0.2, 24
local ICON_COORDS = { 0, 0.25, 0, 0.25 }

local function Ease(progress)
	return 1 - (1 - progress) ^ 3
end

local function PrimaryButton(parent, onClick)
	local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
	ob.Panel(button, C.accent)
	ob.Glow(button, C.accent):Show()
	button.text = ob.Text(button, 14, COLORS.ink, true)
	button.text:SetPoint("CENTER")
	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function() ob.Paint(button, { 0.45, 0.73, 1, 1 }) end)
	button:SetScript("OnLeave", function() ob.Paint(button, C.accent) end)
	return button
end

function Shell:BuildRail(window, steps, owner)
	local rail = CreateFrame("Frame", nil, window, "BackdropTemplate")
	rail:SetPoint("TOPLEFT", 1, -3)
	rail:SetPoint("BOTTOMLEFT", 1, 1)
	rail:SetWidth(Shell.RAIL)
	ob.Panel(rail, COLORS.rail)
	local icon = rail:CreateTexture(nil, "ARTWORK")
	icon:SetTexture([[Interface\Glues\CharacterCreate\UI-CharacterCreate-Classes]])
	icon:SetTexCoord(unpack(ICON_COORDS))
	icon:SetSize(30, 30)
	icon:SetPoint("TOPLEFT", 28, -34)
	local brand = ob.Text(rail, 11, C.accent, true)
	brand:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 1)
	brand:SetText("UNITFRAMES")
	local title = ob.Text(rail, 19, C.text, true)
	title:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 0, -3)
	title:SetText("Getting started")

	local top = -112
	local line = rail:CreateTexture(nil, "BORDER")
	line:SetColorTexture(unpack(C.border))
	line:SetSize(2, NODE_GAP * (#steps - 1))
	line:SetPoint("TOPLEFT", 39, top - 11)
	self.progress = rail:CreateTexture(nil, "ARTWORK")
	self.progress:SetColorTexture(unpack(C.accent))
	self.progress:SetPoint("TOPLEFT", line, "TOPLEFT")
	self.progress:SetSize(2, 1)
	self.nodes = {}
	for index, step in ipairs(steps) do
		local node = CreateFrame("Button", nil, rail)
		node:SetSize(Shell.RAIL - 40, 24)
		node:SetPoint("TOPLEFT", 28, top - (index - 1) * NODE_GAP)
		node.box = CreateFrame("Frame", nil, node, "BackdropTemplate")
		node.box:SetSize(24, 24)
		node.box:SetPoint("LEFT")
		ob.Panel(node.box, C.panel, C.border)
		node.glow = ob.Glow(node.box, C.accent)
		node.number = ob.Text(node.box, 12, C.textDim, true)
		node.number:SetPoint("CENTER")
		node.number:SetText(index)
		node.check = node.box:CreateTexture(nil, "OVERLAY")
		node.check:SetTexture(ob.CHECK)
		node.check:SetVertexColor(unpack(COLORS.ink))
		node.check:SetAllPoints()
		node.label = ob.Text(node, 14)
		node.label:SetPoint("LEFT", node.box, "RIGHT", 12, 0)
		node.label:SetText(step.label)
		node:SetScript("OnClick", function() owner:Jump(index) end)
		self.nodes[index] = node
	end

	local skip = CreateFrame("Button", nil, rail)
	skip:SetSize(120, 18)
	skip:SetPoint("BOTTOMLEFT", 28, 58)
	local skipText = ob.Text(skip, 12, C.textDim)
	skipText:SetPoint("LEFT")
	skipText:SetText("Skip for now")
	skip:SetScript("OnClick", function() owner:Close() end)
	skip:SetScript("OnEnter", function() skipText:SetTextColor(unpack(C.text)) end)
	skip:SetScript("OnLeave", function() skipText:SetTextColor(unpack(C.textDim)) end)
	self.skip = skip
	local reopen = ob.Text(rail, 11, COLORS.faint)
	reopen:SetPoint("TOPLEFT", skip, "BOTTOMLEFT", 0, -6)
	reopen:SetText("Reopen any time: /uf welcome")
end

function Shell:Init(owner, steps)
	local backdrop = CreateFrame("Frame", "UnitFramesOnboarding", UIParent)
	backdrop:SetAllPoints(UIParent)
	backdrop:SetFrameStrata("FULLSCREEN_DIALOG")
	backdrop:EnableMouse(true)
	backdrop:Hide()
	tinsert(UISpecialFrames, "UnitFramesOnboarding")
	self.frame = backdrop
	local dim = backdrop:CreateTexture(nil, "BACKGROUND")
	dim:SetAllPoints()
	dim:SetColorTexture(0, 0, 0, 0.6)
	local fade = backdrop:CreateAnimationGroup()
	local alpha = fade:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0)
	alpha:SetToAlpha(1)
	alpha:SetDuration(0.25)
	alpha:SetSmoothing("OUT")
	self.fade = fade

	local window = CreateFrame("Frame", nil, backdrop, "BackdropTemplate")
	window:SetSize(Shell.WIDTH, Shell.HEIGHT)
	window:SetPoint("CENTER")
	window:EnableMouse(true)
	ob.Panel(window, C.window, C.border)
	local accent = window:CreateTexture(nil, "OVERLAY")
	accent:SetColorTexture(unpack(C.accent))
	accent:SetPoint("TOPLEFT", 1, -1)
	accent:SetPoint("TOPRIGHT", -1, -1)
	accent:SetHeight(2)
	local close = CreateFrame("Button", nil, window, "UIPanelCloseButtonNoScripts")
	close:SetPoint("TOPRIGHT", -4, -6)
	close:SetScript("OnClick", function() owner:Close() end)
	self:BuildRail(window, steps, owner)

	local left = Shell.RAIL + 32
	self.title = ob.Text(window, 28, C.text, true)
	self.title:SetPoint("TOPLEFT", left, -36)
	self.subtitle = ob.Text(window, 13, C.textDim)
	self.subtitle:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -8)
	self.subtitle:SetWidth(Shell.PAGE_WIDTH)
	self.body = CreateFrame("Frame", nil, window)
	self.body:SetSize(Shell.PAGE_WIDTH, Shell.PAGE_HEIGHT)
	self.body:SetPoint("TOPLEFT", left, -100)

	self.back = UF.Widgets.Button:New(window, { text = "Back", width = 92, height = 34, onClick = function() owner:Back() end })
	self.back:SetPoint("BOTTOMLEFT", left, 24)
	self.counter = ob.Text(window, 12, C.textDim)
	self.counter:SetPoint("BOTTOM", window, "BOTTOMLEFT", left + Shell.PAGE_WIDTH / 2, 35)
	self.next = PrimaryButton(window, function() owner:Next() end)
	self.next:SetSize(190, 34)
	self.next:SetPoint("BOTTOMRIGHT", -32, 24)
	self.message = ob.Text(window, 12, C.warning)
	self.message:SetPoint("BOTTOMRIGHT", self.next, "TOPRIGHT", 0, 10)
end

function Shell:SetStep(index, step, count)
	self.title:SetText(step.title)
	self.subtitle:SetText(step.subtitle)
	self.counter:SetText(("Step %d of %d"):format(index, count))
	self.next.text:SetText(step.nextLabel)
	self.back:SetShown(index > 1 and index < count)
	self.skip:SetShown(index < count)
	self:SetMessage(nil)
	for nodeIndex, node in ipairs(self.nodes) do
		local done, current = nodeIndex < index, nodeIndex == index
		ob.Paint(node.box, (done or current) and C.accent or C.panel, (done or current) and C.accent or C.border)
		node.glow:SetShown(current)
		node.number:SetShown(not done)
		node.number:SetTextColor(unpack(current and COLORS.ink or C.textDim))
		node.check:SetShown(done)
		node.label:SetTextColor(unpack((done or current) and C.text or C.textDim))
		node:SetEnabled(done and index < count)
	end
	self.railFrom, self.railTo = self.railTo or 0, NODE_GAP * (index - 1)
	self.transition = { page = step.page, time = 0 }
	step.page:SetAlpha(0)
end

function Shell:SetMessage(text)
	self.message:SetText(text or "")
end

function Shell:Tick(elapsed)
	local transition = self.transition
	if not transition then return end
	transition.time = transition.time + elapsed
	local eased = Ease(math.min(1, transition.time / TRANSITION))
	transition.page:SetAlpha(eased)
	transition.page:ClearAllPoints()
	transition.page:SetPoint("TOPLEFT", SLIDE * (1 - eased), 0)
	transition.page:SetSize(Shell.PAGE_WIDTH, Shell.PAGE_HEIGHT)
	self.progress:SetHeight(math.max(1, self.railFrom + (self.railTo - self.railFrom) * eased))
	if eased >= 1 then self.transition = nil end
end

function Shell:Show()
	self.frame:Show()
	self.fade:Play()
end
