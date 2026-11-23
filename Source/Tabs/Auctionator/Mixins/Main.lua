AuctionatorConfigTabMixin = {}

local restoreSettingsPanel
local settingsCloseHookInstalled = false

local function OpenOptionsOverAuctionHouse(categoryID)
  local panel = SettingsPanel
  if not panel:IsShown() then
    local transition = panel.TransitionBackOpeningPanel
    if not settingsCloseHookInstalled then
      panel:HookScript("OnHide", function()
        if restoreSettingsPanel then
          restoreSettingsPanel()
          restoreSettingsPanel = nil
        end
      end)
      settingsCloseHookInstalled = true
    end

    panel.TransitionBackOpeningPanel = panel.Hide
    restoreSettingsPanel = function()
      panel.TransitionBackOpeningPanel = transition
    end
    -- Keep the auction panel registered while showing Settings above it.
    panel:Show()
  end

  local category = panel:GetCategoryList():GetCategory(categoryID)
  if category then
    category:SetExpanded(true)
    panel:SelectCategory(category)
  end
end

function AuctionatorConfigTabMixin:OnLoad()
  Auctionator.Debug.Message("AuctionatorConfigTabMixin:OnLoad()")

  if Auctionator.Constants.IsLegacyAH then
    -- Reposition lower down translator entries so that they don't go past the
    -- bottom of the tab
    self.esES:SetPoint("TOPLEFT", self.deDE, "TOPLEFT", 300, 0)
    self.koKR:SetPoint("TOPLEFT", self.esES, "TOPLEFT", 300, 0)
  else
    self.ruRU:SetPoint("TOPLEFT", self.deDE, "TOPLEFT", 300, 0)
  end

  if Auctionator.Constants.IsForever then
    self.OptionsButton:Hide()
  end
end

function AuctionatorConfigTabMixin:OpenOptions()
  local categoryID = Auctionator.State.OptionsCategory:GetID()
  if Auctionator.Constants.IsForever and AuctionHouseFrame:IsShown() then
    OpenOptionsOverAuctionHouse(categoryID)
  else
    Settings.OpenToCategory(categoryID)
  end
end
