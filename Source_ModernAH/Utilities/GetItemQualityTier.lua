Auctionator.Utilities = Auctionator.Utilities or {}

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

local function GetCraftingQualityTier(itemID, itemLink)
  if not C_TradeSkillUI then
    return nil
  end

  local quality
  if C_TradeSkillUI.GetItemCraftedQualityByItemInfo then
    quality = (itemLink and C_TradeSkillUI.GetItemCraftedQualityByItemInfo(itemLink))
      or (itemID and C_TradeSkillUI.GetItemCraftedQualityByItemInfo(itemID))
  end

  if not quality and C_TradeSkillUI.GetItemReagentQualityByItemInfo then
    quality = (itemLink and C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemLink))
      or (itemID and C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemID))
  end

  return quality
end

local function GetProfessionTemplateQualityTier(itemID, itemLevel)
  if not Auctionator.ProfessionQualityTemplates then
    return nil
  end

  return Auctionator.ProfessionQualityTemplates.GetTier(itemID, itemLevel)
end

function Auctionator.Utilities.GetItemQualityTier(itemID, itemLink, itemLevel, classID)
  if not Auctionator.Constants.IsRetail or not itemID then
    return nil
  end

  local qualityTier
  local isEquipment = classID ~= nil and Auctionator.Utilities.IsEquipment(classID)

  if isEquipment then
    qualityTier = GetTrackQualityTier(itemLink)

    if not qualityTier and IsProfessionEquipmentItem(itemID, itemLink) then
      qualityTier = GetProfessionLinkQualityTier(itemLink)
        or GetProfessionTemplateQualityTier(itemID, itemLevel)
        or GetCraftingQualityTier(itemID, itemLink)
    end
  else
    qualityTier = GetCraftingQualityTier(itemID, itemLink)
  end

  if qualityTier and qualityTier >= 1 and qualityTier <= 5 then
    return qualityTier
  end

  return nil
end
