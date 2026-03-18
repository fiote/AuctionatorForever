AuctionatorShoppingTabFrameMixin = {}

local EVENTBUS_EVENTS = {
  Auctionator.Shopping.Events.ListImportFinished,
  Auctionator.Shopping.Tab.Events.ListSearchRequested,
  Auctionator.Shopping.Tab.Events.ShowHistoricalPrices,
  Auctionator.Shopping.Tab.Events.UpdateSearchTerm,
  Auctionator.Shopping.Tab.Events.BuyScreenShown,
  Auctionator.Shopping.Tab.Events.SearchEnd,
  Auctionator.Shopping.Tab.Events.AutoBuyCommodityPurchaseSucceeded,
  Auctionator.Shopping.Tab.Events.AutoBuyCommodityPurchaseFailed,
}

local AUTO_BUY_LIST_NAME = "[__] X to Buy"
local initialAutoLogicPrefetchDone = false
local initialAutoLogicPrefetchPending = false

local function AutoBuyPrint(...)
  print("[AutoBuy]", ...)
end

local function AutoBuyFormatPrice(money)
  return GetMoneyString(money or 0, true)
end

local function TermsMatch(left, right)
  if left == nil or right == nil or #left ~= #right then
    return false
  end

  for index = 1, #left do
    if left[index] ~= right[index] then
      return false
    end
  end

  return true
end

local function ItemKeysMatch(left, right)
  if left == nil or right == nil then
    return false
  end

  return Auctionator.Utilities.ItemKeyString(left) == Auctionator.Utilities.ItemKeyString(right)
end

local function GetSearchTermMaxPrice(searchTerm)
  local parsed = Auctionator.Search.SplitAdvancedSearch(searchTerm)
  return parsed and parsed.maxPrice or nil
end

local function GetSearchTermQuantity(searchTerm)
  local parsed = Auctionator.Search.SplitAdvancedSearch(searchTerm)
  if parsed and parsed.quantity ~= nil and parsed.quantity > 0 then
    return parsed.quantity
  end

  return 1
end

function AuctionatorShoppingTabFrameMixin:DoSearch(terms, options)
  if #terms == 0 then
    return
  end

  if options == nil and Auctionator.Constants.IsClassic and IsShiftKeyDown() then
    options = { searchAllPages = true }
  end

  self:StopSearch()
  self.lastPreventedRowRetried = nil

  if self.pendingAutoBuySearch == nil then
    self.autoBuyResultsReady = false
    self.autoBuyLoadedTerms = nil
  end

  if ResetAutoBuyFlowState then
    ResetAutoBuyFlowState()
  end

  self.searchRunning = true
  Auctionator.EventBus
    :RegisterSource(self, "AuctionatorShoppingTabFrameMixin")
    :Fire(self, Auctionator.Shopping.Tab.Events.SearchStart, terms)
    :UnregisterSource(self)
  self.SearchProvider:Search(terms, options or {})
  self:StartSpinner()
end

function AuctionatorShoppingTabFrameMixin:GetAutoBuyList()
  local listIndex = Auctionator.Shopping.ListManager:GetIndexForName(AUTO_BUY_LIST_NAME)
  if listIndex == nil then
    return nil
  end

  return Auctionator.Shopping.ListManager:GetByIndex(listIndex)
end

function AuctionatorShoppingTabFrameMixin:AdvanceAutoBuyIndex(list, currentIndex)
  local itemCount = list and list:GetItemCount() or 0
  if itemCount == 0 then
    self.autoBuyNextIndex = 1
  else
    self.autoBuyNextIndex = currentIndex % itemCount + 1
  end
end

function AuctionatorShoppingTabFrameMixin:InvalidateAutoBuyResults()
  self.autoBuyResultsReady = false
  self.autoBuyLoadedTerms = nil
end

function AuctionatorShoppingTabFrameMixin:CommitAutoBuyPurchase(index, searchTerm, purchasedQuantity)
  local remainingQuantity = math.max(0, self:GetRemainingAutoBuyQuantity(index, searchTerm) - (purchasedQuantity or 0))
  self:SetRemainingAutoBuyQuantity(index, searchTerm, remainingQuantity)
  self:InvalidateAutoBuyResults()
  return remainingQuantity
end

function AuctionatorShoppingTabFrameMixin:CompleteAutoBuyEntry(index)
  local shoppingList = self:GetAutoBuyList()
  if shoppingList ~= nil and shoppingList:GetItemCount() > 0 then
    self:AdvanceAutoBuyIndex(shoppingList, index)
  end
end

