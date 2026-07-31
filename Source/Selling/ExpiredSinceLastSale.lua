-- Reports how many auctions of an item expired since it last sold.
--
-- The value comes from WarbandMoney's shared helper (WarbandMoney.addons\
-- BetterBags-WarbandMoney\features\expired-source.lua), which queries TSM's
-- NumExpires by base itemID, ignoring quality/bonus variations. This keeps
-- Auctionator's Z%OFF discount, WarbandMoney's merchant overlay, and CraftSim's
-- Recipe Scan "Expd" column all reporting the same number for the same item.

local function GetItemLink(item)
  if type(item) == "table" then
    return item.itemLink
  elseif type(item) == "string" then
    return item
  end
end

function Auctionator.GetTSMExpiredSinceLastSale(item)
  local itemLink = GetItemLink(item)
  if itemLink == nil or
     type(WarbandMoney) ~= "table" or
     type(WarbandMoney.GetExpiredSinceLastSale) ~= "function" then
    return nil
  end

  return WarbandMoney.GetExpiredSinceLastSale(itemLink)
end

function Auctionator.GetExpiredSinceLastSale(item)
  return Auctionator.GetTSMExpiredSinceLastSale(item) or 0
end
