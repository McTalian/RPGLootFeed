---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class RLF_LootDisplayFrame: Frame
---@field BoundingBox Texture
---@field InstructionText FontString
---@field ArrowUp Texture
---@field ArrowDown Texture
---@field ArrowLeft Texture
---@field ArrowRight Texture
---@field isClickThrough boolean
---@field shiftingRowCount integer
---@field bypassShiftAnimation boolean
---@field hasPinnedRow boolean
LootDisplayFrameMixin = {}

-- Maps a loot element's .type field (G_RLF.FeatureModule value) to the
-- matching key in db.global.frames[id].features.
local featureKeyForType = {
	[G_RLF.FeatureModule.ItemLoot] = "itemLoot",
	[G_RLF.FeatureModule.PartyLoot] = "partyLoot",
	[G_RLF.FeatureModule.Currency] = "currency",
	[G_RLF.FeatureModule.Money] = "money",
	[G_RLF.FeatureModule.Experience] = "experience",
	[G_RLF.FeatureModule.Reputation] = "reputation",
	[G_RLF.FeatureModule.Profession] = "profession",
	[G_RLF.FeatureModule.TravelPoints] = "travelPoints",
	[G_RLF.FeatureModule.Transmog] = "transmog",
}

--- Check whether this frame should display the given loot element based on
--- the frame's per-feature configuration.
--- @param element RLF_BaseLootElement
--- @return boolean
function LootDisplayFrameMixin:IsFeatureEnabled(element)
	local featureKey = featureKeyForType[element.type]
	if not featureKey then
		-- Non-feature elements (e.g. Notifications) fall back to their own
		-- module-level IsEnabled gate and only show on the main frame.
		return self.frameType == G_RLF.Frames.MAIN and element.IsEnabled()
	end
	local frameConfig = G_RLF.db.global.frames[self.frameType]
	if not frameConfig then
		return false
	end
	local featureCfg = frameConfig.features[featureKey]
	return featureCfg and featureCfg.enabled or false
end

function LootDisplayFrameMixin:getFrameHeight()
	local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)
	local padding = sizingDb.padding
	return sizingDb.maxRows * (sizingDb.rowHeight + padding) - padding
end

function LootDisplayFrameMixin:getNumberOfRows()
	return self.rows.length
end

function LootDisplayFrameMixin:getPositioningDetails()
	local stylingDb = G_RLF.DbAccessor:Styling(self.frameType)
	local growUp = stylingDb.growUp
	-- Position the new row at the bottom (or top if growing down)
	local textAlignment = stylingDb.textAlignment
	local horizDir = (textAlignment ~= G_RLF.TextAlignment.RIGHT) and "LEFT" or "RIGHT"
	local vertDir = growUp and "BOTTOM" or "TOP"
	local opposite = growUp and "TOP" or "BOTTOM"
	local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)
	local yOffset = sizingDb.padding
	if not growUp then
		yOffset = -yOffset
	end

	return vertDir, opposite, yOffset, horizDir
end

local function configureArrowRotation(arrow, direction)
	if direction == "UP" then
		arrow:SetRotation(0)
	elseif direction == "DOWN" then
		arrow:SetRotation(math.pi)
	elseif direction == "LEFT" then
		arrow:SetRotation(math.pi * 0.5)
	elseif direction == "RIGHT" then
		arrow:SetRotation(math.pi * 1.5)
	end
end

function LootDisplayFrameMixin:CreateArrowsTestArea()
	if not self.arrows then
		self.arrows = { self.ArrowUp, self.ArrowDown, self.ArrowLeft, self.ArrowRight }

		-- Set arrow rotations
		configureArrowRotation(self.ArrowUp, "UP")
		configureArrowRotation(self.ArrowDown, "DOWN")
		configureArrowRotation(self.ArrowLeft, "LEFT")
		configureArrowRotation(self.ArrowRight, "RIGHT")

		-- Hide arrows initially
		for _, arrow in ipairs(self.arrows) do
			arrow:Hide()
		end
	end
end

