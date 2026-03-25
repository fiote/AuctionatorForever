AuctionatorGroupsViewItemMixin = {}

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

local function GetReagentQualityTier(itemID, itemLink)
  if not C_TradeSkillUI then
    return nil
  end

  local quality
  if C_TradeSkillUI.GetItemCraftedQualityByItemInfo then
    if itemLink then
      quality = C_TradeSkillUI.GetItemCraftedQualityByItemInfo(itemLink)
    end
    if not quality and itemID then
      quality = C_TradeSkillUI.GetItemCraftedQualityByItemInfo(itemID)
    end
  end

  if not quality and C_TradeSkillUI.GetItemReagentQualityByItemInfo then
    if itemLink then
      quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemLink)
    end
    if not quality and itemID then
      quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemID)
    end
  end

  return quality
end

local function GetDisplayQualityTier(itemInfo)
  if not Auctionator.Constants.IsRetail or not itemInfo then
    return nil
  end

  local classID = itemInfo.classID or itemInfo.classId
  local isEquipment = classID ~= nil and Auctionator.Utilities.IsEquipment(classID)
  local isProfessionEquipment = IsProfessionEquipmentItem(itemInfo.itemID, itemInfo.itemLink)
  local isProfessionEntry = classID == Enum.ItemClass.Profession

  local qualityTier
  if isProfessionEntry or isProfessionEquipment then
    qualityTier = GetTrackQualityTier(itemInfo.itemLink)
      or GetProfessionLinkQualityTier(itemInfo.itemLink)
      or GetReagentQualityTier(itemInfo.itemID, itemInfo.itemLink)
  elseif not isEquipment then
    qualityTier = GetReagentQualityTier(itemInfo.itemID, itemInfo.itemLink)
  end

  if qualityTier and qualityTier >= 1 and qualityTier <= 5 then
    return qualityTier
  end

  return nil
end

local function GetExpiredSinceLastSale(itemLink)
  if Auctionator.Selling == nil or
     Auctionator.Selling.TSMAccounting == nil or
     type(Auctionator.Selling.TSMAccounting.GetExpiredSinceLastSale) ~= "function" then
    return 0
  end

  return Auctionator.Selling.TSMAccounting.GetExpiredSinceLastSale(itemLink) or 0
end

function AuctionatorGroupsViewItemMixin:SetClickEvent(eventName)
  self.clickEventName = eventName
end

function AuctionatorGroupsViewItemMixin:EnsureTSMExpiredText()
  if self.TSMExpiredText ~= nil then
    return
  end

  local text = self:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  text:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 3, 3)
  text:SetSize(22, 18)
  text:SetJustifyH("LEFT")
  text:SetShadowColor(0, 0, 0, 1)
  text:SetShadowOffset(1, -1)
  self.TSMExpiredText = text
end

function AuctionatorGroupsViewItemMixin:UpdateTSMExpiredText(info)
  if self.clickEventName ~= "BagUse.BagItemClicked" or info == nil then
    if self.TSMExpiredText ~= nil then
      self.TSMExpiredText:Hide()
    end
    return
  end

  self:EnsureTSMExpiredText()

  local expiredCount = GetExpiredSinceLastSale(info.itemLink)
  if expiredCount > 10 then
    self.TSMExpiredText:SetTextColor(1, 0.45, 0)
  elseif expiredCount >= 1 then
    self.TSMExpiredText:SetTextColor(1, 0.82, 0)
  else
    self.TSMExpiredText:SetTextColor(0.7, 0.7, 0.7)
  end

  self.TSMExpiredText:SetText(expiredCount)
  self.TSMExpiredText:Show()
end

function AuctionatorGroupsViewItemMixin:SetItemInfo(info)
  self.itemInfo = info

  if info ~= nil then

    self.Icon:SetTexture(info.iconTexture)
    self.Icon:Show()

    if info.selected then
      self.Icon:SetAlpha(0.8)
    else
      self.Icon:SetAlpha(1)
    end
    local selectedColor = {r=0.977, g=0.592, b=0.086}

    self.IconSelectedHighlight:SetVertexColor(selectedColor.r, selectedColor.g, selectedColor.b)
    self.IconSelectedHighlight:SetShown(info.selected)

    self.IconBorder:SetVertexColor(
      ITEM_QUALITY_COLORS[self.itemInfo.quality].r,
      ITEM_QUALITY_COLORS[self.itemInfo.quality].g,
      ITEM_QUALITY_COLORS[self.itemInfo.quality].b,
      1
    )
    self.IconBorder:SetShown(not info.selected)

    self.Text:SetText(info.itemCount)

    self:ApplyQualityIcon(info)
    self:UpdateTSMExpiredText(info)

  else
    self.IconBorder:Hide()
    self.Icon:Hide()
    self.Text:SetText("")
    self:SetAlpha(1)

    self:HideQualityIcon()
    self:UpdateTSMExpiredText(nil)
  end

  self.initializationTime = GetTime()
end

function AuctionatorGroupsViewItemMixin:OnEnter()
  if GetTime() - self.initializationTime > 0 then
    self:UpdateTooltip()
  end
end

function AuctionatorGroupsViewItemMixin:UpdateTooltip()
  if self.itemInfo ~= nil then
    if IsModifiedClick("DRESSUP") then
      ShowInspectCursor();
    else
      ResetCursor()
    end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if Auctionator.Utilities.IsPetLink(self.itemInfo.itemLink) then
      BattlePetToolTip_ShowLink(self.itemInfo.itemLink)
    else
      local success = pcall(GameTooltip.SetHyperlink, GameTooltip, self.itemInfo.itemLink)
      if success then
        GameTooltip:Show()
      end
    end
  end
end

function AuctionatorGroupsViewItemMixin:OnLeave()
  ResetCursor()
  if BattlePetTooltip then
    BattlePetTooltip:Hide()
  end
  GameTooltip:Hide()
end

function AuctionatorGroupsViewItemMixin:OnClick(button)
  if self.itemInfo ~= nil then
    if IsModifiedClick("DRESSUP") then
      -- Retail vs Classic functions
      (DressUpLink or DressUpItemLink)(self.itemInfo.itemLink)

    elseif IsModifiedClick("CHATLINK") then
      Auctionator.Utilities.InsertLink(self.itemInfo.itemLink)

    else
      Auctionator.Groups.CallbackRegistry:TriggerEvent(self.clickEventName, self, button)
    end
  end
end

function AuctionatorGroupsViewItemMixin:ApplyQualityIcon(itemInfo)
  local qualityTier = GetDisplayQualityTier(itemInfo)
  if qualityTier == nil then
    self:HideQualityIcon()
    return
  end

  if not self.ProfessionQualityOverlay then
    self.ProfessionQualityOverlay = self:CreateTexture(nil, "OVERLAY")
    self.ProfessionQualityOverlay:SetPoint("TOPLEFT", -2, 2)
    self.ProfessionQualityOverlay:SetDrawLayer("OVERLAY", 7)
  end
  self.ProfessionQualityOverlay:Show()

  local atlas = ("Professions-Icon-Quality-Tier%d-Inv"):format(qualityTier)
  self.ProfessionQualityOverlay:SetAtlas(atlas, TextureKitConstants.UseAtlasSize)
end

function AuctionatorGroupsViewItemMixin:HideQualityIcon()
  if self.ProfessionQualityOverlay then
    self.ProfessionQualityOverlay:Hide()
  end
end
