function Auctionator.AH.SendSearchQueryByGenerator(itemKeyGenerator, sorts, splitOwnedItems)
  function rawSearch(itemKey)
    C_AuctionHouse.SendSearchQuery(itemKey, sorts, splitOwnedItems)
  end

  Auctionator.AH.Internals.searchScan:SetSearch(itemKeyGenerator, rawSearch)
end

function Auctionator.AH.SendSearchQueryByItemKey(itemKey, sorts, splitOwnedItems)
  function itemKeyGenerator()
    return itemKey
  end
  function rawSearch(itemKey)
    C_AuctionHouse.SendSearchQuery(itemKey, sorts, splitOwnedItems)
  end

  Auctionator.AH.Internals.searchScan:SetSearch(itemKeyGenerator, rawSearch)
end

function Auctionator.AH.SendSellSearchQueryByGenerator(itemKeyGenerator, sorts, splitOwnedItems)
  function rawSearch(itemKey)
    C_AuctionHouse.SendSellSearchQuery(itemKey, sorts, splitOwnedItems)
  end

  Auctionator.AH.Internals.searchScan:SetSearch(itemKeyGenerator, rawSearch)
end

function Auctionator.AH.SendSellSearchQueryByItemKey(itemKey, sorts, splitOwnedItems)
  function itemKeyGenerator()
    return itemKey
  end
  function rawSearch(itemKey)
    C_AuctionHouse.SendSellSearchQuery(itemKey, sorts, splitOwnedItems)
  end

  Auctionator.AH.Internals.searchScan:SetSearch(itemKeyGenerator, rawSearch)
end

local function GetQueue()
  if Auctionator.AH.Queue == nil then
    Auctionator.AH.Initialize()
  end

  return Auctionator.AH.Queue
end

function Auctionator.AH.QueryOwnedAuctions(...)
  local args = {...}
  GetQueue():Enqueue(function()
    C_AuctionHouse.QueryOwnedAuctions(unpack(args))
  end)
end

function Auctionator.AH.QueryOwnedAuctionsWithCallback(onSent, ...)
  local args = {...}
  GetQueue():Enqueue(function()
    C_AuctionHouse.QueryOwnedAuctions(unpack(args))
    onSent()
  end)
end

local sentBrowseQuery = true
function Auctionator.AH.SendBrowseQuery(...)
  local args = {...}
  sentBrowseQuery = false
  GetQueue():Enqueue(function()
    sentBrowseQuery = true
    C_AuctionHouse.SendBrowseQuery(unpack(args))
  end)
end

function Auctionator.AH.HasFullBrowseResults()
  return sentBrowseQuery and C_AuctionHouse.HasFullBrowseResults()
end

function Auctionator.AH.RequestMoreBrowseResults(...)
  local args = {...}
  GetQueue():Enqueue(function()
    C_AuctionHouse.RequestMoreBrowseResults(unpack(args))
  end)
end

-- Event ThrottleUpdate will fire whenever the state changes
function Auctionator.AH.IsNotThrottled()
  return Auctionator.AH.Internals.throttling:IsReady()
end

function Auctionator.AH.CancelAuction(...)
  -- Can't be queued, "protected" call
  C_AuctionHouse.CancelAuction(...)
end

function Auctionator.AH.ReplicateItems()
  C_AuctionHouse.ReplicateItems()
end

function Auctionator.AH.GetItemKeyInfo(itemKey, callback)
  Auctionator.AH.Internals.itemKeyLoader:Get(itemKey, callback)
end

function Auctionator.AH.GetAuctionItemSubClasses(classID)
  return C_AuctionHouse.GetAuctionItemSubClasses(classID)
end