function LootDisplayFrameMixin:ConfigureTestArea()
	self.BoundingBox:Hide() -- Hide initially

	self:MakeUnmovable()

	-- Use the frame's configured display name when available; fall back to the
	-- addon name alone for the main frame or when the DB entry is absent.
	local firstLine = addonName
	local frameConfig = G_RLF.db and G_RLF.db.global.frames and G_RLF.db.global.frames[self.frameType]
	if frameConfig and frameConfig.name and frameConfig.name ~= "" then
		firstLine = firstLine .. " - " .. frameConfig.name
	end
	self.InstructionText:SetText(firstLine .. "\n" .. G_RLF.L["Drag to Move"]) -- Set localized text
	self.InstructionText:Hide() -- Hide initially

	self:CreateArrowsTestArea()
end

-- Create the tab frame and anchor it to the loot frame
function LootDisplayFrameMixin:CreateTab()
	self.tab = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate") --[[@as Button]]
	self.tab:SetSize(14, 14)
	local stylingDb = G_RLF.DbAccessor:Styling(self.frameType)
	if stylingDb.growUp then
		self.tab:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", -14, 0)
	else
		self.tab:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
	end
	self.tab:SetAlpha(0.2)
	self.tab:Hide()

	-- Add an icon to the button
	local icon = self.tab:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09") -- Replace with the desired icon path
	icon:SetAllPoints(self.tab)

	-- Handle mouse enter and leave events to change alpha
	self.tab:SetScript("OnEnter", function()
		self.tab:SetAlpha(1.0)
		GameTooltip:SetOwner(self.tab, "ANCHOR_RIGHT")
		GameTooltip:SetText(G_RLF.L["Toggle Loot History"], 1, 1, 1)
		GameTooltip:Show()
	end)
	self.tab:SetScript("OnLeave", function()
		self.tab:SetAlpha(0.2)
		GameTooltip:Hide()
	end)

	-- Handle click event to show the history frame
	self.tab:SetScript("OnClick", function()
		G_RLF.HistoryService:ToggleHistoryFrame()
	end)
end

--- Function to update the loot history tab visibility
function LootDisplayFrameMixin:UpdateTabVisibility()
	if not self.tab then
		return
	end

	local isEnabled = G_RLF.db.global.lootHistory.enabled
	if not isEnabled then
		self.tab:Hide()
		return
	end

	local hideTab = G_RLF.db.global.lootHistory.hideTab
	if hideTab then
		self.tab:Hide()
		return
	end

	local inCombat = UnitAffectingCombat("player")
	local hasItems = self:getNumberOfRows() > 0

	if not inCombat and not hasItems then
		self.tab:Show()
	else
		G_RLF.HistoryService:HideHistoryFrame()
		self.tab:Hide()
	end
end

--- Load the loot display frame
--- @param frame? G_RLF.Frames
function LootDisplayFrameMixin:Load(frame)
	self.frameType = frame or G_RLF.Frames.MAIN
	---@type list<RLF_LootDisplayRow>
	self.rows = G_RLF.list()
	---@type table<string, RLF_LootDisplayRow | integer>
	self.keyRowMap = {
		---@type integer
		length = 0,
	}
	---@type RLF_LootHistoryRowData[]
	self.rowHistory = {}
	self.rowFramePool = CreateFramePool("Frame", self, "LootDisplayRowTemplate")
	self.vertDir, self.opposite, self.yOffset, self.horizDir = self:getPositioningDetails()
	local positioningDb = G_RLF.DbAccessor:Positioning(self.frameType)
	self:UpdateSize()
	self:SetPoint(
		positioningDb.anchorPoint,
		_G[positioningDb.relativePoint],
		positioningDb.xOffset,
		positioningDb.yOffset
	)

	self:SetFrameStrata(positioningDb.frameStrata) -- Set the frame strata here

	self:InitQueueLabel()
	self:ConfigureTestArea()
	if self.frameType == G_RLF.Frames.MAIN then
		self:CreateTab()
	else
		self.tab = nil -- No tab for party frame
	end
end

