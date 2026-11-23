if not Auctionator.Constants.IsForever or GetLocale() ~= "enUS" then
  return
end

local foodAndDrink = 5
local bandage = 7
local potion = 1
local elixir = 2
local firstAidSkillLine = 129
local foreverFirstAidSkillLine = 2942
local categories = {
  [potion] = "Potions",
  [elixir] = "Elixirs",
  [3] = "Flasks",
  [bandage] = "Bandages",
}

local currentScan
local foodAndDrinkDetails = {}
local potionAndElixirDetails = {}

local statPatterns = {
  { "HP5", "health%s+every%s+5%s+sec", "health%s+per%s+5%s+sec" },
  { "MP5", "mana%s+every%s+5%s+sec", "mana%s+per%s+5%s+sec" },
  { "Armor Penetration", "armor penetration" },
  { "Armor", "armor" },
  { "Strength", "strength" },
  { "Agility", "agility" },
  { "Stamina", "stamina" },
  { "Intellect", "intellect" },
  { "Spirit", "spirit" },
  { "Fishing", "fishing skill", "fishing" },
  { "Health", "maximum health", "max health", "health%s+by" },
  { "Mana", "maximum mana", "max mana", "mana%s+by" },
  { "Attack Power", "attack power" },
  { "Arcane Damage", "arcane damage", "arcane spell damage", "damage done by arcane spells" },
  { "Fire Damage", "fire damage", "fire spell damage", "damage done by fire spells" },
  { "Frost Damage", "frost damage", "frost spell damage", "damage done by frost spells" },
  { "Holy Damage", "holy damage", "holy spell damage", "damage done by holy spells" },
  { "Nature Damage", "nature damage", "nature spell damage", "damage done by nature spells" },
  { "Shadow Damage", "shadow damage", "shadow spell damage", "damage done by shadow spells" },
  { "Spell Power", "spell power", "spell damage", "damage done by spells" },
  { "Healing", "healing done by spells and effects", "healing done by spells", "spell healing", "healing power", "bonus healing" },
  { "Damage", "physical damage", "weapon damage", "damage" },
  { "Critical Strike", "critical strike", "critical hit" },
  { "Hit", "hit rating", "chance to hit" },
  { "Haste", "haste" },
  { "Defense", "defense" },
  { "Dodge", "dodge" },
  { "Resistance", "resistance to all schools of magic", "resistance" },
  { "Movement Speed", "movement speed", "run speed", "running speed" },
  { "Damage Absorption", "damage absorbed" },
}

