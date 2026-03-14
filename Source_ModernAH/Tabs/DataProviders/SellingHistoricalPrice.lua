AuctionatorSellingHistoricalPriceProviderMixin = CreateFromMixins(AuctionatorHistoricalPriceProviderMixin)

function AuctionatorSellingHistoricalPriceProviderMixin:OnLoad()
  AuctionatorHistoricalPriceProviderMixin.OnLoad(self)

  Auctionator.EventBus:Register( self, {
    Auctionator.Selling.Events.BagItemClicked,
    Auctionator.Selling.Events.ClearBagItem,
    Auctionator.Selling.Events.RefreshHistory,
  })
end

function AuctionatorSellingHistoricalPriceProviderMixin:ReceiveEvent(eventName, itemInfo)
  if eventName == Auctionator.Selling.Events.BagItemClicked then
    local itemLink = itemInfo.itemLink
    self.currentItemLink = itemLink
    self.lastDBKey = nil

    Auctionator.Utilities.DBKeyFromLink(itemLink, function(dbKeys)
      if self.currentItemLink ~= itemLink then
        return
      end

      local dbKey = dbKeys[1]
      self:SetItem(dbKey)
    end)

  elseif eventName == Auctionator.Selling.Events.ClearBagItem then
    self.currentItemLink = nil
    self.lastDBKey = nil
    self:Reset()

  elseif eventName == Auctionator.Selling.Events.RefreshHistory and self.lastDBKey ~= nil then
    self:SetItem(self.lastDBKey)
  end
end

function AuctionatorSellingHistoricalPriceProviderMixin:GetRowTemplate()
  return "AuctionatorHistoricalPriceRowTemplate"
end

function AuctionatorSellingHistoricalPriceProviderMixin:GetColumnHideStates()
  return Auctionator.Config.Get(Auctionator.Config.Options.COLUMNS_HISTORICAL_PRICES)
end
