function Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID)
  Auctionator.API.InternalVerifyID(callerID)

  -- Convert string to number if needed
  if type(itemID) == "string" then
    itemID = tonumber(itemID)
  end

  if type(itemID) ~= "number" then
    Auctionator.API.ComposeError(
      callerID,
      "Usage Auctionator.API.v1.GetAuctionPriceByItemID(string, number)"
    )
  end

  if Auctionator.Database == nil then
    return nil
  end

  return Auctionator.Database:GetPrice(tostring(itemID))
end

function Auctionator.API.v1.GetAuctionPriceByItemLink(callerID, itemLink)
  Auctionator.API.InternalVerifyID(callerID)

  if type(itemLink) ~= "string" then
    Auctionator.API.ComposeError(
      callerID,
      "Usage Auctionator.API.v1.GetAuctionPriceByItemLink(string, string)"
    )
  end

  if Auctionator.Database == nil then
    return nil
  end

  local dbKeys = nil
  -- Use that the callback is called immediately (and populates dbKeys) if the
  -- item info for item levels is available now.
  Auctionator.Utilities.DBKeyFromLink(itemLink, function(dbKeysCallback)
    dbKeys = dbKeysCallback
  end)

  if dbKeys then
    return Auctionator.Database:GetFirstPrice(dbKeys)
  else
    return Auctionator.Database:GetPrice(
      Auctionator.Utilities.BasicDBKeyFromLink(itemLink)
    )
  end
end

function Auctionator.API.v1.GetAuctionEntryByItemID(callerID, itemID)
  Auctionator.API.InternalVerifyID(callerID)

  -- Convert string to number if needed
  if type(itemID) == "string" then
    itemID = tonumber(itemID)
  end

  if type(itemID) ~= "number" then
    Auctionator.API.ComposeError(
      callerID,
      "Usage Auctionator.API.v1.GetAuctionEntryByItemID(string, number)"
    )
  end

  if Auctionator.Database == nil then
    return nil
  end

  return Auctionator.Database.db[tostring(itemID)]
end

function Auctionator.API.v1.GetAuctionEntryByItemLink(callerID, itemLink)
  Auctionator.API.InternalVerifyID(callerID)

  if type(itemLink) ~= "string" then
    Auctionator.API.ComposeError(
      callerID,
      "Usage Auctionator.API.v1.GetAuctionEntryByItemLink(string, string)"
    )
  end

  if Auctionator.Database == nil then
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
      local entry = Auctionator.Database.db[dbKey]
      if entry then
        return entry
      end
    end
    return nil
  else
    return Auctionator.Database.db[
      Auctionator.Utilities.BasicDBKeyFromLink(itemLink)
    ]
  end
end
