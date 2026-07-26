local function GetItemLink(item)
  if type(item) == "table" then
    return item.itemLink
  elseif type(item) == "string" then
    return item
  end
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

local function GetAdjustmentKey(item)
  local itemLink = GetItemLink(item)
  if itemLink == nil then
    return nil
  end

  return GetTSMItemString(itemLink) or itemLink
end

local function GetAdjustmentStore()
  Auctionator.SavedState.ExpiredSinceLastSaleAdjustments = Auctionator.SavedState.ExpiredSinceLastSaleAdjustments or {}
  return Auctionator.SavedState.ExpiredSinceLastSaleAdjustments
end

local function ClampAdjustment(adjustment, tsmExpires)
  adjustment = math.floor(tonumber(adjustment) or 0)
  tsmExpires = math.floor(tonumber(tsmExpires) or 0)

  return math.min(math.max(adjustment, 0), math.max(tsmExpires, 0))
end

function Auctionator.GetTSMExpiredSinceLastSale(item)
  local itemLink = GetItemLink(item)
  if itemLink == nil or
     Auctionator.Selling == nil or
     Auctionator.Selling.TSMAccounting == nil or
     type(Auctionator.Selling.TSMAccounting.GetExpiredSinceLastSale) ~= "function" then
    return nil
  end

  return Auctionator.Selling.TSMAccounting.GetExpiredSinceLastSale(itemLink)
end

function Auctionator.GetExpiredSinceLastSaleAdjustment(item, tsmExpires)
  local key = GetAdjustmentKey(item)
  if key == nil then
    return 0
  end

  if tsmExpires == nil then
    tsmExpires = Auctionator.GetTSMExpiredSinceLastSale(item) or 0
  end

  local adjustments = GetAdjustmentStore()
  local adjustment = ClampAdjustment(adjustments[key], tsmExpires)

  if adjustment == 0 then
    adjustments[key] = nil
  else
    adjustments[key] = adjustment
  end

  return adjustment
end

function Auctionator.SetExpiredSinceLastSaleAdjustment(item, adjustment, tsmExpires)
  local key = GetAdjustmentKey(item)
  if key == nil then
    return 0
  end

  if tsmExpires == nil then
    tsmExpires = Auctionator.GetTSMExpiredSinceLastSale(item) or 0
  end

  adjustment = ClampAdjustment(adjustment, tsmExpires)

  local adjustments = GetAdjustmentStore()
  if adjustment == 0 then
    adjustments[key] = nil
  else
    adjustments[key] = adjustment
  end

  return adjustment
end

function Auctionator.IncrementExpiredSinceLastSaleAdjustment(item, quantity)
  quantity = math.floor(tonumber(quantity) or 0)
  if quantity <= 0 then
    return Auctionator.GetExpiredSinceLastSaleAdjustment(item)
  end

  local tsmExpires = Auctionator.GetTSMExpiredSinceLastSale(item) or 0
  local adjustment = Auctionator.GetExpiredSinceLastSaleAdjustment(item, tsmExpires)

  return Auctionator.SetExpiredSinceLastSaleAdjustment(item, adjustment + quantity, tsmExpires)
end

function Auctionator.GetExpiredSinceLastSale(item)
  local tsmExpires = Auctionator.GetTSMExpiredSinceLastSale(item) or 0
  local adjustment = Auctionator.GetExpiredSinceLastSaleAdjustment(item, tsmExpires)

  return math.max(tsmExpires - adjustment, 0)
end
