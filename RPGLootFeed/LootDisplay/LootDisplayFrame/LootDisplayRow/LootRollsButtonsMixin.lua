---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

--- Mixin that adds Need/Middle/Pass action buttons to a LootDisplayRow.
---
--- Three buttons: Need, a context-dependent middle option (Greed, Transmog, or
--- Disenchant), and Pass.  Mirrors Blizzard's GroupLootFrame layout.
---
--- Key design constraints:
---   • ClickableButton must stay VISIBLE — it provides item-link tooltip hover.
---     Roll buttons sit above it via SetFrameLevel.
---   • Alt+Click anywhere on the row when suppression is enabled shows the
---     underlying GroupLootFrame.  We hook the row's OnMouseUp for this.
---   • OnClick (not OnMouseUp) is used on buttons — Button+OnClick is atomic;
---     Frame+OnMouseUp requires matching MouseDown on same frame.
---
---@class RLF_LootRollsButtonsMixin
RLF_LootRollsButtonsMixin = {}

local SLOT_KEYS = { "NEED", "MIDDLE", "PASS" }

-- Blizzard atlas names from GroupLootFrame.xml (lootroll-toast-icon-*-up).
local FIXED_SLOT_DEFS = {
	NEED = { atlas = "lootroll-toast-icon-need-up", label = NEED },
	PASS = { atlas = "lootroll-toast-icon-pass-up", label = PASS },
}

local MIDDLE_DEFS = {
	GREED = { atlas = "lootroll-toast-icon-greed-up", label = GREED },
	TRANSMOG = { atlas = "lootroll-toast-icon-transmog-up", label = TRANSMOGRIFY },
	DISENCHANT = { atlas = "lootroll-toast-icon-greed-up", label = ROLL_DISENCHANT }, -- Classic reuses greed icon
}

local SUBMIT_METHOD = {
	NEED = "SubmitNeed",
	GREED = "SubmitGreed",
	TRANSMOG = "SubmitTransmog",
	DISENCHANT = "SubmitDisenchant",
	PASS = "SubmitPass",
}

local BUTTON_SIZE = 18
local BUTTON_GAP = 3

--- Choose the middle slot from validity flags.
--- Priority: Transmog > Disenchant > Greed (Greed is the universal fallback).
local function resolveMiddleSlot(validity)
	if validity.canTransmog then
		return "TRANSMOG"
	elseif validity.canDisenchant then
		return "DISENCHANT"
	else
		return "GREED"
	end
end

