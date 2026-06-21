local SALE_ITEM_EVENTS = {
  Auctionator.AH.Events.CommoditySearchResultsReady,
  Auctionator.AH.Events.ItemSearchResultsReady,
}

local POSTING_EVENTS = {
  "AUCTION_HOUSE_AUCTION_CREATED",
  "AUCTION_HOUSE_POST_ERROR",
  "AUCTION_HOUSE_POST_WARNING",
  "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
}

-- Necessary because attempting to post an auction with copper value silently
-- fails
local function NormalizePrice(price)
  local normalizedPrice = price

  if Auctionator.Constants.IsRetail then
    -- Round up
    if normalizedPrice % 100 ~= 0 then
      normalizedPrice = normalizedPrice + (100 - normalizedPrice % 100)
    end

    -- Need to have a price of at least one silver (retail) or one copper (cata)
    if normalizedPrice < 100 then
      normalizedPrice = 100
    end
  elseif normalizedPrice < 1 then
    normalizedPrice = 1
  end

  return normalizedPrice
end

local function IsEquipment(itemInfo)
  -- Commodity check because some items like Secret Sauce are set to the wrong item class
  return not itemInfo.isCommodity and Auctionator.Utilities.IsEquipment(itemInfo.classId)
end

local function RequiresSingleVariantPost(itemInfo)
  return itemInfo ~= nil and IsEquipment(itemInfo) and itemInfo.hasItemIDVariants == true
end

local function GetVariantPostingLocations(itemInfo)
  if not itemInfo then
    return {}
  end

  if itemInfo.locations and #itemInfo.locations > 0 then
    return itemInfo.locations
  end

  if itemInfo.location then
    return { itemInfo.location }
  end

  return {}
end

local function GetVariantLocationPostCount(itemInfo)
  if not itemInfo or not itemInfo.location or not C_Item.DoesItemExist(itemInfo.location) then
    return 0
  end

  if not C_AuctionHouse.IsSellItemValid(itemInfo.location, false) then
    return 0
  end

  return math.max(0, C_AuctionHouse.GetAvailablePostCount(itemInfo.location) or 0)
end

local function SelectBestVariantLocation(itemInfo)
  local bestLocation = itemInfo and itemInfo.location
  local bestCount = 0
  if bestLocation and C_Item.DoesItemExist(bestLocation) and C_AuctionHouse.IsSellItemValid(bestLocation, false) then
    bestCount = math.max(0, C_AuctionHouse.GetAvailablePostCount(bestLocation) or 0)
  end

  for _, location in ipairs(GetVariantPostingLocations(itemInfo)) do
    if location and C_Item.DoesItemExist(location) and C_AuctionHouse.IsSellItemValid(location, false) then
      local availableCount = math.max(0, C_AuctionHouse.GetAvailablePostCount(location) or 0)
      if availableCount > bestCount then
        bestCount = availableCount
        bestLocation = location
      end
    end
  end

  return bestLocation
end

local function IsValidItem(item)
  return item ~= nil and
    -- May be a favourite with no items available, ignore it.
    item.location ~= nil and
    -- Location may be invalid because of items being moved in the bag
    C_Item.DoesItemExist(item.location)
end

local function GetExpiredSinceLastSale(itemInfo)
  if itemInfo == nil or
     itemInfo.itemLink == nil or
     Auctionator.Selling == nil or
     Auctionator.Selling.TSMAccounting == nil or
     type(Auctionator.Selling.TSMAccounting.GetExpiredSinceLastSale) ~= "function" then
    return 0
  end

  return Auctionator.Selling.TSMAccounting.GetExpiredSinceLastSale(itemInfo.itemLink) or 0
end

AuctionatorSaleItemMixin = {}

function AuctionatorSaleItemMixin:OnLoad()
  if Auctionator.Config.Get(Auctionator.Config.Options.SHOW_SELLING_BID_PRICE) then
    self.BidPrice:Show()
  end
end

function AuctionatorSaleItemMixin:OnShow()
  FrameUtil.RegisterFrameForEvents(self, POSTING_EVENTS)
  Auctionator.EventBus:Register(self, {
    Auctionator.Selling.Events.BagItemClicked,
    Auctionator.Selling.Events.ClearBagItem,
    Auctionator.Selling.Events.RequestPost,
    Auctionator.Selling.Events.ConfirmPost,
    Auctionator.Selling.Events.SkipItem,
    Auctionator.AH.Events.ThrottleUpdate,
    Auctionator.Selling.Events.PriceSelected,
    Auctionator.Selling.Events.RefreshSearch,
    Auctionator.Selling.Events.OwnedAuctionsQueryPending,
    Auctionator.Components.Events.EnterPressed,
  })
  Auctionator.EventBus:RegisterSource(self, "AuctionatorSaleItemMixin")

  local function SetupBindings()
    if self:IsVisible() then
      SetOverrideBinding(self, false, Auctionator.Config.Get(Auctionator.Config.Options.SELLING_POST_SHORTCUT), "CLICK AuctionatorPostButton:LeftButton")
      SetOverrideBinding(self, false, Auctionator.Config.Get(Auctionator.Config.Options.SELLING_SKIP_SHORTCUT), "CLICK AuctionatorSkipPostingButton:LeftButton")
      SetOverrideBinding(self, false, Auctionator.Config.Get(Auctionator.Config.Options.SELLING_PREV_SHORTCUT), "CLICK AuctionatorPrevPostingButton:LeftButton")
    end
  end
  if InCombatLockdown() then
    EventUtil.ContinueAfterAllEvents(SetupBindings, "PLAYER_REGEN_ENABLED")
  else
    SetupBindings()
  end

  self.lastItemInfo = nil
  self.nextItem = nil
  self.prevItem = nil
  self.priceCheckPassed = true
  self.ownedAuctionsQueryPending = false
  self.sellSearchPending = false
  self.sellSearchSequence = 0
  self.manualPostingPending = false
  self.pendingPostNextItem = nil
  self.pendingPostBuyout = nil

  self:UpdateSkipButton()
  self:Reset()

  if Auctionator.Config.Get(Auctionator.Config.Options.SELLING_SHOULD_RESELECT_ITEM) then
    local key = Auctionator.Config.Get(Auctionator.Config.Options.SELLING_RESELECT_ITEM)
    if key ~= nil then
      Auctionator.EventBus:Fire(
        self, Auctionator.Selling.Events.BagItemRequest, key
      )
    end
  end
end

function AuctionatorSaleItemMixin:OnHide()
  FrameUtil.UnregisterFrameForEvents(self, POSTING_EVENTS)
  Auctionator.EventBus:Unregister(self, {
    Auctionator.Selling.Events.BagItemClicked,
    Auctionator.Selling.Events.ClearBagItem,
    Auctionator.Selling.Events.RequestPost,
    Auctionator.Selling.Events.ConfirmPost,
    Auctionator.Selling.Events.SkipItem,
    Auctionator.AH.Events.ThrottleUpdate,
    Auctionator.Selling.Events.PriceSelected,
    Auctionator.Selling.Events.RefreshSearch,
    Auctionator.Selling.Events.OwnedAuctionsQueryPending,
    Auctionator.Components.Events.EnterPressed,
  })
  if self.saleItemEventsRegistered then
    Auctionator.EventBus:Unregister(self, SALE_ITEM_EVENTS)
  end
  Auctionator.Config.Set(Auctionator.Config.Options.SELLING_RESELECT_ITEM, self.lastKey)
  Auctionator.EventBus:UnregisterSource(self)
  self:UnlockItem()

  if InCombatLockdown() then
    EventUtil.ContinueAfterAllEvents(function() ClearOverrideBindings(self) end, "PLAYER_REGEN_ENABLED")
  else
    ClearOverrideBindings(self)
  end
