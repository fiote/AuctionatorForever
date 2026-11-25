AuctionatorShoppingListManagerMixin = {}

local itemOrder = { Foods = 1, Drinks = 2, Potions = 3, Elixirs = 4, Burst = 5 }

-- getData: function() -> table. Returns raw shopping list data storage
-- setData: function(newVal) newVal: table -> nil. Used to overwrite the
--  shopping list data storage with new data
function AuctionatorShoppingListManagerMixin:Init(getData, setData)
  assert(type(getData) == "function" and type(setData) == "function")
  self.getData = getData
  self.setData = setData

  if self.getData() == nil then
    self.setData({})
  end

  Auctionator.EventBus:RegisterSource(self, "shopping list manager")

  self:Prune()
  self:Sort()
end

function AuctionatorShoppingListManagerMixin:Create(listName, isTemporary)
  isTemporary = isTemporary or false

  assert(type(listName) == "string")
  assert(type(isTemporary) == "boolean")

  table.insert(self.getData(), {
    name = listName,
    items = {},
    isTemporary = isTemporary,
  })

  self:Sort()

  self:FireMetaChangeEvent(listName)
end

local function GetGearSuggestion(category)
  local getGear = Auctionator.Shopping.GetGearSuggestion
  return getGear and getGear(category) or nil
end

local function GetSuggestedListName(category)
  local gear = GetGearSuggestion(category)
  if gear then
    return "[Gear] " .. gear.name
  end
  return "[Item] " .. (category == "Burst" and "Bursts" or category)
end

local function GetListSortKey(list)
  local category = list.suggestedCategory
  local gear = GetGearSuggestion(category)
  -- Use one alphabetical position for both generated groups.
  if gear then
    return "[gear]", 2, gear.order
  elseif category then
    return "[gear]", 1, itemOrder[category] or math.huge
  end
  return list.name:lower(), 3, 0
end

function AuctionatorShoppingListManagerMixin:Sort()
  table.sort(self.getData(), function(left, right)
    local leftKey, leftGroup, leftOrder = GetListSortKey(left)
    local rightKey, rightGroup, rightOrder = GetListSortKey(right)
    if leftKey ~= rightKey then
      return leftKey < rightKey
    elseif leftGroup ~= rightGroup then
      return leftGroup < rightGroup
    elseif leftOrder ~= rightOrder then
      return leftOrder < rightOrder
    end
    return left.name < right.name
  end)

  self:FireMetaChangeEvent()
end

function AuctionatorShoppingListManagerMixin:UpdateSuggestedLists(suggestions)
  local lists = self.getData()
  local updated = {}

  for index = #lists, 1, -1 do
    local list = lists[index]
    if list.suggestedCategory then
      local items = suggestions[list.suggestedCategory]
      if items then
        local name = GetSuggestedListName(list.suggestedCategory)
        list.name = self:GetUnusedName(name, list.name)
        list.items = items
        updated[list.suggestedCategory] = true
      else
        table.remove(lists, index)
      end
    end
  end

  for category, items in pairs(suggestions) do
    if not updated[category] then
      local name = GetSuggestedListName(category)
      table.insert(lists, {
        name = self:GetUnusedName(name),
        items = items,
        isTemporary = true,
        suggestedCategory = category,
      })
    end
  end

  self:Sort()
end

function AuctionatorShoppingListManagerMixin:Prune()
  local lists = {}

  for _, list in ipairs(self.getData()) do
    if not list.isTemporary then
      table.insert(lists, list)
    end
  end

  self.setData(lists)

  self:FireMetaChangeEvent()
end

function AuctionatorShoppingListManagerMixin:GetIndexForName(listName)
  for index, list in ipairs(self.getData()) do
    if list.name == listName then
      return index
    end
  end

  return nil
end

function AuctionatorShoppingListManagerMixin:GetCount()
  return #self.getData()
end

function AuctionatorShoppingListManagerMixin:GetByIndex(listIndex)
  local data =  self.getData()[listIndex]
  assert(data, "List index doesn't exist")

  return CreateAndInitFromMixin(AuctionatorShoppingListMixin, data, self)
end

function AuctionatorShoppingListManagerMixin:GetByName(listName)
  return self:GetByIndex(self:GetIndexForName(listName))
end

function AuctionatorShoppingListManagerMixin:Delete(listName)
  local listIndex = self:GetIndexForName(listName)
  assert(listIndex ~= nil, "List doesn't exist")

  table.remove(self.getData(), listIndex)

  self:FireMetaChangeEvent(listName)
end

function AuctionatorShoppingListManagerMixin:GetUnusedName(prefix, currentName)
  local currentIndex = 1
  local newName = prefix

  while newName ~= currentName and self:GetIndexForName(newName) ~= nil do
    currentIndex = currentIndex + 1
    newName = prefix .. " " .. currentIndex
  end

  return newName
end

function AuctionatorShoppingListManagerMixin:FireItemChangeEvent(listName)
  Auctionator.EventBus:Fire(self, Auctionator.Shopping.Events.ListItemChange, listName)
end

function AuctionatorShoppingListManagerMixin:FireMetaChangeEvent(listName)
  Auctionator.EventBus:Fire(self, Auctionator.Shopping.Events.ListMetaChange, listName)
end
