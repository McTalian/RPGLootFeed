---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class LootDisplay: RLF_Module, AceBucket-3.0, AceEvent-3.0, AceHook-3.0
local LootDisplay = G_RLF.RLF:NewModule(G_RLF.SupportModule.LootDisplay, "AceBucket-3.0", "AceEvent-3.0", "AceHook-3.0")

local lsm = G_RLF.lsm

-- Private variable declaration
---@type table<G_RLF.Frames, RLF_LootDisplayFrame | nil>
local lootFrames = {
	[G_RLF.Frames.MAIN] = nil,
	[G_RLF.Frames.PARTY] = nil,
}
---@type table<G_RLF.Frames, Queue>
local lootQueues = {
	[G_RLF.Frames.MAIN] = G_RLF.Queue:new(),
	[G_RLF.Frames.PARTY] = G_RLF.Queue:new(),
}
G_RLF.tempFontString = nil

-- Function to update queue labels
local function updateQueueLabels()
	if lootFrames[G_RLF.Frames.MAIN] ~= nil then
		lootFrames[G_RLF.Frames.MAIN]:UpdateQueueLabel(lootQueues[G_RLF.Frames.MAIN]:size())
	end

	if lootFrames[G_RLF.Frames.PARTY] ~= nil then
		lootFrames[G_RLF.Frames.PARTY]:UpdateQueueLabel(lootQueues[G_RLF.Frames.PARTY]:size())
	end
end
-- Wrapper function to update queue labels after calling the original function
local function updateQueueLabelsWrapper(func)
	return function(...)
		local result = { func(...) }
		updateQueueLabels()
		return unpack(result)
	end
end

lootQueues[G_RLF.Frames.MAIN].enqueue = updateQueueLabelsWrapper(lootQueues[G_RLF.Frames.MAIN].enqueue)
lootQueues[G_RLF.Frames.MAIN].dequeue = updateQueueLabelsWrapper(lootQueues[G_RLF.Frames.MAIN].dequeue)
lootQueues[G_RLF.Frames.PARTY].enqueue = updateQueueLabelsWrapper(lootQueues[G_RLF.Frames.PARTY].enqueue)
lootQueues[G_RLF.Frames.PARTY].dequeue = updateQueueLabelsWrapper(lootQueues[G_RLF.Frames.PARTY].dequeue)

-- Public methods
function LootDisplay:OnInitialize()
	---@type RLF_LootDisplayFrame
	lootFrames[G_RLF.Frames.MAIN] = CreateFrame("Frame", "RLF_MainLootFrame", UIParent, "RLF_LootDisplayFrameTemplate") --[[@as RLF_LootDisplayFrame]]
	G_RLF.RLF_MainLootFrame = lootFrames[G_RLF.Frames.MAIN]
	lootFrames[G_RLF.Frames.MAIN]:Load(G_RLF.Frames.MAIN)
	---@type RLF_LootDisplayFrame | nil
	G_RLF.RLF_PartyLootFrame = nil
	if G_RLF.db.global.partyLoot.enabled and G_RLF.db.global.partyLoot.separateFrame then
		self:CreatePartyFrame()
	end

	G_RLF.tempFontString = UIParent:CreateFontString(nil, "ARTWORK")
	G_RLF.tempFontString:Hide() -- Prevent it from showing up
end