end

function AuctionatorSaleItemMixin:UpdateSkipButton()
  self:UpdatePostAndSkipButtonLayout()
end

function AuctionatorSaleItemMixin:ShouldSwapPostAndSkipButtons()
  return Auctionator.Config.Get(Auctionator.Config.Options.SELLING_AUTO_SELECT_NEXT) and
    self.priceCheckPassed == false
end

function AuctionatorSaleItemMixin:UpdatePostAndSkipButtonLayout()
  local autoSelectNext = Auctionator.Config.Get(Auctionator.Config.Options.SELLING_AUTO_SELECT_NEXT)
  local swapButtons = self:ShouldSwapPostAndSkipButtons()

  if self.postAndSkipButtonLayoutAutoSelectNext == autoSelectNext and
     self.postAndSkipButtonsSwapped == swapButtons then
    return
  end

  self.postAndSkipButtonLayoutAutoSelectNext = autoSelectNext
  self.postAndSkipButtonsSwapped = swapButtons

  if autoSelectNext then
    self.PostButton:SetSize(75, 22)
    self.SkipButton:Show()
  else
    self.PostButton:SetSize(150, 22)
    self.SkipButton:Hide()
  end

  self.PostButton:ClearAllPoints()
  self.SkipButton:ClearAllPoints()
  self.PrevButton:ClearAllPoints()
  self.Deposit:ClearAllPoints()

  if swapButtons then
    self.SkipButton:SetPoint("TOPLEFT", self.Duration, "BOTTOMLEFT", 20, 0)
    self.PostButton:SetPoint("TOPLEFT", self.SkipButton, "TOPRIGHT", 0, 0)
    self.PrevButton:SetPoint("TOPRIGHT", self.SkipButton, "TOPLEFT", 0, 0)
    self.Deposit:SetPoint("TOPLEFT", self.PostButton, "TOPRIGHT", 15, 50)
  else
    self.PostButton:SetPoint("TOPLEFT", self.Duration, "BOTTOMLEFT", 20, 0)
    self.SkipButton:SetPoint("TOPLEFT", self.PostButton, "TOPRIGHT", 0, 0)
    self.PrevButton:SetPoint("TOPRIGHT", self.PostButton, "TOPLEFT", 0, 0)
    self.Deposit:SetPoint("TOPLEFT", self.SkipButton, "TOPRIGHT", 15, 50)
  end
end

function AuctionatorSaleItemMixin:UnlockItem()
  if self.itemInfo ~= nil then
    --Existence check added because of a bug report from a user where (for an
    --unknown reason) the item no longer existed.
    if IsValidItem(self.itemInfo) then
      C_Item.UnlockItem(self.itemInfo.location)
    end
    self.itemInfo = nil
  end
end

function AuctionatorSaleItemMixin:LockItem()
  if IsValidItem(self.itemInfo) then
    C_Item.LockItem(self.itemInfo.location)
  end
end

function AuctionatorSaleItemMixin:OnUpdate()
  if self.itemInfo == nil then
    return

  elseif self.itemInfo.count == 0 then
    return

  elseif not C_Item.DoesItemExist(self.itemInfo.location) then
    --Bag item location invalid due to posting (race condition)
    self.itemInfo = nil
    self:Reset()
    return
  end

  self.TotalPrice:SetText(
    Auctionator.Utilities.CreatePaddedMoneyString(self.Quantity:GetNumber() * self.Price:GetAmount(), true, true, true)
  )

  if self.Quantity:GetNumber() > self:GetPostLimit() then
    self:SetMax()
  end

  self.MaxButton:SetEnabled(self.Quantity:GetNumber() ~= self:GetPostLimit())

  local deposit = self:GetDeposit()
  local unitDeposit = self:GetDeposit(1)
  local expiredCount = GetExpiredSinceLastSale(self.itemInfo)
  local depositText = GetMoneyString(deposit, true)

  if expiredCount > 0 then
    depositText = depositText .. " (" .. GetMoneyString(unitDeposit * expiredCount, true) .. ")"
  end

  self.DepositPrice:SetText(depositText)
  self:ValidateMinimumPrice()
  self:UpdatePostButtonState()
  self:UpdateSkipButtonState()
end

function AuctionatorSaleItemMixin:GetPostLimit()
  if RequiresSingleVariantPost(self.itemInfo) then
    return math.min(self.itemInfo.count, GetVariantLocationPostCount(self.itemInfo))
  end
  return math.min(C_AuctionHouse.GetAvailablePostCount(self.itemInfo.location), self.itemInfo.count)
end
function AuctionatorSaleItemMixin:SetMax()
  self.Quantity:SetNumber(self:GetPostLimit())
end

function AuctionatorSaleItemMixin:GetDeposit(quantity)
  local deposit = 0

  -- Protect against nil itemInfo
  if not self.itemInfo then
    return deposit
  end

  local duration = self:GetDuration()
  quantity = quantity or self.Quantity:GetNumber()

  if duration == nil then
    local selectedDuration = self.Duration:GetValue() or Auctionator.Config.Get(Auctionator.Config.Options.AUCTION_DURATION)

    if selectedDuration == 12 then
      duration = 1
    elseif selectedDuration == 24 then
      duration = 2
    elseif selectedDuration == 48 then
      duration = 3
    end
  end

  if C_AuctionHouse.GetItemCommodityStatus(self.itemInfo.location) == Enum.ItemCommodityStatus.Commodity then
    deposit = C_AuctionHouse.CalculateCommodityDeposit(
      self.itemInfo.itemID,
      duration,
      quantity
    ) or deposit

  else
    deposit = C_AuctionHouse.CalculateItemDeposit(
      self.itemInfo.location,
      duration,
      quantity
    ) or deposit
  end

  return NormalizePrice(deposit)
end