function LootDisplayFrameMixin:InitQueueLabel()
	if not self.QueueLabel then
		self.QueueLabel = UIParent:CreateFontString(nil, "OVERLAY")
	end
	local anchorPoint = self.vertDir .. self.horizDir
	local relativePoint = self.opposite .. self.horizDir
	local stylingDb = G_RLF.DbAccessor:Styling(self.frameType)
	if stylingDb.useFontObjects then
		self.QueueLabel:SetFontObject(stylingDb.font)
	else
		local fontPath = G_RLF.lsm:Fetch(G_RLF.lsm.MediaType.FONT, stylingDb.fontFace)
		if not fontPath then
			error("Font not found: " .. tostring(stylingDb.fontFace))
		end
		self.QueueLabel:SetFont(fontPath, stylingDb.fontSize, G_RLF:FontFlagsToString())
	end
	self.QueueLabel:ClearAllPoints()
	self.QueueLabel:SetPoint(anchorPoint, self, relativePoint, 0, 0)
	self.QueueLabel:Hide()
end

function LootDisplayFrameMixin:ShowQueueLabel()
	if self.QueueLabel:IsShown() then
		return
	end
	local vertDir, opposite, _, horizDir = self:getPositioningDetails()
	self.QueueLabel:ClearAllPoints()
	self.QueueLabel:SetPoint(vertDir .. horizDir, self, opposite .. horizDir, 0, 0)
	self.QueueLabel:Show()
end

function LootDisplayFrameMixin:HideQueueLabel()
	self.QueueLabel:Hide()
end

function LootDisplayFrameMixin:UpdateQueueLabel(count)
	if count > 0 then
		self.QueueLabel:SetText(
			"|Tinterface/Widgets/azsharawards-state2-fill:0|t" .. string.format(G_RLF.L["Pending Items"], count)
		)
		self:ShowQueueLabel()
	else
		self.QueueLabel:Hide()
	end
end

function LootDisplayFrameMixin:ClearFeed()
	local row = self.rows.last --[[@as RLF_LootDisplayRow]]

	while row do
		local oldRow = row
		row = row._prev
		oldRow.ExitAnimation:Stop()
		oldRow:Hide()
		self:ReleaseRow(oldRow)
	end
end

function LootDisplayFrameMixin:UpdateSize()
	local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)
	self:SetSize(sizingDb.feedWidth, self:getFrameHeight())

	self:UpdateStyles()
end

function LootDisplayFrameMixin:UpdateStyles()
	for row in self.rows:iterate() do
		local row = row --[[@as RLF_LootDisplayRow]]
		row:UpdateStyles()
	end
end

function LootDisplayFrameMixin:UpdateFadeDelay()
	for row in self.rows:iterate() do
		local row = row --[[@as RLF_LootDisplayRow]]
		row:UpdateFadeoutDelay()
	end
end

function LootDisplayFrameMixin:UpdateEnterAnimationType()
	for row in self.rows:iterate() do
		local row = row --[[@as RLF_LootDisplayRow]]
		row:UpdateEnterAnimation()
	end
end

function LootDisplayFrameMixin:OnDragStop()
	self:StopMovingOrSizing()

	-- Save the new position
	local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
	local positioningDb = G_RLF.DbAccessor:Positioning(self.frameType)
	positioningDb.anchorPoint = point
	positioningDb.relativePoint = relativeTo or "UIParent"
	positioningDb.xOffset = xOfs
	positioningDb.yOffset = yOfs

	-- Update the frame position
	G_RLF.LootDisplay:UpdatePosition(self.frameType)
	G_RLF:NotifyChange(addonName)
end

function LootDisplayFrameMixin:ShowTestArea()
	self.BoundingBox:Show()
	self:RegisterForDrag("LeftButton")
	self:SetMovable(true)
	self:EnableMouse(true)
	self.InstructionText:Show()
	for i, a in ipairs(self.arrows) do
		a:Show()
	end
end

