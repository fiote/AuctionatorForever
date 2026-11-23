local SHOPPING_LIST_TABLE_LAYOUT = {
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerParameters = { "minPrice" },
    headerText = AUCTIONATOR_L_RESULTS_PRICE_COLUMN,
    cellTemplate = "AuctionatorShoppingPriceCellTemplate",
    cellParameters = { "minPrice" },
    width = 92
  },
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerParameters = { "name" },
    headerText = AUCTIONATOR_L_RESULTS_NAME_COLUMN,
    cellTemplate = "AuctionatorItemKeyCellTemplate"
  },
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerParameters = { "itemLevel" },
    headerText = AUCTIONATOR_L_ITEM_LEVEL,
    cellTemplate = "AuctionatorStringCellTemplate",
    cellParameters = { "itemLevel" },
    defaultHide = true,
    width = 70,
  },
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerParameters = { "isOwned" },
    headerText = AUCTIONATOR_L_OWNED_COLUMN,
    cellTemplate = "AuctionatorStringCellTemplate",
    cellParameters = { "isOwned" },
    defaultHide = true,
    width = 70,
  },
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerText = AUCTIONATOR_L_RESULTS_AVAILABLE_COLUMN,
    headerParameters = { "totalQuantity" },
    cellTemplate = "AuctionatorStringCellTemplate",
    cellParameters = { "available" },
    width = 70
  },
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerParameters = { "value" },
    headerText = AUCTIONATOR_L_RESULTS_VALUE_COLUMN,
    cellTemplate = "AuctionatorStringCellTemplate",
    cellParameters = { "value" },
    width = 70,
  },
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerParameters = { "stat" },
    headerText = AUCTIONATOR_L_RESULTS_STAT_COLUMN,
    cellTemplate = "AuctionatorStringCellTemplate",
    cellParameters = { "statDisplay" },
    width = 105,
  }
}

AuctionatorShoppingTabDataProviderMixin = CreateFromMixins(AuctionatorDataProviderMixin, AuctionatorItemKeyLoadingMixin)

function AuctionatorShoppingTabDataProviderMixin:OnLoad()
  Auctionator.Debug.Message("AuctionatorShoppingTabDataProviderMixin:OnLoad()")

  self:SetUpEvents()

  AuctionatorDataProviderMixin.OnLoad(self)
  AuctionatorItemKeyLoadingMixin.OnLoad(self)
end

function AuctionatorShoppingTabDataProviderMixin:ShouldDisplayGearQualityIcon()
  return true
end

function AuctionatorShoppingTabDataProviderMixin:SetUpEvents()
  Auctionator.EventBus:RegisterSource(self, "Shopping List Data Provider")

  Auctionator.EventBus:Register( self, {
    Auctionator.Shopping.Tab.Events.SearchStart,
    Auctionator.Shopping.Tab.Events.SearchEnd,
    Auctionator.Shopping.Tab.Events.SearchIncrementalUpdate,
  })
end

function AuctionatorShoppingTabDataProviderMixin:ReceiveEvent(eventName, eventData, ...)
  if eventName == Auctionator.Shopping.Tab.Events.SearchStart then
    local category = ...
    self.showFoodStatValue = category == "Foods"
    self.groupByStat = category == "Foods" or category == "Elixirs" or category == "Potions" or category == "Burst"
    if self.groupByStat and not self.presetSort.key then
      self:UseDefaultGroupedSort()
    elseif not self.groupByStat and self.usingDefaultGroupedSort then
      self:SetPresetSort(nil, nil)
    end
    self:Reset()
    self.onSearchStarted()
  elseif eventName == Auctionator.Shopping.Tab.Events.SearchEnd then
    self:AppendEntries(self:PrettifyData(eventData), true)
  elseif eventName == Auctionator.Shopping.Tab.Events.SearchIncrementalUpdate then
    self:AppendEntries(self:PrettifyData(eventData))
  end
end

local function FormatStat(stat, bonus)
  if stat ~= "" and bonus ~= nil then
    return ("%s %g"):format(stat, bonus)
  end
  return stat
end

function AuctionatorShoppingTabDataProviderMixin:PrettifyData(entries)
  for _, entry in ipairs(entries) do
    if entry.containsOwnerItem then
      entry.isOwned = AUCTIONATOR_L_UNDERCUT_YES
    else
      entry.isOwned = ""
    end
    entry.available = FormatLargeNumber(entry.totalQuantity)
    entry.itemLevel = entry.itemKey.itemLevel
    -- Search completion sends the same entries as the incremental updates.
    entry.value = entry.value or 0
    entry.stat = entry.stat or ""
    entry.statDisplay = FormatStat(entry.stat, self.showFoodStatValue and entry.foodStatValue or nil)
    if not self.groupByStat then
      entry.startsStatGroup = nil
    end
  end

  return entries
end