function AuctionatorSaleItemMixin:ReceiveEvent(event, ...)
  if event == Auctionator.Selling.Events.BagItemClicked then
    self.pendingPostBuyout = nil
    self:UnlockItem()
    local itemInfo = ...
    Auctionator.AH.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(itemInfo.itemID), function(itemKeyInfo)
      self.itemInfo = itemInfo
      self.itemInfo.isCommodity = itemKeyInfo.isCommodity
      if self.itemInfo.sortKey and Auctionator.Groups and Auctionator.Groups.Utilities and Auctionator.Groups.Utilities.HasItemIDVariants then
        self.itemInfo.hasItemIDVariants = Auctionator.Groups.Utilities.HasItemIDVariants(self.itemInfo.itemID, self.itemInfo.sortKey)
        if self.itemInfo.hasItemIDVariants and (not self.itemInfo.locations or #self.itemInfo.locations == 0) and Auctionator.Groups.Utilities.QueryItem then
          local groupedInfo = Auctionator.Groups.Utilities.QueryItem(self.itemInfo.sortKey)
          if groupedInfo then
            self.itemInfo.locations = groupedInfo.locations
            self.itemInfo.count = groupedInfo.itemCount
          end
        end
        if self.itemInfo.hasItemIDVariants then
          local bestLocation = SelectBestVariantLocation(self.itemInfo)
          if bestLocation then
            self.itemInfo.location = bestLocation
          end
        end
      end
      self.nextItem = self.itemInfo and self.itemInfo.nextItem
      self.prevItem = self.itemInfo and self.itemInfo.prevItem
      self.lastKey = self.itemInfo and self.itemInfo.key
      Auctionator.Selling.TrySelectOpenProfessionRecipe(self.itemInfo and self.itemInfo.itemID)
      self:LockItem()
      self:Update()
    end)

  elseif event == Auctionator.Selling.Events.ClearBagItem then
    self.pendingPostBuyout = nil
    self.nextItem = nil
    self.prevItem = nil
    self.lastKey = nil
    self:Reset()
    if self.manualPostingPending then
      self:FinishManualPosting()
    end

  elseif event == Auctionator.AH.Events.ThrottleUpdate then
    self:UpdatePostButtonState()

  elseif event == Auctionator.Selling.Events.OwnedAuctionsQueryPending then
    self.ownedAuctionsQueryPending = ...
    self:UpdatePostButtonState()

  elseif event == Auctionator.Selling.Events.RequestPost then
    self:PostItem()

  elseif event == Auctionator.Selling.Events.ConfirmPost then
    self:PostItem(true)

  elseif event == Auctionator.Selling.Events.SkipItem then
    self.pendingPostBuyout = nil
    self:SkipItem()

  elseif event == Auctionator.Components.Events.EnterPressed then
    self:PostItem()

  elseif event == Auctionator.Selling.Events.PriceSelected and
         self.itemInfo ~= nil then
    local selectedPrices, shouldUndercut = ...
    local buyoutAmount = selectedPrices.buyout or selectedPrices.bid
    local itemLink = self.itemInfo and self.itemInfo.itemLink

    if shouldUndercut then
      buyoutAmount = Auctionator.Selling.CalculateItemPriceFromPrice(buyoutAmount, itemLink)
    else
      buyoutAmount = Auctionator.Selling.ApplyCraftSimQualityPriceLimit(buyoutAmount, itemLink)
    end

    if Auctionator.Config.Get(Auctionator.Config.Options.SHOW_SELLING_BID_PRICE) then
      self:UpdateSalesPrice(buyoutAmount, selectedPrices.bid, true)
    else
      self:UpdateSalesPrice(buyoutAmount)
    end

  elseif event == Auctionator.Selling.Events.RefreshSearch then
    self:RefreshButtonClicked()

  elseif event == Auctionator.AH.Events.CommoditySearchResultsReady then
    local itemID = ...
    if itemID ~= self.expectedItemKey.itemID then
      return
    end

    local searchSequence = self.sellSearchSequence
    self:ProcessCommodityResults(...)
    self:CompleteSellSearch(searchSequence)
    self.saleItemEventsRegistered = false
    Auctionator.EventBus:Unregister(self, SALE_ITEM_EVENTS)

  elseif event == Auctionator.AH.Events.ItemSearchResultsReady then
    local itemKey = ...
    if Auctionator.Utilities.ItemKeyString(itemKey) ~=
        Auctionator.Utilities.ItemKeyString(self.expectedItemKey) then
      return
    end

    local searchSequence = self.sellSearchSequence
    local item = Item:CreateFromItemID(itemKey.itemID)
    item:ContinueOnItemLoad(function()
      self:ProcessItemResults(itemKey)
      self:CompleteSellSearch(searchSequence)
    end)
    self.saleItemEventsRegistered = false
    Auctionator.EventBus:Unregister(self, SALE_ITEM_EVENTS)
  end
end

function AuctionatorSaleItemMixin:Update(skipSearch)
  self:UpdateVisuals()

  if self.itemInfo ~= nil then
    self:UpdateForNewItem(skipSearch)
  else
    self:UpdateForNoItem()
  end

  self:ValidateMinimumPrice()
  self:UpdatePostButtonState()
  self:UpdateSkipButtonState()
end

function AuctionatorSaleItemMixin:UpdateVisuals()
  self.Icon:SetItemInfo(self.itemInfo)

  if self.itemInfo ~= nil then
    self:SetItemName()


    -- Fade the (optionally visible) bid price if posting a commodity
    if self.itemInfo.isCommodity then
      self.BidPrice:SetAlpha(0.5)
    else
      self.BidPrice:SetAlpha(1)
    end

  else
    -- No item, reset all the visuals
    self.TitleArea.Text:SetText("")
  end
end

-- The exact item name is only loaded when needed as it slows down loading the
-- bag items too much to do in BagDataProvider.
function AuctionatorSaleItemMixin:SetItemName()
  local reagentQualityInfo
  if Auctionator.Constants.IsRetail then
    reagentQualityInfo = C_TradeSkillUI.GetItemReagentQualityInfo(self.itemInfo.itemID)
  end
  local itemName = self.itemInfo.itemName
  if reagentQualityInfo then
    itemName = itemName .. " " .. CreateAtlasMarkup(reagentQualityInfo.iconChat, 17, 17)
  elseif self.itemInfo.itemLevel then
    itemName = AUCTIONATOR_L_ITEM_NAME_X_ITEM_LEVEL_X:format(itemName, self.itemInfo.itemLevel)
  elseif self.itemInfo.itemLink:find("battlepet", nil, true) then
    itemName = AUCTIONATOR_L_ITEM_NAME_X_ITEM_LEVEL_X:format(itemName, Auctionator.Utilities.GetPetLevelFromLink(self.itemInfo.itemLink))
  end
  itemName = ITEM_QUALITY_COLORS[self.itemInfo.quality].color:WrapTextInColorCode(itemName)
  self.TitleArea.Text:SetText(itemName)
end

function AuctionatorSaleItemMixin:UpdateForNewItem(skipSearch)
  self:SetDuration()

  self.MaxButton:Disable() -- Disable needed for case quantity is 0

  self:SetQuantity()

  Auctionator.Utilities.DBKeyFromLink(self.itemInfo.itemLink, function(dbKeys)
    local price = Auctionator.Database:GetFirstPrice(dbKeys)

    if price ~= nil then
      self:UpdateSalesPrice(Auctionator.Selling.ApplyCraftSimQualityPriceLimit(
        price,
        self.itemInfo and self.itemInfo.itemLink
      ))
    elseif IsEquipment(self.itemInfo) then
      self:SetEquipmentMultiplier(self.itemInfo.itemLink)
    else
      self:UpdateSalesPrice(0)
    end
  end)

  if not skipSearch then
    self:DoSearch(self.itemInfo)
  end
end

function AuctionatorSaleItemMixin:UpdateForNoItem()
  self.Quantity:SetNumber(0)
  self.MaxButton:Disable()
  self:UpdateSalesPrice(0)

  self.DepositPrice:SetText(GetMoneyString(100, true))
  self.TotalPrice:SetText(Auctionator.Utilities.CreatePaddedMoneyString(100, true, true, true))
end

