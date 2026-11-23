function Auctionator.Config.InitializeFrames()
  local frames = {
    "BasicOptions",
    "Tooltips",

    "ShoppingAlt",
    "Selling",
    "SellingShortcuts",
    "SellingAllItems",
    "Quantities",
    "Cancelling",

    "Profile",

    "Advanced",
  }
  if Auctionator.Shopping.GetSuggestedStats then
    table.insert(frames, 4, "Suggestions")
  end
  Auctionator.Config.InternalInitializeFrames(frames)
end