function LootDisplay:OnEnable()
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnPlayerCombatChange")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnPlayerCombatChange")
	self:RegisterBucketEvent("BAG_UPDATE_DELAYED", 0.5, "BAG_UPDATE_DELAYED")
	self:RegisterMessage("RLF_NEW_LOOT", "OnLootReady")
	self:RegisterMessage("RLF_NEW_PARTY_LOOT", "OnPartyLootReady")
	self:RegisterBucketMessage("RLF_ROW_RETURNED", 0.3, "OnRowReturn")
	self:RegisterBucketMessage("RLF_PARTY_ROW_RETURNED", 0.3, "OnPartyRowReturn")

	RunNextFrame(function()
		---@type RLF_TestMode
		local TestModeModule = G_RLF.RLF:GetModule(G_RLF.SupportModule.TestMode) --[[@as RLF_TestMode]]
		TestModeModule:OnLootDisplayReady()
	end)

	-- So far up through MoP Classic, some/all of these methods are not defined
	if not G_RLF:IsRetail() then
		if not ItemButtonMixin.SetItemButtonTexture then
			ItemButtonMixin.SetItemButtonTexture = function(self, texture) end
		end

		self:RawHook(ItemButtonMixin, "SetItemButtonTexture", function(self, texture)
			if SetItemButtonTexture_Base then
				SetItemButtonTexture_Base(texture)
			else
				-- Handle the case where SetItemButtonTexture_Base doesn't exist
				self.icon:SetTexture(texture)
			end
		end, true)

		if not ItemButtonMixin.SetItemButtonQuality then
			ItemButtonMixin.SetItemButtonQuality = function(self, quality, itemIDOrLink) end
		end

		self:RawHook(ItemButtonMixin, "SetItemButtonQuality", function(self, quality, itemIDOrLink)
			if SetItemButtonQuality_Base then
				SetItemButtonQuality_Base(quality, itemIDOrLink)
			else
				if quality then
					-- Handle the case where SetItemButtonQuality_Base doesn't exist
					local r, g, b = C_Item.GetItemQualityColor(quality)
					self.IconBorder:SetVertexColor(r, g, b)
				end
			end
		end, true)
	end
end

function LootDisplay:OnPlayerCombatChange()
	if lootFrames[G_RLF.Frames.MAIN] == nil then
		return
	end

	lootFrames[G_RLF.Frames.MAIN]:UpdateTabVisibility()
end

function LootDisplay:CreatePartyFrame()
	if lootFrames[G_RLF.Frames.PARTY] == nil then
		lootFrames[G_RLF.Frames.PARTY] =
			CreateFrame("Frame", "RLF_PartyLootFrame", UIParent, "RLF_LootDisplayFrameTemplate") --[[@as RLF_LootDisplayFrame]]
		G_RLF.RLF_PartyLootFrame = lootFrames[G_RLF.Frames.PARTY]
		lootFrames[G_RLF.Frames.PARTY]:Load(G_RLF.Frames.PARTY)

		if lootFrames[G_RLF.Frames.MAIN] and lootFrames[G_RLF.Frames.MAIN].BoundingBox:IsVisible() then
			lootFrames[G_RLF.Frames.PARTY]:ShowTestArea()
		end
	end
end

function LootDisplay:DestroyPartyFrame()
	if lootFrames[G_RLF.Frames.PARTY] then
		lootFrames[G_RLF.Frames.PARTY]:Hide()
		lootFrames[G_RLF.Frames.PARTY]:ClearFeed()
		lootFrames[G_RLF.Frames.PARTY]:HideTestArea()
		lootFrames[G_RLF.Frames.PARTY] = nil
		G_RLF.RLF_PartyLootFrame = nil
	end
end

function LootDisplay:SetBoundingBoxVisibility(show)
	if lootFrames[G_RLF.Frames.MAIN] == nil then
		return
	end

	if show then
		lootFrames[G_RLF.Frames.MAIN]:ShowTestArea()
		if lootFrames[G_RLF.Frames.PARTY] then
			lootFrames[G_RLF.Frames.PARTY]:ShowTestArea()
		end
	else
		lootFrames[G_RLF.Frames.MAIN]:HideTestArea()
		if lootFrames[G_RLF.Frames.PARTY] then
			lootFrames[G_RLF.Frames.PARTY]:HideTestArea()
		end
	end
end

function LootDisplay:ToggleBoundingBox()
	if lootFrames[G_RLF.Frames.MAIN] == nil then
		return
	end
	self:SetBoundingBoxVisibility(not lootFrames[G_RLF.Frames.MAIN].BoundingBox:IsVisible())

	if lootFrames[G_RLF.Frames.PARTY] and G_RLF.db.global.partyLoot.separateFrame then
		self:SetBoundingBoxVisibility(not lootFrames[G_RLF.Frames.PARTY].BoundingBox:IsVisible())
	end