local DURATIONS_TO_TIME = {
  [1] = 12,
  [2] = 24,
  [3] = 48,
}
function AuctionatorSaleItemMixin:SetDuration()
  local duration = Auctionator.Config.Get(Auctionator.Config.Options.AUCTION_DURATION)

  self.Duration:SetSelectedValue(duration)
end

function AuctionatorSaleItemMixin:SetQuantity()
  local defaultQuantity = Auctionator.Config.Get(Auctionator.Config.Options.DEFAULT_QUANTITIES)[self.itemInfo.classId]

  if self.itemInfo.count == 0 then
    self.Quantity:SetNumber(0)
  elseif defaultQuantity ~= nil and defaultQuantity > 0 then
    -- If a default quantity has been selected (ie non-zero amount)
    self.Quantity:SetNumber(math.min(self.itemInfo.count, defaultQuantity, self:GetPostLimit()))
  else
    -- No default quantity setting, use the maximum possible
    self:SetMax()
  end
end

function AuctionatorSaleItemMixin:DoSearch(itemInfo, ...)
  self.sellSearchSequence = self.sellSearchSequence + 1
  self.sellSearchPending = true
  self:UpdatePostButtonState()

  if self.manualPostingPending then
    self:FinishManualPosting()
  end

  Auctionator.EventBus:Register(self, SALE_ITEM_EVENTS)
  self.saleItemEventsRegistered = true

  local sortingOrder

  if itemInfo.isCommodity then
    sortingOrder = Auctionator.Constants.CommodityResultsSorts
  else
    sortingOrder = Auctionator.Constants.ItemResultsSorts
  end

  local comparisonKey
  if IsEquipment(itemInfo) then
    self.expectedItemKey = {itemID = itemInfo.itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0}
    comparisonKey = {itemID = itemInfo.itemID, itemLevel = itemInfo.itemLevel, itemSuffix = 0, battlePetSpeciesID = 0}
    Auctionator.AH.SendSellSearchQueryByItemKey(self.expectedItemKey, {sortingOrder}, true)
  else
    local battlePetID = itemInfo.itemLink:match("battlepet:(%d+)")

    if battlePetID then
      self.expectedItemKey = C_AuctionHouse.MakeItemKey(itemInfo.itemID, nil, nil, tonumber(battlePetID))
    else
      self.expectedItemKey = C_AuctionHouse.MakeItemKey(itemInfo.itemID)
    end
    comparisonKey = self.expectedItemKey
    Auctionator.AH.SendSearchQueryByItemKey(self.expectedItemKey, {sortingOrder}, true)
  end
  local originalKey = IsValidItem(itemInfo) and C_AuctionHouse.GetItemKeyFromItem(itemInfo.location) or comparisonKey
  if originalKey.itemLevel == 0 then
    originalKey = comparisonKey
  end
  Auctionator.EventBus:Fire(self, Auctionator.Selling.Events.SellSearchStart, self.expectedItemKey, itemInfo.itemLink, originalKey)
end

function AuctionatorSaleItemMixin:CompleteSellSearch(searchSequence)
  C_Timer.After(0, function()
    if self.sellSearchSequence ~= searchSequence then
      return
    end

    self.sellSearchPending = false
    self:UpdatePostButtonState()
  end)
end

function AuctionatorSaleItemMixin:Reset(skipSearch)
  self:UnlockItem()

  self:Update(skipSearch)
end

function AuctionatorSaleItemMixin:UpdateSalesPrice(salesPrice, bidPrice, preserveBidPrice)
  if salesPrice == 0 then
    self.Price:SetAmount(0)
  else
    self.Price:SetAmount(NormalizePrice(salesPrice))
  end
  if bidPrice == nil then
    -- Carry over the bid price from a previously selected row unless its higher
    -- than the unit price chosen
    if not preserveBidPrice or self.BidPrice:GetAmount() >= self.Price:GetAmount() then
      self.BidPrice:Clear()
    end
  else
    self.BidPrice:SetAmount(bidPrice)
  end
end

function AuctionatorSaleItemMixin:SetEquipmentMultiplier(itemLink)
  self:UpdateSalesPrice(0)

  local item = Item:CreateFromItemLink(itemLink)
  item:ContinueOnItemLoad(function()
    local multiplier = Auctionator.Config.Get(Auctionator.Config.Options.GEAR_PRICE_MULTIPLIER)
    local vendorPrice = select(Auctionator.Constants.ITEM_INFO.SELL_PRICE, C_Item.GetItemInfo(itemLink))
    if multiplier ~= 0 and vendorPrice ~= 0 then
      -- Check for a vendor price multiplier being set (and a vendor price)
      self:UpdateSalesPrice(
        vendorPrice * multiplier + self:GetDeposit()
      )
    end
  end)
end

function AuctionatorSaleItemMixin:OnEvent(eventName, ...)
  if eventName == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" and self.sellSearchPending then
    self:CompleteSellSearch(self.sellSearchSequence)
  end

  if not self.manualPostingPending then
    return
  end

  if eventName == "AUCTION_HOUSE_AUCTION_CREATED" then
    self:ContinueAfterManualPosting()

  elseif eventName == "AUCTION_HOUSE_POST_ERROR" or
         eventName == "AUCTION_HOUSE_POST_WARNING" or
         eventName == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
    self:FinishManualPosting()
  end
end

function AuctionatorSaleItemMixin:ContinueAfterManualPosting()
  local nextItem = self.pendingPostNextItem
  self.pendingPostNextItem = nil

  if nextItem then
    Auctionator.EventBus:Fire(
      self, Auctionator.Selling.Events.BagItemRequest, nextItem
    )
  elseif self.lastItemInfo then
    -- DoSearch queues the request when the AH is throttled, while
    -- sellSearchPending keeps Post disabled throughout that wait.
    self:DoSearch(self.lastItemInfo)
  else
    self:FinishManualPosting()
  end
end

function AuctionatorSaleItemMixin:FinishManualPosting()
  self.manualPostingPending = false
  self.pendingPostNextItem = nil
  self:UpdatePostButtonState()
end

function AuctionatorSaleItemMixin:GetCommodityResult(itemID)
  if C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID) > 0 then
    return C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
  else
    return nil
  end
end

-- Identifies when an auction is skewing the current price down and is probably
-- not meant to be so low.
function AuctionatorSaleItemMixin:GetCommodityThreshold(itemID)
  local amount = 0
  -- Scan half the auctions, of the first 500, whichever is fewer
  local target = math.min(5000, math.floor(C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID) * 0.2))
  for index = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
    local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)

    amount = amount + result.quantity

    if amount >= target then
      return Auctionator.Utilities.PriceWarningThreshold(result.unitPrice)
    end
  end

  return nil
end

