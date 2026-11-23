AuctionatorTabContainerMixin = {}

local LibAHTab = LibStub("LibAHTab-1-0")

local padding = 0
local absoluteSize = nil
local minTabWidth = 36

function AuctionatorTabContainerMixin:OnLoad()
  Auctionator.Debug.Message("AuctionatorTabContainerMixin:OnLoad()")

  if Auctionator.Constants.IsForever then
    local auctionHouse = AuctionHouseFrame
    auctionHouse.SellTab:Hide()
    auctionHouse.AuctionsTab:ClearAllPoints()
    auctionHouse.AuctionsTab:SetPoint("LEFT", auctionHouse.BuyTab, "RIGHT", -15, 0)
  end

  -- Tabs are sorted to avoid inconsistent ordering based on the addon loading
  -- order
  table.sort(
    Auctionator.Tabs.State.knownTabs,
    function(left, right)
      return left.tabOrder < right.tabOrder
    end
  )

  self.Tabs = {}

  for _, details in ipairs(Auctionator.Tabs.State.knownTabs) do
    local frameRef = CreateFrame(
      "FRAME",
      details.tabFrameName,
      AuctionHouseFrame,
      details.tabTemplate
    )
    local buttonFrameName = "AuctionatorTabs_" .. details.name
    LibAHTab:CreateTab(buttonFrameName, frameRef, details.textLabel, details.tabHeader)
    _G[buttonFrameName] = LibAHTab:GetButton(buttonFrameName)
    Auctionator.RegisterFontRoot(frameRef)
    Auctionator.RegisterFontRoot(_G[buttonFrameName])
    table.insert(AuctionatorAHTabsContainer.Tabs, _G[buttonFrameName])

    -- Apply small tabs if enabled
    _G[buttonFrameName]:HookScript("OnShow", function(tab)
      if Auctionator.Config.Get(Auctionator.Config.Options.SMALL_TABS) then
        PanelTemplates_TabResize(tab, padding, absoluteSize, minTabWidth)
      end
    end)
    if Auctionator.Config.Get(Auctionator.Config.Options.SMALL_TABS) then
      PanelTemplates_TabResize(_G[buttonFrameName], padding, absoluteSize, minTabWidth)
    end
  end

  if Auctionator.Constants.IsForever then
    local auctionHouse = AuctionHouseFrame
    local button = CreateFrame("Button", nil, auctionHouse, "UIPanelDynamicResizeButtonTemplate")
    auctionHouse.AuctionatorOptionsButton = button
    button:SetText(AUCTIONATOR_L_OPEN_ADDON_OPTIONS)
    DynamicResizeButton_Resize(button)
    button:SetHeight(20)
    button:SetPoint("TOPLEFT", auctionHouse, "TOPLEFT", 64, -4)
    local header = auctionHouse.TitleContainer or auctionHouse
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel(header:GetFrameLevel() + 20)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", AuctionatorConfigTabMixin.OpenOptions)
    Auctionator.RegisterFontRoot(button)
    button:Show()
  end
end

function AuctionatorTabContainerMixin:OnShow()
  if Auctionator.Config.Get(Auctionator.Config.Options.SMALL_TABS) then
    for _, tab in ipairs(AuctionHouseFrame.Tabs) do
      PanelTemplates_TabResize(tab, padding, absoluteSize, minTabWidth)
    end
  end
end