--- Create the three button frames if they don't exist yet (idempotent).
function RLF_LootRollsButtonsMixin:InitializeButtons()
	if self._lootRollButtons then
		return
	end

	self._lootRollButtons = {}

	-- Roll buttons must sit above ClickableButton so they receive mouse events.
	-- ClickableButton stays visible (provides tooltip hover on item link).
	local baseLevel = self.ClickableButton and (self.ClickableButton:GetFrameLevel() + 5) or 10

	for idx, key in ipairs(SLOT_KEYS) do
		local btn = CreateFrame("Button", nil, self)
		btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
		btn:SetFrameLevel(baseLevel + idx)
		btn:Hide()
		btn:EnableMouse(true)
		if btn.RegisterForClicks then
			btn:RegisterForClicks("LeftButtonUp")
		end

		local tex = btn:CreateTexture(nil, "ARTWORK")
		tex:SetAllPoints(btn)
		btn.tex = tex

		local disabledOverlay = btn:CreateTexture(nil, "OVERLAY")
		disabledOverlay:SetAllPoints(btn)
		disabledOverlay:SetColorTexture(0, 0, 0, 0.55)
		disabledOverlay:Hide()
		btn.disabledOverlay = disabledOverlay

		btn.slotKey = key
		btn.rollKey = key -- overwritten for MIDDLE each roll
		btn.rollLabel = key -- overwritten for MIDDLE each roll
		btn.isRollEnabled = false

		btn:SetScript("OnEnter", function(_btn)
			-- if self.ExitAnimation then self.ExitAnimation:Stop() end
			-- if self.StopTimerBar then self:StopTimerBar() end
			GameTooltip:SetOwner(_btn, "ANCHOR_RIGHT")
			GameTooltip:SetText(_btn.rollLabel, 1, 1, 1)
			GameTooltip:Show()
		end)

		btn:SetScript("OnLeave", function(_btn)
			GameTooltip:Hide()
			if not self:IsMouseOver() then
				-- if self.ExitAnimation then self.ExitAnimation:Play() end
				-- if self.StartTimerBar then self:StartTimerBar() end
			end
		end)

		-- Capture row (`self`) in closure so button click reaches row methods.
		local row = self
		btn:SetScript("OnClick", function(_btn, mouseButton)
			if mouseButton ~= "LeftButton" then
				return
			end
			if IsAltKeyDown and IsAltKeyDown() then
				row:OnAltClick()
			elseif _btn.isRollEnabled then
				row:OnButtonClick(_btn.rollKey)
			end
		end)

		self._lootRollButtons[key] = btn
	end

	-- Hook the row's own OnMouseUp so Alt+Click anywhere on the row works,
	-- not just on the button area.  (ClickableButton covers the full row.)
	self.ClickableButton:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" and IsAltKeyDown and IsAltKeyDown() then
			self:OnAltClick()
		end
		-- Normal click handling is handled by RowTooltipMixin which sets
		-- OnMouseUp on ClickableButton after SetupTooltip() is called.
		-- We deliberately do NOT call the original here — SetupTooltip()
		-- will re-install its own handler when the row is next populated.
	end)

	G_RLF:LogDebug("LootRollsButtonsMixin: InitializeButtons done", addonName)
end

--- Set atlas/key/label on the MIDDLE button for this specific roll.
function RLF_LootRollsButtonsMixin:ConfigureMiddleButton(middleKey)
	local btn = self._lootRollButtons and self._lootRollButtons["MIDDLE"]
	if not btn then
		return
	end
	local def = MIDDLE_DEFS[middleKey] or MIDDLE_DEFS["GREED"]
	btn.rollKey = middleKey
	btn.rollLabel = def.label
	if btn.tex and btn.tex.SetAtlas then
		btn.tex:SetAtlas(def.atlas)
	end
end

--- Position buttons right-to-left from the row's right edge (LTR layout) or
--- left-to-right from the left edge (RTL).
function RLF_LootRollsButtonsMixin:LayoutButtons()
	if not self._lootRollButtons then
		return
	end

	local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)
	local stylingDb = G_RLF.DbAccessor:Styling(self.frameType)
	local padding = sizingDb and sizingDb.padding or 2
	local iconOnLeft = not (stylingDb and stylingDb.textAlignment == G_RLF.TextAlignment.RIGHT)

	local totalButtonWidth = (BUTTON_SIZE * 3) + (BUTTON_GAP * 2)

	if iconOnLeft then
		-- LTR: rightmost button hugs right edge, others cascade left.
		local prevAnchor, prevPoint, xOffset = self, "RIGHT", -padding
		for i = #SLOT_KEYS, 1, -1 do
			local btn = self._lootRollButtons[SLOT_KEYS[i]]
			btn:ClearAllPoints()
			btn:SetPoint("RIGHT", prevAnchor, prevPoint, xOffset, 0)
			prevAnchor, prevPoint, xOffset = btn, "LEFT", -BUTTON_GAP
		end
	else
		-- RTL: leftmost button hugs left edge, others cascade right.
		local prevAnchor, prevPoint, xOffset = self, "LEFT", padding
		for _, key in ipairs(SLOT_KEYS) do
			local btn = self._lootRollButtons[key]
			btn:ClearAllPoints()
			btn:SetPoint("LEFT", prevAnchor, prevPoint, xOffset, 0)
			prevAnchor, prevPoint, xOffset = btn, "RIGHT", BUTTON_GAP
		end
	end

	self._lootRollButtonsWidth = totalButtonWidth + padding
end