function AuctionatorSaleItemMixin:ProcessCommodityResults(itemID, ...)
  Auctionator.Debug.Message("AuctionatorSaleItemMixin:ProcessCommodityResults()")

  local dbKeys = Auctionator.Utilities.DBKeyFromBrowseResult({ itemKey = C_AuctionHouse.MakeItemKey(itemID) })

  local result = self:GetCommodityResult(itemID)
  -- Update DB with current lowest price
  if result ~= nil then
    for _, key in ipairs(dbKeys) do
      Auctionator.Database:SetPrice(key, result.unitPrice)
      if Auctionator.GlobalDatabase ~= nil then
        Auctionator.GlobalDatabase:SetPrice(key, result.unitPrice)
      end
    end
  end
  if self.itemInfo ~= nil then
    self.itemInfo.existingValue = result and result.unitPrice
  end

  self.priceThreshold = self:GetCommodityThreshold(itemID)
  self.cheapestCommodityResult = result

  if result == nil then
    return
  end

  -- A few cases to process here:
  -- 1. If the entry containsOwnerItem=true, I should use this price as my
  -- calculated posting price (i.e. I do not want to undercut myself)
  -- 2. Otherwise, this entry is what to base my calculation on:
  --    a. Undercut by percentage (player can choose 0% to become first item chosen via LIFO)
  --    b. Undercut by static value
  local postingPrice = nil

  if result.containsOwnerItem and result.owners[1] == "player" then
    -- No need to undercut myself
    postingPrice = result.unitPrice
  else
    -- Otherwise, we're not the lowest price, so calculate based on user preferences
    postingPrice = Auctionator.Selling.CalculateItemPriceFromPrice(
      result.unitPrice,
      self.itemInfo and self.itemInfo.itemLink
    )
  end

  -- Didn't find anything currently posted, and nothing in DB
  if postingPrice == nil then
    Auctionator.Debug.Message("No prices have been recorded for this item.")
    return
  end

  if self.itemInfo then
    local qtresults = C_AuctionHouse.GetNumCommoditySearchResults(itemID)
    -- consider only the first 15 results
    if qtresults > 15 then qtresults = 15 end

    -- find the biggest stack on those first values, and store its price
    local biggestStack = 0
    local biggestStackPrice = 0

    for index = 1, qtresults do
      local resultInfo = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
      if resultInfo.quantity > biggestStack then
        biggestStack = resultInfo.quantity
        biggestStackPrice = resultInfo.unitPrice
      end
    end

    -- this is the minimum price we should consider
    local minGoodPrice = biggestStackPrice * 0.95

    -- then, instead of using the lowest price, we use the first price that is acceptable
    for index = 1, qtresults do
      local resultInfo = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
      if resultInfo.unitPrice >= minGoodPrice then
        self:UpdateSalesPrice(Auctionator.Selling.ApplyCraftSimQualityPriceLimit(
          resultInfo.unitPrice,
          self.itemInfo and self.itemInfo.itemLink
        ))
        -- and then we return to ignore the default 'match price' logic
        return
      end
    end
  end

  self:UpdateSalesPrice(Auctionator.Selling.ApplyCraftSimQualityPriceLimit(
    postingPrice,
    self.itemInfo and self.itemInfo.itemLink
  ))
end

function AuctionatorSaleItemMixin:GetItemResult(itemKey)
  local itemInfo = self.itemInfo or self.lastItemInfo
  local compareKey = IsValidItem(itemInfo) and C_AuctionHouse.GetItemKeyFromItem(itemInfo.location) or itemKey
  for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
    local resultInfo = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
    if Auctionator.Selling.DoesItemMatchFromKey(compareKey, itemInfo.itemLink, resultInfo.itemKey, resultInfo.itemLink) then
      return resultInfo
    end
  end
  return nil
end

function AuctionatorSaleItemMixin:ProcessItemResults(itemKey)
  Auctionator.Debug.Message("AuctionatorSaleItemMixin:ProcessItemResults()")

  -- Update DB with current lowest price (accomodating for itemKey variations
  -- from the searched for itemKey)
  if C_AuctionHouse.GetNumItemSearchResults(itemKey) > 0 then
    local result = C_AuctionHouse.GetItemSearchResultInfo(itemKey, 1)
    local dbKeys = Auctionator.Utilities.DBKeyFromBrowseResult({ itemKey = result.itemKey })
    for _, key in ipairs(dbKeys) do
      Auctionator.Database:SetPrice(key, result.buyoutAmount or result.bidAmount)
    end
  end

  -- Get the first result that matches the price matching requirements
  local result = self:GetItemResult(itemKey)

  if self.itemInfo ~= nil then
    self.itemInfo.existingValue = result and (result.buyoutAmount or result.bidAmount)
  end

  self.priceThreshold = nil

  local postingPrice = nil

  if result == nil then
    return
  end

  if result.containsOwnerItem then
    -- Posting an item I have alread posted, and that is the current lowest price, so just
    -- use this price
    postingPrice = result.buyoutAmount
  else
    postingPrice = Auctionator.Selling.CalculateItemPriceFromPrice(
      result.buyoutAmount or result.bidAmount,
      self.itemInfo and self.itemInfo.itemLink
    )
  end

  -- Didn't find anything currently posted, and nothing in DB
  if postingPrice == nil then
    Auctionator.Debug.Message("Lowest price not found.")
    return
  end

  self:UpdateSalesPrice(Auctionator.Selling.ApplyCraftSimQualityPriceLimit(
    postingPrice,
    self.itemInfo and self.itemInfo.itemLink
  ))
end

function AuctionatorSaleItemMixin:ValidateMinimumPrice()
  if not self.itemInfo then
    self.priceCheckPassed = true
    return
  end

  local itemInfo = { C_Item.GetItemInfo(self.itemInfo.itemLink) }
  local vendorPrice = itemInfo[Auctionator.Constants.ITEM_INFO.SELL_PRICE]
  if vendorPrice == nil or vendorPrice == 0 then
    self.priceCheckPassed = true
    return
  end

  -- Calculate total price (quantity * price per item)
  local totalPrice = self.Quantity:GetNumber() * self.Price:GetAmount()

  -- Get deposit for this item
  local deposit = self:GetDeposit()
  local unitDeposit = self:GetDeposit(1)
  local expiredCount = GetExpiredSinceLastSale(self.itemInfo)
  local totalDeposit = deposit + (unitDeposit * expiredCount)

  -- Minimum price is 10x the total deposit (current + expired)
  local minRequiredPrice = totalDeposit * 10

  -- Store result in cache (validate once)
  self.priceCheckPassed = totalPrice >= minRequiredPrice
end

function AuctionatorSaleItemMixin:GetPostButtonState()
  return
    self.itemInfo ~= nil and
    self.itemInfo.count > 0 and

    C_Item.DoesItemExist(self.itemInfo.location) and

    -- Sufficient money to cover deposit
    GetMoney() >= self:GetDeposit() and

    -- Valid quantity
    self.Quantity:GetNumber() > 0 and
    self.Quantity:GetNumber() <= self:GetPostLimit() and

    (
      (
      -- Normal pricing
        -- Positive price
        self.Price:GetAmount() > 0 and

        -- Bid price is not bigger than buyout
        self.BidPrice:GetAmount() < self.Price:GetAmount()
      ) or (
      -- Bid only with no buyout price
        Auctionator.Config.Get(Auctionator.Config.Options.SHOW_SELLING_BID_PRICE) and
        -- Only items can have a bid amount
        self.itemInfo.itemType == Auctionator.Constants.ITEM_TYPES.ITEM and
        -- Only items can have a bid amount
        self.Price:GetAmount() == 0 and
        self.BidPrice:GetAmount() > 0
      )
    ) and

    -- Not throttled (to avoid silent post failure)
    Auctionator.AH.IsNotThrottled() and

    -- Keep disabled for the entire search, including gaps between queued AH
    -- operations where the Blizzard throttle may briefly report ready.
    not self.sellSearchPending and

    -- Posting completion is asynchronous. Keep disabled until the
    -- auction-created event starts the next selection/search.
    not self.manualPostingPending and

    -- Wait for owned auctions to load before enabling to avoid briefly
    -- enabling between the price search and QueryOwnedAuctions.
    not self.ownedAuctionsQueryPending
