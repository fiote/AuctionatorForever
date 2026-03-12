Auctionator.Selling.TSMAccounting = {}

local private = {
  realmCache = {},
}

local CURRENT_REALM_KEY_PREFIX = "r@"
local INTERNAL_DATA_KEY_PART = "@internalData@"
local SALES_KEY_SUFFIX = "csvSales"
local EXPIRED_KEY_SUFFIX = "csvExpired"
local SALES_HEADER = "itemString,stackSize,quantity,price,otherPlayer,player,time,source"
local OLD_SALES_HEADER = "itemString,stackSize,quantity,price,buyer,player,time,source"
local EXPIRED_HEADER = "itemString,stackSize,quantity,player,time"

local function GetCurrentRealm()
  if GetRealmName then
    return GetRealmName()
  end
end

local function GetRealmDBKey(realmName, suffix)
  return CURRENT_REALM_KEY_PREFIX .. realmName .. INTERNAL_DATA_KEY_PART .. suffix
end

local function GetBaseItemString(itemString)
  local itemType, itemID = itemString and itemString:match("^([ip]):(%d+)")
  if itemType and itemID then
    return itemType .. ":" .. itemID
  end
  return itemString
end

local function GetTSMItemString(itemLink)
  if type(TSM_API) ~= "table" or type(TSM_API.ToItemString) ~= "function" then
    return nil
  end

  local ok, itemString = pcall(TSM_API.ToItemString, itemLink)
  if ok then
    return itemString
  end

  return nil
end

local function GetCustomPriceValue(itemString)
  if type(TSM_API) ~= "table" or type(TSM_API.GetCustomPriceValue) ~= "function" then
    return nil
  end

  local ok, value = pcall(TSM_API.GetCustomPriceValue, "NumExpires", itemString)
  if ok and type(value) == "number" then
    return value
  end

  return nil
end

local function ParseSalesCSV(cache, csvString)
  if type(csvString) ~= "string" or csvString == "" then
    return
  end

  local isFirstLine = true
  for line in csvString:gmatch("[^\n]+") do
    line = line:gsub("\r$", "")

    if isFirstLine then
      if line ~= SALES_HEADER and line ~= OLD_SALES_HEADER then
        return
      end
      isFirstLine = false
    else
      local itemString, _, _, _, _, _, timestamp, source = strsplit(",", line)
      timestamp = tonumber(timestamp)
      if itemString and timestamp and source ~= "Vendor" then
        cache.lastSaleTimes[itemString] = math.max(cache.lastSaleTimes[itemString] or 0, timestamp)
      end
    end
  end
end

local function ParseExpiredCSV(cache, csvString)
  if type(csvString) ~= "string" or csvString == "" then
    return
  end

  local isFirstLine = true
  for line in csvString:gmatch("[^\n]+") do
    line = line:gsub("\r$", "")

    if isFirstLine then
      if line ~= EXPIRED_HEADER then
        return
      end
      isFirstLine = false
    else
      local itemString, _, quantity, _, timestamp = strsplit(",", line)
      local baseItemString = GetBaseItemString(itemString)
      timestamp = tonumber(timestamp)
      quantity = tonumber(quantity)

      if baseItemString and timestamp and quantity then
        cache.expiredRows[baseItemString] = cache.expiredRows[baseItemString] or {}
        table.insert(cache.expiredRows[baseItemString], timestamp)
        table.insert(cache.expiredRows[baseItemString], quantity)
      end
    end
  end
end

local function GetRealmCache()
  local db = TradeSkillMasterDB
  local realmName = GetCurrentRealm()
  if type(db) ~= "table" or type(realmName) ~= "string" then
    return nil
  end

  local salesKey = GetRealmDBKey(realmName, SALES_KEY_SUFFIX)
  local expiredKey = GetRealmDBKey(realmName, EXPIRED_KEY_SUFFIX)
  local salesCsv = db[salesKey]
  local expiredCsv = db[expiredKey]

  local cache = private.realmCache[realmName]
  if cache and cache.db == db and cache.salesCsv == salesCsv and cache.expiredCsv == expiredCsv then
    return cache
  end

  cache = {
    db = db,
    salesCsv = salesCsv,
    expiredCsv = expiredCsv,
    lastSaleTimes = {},
    expiredRows = {},
  }

  ParseSalesCSV(cache, salesCsv)
  ParseExpiredCSV(cache, expiredCsv)

  private.realmCache[realmName] = cache
  return cache
end

local function GetLiveTSMValue(itemString)
  if type(TSM) ~= "table" or
     type(TSM.Accounting) ~= "table" or
     type(TSM.Accounting.Transactions) ~= "table" or
     type(TSM.Accounting.Auctions) ~= "table" or
     type(TSM.Accounting.Transactions.GetLastSaleTime) ~= "function" or
     type(TSM.Accounting.Auctions.GetStats) ~= "function" then
    return nil
  end

  local lastSaleTime = TSM.Accounting.Transactions.GetLastSaleTime(itemString)
  if not lastSaleTime then
    return nil
  end

  local _, expired = TSM.Accounting.Auctions.GetStats(itemString, lastSaleTime)
  if expired ~= nil then
    return expired
  end

  return nil
end

local function GetSavedVariableValue(itemString)
  local cache = GetRealmCache()
  if cache == nil then
    return nil
  end

  local lastSaleTime = cache.lastSaleTimes[itemString]
  if not lastSaleTime then
    return nil
  end

  local expired = 0
  local rows = cache.expiredRows[GetBaseItemString(itemString)]
  if rows ~= nil then
    for index = 1, #rows, 2 do
      if rows[index] >= lastSaleTime then
        expired = expired + rows[index + 1]
      end
    end
  end

  return expired
end

function Auctionator.Selling.TSMAccounting.GetExpiredSinceLastSale(itemLink)
  local itemString = GetTSMItemString(itemLink)
  if itemString == nil then
    return nil
  end

  local customPriceValue = GetCustomPriceValue(itemString)
  if customPriceValue ~= nil then
    return customPriceValue
  end

  local liveValue = GetLiveTSMValue(itemString)
  if liveValue ~= nil then
    return liveValue
  end

  return GetSavedVariableValue(itemString)
end
