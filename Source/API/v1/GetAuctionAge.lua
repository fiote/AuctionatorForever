-- Returns the number of days since the item was seen in the auction house,
-- except if the number of days exceeds 21, then it returns nil. It will return
-- nil if there is no auction ever seen in the auction house for the item.
function Auctionator.API.v1.GetAuctionAgeByItemID(callerID, itemID)
  Auctionator.API.InternalVerifyID(callerID)

  if type(itemID) ~= "number" then
    Auctionator.API.ComposeError(
      callerID,
      "Usage Auctionator.API.v1.GetAuctionAgeByItemID(string, number)"
    )
  end

  if Auctionator.Database == nil and Auctionator.GlobalDatabase == nil then
    return nil
  end

  return Auctionator.API.v1.GetPreferredPriceAgeForDBKey(tostring(itemID))
end

function Auctionator.API.v1.GetAuctionAgeByItemLink(callerID, itemLink)
  Auctionator.API.InternalVerifyID(callerID)

  if type(itemLink) ~= "string" then
    Auctionator.API.ComposeError(
      callerID,
      "Usage Auctionator.API.v1.GetAuctionAgeByItemLink(string, string)"
    )
  end

  if Auctionator.Database == nil and Auctionator.GlobalDatabase == nil then
    return nil
  end

  local dbKeys = nil
  -- Use that the callback is called immediately (and populates dbKeys) if the
  -- item info for item levels is available now.
  Auctionator.Utilities.DBKeyFromLink(itemLink, function(dbKeysCallback)
    dbKeys = dbKeysCallback
  end)

  if dbKeys then
    for _, dbKey in ipairs(dbKeys) do
      local age = Auctionator.API.v1.GetPreferredPriceAgeForDBKey(dbKey)
      if age ~= nil then
        return age
      end
    end
    return nil
  else
    return Auctionator.API.v1.GetPreferredPriceAgeForDBKey(
      Auctionator.Utilities.BasicDBKeyFromLink(itemLink)
    )
  end
end
