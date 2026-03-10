function Auctionator.API.v1.IsAuctionDataExactByItemID(callerID, itemID)
  Auctionator.API.InternalVerifyID(callerID)

  if type(itemID) ~= "number" then
    Auctionator.API.ComposeError(
      callerID,
      "Usage Auctionator.API.v1.IsAuctionDataExactByItemID(string, number)"
    )
  end

  if Auctionator.Database == nil and Auctionator.GlobalDatabase == nil then
    return nil
  end

  return Auctionator.API.v1.HasPreferredPriceForDBKey(tostring(itemID))
end

function Auctionator.API.v1.IsAuctionDataExactByItemLink(callerID, itemLink)
  Auctionator.API.InternalVerifyID(callerID)

  if type(itemLink) ~= "string" then
    Auctionator.API.ComposeError(
      callerID,
      "Usage Auctionator.API.v1.IsAuctionDataExactByItemLink(string, string)"
    )
  end

  if Auctionator.Database == nil and Auctionator.GlobalDatabase == nil then
    return false
  end

  local dbKeys = nil
  -- Use that the callback is called immediately (and populates dbKeys) if the
  -- item info for item levels is available now.
  Auctionator.Utilities.DBKeyFromLink(itemLink, function(dbKeysCallback)
    dbKeys = dbKeysCallback
  end)

  if dbKeys then
    for _, dbKey in ipairs(dbKeys) do
      if Auctionator.API.v1.HasPreferredPriceForDBKey(dbKey) then
        return true
      end
    end
    return false
  else
    return Auctionator.API.v1.HasPreferredPriceForDBKey(
      Auctionator.Utilities.BasicDBKeyFromLink(itemLink)
    )
  end
end
