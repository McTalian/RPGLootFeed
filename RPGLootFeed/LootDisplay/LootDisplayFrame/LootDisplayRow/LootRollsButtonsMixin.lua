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
---   • OnClick is handled by LootRollButtonTemplate which calls
---     RollOnLoot(self:GetParent().rollID, self:GetID()) directly.
---
---@class RLF_LootRollsButtonsMixin
RLF_LootRollsButtonsMixin = {}

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
	if self.NeedButton then
		return
	end

	-- Roll buttons must sit above ClickableButton so they receive mouse events.
	-- ClickableButton stays visible (provides tooltip hover on item link).
	local baseLevel = self.ClickableButton and (self.ClickableButton:GetFrameLevel() + 5) or 10

	self.NeedButton = CreateFrame("Button", nil, self, "LootRollButtonTemplate")
	self.NeedButton:SetID(1)
	self.NeedButton:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	self.NeedButton:SetFrameLevel(baseLevel + 1)
	self.NeedButton:Hide()
	self.NeedButton:EnableMouse(true)
	self.NeedButton.tooltipText = NEED
	self.NeedButton.newbieText = NEED_NEWBIE
	self.NeedButton:SetNormalAtlas("lootroll-toast-icon-need-up")
	self.NeedButton:SetPushedAtlas("lootroll-toast-icon-need-down")
	self.NeedButton:SetHighlightAtlas("lootroll-toast-icon-need-highlight")

	self.PassButton = CreateFrame("Button", nil, self, "LootRollButtonTemplate")
	self.PassButton:SetID(0)
	self.PassButton:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	self.PassButton:SetFrameLevel(baseLevel + 3)
	self.PassButton:Hide()
	self.PassButton:EnableMouse(true)
	self.PassButton.tooltipText = PASS
	self.PassButton.newbieText = LOOT_PASS_NEWBIE
	self.PassButton:SetNormalAtlas("lootroll-toast-icon-pass-up")
	self.PassButton:SetPushedAtlas("lootroll-toast-icon-pass-down")
	self.PassButton:SetHighlightAtlas("lootroll-toast-icon-pass-highlight")

	self.GreedButton = CreateFrame("Button", nil, self, "LootRollButtonTemplate")
	self.GreedButton:SetID(2)
	self.GreedButton:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	self.GreedButton:SetFrameLevel(baseLevel + 2)
	self.GreedButton:Hide()
	self.GreedButton:EnableMouse(true)
	self.GreedButton.tooltipText = GREED
	self.GreedButton.newbieText = GREED_NEWBIE
	self.GreedButton:SetNormalAtlas("lootroll-toast-icon-greed-up")
	self.GreedButton:SetPushedAtlas("lootroll-toast-icon-greed-down")
	self.GreedButton:SetHighlightAtlas("lootroll-toast-icon-greed-highlight")

	self.TransmogButton = CreateFrame("Button", nil, self, "LootRollButtonTemplate")
	self.TransmogButton:SetID(4)
	self.TransmogButton:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	self.TransmogButton:SetFrameLevel(baseLevel + 4)
	self.TransmogButton:Hide()
	self.TransmogButton:EnableMouse(true)
	self.TransmogButton.tooltipText = TRANSMOGRIFICATION
	self.TransmogButton:SetNormalAtlas("lootroll-toast-icon-transmog-up")
	self.TransmogButton:SetPushedAtlas("lootroll-toast-icon-transmog-down")
	self.TransmogButton:SetHighlightAtlas("lootroll-toast-icon-transmog-highlight")

	G_RLF:LogDebug("LootRollsButtonsMixin: InitializeButtons done", addonName)
end

--- Set atlas on the Greed/Transmog middle slot for this specific roll.
--- Shows TransmogButton over GreedButton when transmog is available;
--- shows GreedButton alone otherwise.
function RLF_LootRollsButtonsMixin:ConfigureMiddleButton(middleKey)
	if middleKey == "TRANSMOG" then
		self.TransmogButton:Show()
		self.GreedButton:Hide()
	else
		self.TransmogButton:Hide()
		self.GreedButton:Show()
	end
end

--- Position buttons mirroring Blizzard's GroupLootFrame layout.
--- NeedButton anchors to the row's right edge; Pass/Greed/Transmog are
--- positioned relative to NeedButton.
function RLF_LootRollsButtonsMixin:LayoutButtons()
	if not self.NeedButton then
		return
	end

	local stylingDb = G_RLF.DbAccessor:Styling(self.frameType)
	local iconOnLeft = not (stylingDb and stylingDb.textAlignment == G_RLF.TextAlignment.RIGHT)
	local totalButtonWidth = (BUTTON_SIZE * 3) + (BUTTON_GAP * 2)

	self.NeedButton:ClearAllPoints()
	self.PassButton:ClearAllPoints()
	self.GreedButton:ClearAllPoints()
	self.TransmogButton:ClearAllPoints()
	-- NeedButton anchors to the right edge of the row.
	if iconOnLeft then
		self.NeedButton:SetPoint("LEFT", self, "RIGHT", -totalButtonWidth - BUTTON_GAP, 0)
	else
		self.NeedButton:SetPoint("RIGHT", self, "LEFT", BUTTON_SIZE + BUTTON_GAP, 0)
	end

	-- GreedButton right of NeedButton
	self.GreedButton:SetPoint("LEFT", self.NeedButton, "RIGHT", BUTTON_GAP, 0)

	-- PassButton to the right of GreedButton
	self.PassButton:SetPoint("LEFT", self.GreedButton, "RIGHT", BUTTON_GAP, 0)

	-- TransmogButton centered on GreedButton (overlaid, shown when valid).
	self.TransmogButton:SetPoint("CENTER", self.GreedButton, "CENTER", 0, 0)