end

--- update the position of the frame
--- @param frame? G_RLF.Frames
function LootDisplay:UpdatePosition(frame)
	frame = frame or G_RLF.Frames.MAIN
	if lootFrames[frame] == nil then
		return
	end
	local positioningDb = G_RLF.DbAccessor:Positioning(frame)
	lootFrames[frame]:ClearAllPoints()
	lootFrames[frame]:SetPoint(
		positioningDb.anchorPoint,
		_G[positioningDb.relativePoint],
		positioningDb.xOffset,
		positioningDb.yOffset
	)
end

--- Update row positions for the frame
--- @param frame? G_RLF.Frames
function LootDisplay:UpdateRowPositions(frame)
	frame = frame or G_RLF.Frames.MAIN
	if lootFrames[frame] == nil then
		return
	end

	lootFrames[frame]:UpdateRowPositions()
end

--- Update the strata of the frame
--- @param frame? G_RLF.Frames
function LootDisplay:UpdateStrata(frame)
	frame = frame or G_RLF.Frames.MAIN
	if lootFrames[frame] then
		local positioningDb = G_RLF.DbAccessor:Positioning(frame)
		lootFrames[frame]:SetFrameStrata(positioningDb.frameStrata)
	end
end

--- Update the size of the frame
--- @param frame? G_RLF.Frames
function LootDisplay:UpdateSize(frame)
	frame = frame or G_RLF.Frames.MAIN
	if lootFrames[frame] == nil then
		return
	end

	lootFrames[frame]:UpdateSize()

	-- Update sample rows if they're currently shown
	self:RefreshSampleRowsIfShown()
end

--- Update row styles for the frame
--- @param frame? G_RLF.Frames
function LootDisplay:UpdateRowStyles(frame)
	frame = frame or G_RLF.Frames.MAIN
	if lootFrames[frame] == nil then
		return
	end

	lootFrames[frame]:UpdateStyles()

	-- Update sample rows if they're currently shown
	self:RefreshSampleRowsIfShown()
end

--- Update enter animation for the frame
--- @param frame? G_RLF.Frames
function LootDisplay:UpdateEnterAnimation(frame)
	frame = frame or G_RLF.Frames.MAIN
	if lootFrames[frame] == nil then
		return
	end

	lootFrames[frame]:UpdateEnterAnimationType()

	-- Update sample rows if they're currently shown
	self:RefreshSampleRowsIfShown()
end

--- Update fade delay for the frame
--- @param frame? G_RLF.Frames
function LootDisplay:UpdateFadeDelay(frame)
	frame = frame or G_RLF.Frames.MAIN
	if lootFrames[frame] == nil then
		return
	end

	lootFrames[frame]:UpdateFadeDelay()

	-- Update sample rows if they're currently shown
	self:RefreshSampleRowsIfShown()
end

function LootDisplay:ReInitQueueLabel(frame)
	frame = frame or G_RLF.Frames.MAIN
	if lootFrames[frame] == nil then
		return
	end

	lootFrames[frame]:InitQueueLabel()
end

--- Handle the BAG_UPDATE_DELAYED event
function LootDisplay:BAG_UPDATE_DELAYED()
	G_RLF:LogInfo("BAG_UPDATE_DELAYED", "WOWEVENT", self.moduleName, nil, "BAG_UPDATE_DELAYED")

	lootFrames[G_RLF.Frames.MAIN]:UpdateRowItemCounts()
end

--- process the row for the proper frame
--- @param element RLF_LootElement
--- @param frame? G_RLF.Frames
local function processRow(element, frame)
	frame = frame or G_RLF.Frames.MAIN
	if lootFrames[frame] == nil then
		return
	end

	if not element:IsEnabled() then
		return
	end

	local key = element.key
	local unit = element.unit

	if unit then
		key = unit .. "_" .. key
	end

	---@type RLF_LootDisplayRow | nil
	local row = lootFrames[frame]:GetRow(key)
	if row then
		RunNextFrame(function()
			row:UpdateQuantity(element)
		end)
	else
		-- New row
		row = lootFrames[frame]:LeaseRow(key)
		if row == nil then
			lootQueues[frame]:enqueue(element)
			return
		end

		RunNextFrame(function()
			row:BootstrapFromElement(element)
		end)
	end
