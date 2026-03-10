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

-- Returns the unix timestamp (seconds) when the item was last seen in an AH
-- scan. Returns nil if no auction has been seen for the item.
function Auctionator.API.v1.GetAuctionTimestampByItemID(callerID, itemID)
  Auctionator.API.InternalVerifyID(callerID)

  if type(itemID) ~= "number" then
    Auctionator.API.ComposeError(
      callerID,
      "Usage Auctionator.API.v1.GetAuctionTimestampByItemID(string, number)"
    )
  end

  if Auctionator.Database == nil and Auctionator.GlobalDatabase == nil then
    return nil
  end

  return Auctionator.API.v1.GetPreferredPriceTimestampForDBKey(tostring(itemID))
end

function Auctionator.API.v1.GetAuctionTimestampByItemLink(callerID, itemLink)
  Auctionator.API.InternalVerifyID(callerID)

  if type(itemLink) ~= "string" then
    Auctionator.API.ComposeError(
      callerID,
      "Usage Auctionator.API.v1.GetAuctionTimestampByItemLink(string, string)"
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
      local timestamp = Auctionator.API.v1.GetPreferredPriceTimestampForDBKey(dbKey)
      if timestamp ~= nil then
        return timestamp
      end
    end
    return nil
  else
    return Auctionator.API.v1.GetPreferredPriceTimestampForDBKey(
      Auctionator.Utilities.BasicDBKeyFromLink(itemLink)
    )
  end
end

-- Returns the number of elapsed seconds since the item was seen in an AH scan.
-- Returns nil if no auction has been seen for the item.
function Auctionator.API.v1.GetAuctionAgeSecondsByItemID(callerID, itemID)
  Auctionator.API.InternalVerifyID(callerID)

  if type(itemID) ~= "number" then
    Auctionator.API.ComposeError(
      callerID,
      "Usage Auctionator.API.v1.GetAuctionAgeSecondsByItemID(string, number)"
    )
  end

  if Auctionator.Database == nil and Auctionator.GlobalDatabase == nil then
    return nil
  end

  return Auctionator.API.v1.GetPreferredPriceAgeSecondsForDBKey(tostring(itemID))
end

function Auctionator.API.v1.GetAuctionAgeSecondsByItemLink(callerID, itemLink)
  Auctionator.API.InternalVerifyID(callerID)

  if type(itemLink) ~= "string" then
    Auctionator.API.ComposeError(
      callerID,
      "Usage Auctionator.API.v1.GetAuctionAgeSecondsByItemLink(string, string)"
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
      local ageSeconds = Auctionator.API.v1.GetPreferredPriceAgeSecondsForDBKey(dbKey)
      if ageSeconds ~= nil then
        return ageSeconds
      end
    end
    return nil
  else
    return Auctionator.API.v1.GetPreferredPriceAgeSecondsForDBKey(
      Auctionator.Utilities.BasicDBKeyFromLink(itemLink)
    )
  end
end
