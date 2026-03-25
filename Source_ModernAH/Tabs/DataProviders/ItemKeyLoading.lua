AuctionatorItemKeyLoadingMixin = {}

local function IsEquipmentItem(itemID)
  local classType = select(6, C_Item.GetItemInfoInstant(itemID))
  return classType ~= nil and Auctionator.Utilities.IsEquipment(classType)
end

local function GetItemLinkFromItemKey(itemKey)
  if not itemKey or not C_TooltipInfo or not C_TooltipInfo.GetItemKey then
    return nil
  end

  local info = C_TooltipInfo.GetItemKey(
    itemKey.itemID,
    itemKey.itemLevel or 0,
    itemKey.itemSuffix or 0
  )
  if info and info.hyperlink and C_Item.GetItemInfoInstant(info.hyperlink) == itemKey.itemID then
    return info.hyperlink
  end

  return nil
end

local function GetLegacyCraftingQualityMarkup(itemID)
  local quality = Auctionator.Utilities.GetItemQualityTier(itemID)
  if quality then
    return Auctionator.Utilities.GetCraftingQualityMarkup(quality)
  end

  return nil
end

function AuctionatorItemKeyLoadingMixin:ShouldDisplayGearQualityIcon()
  return false
end

function AuctionatorItemKeyLoadingMixin:GetGearQualityTier(rowEntry)
  if not self:ShouldDisplayGearQualityIcon() then
    return nil
  end

  local itemID = rowEntry.itemKey and rowEntry.itemKey.itemID
  if not itemID or not IsEquipmentItem(itemID) then
    return nil
  end

  return Auctionator.Utilities.GetItemQualityTier(
    itemID,
    rowEntry.itemLink,
    rowEntry.itemKey and rowEntry.itemKey.itemLevel,
    select(6, C_Item.GetItemInfoInstant(itemID))
  )
end

function AuctionatorItemKeyLoadingMixin:GetGearQualityMarkup(rowEntry)
  local qualityTier = self:GetGearQualityTier(rowEntry)
  if qualityTier then
    return Auctionator.Utilities.GetCraftingQualityMarkup(qualityTier)
  end
  return nil
end

function AuctionatorItemKeyLoadingMixin:OnLoad()
  Auctionator.EventBus:Register(self, {Auctionator.AH.Events.ItemKeyInfo})

  self:SetOnEntryProcessedCallback(function(entry)
    Auctionator.AH.GetItemKeyInfo(entry.itemKey, function(itemKeyInfo, wasCached)
      self:ProcessItemKey(entry, itemKeyInfo)
      if wasCached then
        self:NotifyCacheUsed()
      end
    end)
  end)
end

function AuctionatorItemKeyLoadingMixin:ProcessItemKey(rowEntry, itemKeyInfo)
  local text = AuctionHouseUtil.GetItemDisplayTextFromItemKey(
    rowEntry.itemKey,
    itemKeyInfo,
    false
  )
  local itemID = rowEntry.itemKey and rowEntry.itemKey.itemID
  local isEquipment = itemID and IsEquipmentItem(itemID)
  rowEntry.gearQualityTier = nil

  if rowEntry.itemLink == nil then
    rowEntry.itemLink = GetItemLinkFromItemKey(rowEntry.itemKey)
  end

  if isEquipment then
    text = itemKeyInfo.itemName or text
    rowEntry.gearQualityTier = self:GetGearQualityTier(rowEntry)

    local itemLevel = rowEntry.itemKey and rowEntry.itemKey.itemLevel
    if itemLevel and itemLevel > 0 then
      text = AUCTIONATOR_L_ITEM_NAME_X_ITEM_LEVEL_X:format(text, itemLevel)
    end

    local quality = itemKeyInfo and itemKeyInfo.quality
    if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
      text = ITEM_QUALITY_COLORS[quality].color:WrapTextInColorCode(text)
    end
  else
    local nonEquipmentIcon = GetLegacyCraftingQualityMarkup(itemID)
    if nonEquipmentIcon then
      text = text .. " " .. nonEquipmentIcon
    end
  end

  rowEntry.itemName = text
  rowEntry.plainItemName = itemKeyInfo.itemName
  rowEntry.name = Auctionator.Utilities.RemoveTextColor(text):gsub("|A.-Tier(%d).-|a", AUCTIONATOR_L_TIER .. " %1")
  rowEntry.iconTexture = itemKeyInfo.iconFileID
  rowEntry.noneAvailable = rowEntry.totalQuantity == 0

  self:SetDirty()
end
