function Auctionator.Config.InternalInitializeFrames(templateNames)
  for _, name in ipairs(templateNames) do
    local frame = CreateFrame(
      "FRAME",
      "AuctionatorConfig" .. name .. "Frame",
      SettingsPanel,
      "AuctionatorConfig" .. name .. "FrameTemplate")
    Auctionator.RegisterFontRoot(frame)
  end
end
