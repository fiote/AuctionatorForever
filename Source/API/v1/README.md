# Auctionator External API

Calling any other functions related to Auctionator is not supported and may
break without warning in future releases.

This API is intended to remain stable.

```lua
-- Returns the last scanned price for an item identified by itemID
-- Returns the price in coppers, or nil if one wasn't found
Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID)

-- Returns the last scanned price for an item identified by itemLink
-- Returns the price in coppers, or nil if one wasn't found
Auctionator.API.v1.GetAuctionPriceByItemLink(callerID, itemLink)

-- Returns the age (days) since this item was last seen in AH scan data.
-- Returns nil if not found.
Auctionator.API.v1.GetAuctionAgeByItemID(callerID, itemID)
Auctionator.API.v1.GetAuctionAgeByItemLink(callerID, itemLink)

-- Returns the unix timestamp (seconds) when this item was last seen in AH scan data.
-- Returns nil if not found.
Auctionator.API.v1.GetAuctionTimestampByItemID(callerID, itemID)
Auctionator.API.v1.GetAuctionTimestampByItemLink(callerID, itemLink)

-- Returns the elapsed age in seconds since this item was last seen in AH scan data.
-- Returns nil if not found.
Auctionator.API.v1.GetAuctionAgeSecondsByItemID(callerID, itemID)
Auctionator.API.v1.GetAuctionAgeSecondsByItemLink(callerID, itemLink)

-- Searches for an array of search terms and displays the results
-- The auction house MUST be open.
Auctionator.API.v1.MultiSearch(callerID, terms)
```
