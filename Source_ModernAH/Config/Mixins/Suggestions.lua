AuctionatorConfigSuggestionsFrameMixin = CreateFromMixins(AuctionatorPanelConfigMixin)

local columns = 3
local rowHeight = 24
local columnWidth = 142

function AuctionatorConfigSuggestionsFrameMixin:OnLoad()
  self.name = AUCTIONATOR_L_CONFIG_SUGGESTIONS_CATEGORY
  self.parent = AUCTIONATOR_L_AUCTIONATOR
  self.checkboxes = {}
  self:SetupPanel()
end

function AuctionatorConfigSuggestionsFrameMixin:ShowStatFilters(category)
  local checkboxes = self.checkboxes[category] or {}
  self.checkboxes[category] = checkboxes
  for _, checkbox in ipairs(checkboxes) do
    checkbox:Hide()
  end
  local stats = Auctionator.Shopping.GetSuggestedStats(category)
  for index, stat in ipairs(stats) do
    local checkbox = checkboxes[index]
    if not checkbox then
      checkbox = CreateFrame("Frame", nil, self, "AuctionatorConfigurationCheckbox")
      checkbox:ClearAllPoints()
      local column = (index - 1) % columns
      local row = math.floor((index - 1) / columns)
      checkbox:SetPoint("TOPLEFT", self[category], "BOTTOMLEFT", column * columnWidth, -row * rowHeight)
      checkbox:SetWidth(columnWidth)
      checkbox:SetHeight(rowHeight)
      checkbox.CheckBox:ClearAllPoints()
      checkbox.CheckBox:SetPoint("LEFT", checkbox, "LEFT", 20, 0)
      checkbox.CheckBox:SetSize(22, 22)
      local label = checkbox.CheckBox.Label
      label:ClearAllPoints()
      label:SetPoint("LEFT", checkbox.CheckBox, "RIGHT", 4, 0)
      checkbox.CheckBox:HookScript("OnClick", function()
        Auctionator.Shopping.SetSuggestedStatEnabled(category, checkbox.stat, checkbox:GetChecked())
      end)
      checkboxes[index] = checkbox
      Auctionator.RegisterFontRoot(checkbox)
    end
    checkbox.stat = stat
    checkbox:SetText(stat == "" and AUCTIONATOR_L_CONFIG_SUGGESTIONS_NO_STAT or stat)
    checkbox:SetChecked(Auctionator.Shopping.IsSuggestedStatEnabled(category, stat))
    checkbox:Show()
  end
  return math.ceil(#stats / columns) * rowHeight
end

function AuctionatorConfigSuggestionsFrameMixin:ShowSettings()
  local previousSection, previousHeight
  for _, category in ipairs({ "Foods", "Elixirs", "Burst" }) do
    local section = self[category]
    if previousSection then
      section:ClearAllPoints()
      section:SetPoint("TOPLEFT", previousSection, "BOTTOMLEFT", 0, -previousHeight - 4)
      section:SetPoint("RIGHT", self, "RIGHT")
    end
    previousSection, previousHeight = section, self:ShowStatFilters(category)
  end
end

-- The filters are saved and applied immediately.
function AuctionatorConfigSuggestionsFrameMixin:Save()
end