local function TooltipLineText(line)
  return (line.leftText or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local function RestoredAmount(effect, resource, otherResource)
  local resourceWord = resource .. "%f[%A]"
  if effect:match(resource .. "%s+per%f[%A]") or effect:match(resource .. "%s+every%f[%A]")
      or effect:match(resource .. "%s+each%f[%A]") then
    return
  end

  local amount = effect:match("^(%d[%d,]*)%s+" .. resourceWord)
    or effect:match("^%d[%d,]*%s+" .. otherResource .. "%s+and%s+(%d[%d,]*)%s+" .. resourceWord)
    or effect:match("^(%d[%d,]*)%s+" .. otherResource .. "%s+and%s+" .. resourceWord)
  if amount then
    return tonumber((amount:gsub(",", "")))
  end
end

local ParseConsumableEffect

local function FoodOrDrink(itemID)
  local cached = foodAndDrinkDetails[itemID]
  if cached then
    return cached.category, cached.value, cached.stat, cached.statValue
  end

  -- The client uses one subclass for both foods and drinks.
  local tooltip = C_TooltipInfo.GetItemByID(itemID)
  if not tooltip or not tooltip.lines or #tooltip.lines == 0 then
    return
  end

  local restoresMana, restoresHealth, drink = false, false, false
  local health, mana, stat, statValue
  for _, line in ipairs(tooltip.lines) do
    local text = TooltipLineText(line):lower():gsub("%s+", " ")
    if text:match("^%s*use:") then
      restoresMana = restoresMana or text:find("restores?[^%.]*%f[%a]mana%f[%A]") ~= nil
      restoresHealth = restoresHealth or text:find("restores?[^%.]*%f[%a]health%f[%A]") ~= nil
      drink = drink or text:find("drink", 1, true) ~= nil
        or text:find("alcohol", 1, true) ~= nil or text:find("intoxicat", 1, true) ~= nil

      for effect in text:gmatch("restores?%s+([^%.]+)") do
        health = health or RestoredAmount(effect, "health", "mana")
        mana = mana or RestoredAmount(effect, "mana", "health")
      end

      local buff = text:match("well fed%s+(.+)") or text:match("(%f[%a]gains?%s+%d.+)")
      if buff and not stat then
        stat, statValue = ParseConsumableEffect(buff)
      end
    end
  end

  local category = "Foods"
  local value = health or 0
  if drink or (restoresMana and not restoresHealth) then
    category = "Drinks"
    value = mana or 0
    stat, statValue = nil, nil
  end
  foodAndDrinkDetails[itemID] = { category = category, value = value, stat = stat, statValue = statValue }
  return category, value, stat, statValue
end

function Auctionator.Shopping.GetFoodOrDrinkValue(itemID)
  if not itemID or itemID <= 0 then
    return 0
  end
  local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(itemID)
  if class ~= Enum.ItemClass.Consumable or subclass ~= foodAndDrink then
    return 0
  end

  local _, value, stat, statValue = FoodOrDrink(itemID)
  return value, stat, statValue
end

ParseConsumableEffect = function(text)
  text = text:gsub("%s+", " ")
  local duration, unit = text:match("breathe water for (%d+)%s+(%a+)")
  if not duration then
    duration, unit = text:match("water breathing for (%d+)%s+(%a+)")
  end
  if duration then
    local minutes = tonumber(duration)
    if unit:match("^hour") then
      return "Waterbreathing", minutes * 60
    elseif unit:match("^sec") then
      return "Waterbreathing", minutes / 60
    elseif unit:match("^min") then
      return "Waterbreathing", minutes
    end
  end

  local firstStat, firstPosition, firstValue
  for _, stat in ipairs(statPatterns) do
    for index = 2, #stat do
      local position, ending = text:find("%f[%a]" .. stat[index] .. "%f[%A]")
      if position and (not firstPosition or position < firstPosition) then
        local beforeStat = text:sub(1, position - 1)
        local afterStat = text:sub(ending + 1)
        local amount = afterStat:match("^%s+by%s+(%d[%d,%.]*)")
          or afterStat:match("^%s+by up to%s+(%d[%d,%.]*)")
          or afterStat:match("^%s+goes up by%s+(%d[%d,%.]*)")
          or beforeStat:match("(%d[%d,%.]*)%s+$")
        if not amount and text:sub(position, ending):match(" by$") then
          amount = afterStat:match("^%s+(%d[%d,%.]*)")
        end
        local value = amount and tonumber((amount:gsub(",", ""):gsub("%.$", "")))
        if value then
          firstStat, firstPosition, firstValue = stat[1], position, value
        end
      end
    end
  end
  return firstStat, firstValue
end

local recoveryResources = { health = "Health", mana = "Mana", rage = "Rage" }
local recoveryVerbs = { "restores?", "gains?", "generates?", "grants?", "gives?", "heals? you for", "increases? rage by" }

local function ParsePotionEffect(text)
  text = text:gsub("%s+", " "):gsub("–", "-")
  for _, verb in ipairs(recoveryVerbs) do
    local amount = text:match("%f[%a]" .. verb .. "%s+(.+)")
    if amount then
      amount = amount:gsub("^up to%s+", ""):gsub("^an?%s+additional%s+", "")
      local low, high, ending = amount:match("^(%d[%d,]*)%s+to%s+(%d[%d,]*)()")
      if not low then
        low, high, ending = amount:match("^(%d[%d,]*)%s*%-%s*(%d[%d,]*)()")
      end
      if not low then
        low, ending = amount:match("^(%d[%d,]*)()")
      end
      local suffix = ending and amount:sub(ending)
      local resource = suffix and (suffix:match("^%s+points?%s+of%s+(%a+)") or suffix:match("^%s+(%a+)"))
      local stat = recoveryResources[resource]
      if verb == "increases? rage by" then
        stat = "Rage"
      elseif verb == "heals? you for" then
        stat = "Health"
      end
      if low and stat then
        local minimum = tonumber((low:gsub(",", "")))
        local maximum = high and tonumber((high:gsub(",", ""))) or minimum
        return stat, (minimum + maximum) / 2, "Potions"
      end
    end
  end

  local low, high, school = text:match("absorbs?%s+(%d[%d,]*)%s+to%s+(%d[%d,]*)%s+(%a+)%s+damage")
  if low then
    local minimum = tonumber((low:gsub(",", "")))
    local maximum = tonumber((high:gsub(",", "")))
    return school:gsub("^%l", string.upper) .. " Absorption", (minimum + maximum) / 2, "Burst"
  end

  local stat, value = ParseConsumableEffect(text)
  if stat then
    return stat, value, "Burst"
  end
end

function Auctionator.Shopping.GetPotionOrElixirStat(itemID)
  if not itemID or itemID <= 0 then
    return ""
  end
  local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(itemID)
  if class ~= Enum.ItemClass.Consumable or (subclass ~= elixir and subclass ~= potion) then
    return ""
  end
  local cached = potionAndElixirDetails[itemID]
  if cached then
    return cached.stat, cached.value, nil, cached.category
  end

  local parseEffect = subclass == potion and ParsePotionEffect or ParseConsumableEffect
  local tooltip = C_TooltipInfo.GetItemByID(itemID)
  for _, line in ipairs(tooltip and tooltip.lines or {}) do
    local stat, value, category = parseEffect(TooltipLineText(line):lower())
    if stat then
      potionAndElixirDetails[itemID] = { stat = stat, value = value, category = category }
      return stat, value, nil, category
    end
  end

  -- Some item-use text is supplied by the spell rather than the raw item tooltip.
  local _, spellID = C_Item.GetItemSpell(itemID)
  if spellID then
    local description = C_Spell.GetSpellDescription(spellID)
    if not description or description == "" then
      return nil, nil, spellID
    end
    local stat, value, category = parseEffect(description:lower())
    if stat then
      potionAndElixirDetails[itemID] = { stat = stat, value = value, category = category }
      return stat, value, nil, category
    end
  end

  if tooltip and tooltip.lines and #tooltip.lines > 0 then
    return ""
  end
end

local function BandageFirstAidRequirement(itemID)
  local tooltip = C_TooltipInfo.GetItemByID(itemID)
  if not tooltip or not tooltip.lines or #tooltip.lines == 0 then
    return
  end

  for _, line in ipairs(tooltip.lines) do
    local text = TooltipLineText(line)
    if text:match("^%s*Requires First Aid%f[%A]") then
      if text:match("^%s*Requires First Aid%s*$") then
        return 1
      end
      return tonumber(text:match("First Aid%s*%(%s*(%d+)%s*%)"))
    end
  end
  return 0
end

local function GetSkillRank(skillLine)
  local skill = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID and C_SkillInfo.GetSkillLineInfoByID(skillLine)
  local rank = skill and skill.rank
  if (issecretvalue and issecretvalue(rank)) or type(rank) ~= "number" then
    return 0
  end
  return rank
end

local QueueRefresh

local function GetSavedSuggestionItems()
  local state = Auctionator.SavedState
  local savedScans = state and state.SuggestedConsumablesByRealm
  return savedScans and savedScans[Auctionator.Variables.GetConnectedRealmRoot()]
end

local defaultSuggestedStats = {
  Foods = { "Agility", "Strength", "Stamina", "Intellect", "Fishing" },
  Elixirs = {
    "Agility", "Armor", "Damage", "Healing", "Health", "HP5", "Intellect",
    "MP5", "Spell Power", "Spirit", "Stamina", "Strength", "Waterbreathing",
  },
  Burst = {
    "Arcane Absorption", "Attack Power", "Fire Absorption", "Frost Absorption", "Healing",
    "Holy Absorption", "Movement Speed", "Nature Absorption", "Resistance", "Shadow Absorption", "Spell Power",
  },
}

function Auctionator.Shopping.IsSuggestedStatEnabled(category, stat)
  local filters = AUCTIONATOR_SUGGESTION_FILTERS
  local categoryFilters = filters and filters[category:lower()]
  return not categoryFilters or categoryFilters[stat] ~= false
end

function Auctionator.Shopping.GetSuggestedStats(category)
  local stats = {}
  for _, stat in ipairs(defaultSuggestedStats[category]) do
    stats[stat] = true
  end
  local filters = AUCTIONATOR_SUGGESTION_FILTERS
  for stat in pairs(filters and filters[category:lower()] or {}) do
    stats[stat] = true
  end
  for _, item in ipairs(currentScan and currentScan.items or GetSavedSuggestionItems() or {}) do
    if item.category == category and item.stat then
      stats[item.stat] = true
    end
  end

  stats[""] = nil
  local ordered = {}
  for stat in pairs(stats) do
    table.insert(ordered, stat)
  end
  table.sort(ordered)
  if category == "Foods" then
    table.insert(ordered, "")
  end
  return ordered
end

local function GetSuggestedPotionOrElixirDetails(scan, item)
  if item.stat and (item.damageSchoolParsed or (item.stat ~= "Damage" and item.stat ~= "Spell Power")) then
    return item.stat, item.value
  end

  local itemID = item.itemID
  if not itemID then
    local name = Auctionator.Search.SplitAdvancedSearch(item.term).searchString
    itemID = C_Item.GetItemInfoInstant(name)
    item.itemID = itemID
  end
  if not itemID then
    return
  end

  local stat, value, spellID, category = Auctionator.Shopping.GetPotionOrElixirStat(itemID)
  if stat and stat ~= "" then
    item.stat, item.value = stat, value
    item.damageSchoolParsed = true
    item.category = category or item.category
    return stat, value
  end

  if stat == nil and scan.requestedElixirs and not scan.requestedElixirs[itemID] then
    scan.requestedElixirs[itemID] = true
    if spellID then
      Spell:CreateFromSpellID(spellID):ContinueOnSpellLoad(function()
        QueueRefresh(scan)
      end)
    else
      Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
        local _, _, pendingSpellID = Auctionator.Shopping.GetPotionOrElixirStat(itemID)
        if pendingSpellID then
          Spell:CreateFromSpellID(pendingSpellID):ContinueOnSpellLoad(function()
            QueueRefresh(scan)
          end)
        else
          QueueRefresh(scan)
        end
      end)
    end
  end
