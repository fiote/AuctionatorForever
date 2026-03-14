local HISTORICAL_PRICE_PROVIDER_LAYOUT ={
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerText = AUCTIONATOR_L_UNIT_PRICE,
    headerParameters = { "minSeen" },
    cellTemplate = "AuctionatorHistoricalPriceCellTemplate",
    cellParameters = { "minSeen" }
  },
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerText = AUCTIONATOR_L_UPPER_UNIT_PRICE,
    headerParameters = { "maxSeen" },
    cellTemplate = "AuctionatorHistoricalPriceCellTemplate",
    cellParameters = { "maxSeen" },
    defaultHide = true
  },
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerText = AUCTIONATOR_L_RESULTS_AVAILABLE_COLUMN,
    headerParameters = { "available" },
    cellTemplate = "AuctionatorHistoricalStringCellTemplate",
    cellParameters = { "availableFormatted" },
    width = 100
  },
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerText = AUCTIONATOR_L_DATE,
    headerParameters = { "rawDay" },
    cellTemplate = "AuctionatorHistoricalStringCellTemplate",
    cellParameters = { "date" }
  },
}

AuctionatorHistoricalPriceProviderMixin = CreateFromMixins(AuctionatorDataProviderMixin)

function AuctionatorHistoricalPriceProviderMixin:OnShow()
  self:Reset()
end

function AuctionatorHistoricalPriceProviderMixin:SetItem(dbKey)
  self.lastDBKey = dbKey
  self:Reset()

  -- Reset columns
  self.onSearchStarted()

  local entries = Auctionator.Database:GetPriceHistory(dbKey)
  local lowestMinSeen = nil

  for _, entry in ipairs(entries) do
    if entry.minSeen ~= nil and (lowestMinSeen == nil or entry.minSeen < lowestMinSeen) then
      lowestMinSeen = entry.minSeen
    end
  end

  for _, entry in ipairs(entries) do
    if entry.available then
      entry.availableFormatted = FormatLargeNumber(entry.available)
    else
      entry.availableFormatted = ""
    end

    entry.isLowestHistoricalPrice = lowestMinSeen ~= nil and entry.minSeen == lowestMinSeen
  end

  self:AppendEntries(entries, true)
end

function AuctionatorHistoricalPriceProviderMixin:GetTableLayout()
  return HISTORICAL_PRICE_PROVIDER_LAYOUT
end

function AuctionatorHistoricalPriceProviderMixin:UniqueKey(entry)
  return tostring(entry.rawDay)
end

local COMPARATORS = {
  minSeen = Auctionator.Utilities.NumberComparator,
  maxSeen = Auctionator.Utilities.NumberComparator,
  available = Auctionator.Utilities.NumberComparator,
  rawDay = Auctionator.Utilities.StringComparator
}

function AuctionatorHistoricalPriceProviderMixin:Sort(fieldName, sortDirection)
  local comparator = COMPARATORS[fieldName](sortDirection, fieldName)

  table.sort(self.results, function(left, right)
    return comparator(left, right)
  end)

  self:SetDirty()
end
