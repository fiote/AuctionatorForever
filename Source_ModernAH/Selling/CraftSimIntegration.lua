local function IsCraftSimLoaded()
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    return C_AddOns.IsAddOnLoaded("CraftSim")
  end

  return IsAddOnLoaded and IsAddOnLoaded("CraftSim")
end

local SWITCH_RETRY_DELAY = 0.1
local SWITCH_RETRY_ATTEMPTS = 20
local pendingSelectionToken = 0

local function IsProfessionFrameOpen()
  return ProfessionsFrame
      and ProfessionsFrame:IsShown()
      and C_TradeSkillUI
      and C_TradeSkillUI.IsTradeSkillReady
      and C_TradeSkillUI.IsTradeSkillReady()
end

local function GetCraftSimRecipeID(itemID)
  local craftSim = _G.CraftSim
  if not craftSim or not craftSim.DB or not craftSim.DB.ITEM_RECIPE or not craftSim.DB.ITEM_RECIPE.Get then
    return nil
  end

  local itemRecipeData = craftSim.DB.ITEM_RECIPE:Get(itemID)
  return itemRecipeData and itemRecipeData.recipeID or nil
end

local function IsMatchingRecipeOutput(recipeID, itemID)
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