end

local function BuildSuggestions(scan, level)
  local suggestions, seen = {}, {}
  local firstAidRank = math.max(GetSkillRank(firstAidSkillLine), GetSkillRank(foreverFirstAidSkillLine))
  local potionResources = { Health = true }
  local maxMana = UnitPowerMax("player", Enum.PowerType.Mana)
  local minimumDrinkValue
  if not (issecretvalue and issecretvalue(maxMana)) and type(maxMana) == "number" then
    minimumDrinkValue = maxMana / 2
    potionResources.Mana = maxMana > 0
  end
  local maxRage = UnitPowerMax("player", Enum.PowerType.Rage)
  if not (issecretvalue and issecretvalue(maxRage)) and type(maxRage) == "number" then
    potionResources.Rage = maxRage > 0
  end
  local minimumFoodValue
  local maxHealth = UnitHealthMax("player")
  if not (issecretvalue and issecretvalue(maxHealth)) and type(maxHealth) == "number" and maxHealth > 0 then
    minimumFoodValue = maxHealth / 2
  end

  for _, item in pairs(scan.items) do
    if item.requiredLevel <= level and item.requiredFirstAid <= firstAidRank then
      local category = item.category
      if category == "Potions" or category == "Burst" then
        GetSuggestedPotionOrElixirDetails(scan, item)
        category = item.stat and item.category or nil
      end
      if (category == "Drinks" and item.value == nil)
          or (category == "Foods" and (item.value == nil or item.stat == nil)) then
        local itemID = item.itemID
        if not itemID then
          local name = Auctionator.Search.SplitAdvancedSearch(item.term).searchString
          itemID = C_Item.GetItemInfoInstant(name)
        end
        if itemID then
          local _, value, stat = FoodOrDrink(itemID)
          if value ~= nil then
            item.value = value
            if category == "Foods" then
              item.stat = stat or ""
            end
          elseif not scan.requestedFoodOrDrinks[itemID] then
            scan.requestedFoodOrDrinks[itemID] = true
            Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
              QueueRefresh(scan)
            end)
          end
        end
      end
      local meetsRecoveryRequirement = (category ~= "Drinks" or (minimumDrinkValue and (item.value or 0) > minimumDrinkValue))
        and (category ~= "Foods" or (minimumFoodValue and (item.value or 0) >= minimumFoodValue
          and Auctionator.Shopping.IsSuggestedStatEnabled(category, item.stat or "")))
        and (category ~= "Potions" or potionResources[item.stat])
      local meetsStatRequirement = true
      if category == "Elixirs" or category == "Burst" then
        local stat = GetSuggestedPotionOrElixirDetails(scan, item)
        meetsStatRequirement = stat and Auctionator.Shopping.IsSuggestedStatEnabled(category, stat)
      end
      if category and meetsRecoveryRequirement and meetsStatRequirement then
        if not suggestions[category] then
          suggestions[category] = {}
          seen[category] = {}
        end
        if not seen[category][item.term] then
          seen[category][item.term] = true
          table.insert(suggestions[category], item.term)
        end
      end
    end
  end

  for _, terms in pairs(suggestions) do
    table.sort(terms)
  end

  return suggestions