function LootDisplayFrameMixin:HideTestArea()
	self.BoundingBox:Hide()
	self:MakeUnmovable()
	self.InstructionText:Hide()
	for i, a in ipairs(self.arrows) do
		a:Hide()
	end
end

function LootDisplayFrameMixin:MakeUnmovable()
	self:SetMovable(false)
	self:EnableMouse(false)
	self:RegisterForDrag()
end

--- Get row from key
--- @param key string
--- @return RLF_LootDisplayRow
function LootDisplayFrameMixin:GetRow(key)
	if key == "length" then
		error("Attempted to access key 'length' from GetRow")
	end
	return self.keyRowMap[key] --[[@as RLF_LootDisplayRow]]
end

--- @param key string
--- @param isSampleRow? boolean When true, bypass the maxRows cap
--- @return RLF_LootDisplayRow|nil
function LootDisplayFrameMixin:LeaseRow(key, isSampleRow)
	local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)
	if self:getNumberOfRows() >= sizingDb.maxRows and not isSampleRow then
		-- Skip this, we've already allocated too much
		return nil
	end

	---@type RLF_LootDisplayRow
	local row = self.rowFramePool:Acquire()
	row.frameType = self.frameType
	row.key = key
	RunNextFrame(function()
		row:Hide()
	end)

	local success = self.rows:push(row)
	if not success then
		error("Tried to push a row that already exists in the list")
	end

	row:Init()
	row:SetParent(self)

	self.keyRowMap[key] = row
	self.keyRowMap.length = self.keyRowMap.length + 1

	row:UpdatePosition(self)
	RunNextFrame(function()
		row:ResetHighlightBorder()
	end)
	self:UpdateTabVisibility()

	return row
end

--- @param row RLF_LootDisplayRow
function LootDisplayFrameMixin:ReleaseRow(row)
	if not row.key then
		error("Row without key: " .. row:Dump())
	end

	if self.keyRowMap[row.key] then
		self.keyRowMap[row.key] = nil
		self.keyRowMap.length = self.keyRowMap.length - 1
	end

	if not row.isSampleRow then
		self:StoreRowHistory(row)
	end

	row:UpdateNeighborPositions(self)
	self.rows:remove(row)
	row:SetParent(nil)
	if row.onReleased then
		row.onReleased()
		row.onReleased = nil
	end
	row.key = nil
	row:Reset()
	self.rowFramePool:Release(row)
	-- Notify LootDisplay that capacity has opened on this specific frame so its
	-- queue can be drained.  A single parameterised message replaces the old
	-- dual-message RLF_ROW_RETURNED / RLF_PARTY_ROW_RETURNED scheme.
	G_RLF:SendMessage("RLF_ROW_RETURNED", self.frameType)
	self:UpdateTabVisibility()
end

function LootDisplayFrameMixin:StoreRowHistory(row)
	if not G_RLF.db.global.lootHistory.enabled then
		return
	end

	---@class RLF_LootHistoryRowData
	local rowData = {
		key = row.key,
		amount = row.amount,
		quality = row.quality,
		icon = row.icon,
		link = row.link,
		rowText = row.PrimaryText:GetText(),
		textColor = { row.PrimaryText:GetTextColor() },
		unit = row.unit,
		secondaryText = row.SecondaryText:GetText(),
		secondaryTextColor = { row.SecondaryText:GetTextColor() },
	}
	table.insert(self.rowHistory, 1, rowData)

	-- Trim the history to the configured limit
	if #self.rowHistory > G_RLF.db.global.lootHistory.historyLimit then
		table.remove(self.rowHistory) -- Remove the oldest entry to maintain the limit
	end
end

function LootDisplayFrameMixin:Dump()
	local firstKey, lastKey
	if self.rows.first then
		firstKey = self.rows.first.key or "NONE"
	else
		firstKey = "first nil"
	end

	if self.rows.last then
		lastKey = self.rows.last.key or "NONE"
	else
		lastKey = "last nil"
	end

	return format(
		"{getNumberOfRows=%s,#rowFramePool=%s,#keyRowMap=%s,first.key=%s,last.key=%s}",
		self:getNumberOfRows(),
		self.rowFramePool:size(),
		self.keyRowMap.length,
		firstKey,
		lastKey
	)