end

--- process the row from the queue for the proper frame
--- @param frame? G_RLF.Frames
local function processFromQueue(frame)
	frame = frame or G_RLF.Frames.MAIN
	local queue = lootQueues[frame]
	local snapshotQueueSize = queue:size()
	if snapshotQueueSize > 0 then
		-- In my testing this was fine, but it's possible it could cause performance issues
		-- if the queue is large. This is what to revert if performance issues arise.
		-- local sizingDb = G_RLF.DbAccessor:Sizing(frame)
		local rowsToProcess = snapshotQueueSize -- math.min(snapshotQueueSize, sizingDb.maxRows)
		G_RLF:LogDebug("Processing " .. rowsToProcess .. " items from element queue")
		for i = 1, rowsToProcess do
			if queue:isEmpty() then
				return
			end
			local e = queue:dequeue()
			if e then
				processRow(e, frame)
			end
		end
	end
end

function LootDisplay:OnLootReady(_, element)
	processRow(element, G_RLF.Frames.MAIN)
end

function LootDisplay:OnPartyLootReady(_, element)
	local frameType = G_RLF.Frames.MAIN
	if G_RLF.db.global.partyLoot.separateFrame then
		frameType = G_RLF.Frames.PARTY
	end
	processRow(element, frameType)
end

function LootDisplay:OnRowReturn()
	processFromQueue(G_RLF.Frames.MAIN)
end

function LootDisplay:OnPartyRowReturn()
	local frameType = G_RLF.Frames.MAIN
	if G_RLF.db.global.partyLoot.separateFrame then
		frameType = G_RLF.Frames.PARTY
	end
	processFromQueue(frameType)
end

local function emptyQueues()
	while not lootQueues[G_RLF.Frames.MAIN]:isEmpty() do
		lootQueues[G_RLF.Frames.MAIN]:dequeue()
	end

	while not lootQueues[G_RLF.Frames.PARTY]:isEmpty() do
		lootQueues[G_RLF.Frames.PARTY]:dequeue()
	end
end

function LootDisplay:HideLoot()
	if lootFrames[G_RLF.Frames.MAIN] == nil then
		return
	end

	emptyQueues()
	lootFrames[G_RLF.Frames.MAIN]:ClearFeed()

	if lootFrames[G_RLF.Frames.PARTY] then
		lootFrames[G_RLF.Frames.PARTY]:ClearFeed()
	end
end

--- Show sample rows in existing frames for options preview
function LootDisplay:ShowSampleRows()
	if lootFrames[G_RLF.Frames.MAIN] then
		self:CreateSampleRow(G_RLF.Frames.MAIN)
	end

	if lootFrames[G_RLF.Frames.PARTY] and G_RLF.db.global.partyLoot.separateFrame then
		self:CreateSampleRow(G_RLF.Frames.PARTY)
	end
end

--- Hide sample rows from existing frames
function LootDisplay:HideSampleRows()
	self:HideLoot()
end

--- Create a sample row in the specified frame
--- @param frame G_RLF.Frames
function LootDisplay:CreateSampleRow(frame)
	if not lootFrames[frame] then
		return
	end

	-- Create a sample element using hardcoded data
	---@class RLF_SampleElement: RLF_BaseLootElement
	local sampleElement = G_RLF.LootElementBase:new()

	sampleElement.key = "sample_preview_item"
	sampleElement.type = "SampleItem"
	sampleElement.icon = G_RLF.DefaultIcons.MONEY
	sampleElement.quantity = 1
	sampleElement.quality = G_RLF.ItemQualEnum.Epic
	sampleElement.textFn = function(existingQuantity, truncatedLink)
		return "SamplePrimaryText"
	end
	sampleElement.secondaryText = "SampleSecondaryText"
	sampleElement.highlight = false
	sampleElement.isLink = false
	sampleElement.isSampleRow = true
	sampleElement.eventChannel = "RLF_NEW_LOOT"
	if frame == G_RLF.Frames.PARTY then
		sampleElement.eventChannel = "RLF_NEW_PARTY_LOOT"
	end

	-- Override IsEnabled to always return true for sample
	sampleElement.IsEnabled = function(self)
		return true
	end

	sampleElement:Show()
