local DEFAULT_HISTORICAL_PRICE_COLOR = {1, 1, 1, 1}
local LOWEST_HISTORICAL_PRICE_COLOR = {1, 0.72, 0.45, 1}

local function GetHistoricalPriceRowColor(rowData)
  if rowData ~= nil and rowData.isLowestHistoricalPrice then
    return LOWEST_HISTORICAL_PRICE_COLOR
  end

  return DEFAULT_HISTORICAL_PRICE_COLOR
end

local function SetMoneyDisplayTextColor(moneyDisplay, color)
  if moneyDisplay == nil then
    return
  end

  local displays = {
    moneyDisplay.GoldDisplay,
    moneyDisplay.SilverDisplay,
    moneyDisplay.CopperDisplay,
  }

  for _, display in ipairs(displays) do
    if display ~= nil and display.Text ~= nil then
      display.Text:SetTextColor(unpack(color))
    end
  end
end

AuctionatorHistoricalPriceCellTemplateMixin = CreateFromMixins(AuctionatorPriceCellTemplateMixin)

function AuctionatorHistoricalPriceCellTemplateMixin:Populate(rowData, index)
  AuctionatorPriceCellTemplateMixin.Populate(self, rowData, index)

  SetMoneyDisplayTextColor(self.MoneyDisplay, GetHistoricalPriceRowColor(rowData))
end

AuctionatorHistoricalStringCellTemplateMixin = CreateFromMixins(AuctionatorStringCellTemplateMixin)

function AuctionatorHistoricalStringCellTemplateMixin:Populate(rowData, index)
  AuctionatorStringCellTemplateMixin.Populate(self, rowData, index)

  self.text:SetTextColor(unpack(GetHistoricalPriceRowColor(rowData)))
end