function AuctionatorShoppingTabFrameMixin:SyncAutoBuyRemainingQuantities(list)
  local itemCount = list and list:GetItemCount() or 0

  for index = 1, itemCount do
    local searchTerm = list:GetItemByIndex(index)
    local targetQuantity = GetSearchTermQuantity(searchTerm)
    local state = self.autoBuyRemainingQuantities[index]

    if state == nil or state.searchTerm ~= searchTerm then
      self.autoBuyRemainingQuantities[index] = {
        searchTerm = searchTerm,
        quantity = targetQuantity,
      }
    else
      state.quantity = math.max(0, math.min(state.quantity or targetQuantity, targetQuantity))
    end
  end

  for index = itemCount + 1, #self.autoBuyRemainingQuantities do
    self.autoBuyRemainingQuantities[index] = nil
  end
end

function AuctionatorShoppingTabFrameMixin:GetRemainingAutoBuyQuantity(index, searchTerm)
  local state = self.autoBuyRemainingQuantities[index]
  if state == nil or state.searchTerm ~= searchTerm then
    state = {
      searchTerm = searchTerm,
      quantity = GetSearchTermQuantity(searchTerm),
    }
    self.autoBuyRemainingQuantities[index] = state
  end

  return state.quantity
end

function AuctionatorShoppingTabFrameMixin:SetRemainingAutoBuyQuantity(index, searchTerm, quantity)
  local state = self.autoBuyRemainingQuantities[index]
  if state == nil or state.searchTerm ~= searchTerm then
    state = {
      searchTerm = searchTerm,
      quantity = GetSearchTermQuantity(searchTerm),
    }
    self.autoBuyRemainingQuantities[index] = state
  end

  state.quantity = math.max(0, quantity or 0)
end

function AuctionatorShoppingTabFrameMixin:IsAutoBuyBusy()
  return self.pendingAutoBuySearch ~= nil or
    self.pendingAutoBuyItemPurchase ~= nil or
    self.pendingAutoBuyCommodityPurchase ~= nil or
    (IsShoppingPurchaseInProgress ~= nil and IsShoppingPurchaseInProgress())
end

function AuctionatorShoppingTabFrameMixin:RunAutoLogic()
  local shoppingList = self:GetAutoBuyList()
  if shoppingList == nil or shoppingList:GetItemCount() == 0 then
    AutoBuyPrint("Shopping list not found or empty:", AUTO_BUY_LIST_NAME)
    return false
  end

  if self.searchRunning or self:IsAutoBuyBusy() then
    AutoBuyPrint("Waiting for the current search or purchase to finish.")
    return true
  end

  local terms = shoppingList:GetAllItems()
  self:SyncAutoBuyRemainingQuantities(shoppingList)
  if not self.autoBuyResultsReady or not TermsMatch(self.autoBuyLoadedTerms, terms) then
    self.pendingAutoBuySearch = {
      listName = shoppingList:GetName(),
      terms = CopyTable(terms),
    }
    AutoBuyPrint("Fetching shopping results for", shoppingList:GetName() .. ".")
    self:DoSearch(terms)
    return true
  end

  local itemCount = shoppingList:GetItemCount()
  local startIndex = math.min(self.autoBuyNextIndex or 1, itemCount)

  for offset = 0, itemCount - 1 do
    local index = ((startIndex + offset - 1) % itemCount) + 1
    local searchTerm = shoppingList:GetItemByIndex(index)
    if type(searchTerm) == "string" and searchTerm ~= "" then
      local actionResult = self:TryBuyAutoBuySearchTerm(index, searchTerm)
      if actionResult == "advance" then
        self:AdvanceAutoBuyIndex(shoppingList, index)
        return true
      elseif actionResult == "hold" then
        return true
      end
    end
  end

  AutoBuyPrint("No affordable auctions found in the loaded X-to-Buy results.")
  return false
end

function AuctionatorShoppingTabFrameMixin:RunInitialAutoLogicPrefetch()
  if initialAutoLogicPrefetchDone then
    return false
  end

  if initialAutoLogicPrefetchPending or self.searchRunning then
    return true
  end

  if Auctionator.Shopping.ListManager:GetCount() == 0 then
    initialAutoLogicPrefetchDone = true
    return false
  end

  local shoppingList = Auctionator.Shopping.ListManager:GetByIndex(1)
  if shoppingList == nil then
    initialAutoLogicPrefetchDone = true
    return false
  end

  initialAutoLogicPrefetchPending = true
  AutoBuyPrint("Initial prefetch:", shoppingList:GetName())
  self:DoSearch(shoppingList:GetAllItems())
  return true
end


function AuctionatorShoppingTabFrameMixin:StopSearch()
  self.searchRunning = false
  self.SearchProvider:AbortSearch()
end

function AuctionatorShoppingTabFrameMixin:StartSpinner()
  self.ListsContainer.SpinnerAnim:Play()
  self.ListsContainer.LoadingSpinner:Show()
  self.ListsContainer.ResultsText:SetText(Auctionator.Locales.Apply("LIST_SEARCH_START", self:GetAppropriateListSearchName()))
  self.ListsContainer.ResultsText:Show()
end

function AuctionatorShoppingTabFrameMixin:CloseAnyDialogs()
  for _, d in ipairs(self.dialogs) do
    if d:IsShown() then
      d:Hide()
    end
  end