end

function AuctionatorSaleItemMixin:GetConfirmationMessage(postBuyout)
  local effectiveUnitPrice = postBuyout or self.Price:GetAmount()
  if Auctionator.Config.Get(Auctionator.Config.Options.SHOW_SELLING_BID_PRICE) and effectiveUnitPrice == 0 then
    effectiveUnitPrice = self.BidPrice:GetAmount()
  end

  -- Check if the item was underpriced compared to the currently on sale items
  if self.priceThreshold ~= nil and self.priceThreshold >= effectiveUnitPrice then
    return AUCTIONATOR_L_CONFIRM_POST_LOW_PRICE:format(GetMoneyString(effectiveUnitPrice, true))
  end

  -- Determine if the item is worth more to sell to a vendor than to post on the
  -- AH.
  local itemInfo = { C_Item.GetItemInfo(self.itemInfo.itemLink) }
  local vendorPrice = itemInfo[Auctionator.Constants.ITEM_INFO.SELL_PRICE]
  if Auctionator.Utilities.IsVendorable(itemInfo) and
     vendorPrice * self.Quantity:GetNumber()
       > math.floor(effectiveUnitPrice * self.Quantity:GetNumber() * Auctionator.Constants.AfterAHCut) then
    return AUCTIONATOR_L_CONFIRM_POST_BELOW_VENDOR
  end
end

function AuctionatorSaleItemMixin:RequiresConfirmationState(postBuyout)
  return
    Auctionator.Config.Get(Auctionator.Config.Options.SELLING_CONFIRM_LOW_PRICE) and
    self:GetConfirmationMessage(postBuyout) ~= nil
end

function AuctionatorSaleItemMixin:UpdatePostButtonState()
  self:UpdatePostAndSkipButtonLayout()

  local enabled = self:GetPostButtonState()
  self.PostButton:SetEnabled(enabled)
  self.DiscountZButton:SetEnabled(enabled)
end

function AuctionatorSaleItemMixin:UpdateSkipButtonState()
  self.SkipButton:SetEnabled(self.SkipButton:IsShown() and self.nextItem)
  self.PrevButton:SetEnabled(self.SkipButton:IsShown() and self.prevItem)
end

local AUCTION_DURATIONS = {
  [12] = 1,
  [24] = 2,
  [48] = 3,
}

function AuctionatorSaleItemMixin:GetDuration()
  return AUCTION_DURATIONS[self.Duration:GetValue()]
end

local tryingPosting = nil
local tryingPostingBuyout = nil
local tryingPostingItemID = nil
local tryingPostingPlannedPrice = nil
local pendingPosting = nil
local pendingPostingBuyout = nil
local pendingPostingItemID = nil
local pendingPostingPlannedPrice = nil
local waitingReadyEvent = false
local isCurrentlyPosting = false

function OnCurrentlyPurchasingEvent(self, eventName, ...)
  if tryingPosting then
    if eventName == 'AUCTION_HOUSE_THROTTLED_MESSAGE_SENT' then
      isCurrentlyPosting = true
      return
    end

    if eventName == 'AUCTION_HOUSE_AUCTION_CREATED' then
      pendingPosting = tryingPosting
      pendingPostingBuyout = tryingPostingBuyout
      pendingPostingItemID = tryingPostingItemID
      pendingPostingPlannedPrice = tryingPostingPlannedPrice
      tryingPostingBuyout = nil
      tryingPostingItemID = nil
      tryingPostingPlannedPrice = nil
      tryingPosting = nil
      waitingReadyEvent = true
      return
    end

    if eventName == 'AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED' then
      print('[Dropped]', tryingPosting)
      tryingPostingBuyout = nil
      tryingPostingItemID = nil
      tryingPostingPlannedPrice = nil
      tryingPosting = nil
      isCurrentlyPosting = false
      return
    end

    if eventName == 'AUCTION_HOUSE_POST_ERROR' then
      print('[Error]', tryingPosting)
      tryingPostingBuyout = nil
      tryingPostingItemID = nil
      tryingPostingPlannedPrice = nil
      tryingPosting = nil
      isCurrentlyPosting = false
      return
    end

    if eventName == 'AUCTION_HOUSE_POST_WARNING' then
      print('[Warn]', tryingPosting)
      tryingPostingBuyout = nil
      tryingPostingItemID = nil
      tryingPostingPlannedPrice = nil
      tryingPosting = nil
      isCurrentlyPosting = false
      return
    end
  end

  if waitingReadyEvent then
    if eventName == 'AUCTION_HOUSE_THROTTLED_SYSTEM_READY' then
      C_Timer.After(0.3, function()
        print('[AH Ready]', '('..QtItemsInBag()..' in bag)')
        isCurrentlyPosting = false
        waitingReadyEvent = false
      end)
      return
    end
  end
end

local f = CreateFrame("Frame")
f:RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED")
f:RegisterEvent("AUCTION_HOUSE_POST_ERROR")
f:RegisterEvent("AUCTION_HOUSE_POST_WARNING")
f:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
-- f:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED")
-- f:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED")
f:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT")
f:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
f:SetScript("OnEvent", OnCurrentlyPurchasingEvent)

local function MONEY(money)
  if money == nil then return '0g' end
  return Auctionator.Utilities.CreatePaddedMoneyString(money, true, true)
end

function QtItemsInBag()
  local qtItems = 0

  for bagId = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
    for slotId = 1, C_Container.GetContainerNumSlots(bagId) do
      local itemLink = C_Container.GetContainerItemLink(bagId, slotId)
      if itemLink then
        qtItems = qtItems + 1
      end
    end
  end

  return qtItems
end

