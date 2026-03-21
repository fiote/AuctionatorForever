local function IsCraftSimLoaded()
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    return C_AddOns.IsAddOnLoaded("CraftSim")
  end

  return IsAddOnLoaded and IsAddOnLoaded("CraftSim")
end

local SWITCH_RETRY_DELAY = 0.1
local SWITCH_RETRY_ATTEMPTS = 20
local pendingSelectionToken = 0
local RESULT_QUALITY_PRICE_STEP_FACTOR = 0.70
local recipeIDCache = {}
local IsMatchingRecipeOutput

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

local function IsProfessionFrameOpen()
  return ProfessionsFrame
      and ProfessionsFrame:IsShown()
      and C_TradeSkillUI
      and C_TradeSkillUI.IsTradeSkillReady
      and C_TradeSkillUI.IsTradeSkillReady()
end

local function GetCraftSimRecipeID(itemID)
  if recipeIDCache[itemID] ~= nil then
    return recipeIDCache[itemID] or nil
  end

  local craftSim = _G.CraftSim
  if not craftSim or not craftSim.DB or not craftSim.DB.ITEM_RECIPE or not craftSim.DB.ITEM_RECIPE.Get then
    return nil
  end

  local itemRecipeData = craftSim.DB.ITEM_RECIPE:Get(itemID)
  if itemRecipeData and itemRecipeData.recipeID then
    recipeIDCache[itemID] = itemRecipeData.recipeID
    return itemRecipeData.recipeID
  end

  local craftSimDB = _G.CraftSimDB
  local crafterData = craftSimDB and craftSimDB.crafterDB and craftSimDB.crafterDB.data or nil
  if not crafterData then
    recipeIDCache[itemID] = false
    return nil
  end

  local checkedRecipes = {}
  for _, data in pairs(crafterData) do
    for _, recipeIDs in pairs(data.cachedRecipeIDs or {}) do
      for _, recipeID in ipairs(recipeIDs) do
        if not checkedRecipes[recipeID] and IsMatchingRecipeOutput(recipeID, itemID) then
          recipeIDCache[itemID] = recipeID
          return recipeID
        end
        checkedRecipes[recipeID] = true
      end
    end
  end

  recipeIDCache[itemID] = false
  return nil
end

IsMatchingRecipeOutput = function(recipeID, itemID)
  if not C_TradeSkillUI.GetRecipeOutputItemData or not C_TradeSkillUI.GetRecipeInfo then
    return false
  end

  local outputData = C_TradeSkillUI.GetRecipeOutputItemData(recipeID)
  if outputData and outputData.itemID == itemID then
    return true
  end

  local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
  if not recipeInfo or not recipeInfo.qualityIDs then
    return false
  end

  for _, qualityID in ipairs(recipeInfo.qualityIDs) do
    local qualityOutputData = C_TradeSkillUI.GetRecipeOutputItemData(recipeID, nil, nil, qualityID)
    if qualityOutputData and qualityOutputData.itemID == itemID then
      return true
    end
  end

  return false
end

local function FindRecipeIDForItem(itemID, recipeIDs)
  for _, recipeID in ipairs(recipeIDs) do
    if IsMatchingRecipeOutput(recipeID, itemID) then
      return recipeID
    end
  end

  return nil
end

local function BuildRecipeLookup(recipeIDs)
  local lookup = {}
  for _, recipeID in ipairs(recipeIDs) do
    lookup[recipeID] = true
  end
  return lookup
end

local function OpenRecipeWhenAvailable(recipeID, selectionToken, attemptsLeft)
  if selectionToken ~= pendingSelectionToken
      or attemptsLeft <= 0
      or not IsProfessionFrameOpen()
      or not C_TradeSkillUI.GetAllRecipeIDs
      or not C_TradeSkillUI.OpenRecipe then
    return
  end

  local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
  if recipeIDs and #recipeIDs > 0 and BuildRecipeLookup(recipeIDs)[recipeID] then
    C_TradeSkillUI.OpenRecipe(recipeID)
    return
  end

  if C_Timer and C_Timer.After then
    C_Timer.After(SWITCH_RETRY_DELAY, function()
      OpenRecipeWhenAvailable(recipeID, selectionToken, attemptsLeft - 1)
    end)
  end
end

local function TrySwitchProfessionAndOpenRecipe(recipeID, selectionToken)
  if not C_TradeSkillUI.GetProfessionInfoByRecipeID
      or not C_TradeSkillUI.OpenTradeSkill
      or not C_TradeSkillUI.GetProfessionChildSkillLineID then
    return false
  end

  local professionInfo = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
  local targetSkillLineID = professionInfo and professionInfo.professionID
  local currentSkillLineID = C_TradeSkillUI.GetProfessionChildSkillLineID()

  if not targetSkillLineID or targetSkillLineID == currentSkillLineID then
    return false
  end

  C_TradeSkillUI.OpenTradeSkill(targetSkillLineID)

  if C_Timer and C_Timer.After then
    OpenRecipeWhenAvailable(recipeID, selectionToken, SWITCH_RETRY_ATTEMPTS)
  elseif C_TradeSkillUI.OpenRecipe then
    C_TradeSkillUI.OpenRecipe(recipeID)
  end

  return true
end