end

local function RefreshLists(scan, level)
  Auctionator.Shopping.ListManager:UpdateSuggestedLists(BuildSuggestions(scan, level))
end

QueueRefresh = function(scan)
  if scan.refreshQueued then
    return
  end
  scan.refreshQueued = true
  C_Timer.After(0.2, function()
    scan.refreshQueued = false
    if currentScan == scan then
      RefreshLists(scan, UnitLevel("player"))
    end
  end)
end

function Auctionator.Shopping.GenerateSuggestions(silent)
  if not currentScan then
    local items = GetSavedSuggestionItems()
    if not items then
      if not silent then
        Auctionator.Utilities.Message(AUCTIONATOR_L_GENERATE_SUGGESTIONS_NO_SCAN)
      end
      return
    end
    currentScan = { items = items, requestedElixirs = {}, requestedFoodOrDrinks = {} }
  end

  RefreshLists(currentScan, UnitLevel("player"))
end

function Auctionator.Shopping.SetSuggestedStatEnabled(category, stat, enabled)
  AUCTIONATOR_SUGGESTION_FILTERS = AUCTIONATOR_SUGGESTION_FILTERS or {}
  local filters = AUCTIONATOR_SUGGESTION_FILTERS
  local key = category:lower()
  filters[key] = filters[key] or {}
  if enabled then
    filters[key][stat] = nil
  else
    filters[key][stat] = false
  end
  Auctionator.Shopping.GenerateSuggestions(true)
