AuctionatorShoppingPriceCellTemplateMixin = CreateFromMixins(AuctionatorStringCellTemplateMixin)

local RIGHT_PADDING = 8

function AuctionatorShoppingPriceCellTemplateMixin:SetMoneyLayout(isMoney)
  if self.moneyLayout == isMoney then
    return
  end
  self.moneyLayout = isMoney
  self.text:ClearAllPoints()
  if isMoney then
    self.text:SetJustifyH("RIGHT")
    self.text:SetPoint("TOPLEFT")
    self.text:SetPoint("BOTTOMRIGHT", -RIGHT_PADDING, 0)
  else
    self.text:SetJustifyH("LEFT")
    self.text:SetAllPoints(self)
  end
end

function AuctionatorShoppingPriceCellTemplateMixin:Init(columnName, isValueColumn)
  AuctionatorStringCellTemplateMixin.Init(self, columnName)
  self.isValueColumn = isValueColumn
  self:SetMoneyLayout(not isValueColumn)
end

function AuctionatorShoppingPriceCellTemplateMixin:Populate(rowData, index)
  AuctionatorCellMixin.Populate(self, rowData, index)

  local amount = rowData[self.columnName]
  if self.isValueColumn then
    local profit = rowData.vendorProfit
    self:SetMoneyLayout(profit ~= nil)
    if profit == nil then
      self.text:SetText(amount)
      return
    end
    amount = profit
  end
  if amount ~= nil then
    local sign = amount < 0 and "-" or ""
    self.text:SetText(sign .. Auctionator.Utilities.CreatePaddedMoneyString(math.abs(amount), false, false, true))
  else
    self.text:SetText("")
  end
end
