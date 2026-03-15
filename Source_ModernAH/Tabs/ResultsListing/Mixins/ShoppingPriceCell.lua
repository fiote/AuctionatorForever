AuctionatorShoppingPriceCellTemplateMixin = CreateFromMixins(AuctionatorStringCellTemplateMixin)

local RIGHT_PADDING = 12

function AuctionatorShoppingPriceCellTemplateMixin:Init(columnName)
  AuctionatorStringCellTemplateMixin.Init(self, columnName)

  self.text:SetJustifyH("RIGHT")
  self.text:ClearAllPoints()
  self.text:SetPoint("TOPLEFT")
  self.text:SetPoint("BOTTOMRIGHT", -RIGHT_PADDING, 0)
end

function AuctionatorShoppingPriceCellTemplateMixin:Populate(rowData, index)
  AuctionatorCellMixin.Populate(self, rowData, index)

  local amount = rowData[self.columnName]
  if amount ~= nil then
    self.text:SetText(Auctionator.Utilities.CreatePaddedMoneyString(amount, true, true, true))
  else
    self.text:SetText("")
  end
end