end

local function GetSuggestionItem(itemID, subclass)
  local name, _, _, _, requiredLevel = C_Item.GetItemInfo(itemID)
  if not name or not requiredLevel then
    return
  end

  local category, value, stat, statValue = categories[subclass], nil, nil, nil
  local requiredFirstAid = 0
  if subclass == foodAndDrink then
    category, value, stat, statValue = FoodOrDrink(itemID)
    if category == "Foods" then
      stat = stat or ""
    end
  elseif subclass == bandage then
    requiredFirstAid = BandageFirstAidRequirement(itemID)
    if not requiredFirstAid then
      return
    end
  end
  if category then
    return {
      category = category,
      itemID = itemID,
      value = value,
      stat = stat,
      statValue = statValue,
      requiredLevel = requiredLevel,
      requiredFirstAid = requiredFirstAid,
      term = Auctionator.Search.ReconstituteAdvancedSearch({
        searchString = name,
        isExact = true,
      }),
    }
  end
end

function Auctionator.Shopping.GetSuggestedSearchFilters(category)
  if category == "Foods" or category == "Drinks" then
    return { { classID = Enum.ItemClass.Consumable, subClassID = foodAndDrink } }
  end
  if category == "Burst" then
    return { { classID = Enum.ItemClass.Consumable, subClassID = potion } }
  end
  for subclass, name in pairs(categories) do
    if name == category then
      return { { classID = Enum.ItemClass.Consumable, subClassID = subclass } }
    end
  end
end

