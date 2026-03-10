local function GetPreferredDatabase(dbKey)
  local realmDatabase = Auctionator.Database
  local globalDatabase = Auctionator.GlobalDatabase

  if realmDatabase == nil then
    return globalDatabase
  end

  if globalDatabase == nil then
    return realmDatabase
  end

  local realmDay = realmDatabase:GetMostRecentDay(dbKey)
  local globalDay = globalDatabase:GetMostRecentDay(dbKey)

  if globalDay ~= nil and (realmDay == nil or globalDay > realmDay) then
    return globalDatabase
  end

  return realmDatabase
end

function Auctionator.API.v1.GetPreferredDatabaseForDBKey(dbKey)
  return GetPreferredDatabase(dbKey)
end

function Auctionator.API.v1.GetPreferredPriceForDBKey(dbKey)
  local database = GetPreferredDatabase(dbKey)
  if database == nil then
    return nil
  end

  return database:GetPrice(dbKey)
end

function Auctionator.API.v1.GetPreferredPriceAgeForDBKey(dbKey)
  local database = GetPreferredDatabase(dbKey)
  if database == nil then
    return nil
  end

  return database:GetPriceAge(dbKey)
end

function Auctionator.API.v1.GetPreferredPriceTimestampForDBKey(dbKey)
  local database = GetPreferredDatabase(dbKey)
  if database == nil then
    return nil
  end

  return database:GetPriceTimestamp(dbKey)
end

function Auctionator.API.v1.GetPreferredPriceAgeSecondsForDBKey(dbKey)
  local database = GetPreferredDatabase(dbKey)
  if database == nil then
    return nil
  end

  return database:GetPriceAgeSeconds(dbKey)
end

function Auctionator.API.v1.HasPreferredPriceForDBKey(dbKey)
  return Auctionator.API.v1.GetPreferredPriceForDBKey(dbKey) ~= nil
end

function Auctionator.API.v1.GetPreferredEntryForDBKey(dbKey)
  local database = GetPreferredDatabase(dbKey)
  if database == nil then
    return nil
  end

  return database.db[dbKey]
end