--- Apply enabled/disabled visual state to all three buttons.
function RLF_LootRollsButtonsMixin:UpdateButtonStates(validity, middleKey)
	if not self._lootRollButtons then
		return
	end

	local function apply(btn, enabled)
		btn.isRollEnabled = enabled
		if enabled then
			btn.disabledOverlay:Hide()
			if btn.tex.SetDesaturated then
				btn.tex:SetDesaturated(false)
			end
			btn:SetAlpha(1)
		else
			btn.disabledOverlay:Show()
			if btn.tex.SetDesaturated then
				btn.tex:SetDesaturated(true)
			end
			btn:SetAlpha(0.6)
		end
	end

	-- Default everything to true when validity is absent — if the roll is
	-- open and we just don't have API data, showing all options is safer than
	-- showing all disabled.
	local v = validity or {}
	local canNeed = v.canNeed ~= false and (v.canNeed ~= nil or true)
	local canPass = v.canPass ~= false and (v.canPass ~= nil or true)
	local canMiddle
	if middleKey == "TRANSMOG" then
		canMiddle = v.canTransmog ~= false and (v.canTransmog ~= nil or true)
	elseif middleKey == "DISENCHANT" then
		canMiddle = v.canDisenchant ~= false and (v.canDisenchant ~= nil or true)
	else
		canMiddle = v.canGreed ~= false and (v.canGreed ~= nil or true)
	end

	-- When validity is explicitly provided and all flags are false, respect that.
	if validity then
		canNeed = validity.canNeed or false
		canPass = validity.canPass ~= false -- canPass defaults true
		if middleKey == "TRANSMOG" then
			canMiddle = validity.canTransmog or false
		elseif middleKey == "DISENCHANT" then
			canMiddle = validity.canDisenchant or false
		else
			canMiddle = validity.canGreed or false
		end
	end

	apply(self._lootRollButtons["NEED"], canNeed)
	apply(self._lootRollButtons["MIDDLE"], canMiddle)
	apply(self._lootRollButtons["PASS"], canPass)

	-- Refresh atlases and labels for fixed slots (may have been reset on recycle).
	local needBtn = self._lootRollButtons["NEED"]
	needBtn.rollKey = "NEED"
	needBtn.rollLabel = FIXED_SLOT_DEFS.NEED.label
	if needBtn.tex.SetAtlas then
		needBtn.tex:SetAtlas(FIXED_SLOT_DEFS.NEED.atlas)
	end

	local passBtn = self._lootRollButtons["PASS"]
	passBtn.rollKey = "PASS"
	passBtn.rollLabel = FIXED_SLOT_DEFS.PASS.label
	if passBtn.tex.SetAtlas then
		passBtn.tex:SetAtlas(FIXED_SLOT_DEFS.PASS.atlas)
	end

	G_RLF:LogDebug(
		"LootRollsButtonsMixin:UpdateButtonStates"
			.. " canNeed="
			.. tostring(canNeed)
			.. " middle="
			.. middleKey
			.. " canMiddle="
			.. tostring(canMiddle)
			.. " canPass="
			.. tostring(canPass),
		addonName
	)
end

function RLF_LootRollsButtonsMixin:ShowButtons()
	if not self._lootRollButtons then
		return
	end
	for _, key in ipairs(SLOT_KEYS) do
		self._lootRollButtons[key]:Show()
	end
end

function RLF_LootRollsButtonsMixin:HideButtons()
	if not self._lootRollButtons then
		return
	end
	for _, key in ipairs(SLOT_KEYS) do
		self._lootRollButtons[key]:Hide()
	end
end

