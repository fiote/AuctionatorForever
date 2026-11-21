AuctionatorBagUseMixin = {}
function AuctionatorBagUseMixin:OnLoad()
  self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")

  Auctionator.EventBus:RegisterSource(self, "AuctionatorBagUseMixin")
  self.View.rowWidth = math.ceil(5 * 42 / Auctionator.Config.Get(Auctionator.Config.Options.SELLING_ICON_SIZE))
  self.awaitingCompletion = true

  Auctionator.EventBus:Register(self, {
    Auctionator.Selling.Events.BagItemRequest,
    Auctionator.Selling.Events.BagItemClicked,
  })
end

function AuctionatorBagUseMixin:OnShow()
  Auctionator.Groups.CallbackRegistry:RegisterCallback("BagUse.BagItemClicked", self.BagItemClicked, self)
  Auctionator.Groups.CallbackRegistry:RegisterCallback("BagUse.AddToDefaultGroup", self.AddToDefaultGroup, self)

  Auctionator.Groups.CallbackRegistry:RegisterCallback("ViewComplete", function(_, listsCached)
    self.awaitingCompletion = false
    if self.pendingKey then
      self:ReturnItem(self.pendingKey)
      self.pendingKey = nil
    elseif self.pendingItemID then
      local itemID = self.pendingItemID
      self.pendingItemID = nil
      if not self:SelectFirstItemByID(itemID) then
        Auctionator.EventBus:Fire(self, Auctionator.Selling.Events.ClearBagItem)
      end
    end
  end, self)
  Auctionator.Groups.CallbackRegistry:TriggerEvent("BagCacheOn")
end

function AuctionatorBagUseMixin:OnHide()
  self.View:SetSelected(nil)
  self.pendingItemID = nil
  Auctionator.Groups.CallbackRegistry:UnregisterCallback("BagUse.BagItemClicked", self)
  Auctionator.Groups.CallbackRegistry:UnregisterCallback("BagUse.AddToDefaultGroup", self)
  Auctionator.Groups.CallbackRegistry:UnregisterCallback("BagUse.RemoveFromDefaultGroup", self)
  Auctionator.Groups.CallbackRegistry:UnregisterCallback("ViewComplete", self)
  Auctionator.Groups.CallbackRegistry:TriggerEvent("BagCacheOff")
  self.awaitingCompletion = true
end

function AuctionatorBagUseMixin:ReturnItem(key)
  local button = (self.View.itemMap[key.keyName] and self.View.itemMap[key.keyName][key.sortKey])
  if not button then
    Auctionator.EventBus:Fire(self, Auctionator.Selling.Events.ClearBagItem)
  else
    button:Click()
  end
end

function AuctionatorBagUseMixin:SelectFirstItemByID(itemID)
  for _, group in ipairs(self.View.groups) do
    for _, button in ipairs(group.buttons) do
      if button.itemInfo and
         button.itemInfo.itemID == itemID and
         button.itemInfo.itemCount > 0 and
         button.itemInfo.auctionable then
        button:Click()
        return true
      end
    end
  end
  return false
end

function AuctionatorBagUseMixin:RefreshForGroupingChange(itemID)
  self.pendingKey = nil
  self.pendingItemID = itemID
  self.awaitingCompletion = true

  if self.View and self.View.RefreshHiddenItems then
    self.View:RefreshHiddenItems()
  end

  if AuctionatorBagCacheFrame then
    AuctionatorBagCacheFrame:DoBagRefresh()
  end
end

function AuctionatorBagUseMixin:ReceiveEvent(eventName, info, ...)
  if eventName == Auctionator.Selling.Events.BagItemRequest then
    if self.awaitingCompletion then
      self.pendingKey = info
    else
      self:ReturnItem(info)
    end
  elseif eventName == Auctionator.Selling.Events.BagItemClicked then
    if self:IsVisible() then
      self.View:SetSelected(info.key)
      self.View:ScrollToSelected()
    end
  elseif eventName == Auctionator.Selling.Events.ClearBagItem then
    self.View:SetSelected(nil)
  end
end

