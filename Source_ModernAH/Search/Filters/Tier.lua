Auctionator.Search.Filters.TierMixin = {}

function Auctionator.Search.Filters.TierMixin:Init(filterTracker, browseResult, tier)
  self.tier = tier

  filterTracker:ReportFilterComplete(self:FilterCheck(browseResult))
end

function Auctionator.Search.Filters.TierMixin:FilterCheck(browseResult)
  return self:TierCheck(browseResult)
end

function Auctionator.Search.Filters.TierMixin:TierCheck(browseResult)
  local itemKey = browseResult.itemKey
  local classID = select(6, C_Item.GetItemInfoInstant(itemKey.itemID))

  return Auctionator.Utilities.GetItemQualityTier(
    itemKey.itemID,
    browseResult.itemLink,
    itemKey.itemLevel,
    classID
  ) == self.tier
end