end

--- Apply enabled/disabled visual state to the named buttons.
function RLF_LootRollsButtonsMixin:UpdateButtonStates(validity)
	if not self.NeedButton then
		return
	end

	local function setButtonState(btn, enabled)
		if enabled then
			btn:Enable()
			btn:SetAlpha(1)
			SetDesaturation(btn:GetNormalTexture(), false)
		else
			btn:Disable()
			btn:SetAlpha(0.35)
			SetDesaturation(btn:GetNormalTexture(), true)
		end
	end

	if validity == nil then
		G_RLF:LogWarn(
			"LootRollsButtonsMixin:UpdateButtonStates called with nil validity — all buttons disabled",
			addonName
		)
	end
	local v = validity or {}
	local canNeed = v.canNeed == true
	local canPass = v.canPass == true
	local canGreed = v.canGreed == true
	local canTransmog = v.canTransmog == true

	setButtonState(self.NeedButton, canNeed)
	setButtonState(self.PassButton, canPass)
	setButtonState(self.GreedButton, canGreed)
	setButtonState(self.TransmogButton, canTransmog)

	G_RLF:LogDebug(
		"LootRollsButtonsMixin:UpdateButtonStates"
			.. " canNeed="
			.. tostring(canNeed)
			.. " canGreed="
			.. tostring(canGreed)
			.. " canTransmog="
			.. tostring(canTransmog)
			.. " canPass="
			.. tostring(canPass),
		addonName
	)
end

function RLF_LootRollsButtonsMixin:ShowButtons()
	if not self.NeedButton then
		return
	end
	self.NeedButton:Show()
	self.PassButton:Show()
	-- GreedButton and TransmogButton visibility is managed by ConfigureMiddleButton.
end

function RLF_LootRollsButtonsMixin:HideButtons()
	if not self.NeedButton then
		return
	end
	self.NeedButton:Hide()
	self.PassButton:Hide()
	self.GreedButton:Hide()
	self.TransmogButton:Hide()
end

--- Called from LootDisplayRow whenever the element payload is updated.
function RLF_LootRollsButtonsMixin:UpdateLootRollButtons(payload)
	-- ── Dismiss gating (S04/T02) ─────────────────────────────────────────────
	-- pending/result phases: lock dismiss (SetClickThrough=true → mouse disabled)
	-- resolved/cancelled phases: unlock dismiss (SetClickThrough=false → interactive)
	-- Default to locked ("pending") when rowPhase is absent for safety.
	local rowPhase = payload and payload.rowPhase or "pending"
	local dismissLocked = rowPhase ~= "resolved" and rowPhase ~= "cancelled"
	self:SetClickThrough(dismissLocked)
	G_RLF:LogDebug(
		"Row %s dismiss lock=%s (phase=%s)",
		addonName,
		"LootRollsButtonsMixin",
		tostring(payload and payload.key),
		tostring(dismissLocked),
		rowPhase
	)

	local lootRollsConfig = G_RLF.DbAccessor:AnyFeatureConfig("lootRolls") or {}
	if not lootRollsConfig.enableLootRollActions then
		G_RLF:LogDebug(
			"UpdateLootRollButtons: buttons hidden — enableLootRollActions=false",
			addonName,
			"LootRollsButtonsMixin",
			"rollID=" .. tostring(payload and payload.rollID),
			"itemLink=" .. tostring(payload and payload.itemLink)
		)
		self:HideButtons()
		return
	end

	if payload.rollState ~= "pending" then
		self:HideButtons()
		return
	end

	self:InitializeButtons()

	-- rollID from START_LOOT_ROLL (Retail) is required by RollOnLoot().
	-- Classic uses lootListID as a stand-in (the Classic event path stores
	-- rollID_rollID so lootListID == rollID there).
	self.rollID = payload.rollID or payload.lootListID

	local validity = payload.buttonValidity
	local middleKey = resolveMiddleSlot(validity or {})

	self:ConfigureMiddleButton(middleKey)
	self:LayoutButtons()
	self:UpdateButtonStates(validity)
	self:ShowButtons()
end

--- Called from LootDisplayRow:Reset().
function RLF_LootRollsButtonsMixin:ResetButtons()
	self.rollID = nil
	self:HideButtons()
end

G_RLF.RLF_LootRollsButtonsMixin = RLF_LootRollsButtonsMixin