function AuctionatorSaleItemMixin:RunAutoLogic()
  local WM = WarbandMoney.addon
	local duration = WM.auctionatorDuration
  local quantity = 1
  local unknownAuctionFallbackPrice = WM.unknownAuctionFallbackPrice or (10000 * WM.g)
  local warbandMoneyPlanActive = WarbandMoney and WarbandMoney.HasPostingPlan and WarbandMoney.HasPostingPlan()

  if WarbandMoney and WarbandMoney.ConsumePlannedPostingPrice and pendingPostingItemID and pendingPostingPlannedPrice then
    WarbandMoney.ConsumePlannedPostingPrice(pendingPostingItemID, pendingPostingPlannedPrice)
    pendingPosting = nil
    pendingPostingBuyout = nil
    pendingPostingItemID = nil
    pendingPostingPlannedPrice = nil
  end

  if isCurrentlyPosting or waitingReadyEvent or tryingPosting then
    return
  end

  isCurrentlyPosting = true

  local saleSlots = {}
  local scanIndex = 0
  for bagId = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
    for slotId = 1, C_Container.GetContainerNumSlots(bagId) do
      local itemLink = C_Container.GetContainerItemLink(bagId, slotId)
      if itemLink then
        scanIndex = scanIndex + 1
        local itemID = C_Item.GetItemIDForItemInfo(itemLink)
        local plannedPostingPrice = nil
        if WarbandMoney and WarbandMoney.PeekPlannedPostingPrice and itemID ~= WM.swordID then
          plannedPostingPrice = WarbandMoney.PeekPlannedPostingPrice(itemID)
        end

        table.insert(saleSlots, {
          bagId = bagId,
          slotId = slotId,
          plannedPostingPrice = plannedPostingPrice,
          scanIndex = scanIndex,
        })
      end
    end
  end

  if warbandMoneyPlanActive then
    table.sort(saleSlots, function(a, b)
      local aPrice = a.plannedPostingPrice or 0
      local bPrice = b.plannedPostingPrice or 0
      if aPrice == bPrice then
        return a.scanIndex < b.scanIndex
      end
      return aPrice > bPrice
    end)
  end

  for _, saleSlot in ipairs(saleSlots) do
    local bagId = saleSlot.bagId
    local slotId = saleSlot.slotId
    local itemLink = C_Container.GetContainerItemLink(bagId, slotId)
    if itemLink then
      local itemID = C_Item.GetItemIDForItemInfo(itemLink)
        local itemName, itemLink, itemRarity, itemLevel = GetItemInfo(itemLink)
        local craftData = CraftInfoAnywhere.API.GetData(itemID, itemLevel)
        local buyout = 0
        local warbandMoneyBuyout = nil
        local plannedPostingPrice = saleSlot.plannedPostingPrice

        local dsprofit = ''
        local overselling = ''

        if plannedPostingPrice then
          warbandMoneyBuyout = plannedPostingPrice
        end

        if warbandMoneyBuyout and warbandMoneyBuyout > 0 then
          buyout = warbandMoneyBuyout
          if craftData and craftData.craftCost then
            dsprofit = MONEY(buyout - craftData.craftCost)
          else
            dsprofit = MONEY(buyout)
          end
        elseif not warbandMoneyPlanActive and craftData and type(WM.minProfitPerItem) == "number" then
          local craftAuctionPrice = craftData.auctionPrice or 0
          local craftProfit = craftData.profit or 0

          if craftAuctionPrice <= 0 then
            craftAuctionPrice = unknownAuctionFallbackPrice
            if craftData.craftCost then
              craftProfit = craftAuctionPrice - craftData.craftCost
            elseif craftProfit <= 0 then
              craftProfit = craftAuctionPrice
            end
          end

          buyout = craftAuctionPrice
          if craftProfit < WM.minProfitPerItem*0.98 then
            buyout = WM.oversellPrice
            if craftData.craftCost then
              craftProfit = WM.oversellPrice - craftData.craftCost
            else
              craftProfit = WM.oversellPrice
            end
            overselling = '[OVERSELLING]'
          end

          dsprofit = MONEY(craftProfit)
        end

        local gold = WM.g

        if itemID == WM.swordID then -- sword item
          local auctionPrice = Auctionator.API.v1.GetAuctionPriceByItemID('AuctionatorSaleItemMixin:RunAutoLogic', itemID)
          local auctionEntry = Auctionator.API.v1.GetAuctionEntryByItemID('AuctionatorSaleItemMixin:RunAutoLogic', itemID)

          local auctionQty = 0
          if auctionEntry and auctionEntry.qty then auctionQty = auctionEntry.qty end

          print('[Sword]', 'price', MONEY(auctionPrice), 'qty', tostring(auctionQty))

          if auctionQty < 1 then
            print('[Sword]', 'no amount, lets set it to max')
            buyout = WM.swordSellMax
          else
            if (auctionPrice < WM.swordBuyFor) then
              print('[Sword]', '[GOOD PRICE, BUT IT]', itemLink, MONEY(auctionPrice))
              -- return
            end
            if auctionPrice <= WM.swordSellMin then
              print('[Sword]', 'current price is too low, lets simply use our max value')
              buyout = WM.swordSellMax
            else
              if auctionPrice > WM.swordSellMax then
                print('[Sword]', 'current price is too high, lets get half of it')
                buyout = math.floor(auctionPrice/2)
                print('[Sword]', 'new price', MONEY(buyout))
                if buyout <= WM.swordSellMin then
                  print('[Sword]', 'new price is still WAY low, lets just use our max')
                  buyout = WM.swordSellMax
                  print('[Sword]', 'new price', MONEY(buyout))
                end
                if buyout >= WM.swordSellMaxMax then
                  print('[Sword]', 'new price is still WAY high, lets use our max max')
                  buyout = WM.swordSellMaxMax
                  print('[Sword]', 'new price', MONEY(buyout))
                end
              else
                print('[Sword]', 'current price is good, lets use it')
                buyout = auctionPrice - gold
              end
            end
          end

          dsprofit = MONEY(buyout)
        end

        if buyout > 0 then
          buyout = math.floor(buyout/gold)*gold

          local location = ItemLocation:CreateFromBagAndSlot(bagId, slotId)
          tryingPosting = itemLink
          tryingPostingBuyout = buyout
          tryingPostingItemID = itemID
          tryingPostingPlannedPrice = plannedPostingPrice

          print('[Posting]', itemLink, Auctionator.Utilities.CreatePaddedMoneyString(buyout, true, true))
          C_AuctionHouse.PostItem(location, duration, quantity, nil, buyout)
          C_Timer.After(5, function()
            if tryingPosting == itemLink then
              print('[AH Dropped]')
              tryingPostingBuyout = nil
              tryingPostingItemID = nil
              tryingPostingPlannedPrice = nil
              tryingPosting = nil
              isCurrentlyPosting = false
            end
          end)

          return
        end
    end
  end

  isCurrentlyPosting = false

  if AuctionatorShoppingFrame:RunInitialAutoLogicPrefetch() then
    return
  end

  AuctionatorShoppingFrame:RunAutoLogic()
end

function AuctionatorSaleItemMixin:GetPercentDiscountPrice(multiplier)
  local currentPrice = self:GetHistoricalDiscountPrice()

  if currentPrice == nil then
    -- Do not apply discount if the cheapest price is from the current character
    if self.cheapestCommodityResult and self.cheapestCommodityResult.containsOwnerItem and self.cheapestCommodityResult.owners[1] == "player" then
      return nil
    end

    local itemKey = self.expectedItemKey

    if C_AuctionHouse.GetNumItemSearchResults(itemKey) > 0 then
      local result = C_AuctionHouse.GetItemSearchResultInfo(itemKey, 1)
      local isOwner = result.containsOwnerItem and result.owners[1] == "player"
      if isOwner then
        return nil
      end
    end

    currentPrice = self.Price:GetAmount()
  end

  if currentPrice > 0 then
    -- Calculate the discounted price and round up
    local discountedPrice = math.ceil(currentPrice * multiplier)
    -- Normalize the price to meet AH requirements
    return NormalizePrice(discountedPrice)
  end

  return nil
end