function AuctionatorShoppingTabDataProviderMixin:ProcessItemKey(entry, itemKeyInfo)
  AuctionatorItemKeyLoadingMixin.ProcessItemKey(self, entry, itemKeyInfo)

  local getFoodOrDrinkValue = Auctionator.Shopping.GetFoodOrDrinkValue
  local getPotionOrElixirStat = Auctionator.Shopping.GetPotionOrElixirStat
  if not getFoodOrDrinkValue then
    return
  end

  local itemID = entry.itemKey.itemID
  local function ApplyDetails(value, stat, foodStatValue)
    local statDisplay = FormatStat(stat, self.showFoodStatValue and foodStatValue or nil)
    local sortKey = self.presetSort.key
    local needsSort = (sortKey == "value" and entry.value ~= value)
      or (sortKey == "stat" and entry.stat ~= stat)
      or (self.groupByStat and (entry.stat ~= stat or (sortKey == "stat" and entry.value ~= value)))
    if entry.value == value and entry.stat == stat and entry.statDisplay == statDisplay then
      return
    end
    entry.value = value
    entry.stat = stat
    entry.statDisplay = statDisplay
    self:SetDirty()
    if needsSort and not self.detailsSortQueued then
      self.detailsSortQueued = true
      C_Timer.After(0, function()
        self.detailsSortQueued = false
        local currentSortKey = self.presetSort.key
        if currentSortKey and (self.groupByStat or currentSortKey == "value" or currentSortKey == "stat") then
          self:Sort(currentSortKey, self.presetSort.direction)
        end
      end)
    end
  end

  local value, foodStat, foodStatValue = getFoodOrDrinkValue(itemID)
  local stat, effectValue = getPotionOrElixirStat(itemID)
  if value ~= nil and stat ~= nil then
    ApplyDetails(effectValue or value, foodStat or stat, foodStatValue)
  else
    local key = self:UniqueKey(entry)
    Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
      if self.insertedKeys[key] ~= entry then
        return
      end
      local loadedStat, loadedEffectValue, spellID = getPotionOrElixirStat(itemID)
      if spellID then
        Spell:CreateFromSpellID(spellID):ContinueOnSpellLoad(function()
          if self.insertedKeys[key] == entry then
            local spellStat, spellValue = getPotionOrElixirStat(itemID)
            ApplyDetails(spellValue or 0, spellStat or "")
          end
        end)
      else
        local loadedFoodValue, loadedFoodStat, loadedFoodStatValue = getFoodOrDrinkValue(itemID)
        ApplyDetails(loadedEffectValue or loadedFoodValue or 0, loadedFoodStat or loadedStat or "", loadedFoodStatValue)
      end
    end)
  end
end


function AuctionatorShoppingTabDataProviderMixin:UniqueKey(entry)
  return Auctionator.Utilities.ItemKeyString(entry.itemKey)
end

local COMPARATORS = {
  minPrice = Auctionator.Utilities.NumberComparator,
  name = Auctionator.Utilities.StringComparator,
  totalQuantity = Auctionator.Utilities.NumberComparator,
  itemLevel = Auctionator.Utilities.NumberComparator,
  isOwned = Auctionator.Utilities.StringComparator,
  value = Auctionator.Utilities.NumberComparator,
  stat = Auctionator.Utilities.StringComparator,
}

function AuctionatorShoppingTabDataProviderMixin:SetPresetSort(fieldName, sortDirection)
  self.usingDefaultGroupedSort = false
  AuctionatorDataProviderMixin.SetPresetSort(self, fieldName, sortDirection)
end

function AuctionatorShoppingTabDataProviderMixin:UseDefaultGroupedSort()
  self:SetPresetSort("value", Auctionator.Constants.SORT.DESCENDING)
  self.usingDefaultGroupedSort = true
end

function AuctionatorShoppingTabDataProviderMixin:ClearSort()
  if self.groupByStat then
    self:UseDefaultGroupedSort()
    self:Sort(self.presetSort.key, self.presetSort.direction)
  else
    AuctionatorDataProviderMixin.ClearSort(self)
  end
end

function AuctionatorShoppingTabDataProviderMixin:Sort(fieldName, sortDirection)
  local comparator = COMPARATORS[fieldName](sortDirection, fieldName)

  if self.groupByStat then
    local sortGroupsDescending = fieldName == "stat" and sortDirection == Auctionator.Constants.SORT.DESCENDING
    if fieldName == "stat" then
      comparator = Auctionator.Utilities.NumberComparator(Auctionator.Constants.SORT.DESCENDING, "value")
    end
    table.sort(self.results, function(left, right)
      local leftStat, rightStat = left.stat or "", right.stat or ""
      if leftStat == rightStat then
        return comparator(left, right)
      elseif leftStat == "" or rightStat == "" then
        return rightStat == ""
      elseif sortGroupsDescending then
        return leftStat > rightStat
      end
      return leftStat < rightStat
    end)
    local previousStat
    for _, entry in ipairs(self.results) do
      local stat = entry.stat or ""
      entry.startsStatGroup = previousStat ~= stat
      previousStat = stat
    end
    self:SetDirty()
    return
  end

  table.sort(self.results, function(left, right)
    return comparator(left, right)
  end)

  self:SetDirty()
end

function AuctionatorShoppingTabDataProviderMixin:GetTableLayout()
  return SHOPPING_LIST_TABLE_LAYOUT
end

function AuctionatorShoppingTabDataProviderMixin:GetDisplayIndexProvider()
  if not self.groupByStat then
    return
  end

  local rows = {}
  for index = 1, self:GetCount() do
    local entry = self:GetEntryAt(index)
    if entry.startsStatGroup then
      local stat = entry.stat or ""
      table.insert(rows, { label = stat ~= "" and stat or AUCTIONATOR_L_CONFIG_SUGGESTIONS_NO_STAT })
    end
    table.insert(rows, index)
  end
  return CreateDataProvider(rows)
end

function AuctionatorShoppingTabDataProviderMixin:GetColumnHideStates()
  return Auctionator.Config.Get(Auctionator.Config.Options.COLUMNS_SHOPPING)
end

function AuctionatorShoppingTabDataProviderMixin:GetRowTemplate()
  return "AuctionatorShoppingResultsRowTemplate"
end
