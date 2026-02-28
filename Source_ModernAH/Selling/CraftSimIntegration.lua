local function IsCraftSimLoaded()
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    return C_AddOns.IsAddOnLoaded("CraftSim")
  end

  return IsAddOnLoaded and IsAddOnLoaded("CraftSim")
end

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

function Auctionator.Selling.TrySelectOpenProfessionRecipe(itemID)
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

  local recipeIDLookup = {}
  for _, recipeID in ipairs(recipeIDs) do
    recipeIDLookup[recipeID] = true
  end

  local recipeID = GetCraftSimRecipeID(itemID)
  if recipeID and not recipeIDLookup[recipeID] then
    recipeID = nil
  end

  if not recipeID then
    recipeID = FindRecipeIDForItem(itemID, recipeIDs)
  end

  if recipeID then
    C_TradeSkillUI.OpenRecipe(recipeID)
  end
end
