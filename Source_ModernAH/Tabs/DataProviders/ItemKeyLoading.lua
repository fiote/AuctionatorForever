AuctionatorItemKeyLoadingMixin = {}

local TRACK_TO_QUALITY_TIER = {
  [970] = 1, -- Explorer
  [971] = 2, -- Adventurer
  [972] = 3, -- Veteran
  [973] = 4, -- Champion
  [974] = 5, -- Hero
}

local PROFESSION_EQUIP_LOCS = {
  INVTYPE_PROFESSION_TOOL = true,
  INVTYPE_PROFESSION_GEAR = true,
}

local function IsEquipmentItem(itemID)
  local classType = select(6, C_Item.GetItemInfoInstant(itemID))
  return classType ~= nil and Auctionator.Utilities.IsEquipment(classType)
end

local function IsProfessionEquipmentItem(itemID, itemLink)
  local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemLink or itemID)
  return equipLoc ~= nil and PROFESSION_EQUIP_LOCS[equipLoc] == true
end

local function GetTrackQualityTier(itemLink)
  if not itemLink or not C_Item.GetItemUpgradeInfo then
    return nil
  end

  local itemUpgradeData = C_Item.GetItemUpgradeInfo(itemLink)
  local trackID = itemUpgradeData and itemUpgradeData.trackStringID
  return trackID and TRACK_TO_QUALITY_TIER[trackID]
end

local function GetProfessionLinkQualityTier(itemLink)
  if not itemLink then
    return nil
  end

  local qualityTier
  if string.find(itemLink, "Quality%-12%-Tier") then
    qualityTier = string.match(itemLink, "Quality%-12%-Tier(%d+)")
  else
    qualityTier = string.match(itemLink, "Quality%-Tier(%d+)")
  end

  return tonumber(qualityTier)
end

local function GetProfessionItemLevelQualityTier(itemLevel)
  if not itemLevel then
    return nil
  end

  if itemLevel >= 206 then
    return 5
  elseif itemLevel >= 199 then
    return 4
  elseif itemLevel >= 192 then
    return 3
  elseif itemLevel >= 186 then
    return 2
  elseif itemLevel >= 183 then
    return 2
  elseif itemLevel >= 180 then
    return 1
  end

  return nil
end

local function GetLegacyCraftingQualityMarkup(itemID)
  if not itemID or not C_TradeSkillUI or not C_TradeSkillUI.GetItemReagentQualityByItemInfo then
    return nil
  end

  local quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemID)
  if quality then
    return Auctionator.Utilities.GetCraftingQualityMarkup(quality)
  end

  return nil
end

function AuctionatorItemKeyLoadingMixin:ShouldDisplayGearQualityIcon()
  return false
end

function AuctionatorItemKeyLoadingMixin:GetGearQualityMarkup(rowEntry)
  if not self:ShouldDisplayGearQualityIcon() then
    return nil
  end

  local itemID = rowEntry.itemKey and rowEntry.itemKey.itemID
  if not itemID or not IsEquipmentItem(itemID) then
    return nil
  end

  local qualityTier = GetTrackQualityTier(rowEntry.itemLink)
  if not qualityTier and IsProfessionEquipmentItem(itemID, rowEntry.itemLink) then
    qualityTier = GetProfessionLinkQualityTier(rowEntry.itemLink)
      or GetProfessionItemLevelQualityTier(rowEntry.itemKey and rowEntry.itemKey.itemLevel)
      or (
        C_TradeSkillUI and
        C_TradeSkillUI.GetItemReagentQualityByItemInfo and
        C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemID)
      )
  end

  if qualityTier and qualityTier >= 1 and qualityTier <= 5 then
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

  if isEquipment then
    text = itemKeyInfo.itemName or text
    local gearIcon = self:GetGearQualityMarkup(rowEntry)
    if gearIcon then
      text = text .. " " .. gearIcon
    end

    local itemLevel = rowEntry.itemKey and rowEntry.itemKey.itemLevel
    if itemLevel and itemLevel > 0 then
      text = AUCTIONATOR_L_ITEM_NAME_X_ITEM_LEVEL_X:format(text, itemLevel)
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
