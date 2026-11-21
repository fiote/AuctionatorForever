function Auctionator.Groups.DoesGroupExist(name)
  return Auctionator.Groups.Utilities.IsContainedPredicate(AUCTIONATOR_SELLING_GROUPS.CustomGroups, function(item) return item.name == name end)
end
function Auctionator.Groups.AddGroup(name)
  assert(not Auctionator.Groups.DoesGroupExist(name), "Group already exists")

  table.insert(AUCTIONATOR_SELLING_GROUPS.CustomGroups, {
    name = name,
    type = Auctionator.Groups.Constants.GroupType.List,
    list = {},
    hidden = false,
  })
end

function Auctionator.Groups.GetGroupIndex(name)
  for index, s in ipairs(AUCTIONATOR_SELLING_GROUPS.CustomGroups) do
    if s.name == name then
      return index
    end
  end
  return nil
end

function Auctionator.Groups.GetGroupNameByIndex(index)
  return AUCTIONATOR_SELLING_GROUPS.CustomGroups[index] and AUCTIONATOR_SELLING_GROUPS.CustomGroups[index].name
end

function Auctionator.Groups.GetGroupList(name)
  return AUCTIONATOR_SELLING_GROUPS.CustomGroups[Auctionator.Groups.GetGroupIndex(name)].list
end

function Auctionator.Groups.HideItemLink(itemLink)
  table.insert(AUCTIONATOR_SELLING_GROUPS.HiddenItems, itemLink)
end

local TEMP_HIDDEN_ITEM_SECONDS = 48 * 60 * 60

function Auctionator.Groups.PruneTempHiddenItems()
  local tempHiddenItems = AUCTIONATOR_SELLING_GROUPS.TempHiddenItems or {}
  local oldestAllowed = time() - TEMP_HIDDEN_ITEM_SECONDS

  for itemLink, hiddenAt in pairs(tempHiddenItems) do
    if type(hiddenAt) ~= "number" or hiddenAt <= oldestAllowed then
      tempHiddenItems[itemLink] = nil
    end
  end

  AUCTIONATOR_SELLING_GROUPS.TempHiddenItems = tempHiddenItems
end

function Auctionator.Groups.TempHideItemLink(itemLink)
  AUCTIONATOR_SELLING_GROUPS.TempHiddenItems = AUCTIONATOR_SELLING_GROUPS.TempHiddenItems or {}
  Auctionator.Groups.PruneTempHiddenItems()
  AUCTIONATOR_SELLING_GROUPS.TempHiddenItems[itemLink] = time()
end

function Auctionator.Groups.TempUnhideItemLink(itemLink)
  if AUCTIONATOR_SELLING_GROUPS.TempHiddenItems then
    AUCTIONATOR_SELLING_GROUPS.TempHiddenItems[itemLink] = nil
  end
end

function Auctionator.Groups.UnhideItemLink(itemLink)
  local index = tIndexOf(AUCTIONATOR_SELLING_GROUPS.HiddenItems, itemLink)
  if index ~= nil then
    table.remove(AUCTIONATOR_SELLING_GROUPS.HiddenItems, index)
  end
end

function Auctionator.Groups.UnhideAll()
  AUCTIONATOR_SELLING_GROUPS.HiddenItems = {}
end

function Auctionator.Groups.GetHiddenItemLinks()
  return AUCTIONATOR_SELLING_GROUPS.HiddenItems
end

function Auctionator.Groups.GetTempHiddenItemLinks()
  Auctionator.Groups.PruneTempHiddenItems()

  local result = {}
  for itemLink in pairs(AUCTIONATOR_SELLING_GROUPS.TempHiddenItems) do
    table.insert(result, itemLink)
  end
  return result
end