function AuctionatorBagUseMixin:BagItemClicked(button, mouseButton)
  if mouseButton == "LeftButton" then
    local postingInfo = Auctionator.Groups.Utilities.ToPostingItem(button.itemInfo)
    postingInfo.nextItem = button.nextItem
    postingInfo.prevItem = button.prevItem
    postingInfo.key = button.key
    postingInfo.sortKey = button.itemInfo.sortKey
    Auctionator.EventBus:Fire(self, Auctionator.Selling.Events.BagItemClicked, postingInfo)
  elseif mouseButton == "RightButton" then
    local defaultName = Auctionator.Groups.GetGroupNameByIndex(1)
    local isInDefaultGroup = self.View.itemMap[defaultName][button.itemInfo.sortKey] ~= nil
    local options = {}
    local defaultPrintName = _G["AUCTIONATOR_L_" .. defaultName] or defaultName
    MenuUtil.CreateContextMenu(self, function(_, rootDescription)
      if isInDefaultGroup then
        rootDescription:CreateButton(AUCTIONATOR_L_REMOVE_FROM_X:format(defaultPrintName), function() self:RemoveFromDefaultGroup(button) end)
      else
        rootDescription:CreateButton(AUCTIONATOR_L_ADD_TO_X:format(defaultPrintName), function() self:AddToDefaultGroup(button) end)
      end
      if not button.itemInfo.isCustom then
        if not self.View.hiddenItems[button.itemInfo.sortKey] then
          rootDescription:CreateButton(AUCTIONATOR_L_HIDE, function() self:HideItem(button) end)
        else
          rootDescription:CreateButton(AUCTIONATOR_L_UNHIDE, function() self:UnhideItem(button) end)
        end
        if self.View.tempHiddenItems[button.itemInfo.sortKey] then
          rootDescription:CreateButton(AUCTIONATOR_L_UNHIDE_TEMP, function() self:TempUnhideItem(button) end)
        else
          rootDescription:CreateButton(AUCTIONATOR_L_HIDE_TEMP, function() self:TempHideItem(button) end)
        end
        if next(self.View.hiddenItems) == nil then
          rootDescription:CreateTitle(GRAY_FONT_COLOR:WrapTextInColorCode(AUCTIONATOR_L_UNHIDE_ALL))
        else
          rootDescription:CreateButton(AUCTIONATOR_L_UNHIDE_ALL, function() self:UnhideAll() end)
        end
      end
    end)
  end
end

function AuctionatorBagUseMixin:AddToDefaultGroup(button)
  local defaultName = Auctionator.Groups.GetGroupNameByIndex(1)
  local defaultList = Auctionator.Groups.GetGroupList(defaultName)
  if self.View.itemMap[defaultName][button.itemInfo.sortKey] == nil then
    table.insert(defaultList, button.itemInfo.itemLink)
    Auctionator.Groups.CallbackRegistry:TriggerEvent("Customise.EditMade")
  end
end

function AuctionatorBagUseMixin:RemoveFromDefaultGroup(button)
  local defaultName = Auctionator.Groups.GetGroupNameByIndex(1)
  local defaultList = Auctionator.Groups.GetGroupList(defaultName)
  local info = self.View.itemMap[defaultName][button.itemInfo.sortKey].itemInfo
  for index, itemLink in ipairs(defaultList) do
    local sortKey = AuctionatorBagCacheFrame:GetByLinkInstant(itemLink, info.auctionable).sortKey
    if sortKey == info.sortKey then
      table.remove(defaultList, index)
      Auctionator.Groups.CallbackRegistry:TriggerEvent("Customise.EditMade")
      break
    end
  end
end

function AuctionatorBagUseMixin:HideItem(button)
  if not self.View.hiddenItems[button.itemInfo.sortKey] then
    local itemLink = button.itemInfo.itemLink
    Auctionator.Groups.HideItemLink(itemLink)
    Auctionator.Groups.CallbackRegistry:TriggerEvent("Customise.EditMade")
  end
end

function AuctionatorBagUseMixin:UnhideItem(button)
  local hiddenLink = self.View.hiddenItems[button.itemInfo.sortKey]
  if hiddenLink then
    Auctionator.Groups.UnhideItemLink(hiddenLink)
    Auctionator.Groups.CallbackRegistry:TriggerEvent("Customise.EditMade")
  end
end

function AuctionatorBagUseMixin:TempHideItem(button)
  Auctionator.Groups.TempHideItemLink(button.itemInfo.itemLink)
  Auctionator.Groups.CallbackRegistry:TriggerEvent("Customise.EditMade")
end

function AuctionatorBagUseMixin:TempUnhideItem(button)
  local sortKey = button.itemInfo.sortKey
  for _, link in ipairs(Auctionator.Groups.GetTempHiddenItemLinks()) do
    local info = AuctionatorBagCacheFrame:GetByLinkInstant(link, true)
    if info and info.sortKey == sortKey then
      Auctionator.Groups.TempUnhideItemLink(link)
    end
  end
  Auctionator.Groups.CallbackRegistry:TriggerEvent("Customise.EditMade")
end

function AuctionatorBagUseMixin:UnhideAll()
  Auctionator.Dialogs.ShowConfirm(AUCTIONATOR_L_CONFIRM_UNHIDE_ALL, ACCEPT, CANCEL, function()
    Auctionator.Groups.UnhideAll()
    Auctionator.Groups.CallbackRegistry:TriggerEvent("Customise.EditMade")
  end)
end