end

function AuctionatorShoppingTabFrameMixin:OnLoad()
  Auctionator.EventBus:RegisterSource(self, "AuctionatorShoppingTabFrameMixin")

  self.ResultsListing:Init(self.DataProvider)
  self.autoBuyNextIndex = 1
  self.autoBuyResultsReady = false
  self.autoBuyLoadedTerms = nil
  self.autoBuyRemainingQuantities = {}
  self.pendingAutoBuySearch = nil
  self.pendingAutoBuyItemPurchase = nil
  self.pendingAutoBuyCommodityPurchase = nil

  self.dialogs = {}

  self.itemDialog = CreateFrame("Frame", "AuctionatorShoppingTabItemFrame", self, "AuctionatorShoppingItemTemplate")
  self.itemDialog:SetPoint("CENTER")
  table.insert(self.dialogs, self.itemDialog)

  self.exportDialog = CreateFrame("Frame", "AuctionatorExportListFrame", self, "AuctionatorExportListTemplate")
  self.exportDialog:SetPoint("CENTER")
  table.insert(self.dialogs, self.exportDialog)

  self.importDialog = CreateFrame("Frame", "AuctionatorImportListFrame", self, "AuctionatorImportListTemplate")
  self.importDialog:SetPoint("CENTER")
  table.insert(self.dialogs, self.importDialog)

  self.exportCSVDialog = CreateFrame("Frame", nil, self, "AuctionatorExportTextFrame")
  self.exportCSVDialog:SetPoint("CENTER")
  table.insert(self.dialogs, self.exportCSVDialog)

  self.ExportButton:SetScript("OnClick", function()
    self:CloseAnyDialogs()
    self.exportDialog:Show()
  end)
  self.ImportButton:SetScript("OnClick", function()
    self:CloseAnyDialogs()
    self.importDialog:Show()
  end)

  self.itemHistoryDialog = CreateFrame("Frame", "AuctionatorItemHistoryFrame", self, "AuctionatorItemHistoryTemplate")
  self.itemHistoryDialog:SetPoint("CENTER")
  self.itemHistoryDialog:Init()

  self:SetupSearchProvider()

  self:SetupListsContainer()
  self:SetupRecentsContainer()
  self:SetupTopSearch()

  self.NewListButton:SetScript("OnClick", function()
    Auctionator.Dialogs.ShowEditBox(AUCTIONATOR_L_CREATE_LIST_DIALOG, ACCEPT, CANCEL, function(text)
      local name = Auctionator.Shopping.ListManager:GetUnusedName(text)
      Auctionator.Shopping.ListManager:Create(name)
      self.ListsContainer:ExpandList(Auctionator.Shopping.ListManager:GetByName(name))
    end)
  end)

  self.ContainerTabs:SetView(Auctionator.Config.Get(Auctionator.Config.Options.SHOPPING_LAST_CONTAINER_VIEW))

  self.shouldDefaultOpenOnShow = true
  self:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
  self:RegisterEvent("AUCTION_HOUSE_NEW_BID_RECEIVED")
  self:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
  if Auctionator.Constants.IsVanilla then
    self:RegisterEvent("AUCTION_HOUSE_CLOSED")
  else
    self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
  end
end