--- Called when a roll button is clicked.
function RLF_LootRollsButtonsMixin:OnButtonClick(rollKey)
	local lr = self._lootRollsFeature

	-- Action rows (Retail START_LOOT_ROLL) use rollID directly.
	if self._lootRollIsActionRow then
		G_RLF:LogDebug(
			"LootRollsButtonsMixin:OnButtonClick(action) key="
				.. tostring(rollKey)
				.. " rollID="
				.. tostring(self._lootRollRollID),
			addonName
		)
		if not self._lootRollRollID then
			G_RLF:LogWarn("LootRollsButtonsMixin:OnButtonClick(action) — missing rollID", addonName)
			return
		end
		if lr and lr.SubmitActionRoll then
			lr:SubmitActionRoll(self._lootRollRollID, rollKey)
		else
			G_RLF:LogWarn("LootRollsButtonsMixin:OnButtonClick(action) — SubmitActionRoll not found", addonName)
		end
		return
	end

	-- Result rows (C_LootHistory) use encounterID + lootListID.
	G_RLF:LogDebug(
		"LootRollsButtonsMixin:OnButtonClick key="
			.. tostring(rollKey)
			.. " enc="
			.. tostring(self._lootRollEncounterID)
			.. " list="
			.. tostring(self._lootRollLootListID),
		addonName
	)

	if not self._lootRollEncounterID or not self._lootRollLootListID then
		G_RLF:LogWarn("LootRollsButtonsMixin:OnButtonClick — missing IDs", addonName)
		return
	end

	local submitMethod = SUBMIT_METHOD[rollKey]
	if not submitMethod then
		G_RLF:LogWarn("LootRollsButtonsMixin:OnButtonClick — unknown key: " .. tostring(rollKey), addonName)
		return
	end

	if lr and lr[submitMethod] then
		lr[submitMethod](lr, self._lootRollEncounterID, self._lootRollLootListID)
	else
		G_RLF:LogWarn("LootRollsButtonsMixin:OnButtonClick — LootRolls." .. submitMethod .. " not found", addonName)
	end
end

--- Alt+Click escape hatch: reveal the underlying GroupLootFrame for this roll.
function RLF_LootRollsButtonsMixin:OnAltClick()
	if not self._lootRollDisableFrame then
		return
	end
	if self._lootRollRollState ~= "pending" then
		return
	end

	local id = self._lootRollLootListID
	for i = 1, 4 do
		local f = _G["GroupLootFrame" .. i]
		if f and f.rollID == id then
			f:Show()
			G_RLF:LogDebug("LootRollsButtonsMixin:OnAltClick — showed GroupLootFrame" .. i, addonName)
			return
		end
	end
	G_RLF:LogWarn("LootRollsButtonsMixin:OnAltClick — no GroupLootFrame for lootListID=" .. tostring(id), addonName)
end

--- Called from LootDisplayRow whenever the element payload is updated.
function RLF_LootRollsButtonsMixin:UpdateLootRollButtons(payload)
	-- Only show buttons on action rows, not result rows
	if not payload.isActionRow then
		self:HideButtons()
		return
	end

	if payload.rollState ~= "pending" then
		self:HideButtons()
		return
	end

	self:InitializeButtons()

	-- Store IDs depending on row type.
	-- Action rows (isActionRow=true) use rollID; result rows use encounterID+lootListID.
	self._lootRollIsActionRow = payload.isActionRow or false
	self._lootRollRollID = payload.rollID
	self._lootRollEncounterID = payload.encounterID
	self._lootRollLootListID = payload.lootListID
	self._lootRollRollState = payload.rollState
	local lootRollsActionsConfig = G_RLF.DbAccessor:AnyFeatureConfig("lootRollActions") or {}
	self._lootRollDisableFrame = lootRollsActionsConfig.disableLootRollFrame or false
	self._lootRollsFeature = payload.lootRollsFeature

	local validity = payload.buttonValidity
	local middleKey = resolveMiddleSlot(validity or {})

	self:ConfigureMiddleButton(middleKey)
	self:LayoutButtons()
	self:UpdateButtonStates(validity, middleKey)
	self:ShowButtons()
end

--- Called from LootDisplayRow:Reset().
function RLF_LootRollsButtonsMixin:ResetButtons()
	self._lootRollIsActionRow = nil
	self._lootRollRollID = nil
	self._lootRollEncounterID = nil
	self._lootRollLootListID = nil
	self._lootRollRollState = nil
	self._lootRollDisableFrame = nil
	self._lootRollsFeature = nil
	self:HideButtons()
end

G_RLF.RLF_LootRollsButtonsMixin = RLF_LootRollsButtonsMixin