end

function LootDisplayFrameMixin:UpdateRowPositions()
	self.vertDir, self.opposite, self.yOffset, self.horizDir = self:getPositioningDetails()
	local index = 1
	for row in self.rows:iterate() do
		row:UpdatePosition(self)
		if index > self:getNumberOfRows() + 2 then
			error("Possible infinite loop detected!: " .. self:Dump())
		end
		index = index + 1
	end
end

function LootDisplayFrameMixin:CreateHistoryFrame()
	self.historyFrame = CreateFrame("ScrollFrame", "LootHistoryFrame", UIParent, "UIPanelScrollFrameTemplate")
	self.historyFrame:SetSize(self:GetSize())
	self.historyFrame:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
	self.historyFrame.title = self.historyFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	self.historyFrame.title:SetPoint("BOTTOMLEFT", self.historyFrame, "TOPLEFT", 0, 0)
	local frameName = G_RLF.db.global.frames[self.frameType] and G_RLF.db.global.frames[self.frameType].name or ""
	local titleText = G_RLF.L["Loot History"] --[[@as string]]
	if frameName ~= "" then
		titleText = frameName .. " " .. titleText
	end
	self.historyFrame.title:SetText(titleText)

	self.historyContent = CreateFrame("Frame", "LootHistoryFrameContent", self.historyFrame)
	self.historyContent:SetSize(self:GetSize())
	self.historyFrame:SetScrollChild(self.historyContent)

	---@type RLF_LootDisplayRow[]
	self.historyRows = {}
	local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)
	for i = 1, sizingDb.maxRows do
		local row = CreateFrame("Frame", nil, self.historyContent, "LootDisplayRowTemplate")
		row.frameType = self.frameType
		row:SetSize(sizingDb.feedWidth, sizingDb.rowHeight)
		row:Init()
		table.insert(self.historyRows, row)
	end

	self.historyFrame:SetScript("OnVerticalScroll", function(_, offset)
		self:UpdateHistoryFrame(offset)
	end)
end

function LootDisplayFrameMixin:UpdateHistoryFrame(offset)
	offset = offset or 0
	---@type RLF_ConfigSizing
	local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)
	local padding = sizingDb.padding
	local feedWidth = sizingDb.feedWidth
	local rowHeight = sizingDb.rowHeight + padding
	local visibleRows = sizingDb.maxRows
	local totalRows = #self.rowHistory
	local contentSize = totalRows * rowHeight - padding
	local startIndex = math.floor(offset / rowHeight) + 1
	local endIndex = math.min(startIndex + visibleRows - 1, totalRows)

	for i, row in ipairs(self.historyRows) do
		local dataIndex = startIndex + i - 1
		if dataIndex <= endIndex then
			row:UpdateWithHistoryData(self.rowHistory[dataIndex])
			row:Show()
			row:ElementsVisible()
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", self.historyFrame, "TOPLEFT", 0, (i - 1) * -rowHeight)
		else
			row:Hide()
		end
	end

	self.historyFrame:SetSize(feedWidth, self:getFrameHeight() + rowHeight)
	self.historyContent:SetSize(feedWidth, contentSize)
end

function LootDisplayFrameMixin:ShowHistoryFrame()
	if not self.historyFrame then
		self:CreateHistoryFrame()
	end
	self:UpdateHistoryFrame()
	self.historyFrame:Show()
end

function LootDisplayFrameMixin:HideHistoryFrame()
	if self.historyFrame then
		self.historyFrame:Hide()
		self.historyFrame:SetVerticalScroll(0)
	end
end

function LootDisplayFrameMixin:UpdateRowItemCounts()
	for row in self.rows:iterate() do
		---@type RLF_LootDisplayRow
		local row = row --[[@as RLF_LootDisplayRow]]
		if row.key and row.type == "ItemLoot" and not row.unit then
			row:UpdateItemCount()
		end
	end
end

return LootDisplayFrameMixin