function AuctionatorShoppingTabFrameMixin:SetupSearchProvider()
  self.SearchProvider:InitSearch(
    function(results)
      self.searchRunning = false
      if initialAutoLogicPrefetchPending then
        initialAutoLogicPrefetchPending = false
        initialAutoLogicPrefetchDone = true
        AutoBuyPrint("Initial prefetch completed.")
      end
      if self.pendingAutoBuySearch ~= nil then
        self.autoBuyResultsReady = true
        self.autoBuyLoadedTerms = self.pendingAutoBuySearch.terms
        AutoBuyPrint("X-to-Buy results ready:", #results, "matches.")
        self.pendingAutoBuySearch = nil
        self:PrimeAutoBuyItemPurchase()
      end
      Auctionator.EventBus
        :RegisterSource(self, "AuctionatorShoppingTabFrameMixin")
        :Fire(self, Auctionator.Shopping.Tab.Events.SearchEnd, results)
        :UnregisterSource(self)
      self.ListsContainer.SpinnerAnim:Stop()
      self.ListsContainer.LoadingSpinner:Hide()
      self.ListsContainer.ResultsText:Hide()
	    FlashClientIcon()
      PlaySoundFile(567286)
    end,
    function(current, total, partialResults)
      Auctionator.EventBus
        :RegisterSource(self, "AuctionatorShoppingTabFrameMixin")
        :Fire(self, Auctionator.Shopping.Tab.Events.SearchIncrementalUpdate, partialResults, total, current)
        :UnregisterSource(self)
      self.ListsContainer.ResultsText:SetText(Auctionator.Locales.Apply("LIST_SEARCH_STATUS", current, total, self:GetAppropriateListSearchName()))
    end
  )
end

function AuctionatorShoppingTabFrameMixin:SetupListsContainer()
  self.ListsContainer:SetOnListExpanded(function()
    if Auctionator.Config.Get(Auctionator.Config.Options.AUTO_LIST_SEARCH) then
      self.singleSearch = false
      self:DoSearch(self.ListsContainer:GetExpandedList():GetAllItems())
    end
    self.SearchOptions:OnListExpanded()
  end)
  self.ListsContainer:SetOnListCollapsed(function()
    self:StopSearch()
    self.SearchOptions:OnListCollapsed()
  end)
  self.ListsContainer:SetOnSearchTermClicked(function(list, searchTerm, index)
    self.singleSearch = true
    self:DoSearch({searchTerm})
    self.SearchOptions:SetSearchTerm(searchTerm)
    self.ListsContainer:TemporarilySelectSearchTerm(index)
  end)
  self.ListsContainer:SetOnSearchTermDelete(function(list, searchTerm, index)
    list:DeleteItem(index)
  end)
  self.ListsContainer:SetOnSearchTermEdit(function(list, searchTerm, index)
    self:CloseAnyDialogs()
    self.itemDialog:Init(AUCTIONATOR_L_LIST_EDIT_ITEM_HEADER, AUCTIONATOR_L_EDIT_ITEM)
    self.itemDialog:SetOnFinishedClicked(function(newItemString)
      list:AlterItem(index, newItemString)
    end)
    self.itemDialog:Show()
    self.itemDialog:SetItemString(searchTerm)
  end)
  self.ListsContainer:SetOnListSearch(function(list)
    self.singleSearch = false
    self:DoSearch(list:GetAllItems())
  end)
  self.ListsContainer:SetOnListEdit(function(list)
    if list:IsTemporary() then
      Auctionator.Dialogs.ShowEditBox(AUCTIONATOR_L_MAKE_PERMANENT_CONFIRM:format(list:GetName()), ACCEPT, CANCEL, function(text)
        list:Rename(text)
        list:MakePermanent()
        Auctionator.Shopping.ListManager:Sort()
        self.ListsContainer:ScrollToList(list)
      end)
    else
      Auctionator.Dialogs.ShowEditBox(AUCTIONATOR_L_RENAME_LIST_CONFIRM:format(list:GetName()), ACCEPT, CANCEL, function(text)
        list:Rename(text)
        Auctionator.Shopping.ListManager:Sort()
        self.ListsContainer:ScrollToList(list)
      end)
    end
  end)
  self.ListsContainer:SetOnListDelete(function(list)
    Auctionator.Dialogs.ShowConfirm(AUCTIONATOR_L_DELETE_LIST_CONFIRM:format(list:GetName()):gsub("%%", "%%%%"), ACCEPT, CANCEL, function()
      if Auctionator.Shopping.ListManager:GetIndexForName(list:GetName()) ~= nil then
        Auctionator.Shopping.ListManager:Delete(list:GetName())
      end
    end)
  end)

  self.ListsContainer:SetOnListItemDrag(function(list, oldIndex, newIndex)
    if oldIndex ~= newIndex then
      local old = list:GetItemByIndex(oldIndex)
      list:DeleteItem(oldIndex)
      list:InsertItem(old, newIndex)
    end
  end)
end

function AuctionatorShoppingTabFrameMixin:SetupRecentsContainer()
  self.RecentsContainer:SetOnSearchRecent(function(searchTerm)
    self.singleSearch = true
    self:DoSearch({searchTerm})
    self.SearchOptions:SetSearchTerm(searchTerm)
    self.RecentsContainer:TemporarilySelectSearchTerm(searchTerm)
  end)
  self.RecentsContainer:SetOnDeleteRecent(function(searchTerm)
    Auctionator.Shopping.Recents.DeleteEntry(searchTerm)
  end)
  self.RecentsContainer:SetOnCopyRecent(function(searchTerm)
    local list = self.ListsContainer:GetExpandedList()
    if list == nil then
      Auctionator.Utilities.Message(AUCTIONATOR_L_COPY_NO_LIST_SELECTED)
    else
      list:InsertItem(searchTerm)
      Auctionator.Utilities.Message(AUCTIONATOR_L_COPY_ITEM_ADDED:format(
        GREEN_FONT_COLOR:WrapTextInColorCode(Auctionator.Search.PrettifySearchString(searchTerm)),
        GREEN_FONT_COLOR:WrapTextInColorCode(list:GetName())
      ))
    end
  end)
end

function AuctionatorShoppingTabFrameMixin:SetupTopSearch()
  self.lastPreventedRowRetried = nil

  self.SearchOptions:SetOnSearch(function(searchTerm)
    if self.searchRunning then
      self:StopSearch()
    elseif searchTerm == "" and self.ListsContainer:GetExpandedList() ~= nil then
      self:DoSearch(self.ListsContainer:GetExpandedList():GetAllItems())
    else
      self.singleSearch = true
      self:DoSearch({searchTerm})
      Auctionator.Shopping.Recents.Save(searchTerm)
    end
  end)
  self.SearchOptions:SetOnMore(function(searchTerm)
    self:CloseAnyDialogs()
    self.itemDialog:Init(AUCTIONATOR_L_LIST_EXTENDED_SEARCH_HEADER, AUCTIONATOR_L_SEARCH)
    self.itemDialog:SetOnFinishedClicked(function(searchTerm)
      self.SearchOptions:SetSearchTerm(searchTerm)
      self.singleSearch = true
      self:DoSearch({searchTerm})
      Auctionator.Shopping.Recents.Save(searchTerm)
    end)

    self.itemDialog:Show()
    self.itemDialog:SetItemString(searchTerm)
  end)
  self.SearchOptions:SetOnAddToList(function(searchTerm)
    self.ListsContainer:GetExpandedList():InsertItem(searchTerm)
    self.ListsContainer:ScrollToListEnd()
  end)

  self.SearchOptions:SetOnSmartBuy(function()
    self:SmartBuyNextRow()
  end)
end

function AuctionatorShoppingTabFrameMixin:FindAutoBuyResult(searchTerm)
  local bestMatch = nil

  for _, rowData in ipairs(self.DataProvider.results or {}) do
    if rowData.searchTerm == searchTerm and (rowData.totalQuantity or 0) > 0 then
      if bestMatch == nil or rowData.minPrice < bestMatch.minPrice then
        bestMatch = rowData
      end
    end
  end

  return bestMatch
end

function AuctionatorShoppingTabFrameMixin:GetAutoBuyItemFrame()
  return Auctionator.State and Auctionator.State.BuyItemFrameRef or nil
end

function AuctionatorShoppingTabFrameMixin:GetNextAutoBuyItemAuction(purchaseState)
  local itemFrame = self:GetAutoBuyItemFrame()
  if itemFrame == nil or itemFrame.DataProvider == nil then
    return nil, "waiting"
  end

  if itemFrame.expectedItemKey == nil or not ItemKeysMatch(itemFrame.expectedItemKey, purchaseState.itemKey) then
    return nil, "waiting"
  end

  if not C_AuctionHouse.HasSearchResults(purchaseState.itemKey) or
     not C_AuctionHouse.HasFullItemSearchResults(purchaseState.itemKey) then
    return nil, "waiting"
  end

  for _, rowData in ipairs(itemFrame.DataProvider.results or {}) do
    if not purchaseState.seenAuctionIDs[rowData.auctionID] and
       rowData.canBuy and
       rowData.price ~= nil and
       (purchaseState.maxPrice == nil or rowData.price <= purchaseState.maxPrice) and
       rowData.quantity > 0 and
       rowData.quantity <= purchaseState.remainingQuantity then
      return rowData
    end
  end

  return nil, "nomatch"
end

function AuctionatorShoppingTabFrameMixin:TryBuyAutoBuySearchTerm(index, searchTerm)
  local quantity = self:GetRemainingAutoBuyQuantity(index, searchTerm)
  if quantity <= 0 then
    AutoBuyPrint("Target quantity reached for", Auctionator.Search.PrettifySearchString(searchTerm) .. ".")
    return "advance"
  end

  local rowData = self:FindAutoBuyResult(searchTerm)
  if rowData == nil then
    AutoBuyPrint("No current result for", Auctionator.Search.PrettifySearchString(searchTerm) .. ".")
    return false
  end

  local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(rowData.itemKey)
  if itemKeyInfo == nil then
    AutoBuyPrint("Item data is not ready for", Auctionator.Search.PrettifySearchString(searchTerm) .. ".")
    return false
  end

  if itemKeyInfo.isCommodity then
    local purchaseQuantity = math.min(quantity, rowData.totalQuantity or quantity)
    AutoBuyPrint(
      "Buying",
      tostring(purchaseQuantity),
      "x",
      Auctionator.Search.PrettifySearchString(searchTerm),
      "at",
      AutoBuyFormatPrice(rowData.minPrice),
      "each."
    )
    if PurchaseCommodity(nil, itemKeyInfo.itemID, purchaseQuantity, rowData.minPrice, nil) then
      self.pendingAutoBuyCommodityPurchase = {
        itemID = itemKeyInfo.itemID,
        listIndex = index,
        searchTerm = searchTerm,
        quantity = purchaseQuantity,
      }
      return "hold"
    end

    AutoBuyPrint("Could not start the commodity purchase for", Auctionator.Search.PrettifySearchString(searchTerm) .. ".")
    return "hold"
  end

  if self.pendingAutoBuyItemPurchase ~= nil and
     self.pendingAutoBuyItemPurchase.listIndex == index and
     ItemKeysMatch(self.pendingAutoBuyItemPurchase.itemKey, rowData.itemKey) then
    AutoBuyPrint("Attempting to buy", Auctionator.Search.PrettifySearchString(searchTerm) .. ".")
    return self:PlaceNextAutoBuyItemBid()
  end

  AutoBuyPrint("Opening item results for", Auctionator.Search.PrettifySearchString(searchTerm) .. ".")
  self:StartAutoBuyItemPurchase(rowData, index, searchTerm, quantity)
  return "hold"
end

function AuctionatorShoppingTabFrameMixin:StartAutoBuyItemPurchase(rowData, index, searchTerm, quantity)
  self.pendingAutoBuyItemPurchase = {
    itemKey = rowData.itemKey,
    quantity = quantity,
    remainingQuantity = quantity,
    searchTerm = searchTerm,
    listIndex = index,
    maxPrice = GetSearchTermMaxPrice(searchTerm),
    seenAuctionIDs = {},
    waitingForPurchaseResult = false,
    waitingForResultRefresh = false,
    pendingAuctionID = nil,
    pendingAuctionQuantity = nil,
  }

  local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(rowData.itemKey)
  if itemKeyInfo == nil then
    AutoBuyPrint("Item data is not ready for", Auctionator.Search.PrettifySearchString(searchTerm) .. ".")
    self.pendingAutoBuyItemPurchase = nil
    return
  end

  Auctionator.EventBus
    :RegisterSource(self, "ShoppingTabAutoBuy")
    :Fire(self, Auctionator.Buying.Events.ShowItemBuy, rowData, itemKeyInfo)
    :Fire(self, Auctionator.Shopping.Tab.Events.BuyScreenShown)
    :UnregisterSource(self)
end

function AuctionatorShoppingTabFrameMixin:PrimeAutoBuyItemPurchase()
  local shoppingList = self:GetAutoBuyList()
  if shoppingList == nil or shoppingList:GetItemCount() == 0 or self.pendingAutoBuyItemPurchase ~= nil then
    return
  end

  local currentIndex = math.min(self.autoBuyNextIndex or 1, shoppingList:GetItemCount())
  local searchTerm = shoppingList:GetItemByIndex(currentIndex)
  local rowData = searchTerm and self:FindAutoBuyResult(searchTerm) or nil
  if rowData == nil then
    AutoBuyPrint("Current X-to-Buy entry has no result yet.")
    return
  end

  local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(rowData.itemKey)
  if itemKeyInfo ~= nil and not itemKeyInfo.isCommodity then
    local remainingQuantity = self:GetRemainingAutoBuyQuantity(currentIndex, searchTerm)
    if remainingQuantity <= 0 then
      AutoBuyPrint("Current X-to-Buy entry is already complete.")
      return
    end

    AutoBuyPrint("Opening the current item entry for exact auction results.")
    self:StartAutoBuyItemPurchase(rowData, currentIndex, searchTerm, remainingQuantity)
  end
end

function AuctionatorShoppingTabFrameMixin:PlaceNextAutoBuyItemBid()
  local purchaseState = self.pendingAutoBuyItemPurchase
  if purchaseState == nil then
    AutoBuyPrint("No item purchase is queued right now.")
    return false
  end

  if purchaseState.waitingForPurchaseResult or purchaseState.waitingForResultRefresh then
    AutoBuyPrint("Waiting for the last item purchase to finish refreshing.")
    return "hold"
  end

  local nextAuction, status = self:GetNextAutoBuyItemAuction(purchaseState)
  if status == "waiting" then
    AutoBuyPrint("Waiting for exact item results before bidding.")
    return "hold"
  end

  if nextAuction == nil then
    AutoBuyPrint("No matching item auctions remain for this entry.")
    self.pendingAutoBuyItemPurchase = nil
    return "advance"
  end

  AutoBuyPrint("Placing bid at", AutoBuyFormatPrice(nextAuction.price) .. ".")
  purchaseState.pendingAuctionID = nextAuction.auctionID
  purchaseState.pendingAuctionQuantity = nextAuction.quantity or 1
  purchaseState.waitingForPurchaseResult = true
  C_AuctionHouse.PlaceBid(nextAuction.auctionID, nextAuction.price)

  AutoBuyPrint("Bid sent, waiting for auction house confirmation.")

  return "hold"
end

function AuctionatorShoppingTabFrameMixin:SmartBuyNextRow()
  -- Find the first result row that hasn't been purchased yet and hasn't been prevented
  local resultsList = self.ResultsListing
  if not resultsList or not resultsList.ScrollArea or not resultsList.ScrollArea.ScrollBox then
    return
  end

  -- Access all frames currently displayed in the scroll box
  local scrollBox = resultsList.ScrollArea.ScrollBox
  local normalRowFound = false

  scrollBox:ForEachFrame(function(frame)
    if not normalRowFound and frame.rowData then
      -- Check if this is a commodity and not yet purchased, and not a prevented purchase
      if not frame.rowData.purchased and not frame.rowData.preventedPurchase then
        local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(frame.rowData.itemKey)
        if itemKeyInfo and itemKeyInfo.isCommodity then
          normalRowFound = true

          -- Get the quantity and price from row data
          local quantity = frame.rowData.purchaseQuantity or 1
          local price = frame.rowData.minPrice

          -- Get the cell for feedback display (typically column 5 or the status column)
          local cell = frame.cells and frame.cells[5]
          if cell then
            -- Call PurchaseCommodity with the row and details
            PurchaseCommodity(frame, itemKeyInfo.itemID, quantity, price, cell)
          end
        end
      end
    end
  end)

  -- If no normal unpurchased row was found, try to cycle through prevented purchases
  if not normalRowFound then
    self:TryBuyNextPreventedRow()
  end
end

function AuctionatorShoppingTabFrameMixin:TryBuyNextPreventedRow()
  local resultsList = self.ResultsListing
  if not resultsList or not resultsList.ScrollArea or not resultsList.ScrollArea.ScrollBox then
    return
  end

  local scrollBox = resultsList.ScrollArea.ScrollBox
  local foundNextPrevented = false

  -- First pass: find a prevented row that we haven't tried yet (or after the last one we tried)
  scrollBox:ForEachFrame(function(frame)
    if not foundNextPrevented and frame.rowData and frame.rowData.preventedPurchase then
      -- Skip the one we just tried to cycle to the next
      if self.lastPreventedRowRetried ~= frame.rowData then
        foundNextPrevented = true
        self.lastPreventedRowRetried = frame.rowData

        local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(frame.rowData.itemKey)
        if itemKeyInfo and itemKeyInfo.isCommodity then
          local quantity = frame.rowData.purchaseQuantity or 1
          local price = frame.rowData.minPrice
          local cell = frame.cells and frame.cells[5]
          if cell then
            PurchaseCommodity(frame, itemKeyInfo.itemID, quantity, price, cell)
          end
        end
      end
    end
  end)

  -- If we didn't find a different prevented row (cycled through all), reset and try again from the beginning
  if not foundNextPrevented then
    self.lastPreventedRowRetried = nil
    TryRetryPurchase()
  end
end

function AuctionatorShoppingTabFrameMixin:GetAppropriateListSearchName()
  if self.singleSearch or not self.ListsContainer:GetExpandedList() then
    return AUCTIONATOR_L_NO_LIST
  else
    return self.ListsContainer:GetExpandedList():GetName()
  end
end

function AuctionatorShoppingTabFrameMixin:ReceiveEvent(eventName, ...)
  local eventData = ...
  if eventName == Auctionator.Shopping.Events.ListImportFinished then
    self.ListsContainer:ExpandList(Auctionator.Shopping.ListManager:GetByName(eventData))

  elseif eventName == Auctionator.Shopping.Tab.Events.ListSearchRequested then
    self.ContainerTabs:SetView(Auctionator.Constants.ShoppingListViews.Lists)
    self.ListsContainer:ExpandList(eventData)
    if not Auctionator.Config.Get(Auctionator.Config.Options.AUTO_LIST_SEARCH) then
      self.singleSearch = false
      self:DoSearch(eventData:GetAllItems())
    end

  elseif eventName == Auctionator.Shopping.Tab.Events.ShowHistoricalPrices then
    self:CloseAnyDialogs()
    self.itemHistoryDialog:Show()

  elseif eventName == Auctionator.Shopping.Tab.Events.UpdateSearchTerm then
    self.SearchOptions:SetSearchTerm(eventData)

  elseif eventName == Auctionator.Shopping.Tab.Events.BuyScreenShown then
    self:StopSearch()

  elseif eventName == Auctionator.Shopping.Tab.Events.SearchEnd then
    if self.pendingAutoBuySearch ~= nil then
      self.autoBuyResultsReady = true
      self.autoBuyLoadedTerms = self.pendingAutoBuySearch.terms
      self.pendingAutoBuySearch = nil
    end

  elseif eventName == Auctionator.Shopping.Tab.Events.AutoBuyCommodityPurchaseSucceeded then
    local itemID, quantity = ...
    local purchaseState = self.pendingAutoBuyCommodityPurchase
    if purchaseState ~= nil and purchaseState.itemID == itemID then
      local remainingQuantity = self:CommitAutoBuyPurchase(purchaseState.listIndex, purchaseState.searchTerm, quantity)
      if remainingQuantity <= 0 then
        self:CompleteAutoBuyEntry(purchaseState.listIndex)
      end
      self.pendingAutoBuyCommodityPurchase = nil
    end

  elseif eventName == Auctionator.Shopping.Tab.Events.AutoBuyCommodityPurchaseFailed then
    local itemID = ...
    local purchaseState = self.pendingAutoBuyCommodityPurchase
    if purchaseState ~= nil and purchaseState.itemID == itemID then
      self:InvalidateAutoBuyResults()
      self.pendingAutoBuyCommodityPurchase = nil
    end
  end
end

function AuctionatorShoppingTabFrameMixin:OnEvent(eventName, ...)
  if eventName == "ITEM_SEARCH_RESULTS_UPDATED" then
    local itemKey = ...
    if self.pendingAutoBuyItemPurchase ~= nil and ItemKeysMatch(self.pendingAutoBuyItemPurchase.itemKey, itemKey) then
      -- Let the buy-item data provider consume the search update before
      -- reading its rows to choose the next auction to bid on.
      C_Timer.After(0, function()
        if self.pendingAutoBuyItemPurchase ~= nil and ItemKeysMatch(self.pendingAutoBuyItemPurchase.itemKey, itemKey) then
          if self.pendingAutoBuyItemPurchase.waitingForResultRefresh then
            self.pendingAutoBuyItemPurchase.waitingForResultRefresh = false
            if self.pendingAutoBuyItemPurchase.remainingQuantity <= 0 then
              self:CompleteAutoBuyEntry(self.pendingAutoBuyItemPurchase.listIndex)
              self.pendingAutoBuyItemPurchase = nil
              return
            end
          end
          local listIndex = self.pendingAutoBuyItemPurchase.listIndex
          local actionResult = self:PlaceNextAutoBuyItemBid()
          if actionResult == "advance" and self.pendingAutoBuyItemPurchase == nil then
            self:CompleteAutoBuyEntry(listIndex)
          end
        end
      end)
    end

  elseif eventName == "AUCTION_HOUSE_NEW_BID_RECEIVED" then
    local auctionID = ...
    if self.pendingAutoBuyItemPurchase ~= nil and
       self.pendingAutoBuyItemPurchase.waitingForPurchaseResult and
       self.pendingAutoBuyItemPurchase.pendingAuctionID == auctionID then
      local purchaseState = self.pendingAutoBuyItemPurchase
      purchaseState.waitingForPurchaseResult = false
      purchaseState.waitingForResultRefresh = true
      purchaseState.seenAuctionIDs[auctionID] = true
      purchaseState.pendingAuctionID = nil
      purchaseState.remainingQuantity = self:CommitAutoBuyPurchase(
        purchaseState.listIndex,
        purchaseState.searchTerm,
        purchaseState.pendingAuctionQuantity
      )
      purchaseState.pendingAuctionQuantity = nil

      AutoBuyPrint(
        "Auction house accepted the bid.",
        tostring(purchaseState.remainingQuantity),
        "remaining for this entry."
      )
    end

  elseif eventName == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
    if self.pendingAutoBuyItemPurchase ~= nil then
      self.pendingAutoBuyItemPurchase = nil
      self:InvalidateAutoBuyResults()
    end
    self.pendingAutoBuyCommodityPurchase = nil

  elseif eventName == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
    local showType = ...
    if showType == Enum.PlayerInteractionType.Auctioneer then
      self.shouldDefaultOpenOnShow = true
      self.autoBuyResultsReady = false
      self.autoBuyLoadedTerms = nil
      self.autoBuyRemainingQuantities = {}
      self.pendingAutoBuySearch = nil
      self.pendingAutoBuyItemPurchase = nil
      self.pendingAutoBuyCommodityPurchase = nil
    end
  elseif eventName == "AUCTION_HOUSE_CLOSED" then
    self.shouldDefaultOpenOnShow = true
    self.autoBuyResultsReady = false
    self.autoBuyLoadedTerms = nil
    self.autoBuyRemainingQuantities = {}
    self.pendingAutoBuySearch = nil
    self.pendingAutoBuyItemPurchase = nil
    self.pendingAutoBuyCommodityPurchase = nil
  end
end

function AuctionatorShoppingTabFrameMixin:OnShow()
  -- self.SearchOptions:FocusSearchBox()
  Auctionator.EventBus:Register(self, EVENTBUS_EVENTS)

  if self.shouldDefaultOpenOnShow then
    self:OpenDefaultList()
    self.shouldDefaultOpenOnShow = false
  end
end

function AuctionatorShoppingTabFrameMixin:OnHide()
  if self.searchRunning then
    self:StopSearch()
  end
  Auctionator.EventBus:Unregister(self, EVENTBUS_EVENTS)
end

function AuctionatorShoppingTabFrameMixin:ExportCSVClicked()
  self:CloseAnyDialogs()
  self.DataProvider:GetCSV(function(result)
    self.exportCSVDialog:SetExportString(result)
    self.exportCSVDialog:Show()
  end)
end

function AuctionatorShoppingTabFrameMixin:OpenDefaultList()
  local listName = Auctionator.Config.Get(Auctionator.Config.Options.DEFAULT_LIST)

  if listName == Auctionator.Constants.NO_LIST then
    return
  end

  local listIndex = Auctionator.Shopping.ListManager:GetIndexForName(listName)

  if listIndex ~= nil then
    self.ListsContainer:CollapseList()
    self.ContainerTabs:SetView(Auctionator.Constants.ShoppingListViews.Lists)
    self.ListsContainer:ExpandList(Auctionator.Shopping.ListManager:GetByIndex(listIndex))
  end
end
