local fontPath = "Interface\\AddOns\\Auctionator\\Media\\ExpresswayFree.ttf"
local roots = {}
local updater = CreateFrame("Frame")
local elapsed = 0

local function ApplyFont(text)
  local path, size, flags = text:GetFont()
  if path and size and path ~= fontPath then
    text:SetFont(fontPath, size, flags)
  end
end

local function ApplyToFrame(frame)
  if not frame:IsVisible() then
    return
  end

  if frame:IsObjectType("EditBox") then
    ApplyFont(frame)
  end
  for _, region in ipairs({frame:GetRegions()}) do
    if region:IsObjectType("FontString") then
      ApplyFont(region)
    end
  end
  for _, child in ipairs({frame:GetChildren()}) do
    ApplyToFrame(child)
  end
end

function Auctionator.RegisterFontRoot(frame)
  roots[frame] = true
  frame:HookScript("OnShow", ApplyToFrame)
  ApplyToFrame(frame)
end

updater:SetScript("OnUpdate", function(_, delta)
  elapsed = elapsed + delta
  if elapsed < 1 then
    return
  end
  elapsed = 0
  for frame in pairs(roots) do
    ApplyToFrame(frame)
  end
end)