function Auctionator.Shopping.FilterSuggestedSearchResults(category, rows, callback)
  local scan = { items = {}, requestedFoodOrDrinks = {} }
  local candidates, requested = {}, {}
  local pending, finished = 1, false

  local function Finish()
    if finished then
      return
    end
    finished = true
    local suggestions = BuildSuggestions(scan, UnitLevel("player"))
    local terms = {}
    for _, term in ipairs(suggestions[category] or {}) do
      terms[term] = true
    end
    local results = {}
    for _, row in ipairs(rows) do
      local candidate = row.itemKey and candidates[row.itemKey.itemID]
      if candidate and terms[candidate.term] and (row.totalQuantity or 0) > 0 then
        row.searchTerm = candidate.term
        row.stat = candidate.stat or ""
        row.foodStatValue = candidate.statValue
        row.value = candidate.value or 0
        table.insert(results, row)
      end
    end
    callback(results)
  end

  local function ItemReady()
    pending = pending - 1
    if pending == 0 then
      Finish()
    end
  end

  for _, row in ipairs(rows) do
    local itemID = row.itemKey and row.itemKey.itemID
    if itemID and itemID > 0 and (row.totalQuantity or 0) > 0 and not requested[itemID] then
      requested[itemID] = true
      pending = pending + 1
      Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
        if finished then
          return
        end
        local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(itemID)
        local candidate = class == Enum.ItemClass.Consumable and GetSuggestionItem(itemID, subclass)
        local function AddCandidate(stat, value, effectCategory)
          if candidate then
            if stat and stat ~= "" then
              candidate.stat, candidate.value = stat, value
              candidate.damageSchoolParsed = true
              candidate.category = effectCategory or candidate.category
            end
            if candidate.category == category then
              candidates[itemID] = candidate
              table.insert(scan.items, candidate)
            end
          end
          ItemReady()
        end
        if candidate and (subclass == elixir or subclass == potion) then
          local stat, value, spellID, effectCategory = Auctionator.Shopping.GetPotionOrElixirStat(itemID)
          if spellID then
            Spell:CreateFromSpellID(spellID):ContinueOnSpellLoad(function()
              if not finished then
                local loadedStat, loadedValue, _, loadedCategory = Auctionator.Shopping.GetPotionOrElixirStat(itemID)
                AddCandidate(loadedStat, loadedValue, loadedCategory)
              end
            end)
          else
            AddCandidate(stat, value, effectCategory)
          end
        else
          AddCandidate()
        end
      end)
    end
  end
  ItemReady()
  if not finished then
    C_Timer.After(3, Finish)
  end
end

local function ScanCompleted(event, rows)
  local scan = { items = {}, requestedElixirs = {}, requestedFoodOrDrinks = {} }
  currentScan = scan
  local state = Auctionator.SavedState
  state.SuggestedConsumablesByRealm = state.SuggestedConsumablesByRealm or {}
  state.SuggestedConsumablesByRealm[Auctionator.Variables.GetConnectedRealmRoot()] = scan.items
  local seen = {}
  local isReplicate = event == Auctionator.FullScan.Events.ScanComplete

  for _, row in ipairs(rows) do
    local itemID
    if isReplicate then
      if (row.replicateInfo[3] or 0) > 0 and (row.replicateInfo[10] or 0) > 0 then
        itemID = row.replicateInfo[17]
      end
    elseif row.itemKey then
      itemID = row.itemKey.itemID
    end

    if itemID and itemID > 0 and not seen[itemID] then
      seen[itemID] = true
      local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(itemID)
      if class == Enum.ItemClass.Consumable and (categories[subclass] or subclass == foodAndDrink) then
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
          if currentScan == scan then
            local item = GetSuggestionItem(itemID, subclass)
            if item then
              table.insert(scan.items, item)
              QueueRefresh(scan)
            end
          end
        end)
      end
    end
  end

  QueueRefresh(scan)
end

Auctionator.EventBus:Register({ ReceiveEvent = function(_, event, rows)
  ScanCompleted(event, rows)
end }, {
  Auctionator.FullScan.Events.ScanComplete,
  Auctionator.IncrementalScan.Events.ScanComplete,
})

local characterFrame = CreateFrame("Frame")
characterFrame:RegisterEvent("PLAYER_LEVEL_UP")
characterFrame:RegisterEvent("SKILL_LINES_CHANGED")
characterFrame:RegisterEvent("CHAT_MSG_SKILL")
characterFrame:SetScript("OnEvent", function(_, event, value)
  if not currentScan then
    return
  end

  if event == "PLAYER_LEVEL_UP" then
    RefreshLists(currentScan, value)
  elseif event == "SKILL_LINES_CHANGED"
      or (value and not (issecretvalue and issecretvalue(value)) and value:find("First Aid", 1, true)) then
    QueueRefresh(currentScan)
  end
end)