end

--- Update sample rows when settings change
function LootDisplay:UpdateSampleRows()
	-- Remove existing sample rows
	self:HideSampleRows()

	-- Add them back with new settings
	RunNextFrame(function()
		self:ShowSampleRows()
	end)
end

--- Check if sample rows are currently shown and refresh them
function LootDisplay:RefreshSampleRowsIfShown()
	-- Check if we have any sample rows currently displayed
	local hasSampleRows = false

	if lootFrames[G_RLF.Frames.MAIN] then
		local row = lootFrames[G_RLF.Frames.MAIN]:GetRow("sample_preview_item")
		if row and row.isSampleRow then
			hasSampleRows = true
		end
	end

	-- If we have sample rows, refresh them with new settings
	if hasSampleRows then
		self:UpdateSampleRows()
	end
end

G_RLF.LootDisplay = LootDisplay

--- Calculate the width of a string of text using the frame's font settings
--- @param text string
--- @param frame? G_RLF.Frames
--- @return number
function G_RLF:CalculateTextWidth(text, frame)
	frame = frame or G_RLF.Frames.MAIN
	local stylingDb = G_RLF.DbAccessor:Styling(frame)
	local fontFace = stylingDb.fontFace
	if stylingDb.useFontObjects or not fontFace then
		G_RLF.tempFontString:SetFontObject(stylingDb.font)
	else
		local fontPath = lsm:Fetch(lsm.MediaType.FONT, fontFace)
		if not fontPath then
			G_RLF:LogWarn("Font not found: " .. fontFace, addonName)
			return 0
		end
		G_RLF.tempFontString:SetFont(fontPath, stylingDb.fontSize, G_RLF:FontFlagsToString())
	end
	G_RLF.tempFontString:SetText(text)
	local width = G_RLF.tempFontString:GetUnboundedStringWidth()
	return width
end

--- Truncate an item link to fit within the feed width
--- @param itemLink string
--- @param extraWidth number
--- @param frame? G_RLF.Frames
function G_RLF:TruncateItemLink(itemLink, extraWidth, frame)
	local originalLink = itemLink .. ""
	local itemName = string.match(itemLink, "%[(.-)%]")
	local begIndex, endIndex = string.find(originalLink, itemName, 1, true)
	if begIndex == nil then
		return originalLink
	end
	local linkStart = string.sub(originalLink, 0, begIndex - 1)
	local linkEnd = string.sub(originalLink, endIndex + 1)

	local sizingDb = G_RLF.DbAccessor:Sizing(frame)
	local iconSize = sizingDb.iconSize
	local maxWidth = sizingDb.feedWidth - (iconSize / 4) - iconSize - (iconSize / 4) - extraWidth

	-- Calculate the width of the item name plus the link start and end
	local itemNameWidth = G_RLF:CalculateTextWidth("[" .. itemName .. "]", frame)

	-- If the width exceeds maxWidth, truncate and add ellipses
	if itemNameWidth > maxWidth then
		G_RLF:LogDebug(
			"Truncating item name: "
				.. itemName
				.. " to fit within max width: "
				.. maxWidth
				.. ", original link width: "
				.. itemNameWidth
				.. ", extraWidth: "
				.. extraWidth,
			addonName,
			"General"
		)
		-- Approximate truncation by progressively shortening the name
		while G_RLF:CalculateTextWidth("[" .. itemName .. "...]", frame) > maxWidth and #itemName > 0 do
			itemName = string.sub(itemName, 1, -2)
		end
		itemName = itemName .. "..."
	end

	return linkStart .. itemName .. linkEnd
end

return LootDisplay