function Auctionator.Selling.TrySelectOpenProfessionRecipe(itemID)
  pendingSelectionToken = pendingSelectionToken + 1
  local selectionToken = pendingSelectionToken

  if not itemID
      or not IsCraftSimLoaded()
      or not IsProfessionFrameOpen()
      or not C_TradeSkillUI.OpenRecipe
      or not C_TradeSkillUI.GetAllRecipeIDs then
    return
  end

  local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
  if not recipeIDs or #recipeIDs == 0 then
    return
  end

  local recipeIDLookup = BuildRecipeLookup(recipeIDs)

  local currentRecipeID = FindRecipeIDForItem(itemID, recipeIDs)
  if currentRecipeID then
    C_TradeSkillUI.OpenRecipe(currentRecipeID)
    return
  end

  local recipeID = GetCraftSimRecipeID(itemID)
  if not recipeID then
    return
  end

  if recipeIDLookup[recipeID] then
    C_TradeSkillUI.OpenRecipe(recipeID)
    return
  end

  if TrySwitchProfessionAndOpenRecipe(recipeID, selectionToken) then
    return
  end

  -- Final fallback: try opening directly even if it's not in the current list.
  C_TradeSkillUI.OpenRecipe(recipeID)
end

local function GetRecipeOutputsByQuality(recipeID)
  if not C_TradeSkillUI.GetRecipeInfo or not C_TradeSkillUI.GetRecipeOutputItemData then
    return {}
  end

  local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
  if not recipeInfo then
    return {}
  end

  local outputsByQuality = {}
  if recipeInfo.qualityIDs and #recipeInfo.qualityIDs > 0 then
    for qualityIndex, qualityID in ipairs(recipeInfo.qualityIDs) do
      outputsByQuality[qualityIndex] = C_TradeSkillUI.GetRecipeOutputItemData(recipeID, nil, nil, qualityID)
    end
  else
    outputsByQuality[1] = C_TradeSkillUI.GetRecipeOutputItemData(recipeID)
  end

  return outputsByQuality
end

local function GetQualityIndexForItem(outputsByQuality, itemID, itemLink)
  local itemQualityTier = GetProfessionLinkQualityTier(itemLink)

  for qualityIndex, outputData in ipairs(outputsByQuality) do
    if outputData then
      local outputQualityTier = GetProfessionLinkQualityTier(outputData.hyperlink)
      if outputQualityTier and itemQualityTier and outputQualityTier == itemQualityTier then
        return qualityIndex
      end

      if outputData.itemID == itemID then
        return qualityIndex
      end
    end
  end

  return nil
end

local function GetCraftSimQualityPrice(recipeID, qualityIndex, outputData)
  local craftSim = _G.CraftSim
  if not craftSim or not craftSim.PRICE_SOURCE then
    return 0
  end

  if craftSim.DB and craftSim.DB.PRICE_OVERRIDE and craftSim.DB.PRICE_OVERRIDE.GetResultOverridePrice then
    local overridePrice = craftSim.DB.PRICE_OVERRIDE:GetResultOverridePrice(recipeID, qualityIndex)
    if overridePrice then
      return overridePrice
    end
  end

  if outputData and outputData.hyperlink and craftSim.PRICE_SOURCE.GetMinBuyoutByItemLink then
    local linkPrice = craftSim.PRICE_SOURCE:GetMinBuyoutByItemLink(outputData.hyperlink)
    if linkPrice and linkPrice > 0 then
      return linkPrice
    end
  end

  if outputData and outputData.itemID and craftSim.PRICE_SOURCE.GetMinBuyoutByItemID then
    return craftSim.PRICE_SOURCE:GetMinBuyoutByItemID(outputData.itemID) or 0
  end

  return 0
end

local function NormalizeQualityPrices(rawQualityPrices)
  local normalizedQualityPrices = {}
  local nextHigherKnownPrice = nil
  local stepsFromHigherKnown = 1

  for qualityIndex = #rawQualityPrices, 1, -1 do
    local rawPrice = rawQualityPrices[qualityIndex] or 0
    local normalizedPrice = rawPrice

    if nextHigherKnownPrice and nextHigherKnownPrice > 0 and rawPrice > 0 then
      local maxAllowedPrice = math.floor(
        nextHigherKnownPrice * (RESULT_QUALITY_PRICE_STEP_FACTOR ^ stepsFromHigherKnown)
      )
      normalizedPrice = math.min(rawPrice, maxAllowedPrice)
    end

    normalizedQualityPrices[qualityIndex] = normalizedPrice

    if normalizedPrice > 0 then
      nextHigherKnownPrice = normalizedPrice
      stepsFromHigherKnown = 1
    elseif nextHigherKnownPrice and nextHigherKnownPrice > 0 then
      stepsFromHigherKnown = stepsFromHigherKnown + 1
    end
  end

  return normalizedQualityPrices
end

function Auctionator.Selling.GetCraftSimQualityPriceLimit(itemLink)
  if not itemLink or not IsCraftSimLoaded() then
    return nil
  end

  local itemID = C_Item.GetItemInfoInstant(itemLink)
  if not itemID then
    return nil
  end

  local recipeID = GetCraftSimRecipeID(itemID)
  if not recipeID then
    return nil
  end

  local outputsByQuality = GetRecipeOutputsByQuality(recipeID)
  if #outputsByQuality == 0 then
    return nil
  end

  local qualityIndex = GetQualityIndexForItem(outputsByQuality, itemID, itemLink)
  if not qualityIndex then
    return nil
  end

  local rawQualityPrices = {}
  for currentQualityIndex, outputData in ipairs(outputsByQuality) do
    rawQualityPrices[currentQualityIndex] = GetCraftSimQualityPrice(recipeID, currentQualityIndex, outputData)
  end

  return NormalizeQualityPrices(rawQualityPrices)[qualityIndex]
end

function Auctionator.Selling.ApplyCraftSimQualityPriceLimit(price, itemLink)
  if not price or price <= 0 or not itemLink then
    return price
  end

  local qualityPriceLimit = Auctionator.Selling.GetCraftSimQualityPriceLimit(itemLink)
  if qualityPriceLimit and qualityPriceLimit > 0 then
    return math.min(price, qualityPriceLimit)
  end

  return price
end
