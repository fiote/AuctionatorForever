local function getCopper(amount)
  return amount % 100
end

local function getSilver(amount)
  return (amount % 10000 - getCopper(amount)) / 100
end

local function getGold(amount)
  return (amount - getSilver(amount) * 100 - getCopper(amount)) / 10000
end

local goldIcon = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t"
local silverIcon = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:0:0|t"
local copperIcon = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:0:0|t"
local leftPadding = " "
local rightPadding = " "

function Auctionator.Utilities.CreatePaddedMoneyString(amount, hideSilver, hideCopper, useThousandsSeparator)
  if amount == nil then
    amount = 0
  end

  amount = math.floor(amount)
  hideSilver = hideSilver == true
  hideCopper = hideCopper == true
  useThousandsSeparator = useThousandsSeparator == true

  local gold, silver, copper = getGold(amount), getSilver(amount), getCopper(amount)
  local showGold = gold ~= 0
  local showSilver = not hideSilver and (silver ~= 0 or showGold)
  local showCopper = not hideCopper and (copper ~= 0 or showSilver or showGold)

  if not showGold and not showSilver and not showCopper then
    if not hideCopper then
      showCopper = true
    elseif not hideSilver then
      showSilver = true
    else
      showGold = true
    end
  end

  local parts = {}

  if showGold then
    local goldString = tostring(gold)
    if useThousandsSeparator then
      goldString = BreakUpLargeNumbers(gold)
    end

    table.insert(parts, goldString .. leftPadding .. goldIcon)
  end

  if showSilver then
    local silverString = tostring(silver)
    if showGold and silver < 10 then
      silverString = "0" .. silverString
    end
    table.insert(parts, silverString .. leftPadding .. silverIcon)
  end

  if showCopper then
    local copperString = tostring(copper)
    if (showGold or showSilver) and copper < 10 then
      copperString = "0" .. copperString
    end
    table.insert(parts, copperString .. leftPadding .. copperIcon)
  end

  local result = table.concat(parts, rightPadding)

  return result
end