function AuctionatorSaleItemMixin:GetHistoricalDiscountPrice()
  local parent = self:GetParent()
  if self.itemInfo == nil or parent == nil or parent.PricesTabsContainer == nil or not parent.PricesTabsContainer:IsPriceHistoryView() then
    return nil
  end

  local historicalPriceProvider = parent.HistoricalPriceProvider
  if historicalPriceProvider == nil or historicalPriceProvider.currentItemLink ~= self.itemInfo.itemLink or historicalPriceProvider.lastDBKey == nil then
    return nil
  end

  local historicalPrices = Auctionator.Database:GetPriceHistory(historicalPriceProvider.lastDBKey)
  local lowestHistoricalPrice = nil

  for _, historicalPrice in ipairs(historicalPrices) do
    if historicalPrice.minSeen ~= nil and (
      lowestHistoricalPrice == nil or
      historicalPrice.minSeen < lowestHistoricalPrice
    ) then
      lowestHistoricalPrice = historicalPrice.minSeen
    end
  end

  return lowestHistoricalPrice
end

function AuctionatorSaleItemMixin:ApplyExpiredSinceLastSaleDiscount()
  if self:ShouldSwapPostAndSkipButtons() then
    self:SkipItem()
    return
  end
  local expiredCount = GetExpiredSinceLastSale(self.itemInfo)
  local discountPercent = math.min(math.max(expiredCount, 0), 20)
  local discountedPrice = self:GetPercentDiscountPrice(1 - (discountPercent / 100))
  self:PostItem(false, discountedPrice)
end

function AuctionatorSaleItemMixin:PostItem(confirmed, requestedBuyout)
  if not confirmed then
    self.pendingPostBuyout = requestedBuyout
  end

  local postBuyout = self.pendingPostBuyout or self.Price:GetAmount()

  if not self:GetPostButtonState() then
    self.pendingPostBuyout = nil
    Auctionator.Debug.Message("Trying to post when we can't. Returning")
    return
  elseif not confirmed and self:RequiresConfirmationState(postBuyout) then
    if self.SkipButton:IsEnabled() then
      StaticPopupDialogs[Auctionator.Constants.DialogNames.SellingConfirmPostSkip].text = self:GetConfirmationMessage(postBuyout)
      StaticPopup_Show(Auctionator.Constants.DialogNames.SellingConfirmPostSkip)
    else
      StaticPopupDialogs[Auctionator.Constants.DialogNames.SellingConfirmPost].text = self:GetConfirmationMessage(postBuyout)
      StaticPopup_Show(Auctionator.Constants.DialogNames.SellingConfirmPost)
    end
    return
  end

  local quantity = self.Quantity:GetNumber()
  local duration = self:GetDuration()
  local startingBid = self.BidPrice:GetAmount()
  local buyout = postBuyout
  local bidAmountReported = nil -- Only includes bid price when non-zero and for an item
  self.pendingPostBuyout = nil

  self.manualPostingPending = true
  self.pendingPostNextItem = nil
  if Auctionator.Config.Get(Auctionator.Config.Options.SELLING_AUTO_SELECT_NEXT) then
    self.pendingPostNextItem = self.nextItem
  end
  self:UpdatePostButtonState()

  self.MultisellProgress:SetDetails(self.itemInfo.iconTexture, quantity)

  if not self.itemInfo.isCommodity then
    local params = nil
    if startingBid ~= 0 then
      bidAmountReported = startingBid
      params = {self.itemInfo.location, duration, quantity, startingBid, buyout ~= 0 and buyout or nil}
    else
      params = {self.itemInfo.location, duration, quantity, nil, buyout}
    end
    -- Accomodate 9.2.7 dialog for when the AH requires confirmation before the
    -- commodities AH region merge.
    if C_AuctionHouse.PostItem(unpack(params)) then
      AuctionHouseFrame.ItemSellFrame:CachePendingPost(unpack(params))
    end
  else
    local params = {self.itemInfo.location, duration, quantity, buyout}
    -- Accomodate 9.2.7 dialog for when the AH requires confirmation before the
    -- commodities AH region merge.
    if C_AuctionHouse.PostCommodity(unpack(params)) then
      AuctionHouseFrame.CommoditiesSellFrame:CachePendingPost(unpack(params))
    end
  end

  local postedInfo = {
    itemLink = self.itemInfo.itemLink,
    quantity = quantity,
    buyoutAmount = buyout,
    bidAmount = bidAmountReported,
  }

  --Print auction to chat
  if Auctionator.Config.Get(Auctionator.Config.Options.AUCTION_CHAT_LOG) then
    Auctionator.Utilities.Message(Auctionator.Selling.ComposeAuctionPostedMessage(postedInfo))
  end

  Auctionator.EventBus:Fire(self,
    Auctionator.Selling.Events.AuctionCreated,
    postedInfo
  )

  -- If there aren't any other auctions or this item is posted lower than the
  -- existing auctions then this item has become the new price for the item
  local priceToSave = postedInfo.buyoutAmount
  if postedInfo.buyoutAmount == 0 then
    priceToSave = postedInfo.bidAmount
  end
  if self.itemInfo.existingValue == nil or self.itemInfo.existingValue > priceToSave then
    Auctionator.Utilities.DBKeyFromLink(self.itemInfo.itemLink, function(dbKeys)
      for _, key in ipairs(dbKeys) do
        Auctionator.Database:SetPrice(key, priceToSave)
        if self.itemInfo.isCommodity and Auctionator.GlobalDatabase ~= nil then
          Auctionator.GlobalDatabase:SetPrice(key, priceToSave)
        end
      end
      -- Refresh history listing after the new price is saved
      Auctionator.EventBus:Fire(self, Auctionator.Selling.Events.RefreshHistory)
    end)
  else
    -- Refresh history (posting and price history)
    Auctionator.EventBus:Fire(self, Auctionator.Selling.Events.RefreshHistory)
  end

  if Auctionator.Config.Get(Auctionator.Config.Options.SAVE_LAST_DURATION_AS_DEFAULT) then
    Auctionator.Config.Set(Auctionator.Config.Options.AUCTION_DURATION, self.Duration:GetValue())
  end

  -- Save item info for refreshing search results
  self.lastItemInfo = self.itemInfo
  -- Refresh the controls without starting another search. The single
  -- post-processing search/selection is started after the Blizzard posting
  -- event and throttle completion.
  self:Reset(true)
end

function AuctionatorSaleItemMixin:SkipItem()
  if self.SkipButton:IsEnabled() then
    local skippedItemLink = self.itemInfo and self.itemInfo.itemLink
    if skippedItemLink then
      Auctionator.Groups.TempHideItemLink(skippedItemLink)
    end

    Auctionator.EventBus:Fire(
      self, Auctionator.Selling.Events.BagItemRequest, self.nextItem
    )

    if skippedItemLink then
      Auctionator.Groups.CallbackRegistry:TriggerEvent("Customise.EditMade")
    end
  end
end

function AuctionatorSaleItemMixin:PrevItem()
  if self.PrevButton:IsEnabled() then
    Auctionator.EventBus:Fire(
      self, Auctionator.Selling.Events.BagItemRequest, self.prevItem
    )
  end
end

function AuctionatorSaleItemMixin:RefreshButtonClicked()
  -- Search for the current item or the last item posted
  if self.itemInfo ~= nil then
    self:DoSearch(self.itemInfo)
  elseif self.lastItemInfo ~= nil then
    self:DoSearch(self.lastItemInfo)
  end
end
