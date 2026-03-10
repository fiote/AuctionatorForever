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

  if Auctionator.Database == nil and Auctionator.GlobalDatabase == nil then
    return nil
  end

  return Auctionator.API.v1.GetPreferredPriceForDBKey(tostring(itemID))
end

function Auctionator.API.v1.GetAuctionPriceByItemLink(callerID, itemLink)
  Auctionator.API.InternalVerifyID(callerID)

  if type(itemLink) ~= "string" then
    Auctionator.API.ComposeError(
      callerID,
      "Usage Auctionator.API.v1.GetAuctionPriceByItemLink(string, string)"
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
      local price = Auctionator.API.v1.GetPreferredPriceForDBKey(dbKey)
      if price ~= nil then
        return price
      end
    end
    return nil
  else
    return Auctionator.API.v1.GetPreferredPriceForDBKey(
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

  if Auctionator.Database == nil and Auctionator.GlobalDatabase == nil then
    return nil
  end

  return Auctionator.API.v1.GetPreferredEntryForDBKey(tostring(itemID))
end

function Auctionator.API.v1.GetAuctionEntryByItemLink(callerID, itemLink)
  Auctionator.API.InternalVerifyID(callerID)

  if type(itemLink) ~= "string" then
    Auctionator.API.ComposeError(
      callerID,
      "Usage Auctionator.API.v1.GetAuctionEntryByItemLink(string, string)"
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
      local entry = Auctionator.API.v1.GetPreferredEntryForDBKey(dbKey)
      if entry then
        return entry
      end
    end
    return nil
  else
    return Auctionator.API.v1.GetPreferredEntryForDBKey(
      Auctionator.Utilities.BasicDBKeyFromLink(itemLink)
    )
  end
end
