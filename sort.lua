-- Define sorting rules (item name → category)
local sortingRules = {
    ["minecraft:oak_log"] = "wood",
    ["minecraft:birch_log"] = "wood",
    ["minecraft:spruce_log"] = "wood",
    ["minecraft:cobblestone"] = "stone",
    ["minecraft:stone"] = "stone",
    ["minecraft:iron_ore"] = "ore",
    ["minecraft:gold_ore"] = "ore"
}

-- Barrel positions (update these based on the new layout)
local barrelPositions = {
    ["wood"] = 1,  -- Number of steps to the wood barrel
    ["stone"] = 2, -- Number of steps to the stone barrel
    ["ore"] = 3    -- Number of steps to the ore barrel
}

-- Function to move to the correct barrel
function moveToBarrel(targetCategory)
    local steps = barrelPositions[targetCategory]
    if steps == nil then
        print("No barrel assigned for category: " .. targetCategory)
        return false
    end

    -- Turn 180 degrees to face away from the input barrel
    turtle.turnLeft()
    turtle.turnLeft()

    -- Move the specified number of steps
    for i = 1, steps do
        if not turtle.forward() then
            print("Blocked when moving forward to barrel")
            return false
        end
    end

    -- Turn right to face the barrel
    turtle.turnRight()

    return true
end

-- Function to return to the start position
function returnToStart()
    -- Turn left to face away from the barrel
    turtle.turnLeft()

    -- Move back to the starting position
    for i = 1, 3 do  -- Adjust based on the farthest position
        turtle.back()
    end

    -- Turn 180 degrees to face the input barrel
    turtle.turnLeft()
    turtle.turnLeft()
end

-- Function to sort and place items
function sortItems()
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item then
            local category = sortingRules[item.name]
            if category then
                print("Sorting item: " .. item.name .. " into " .. category)
                
                if moveToBarrel(category) then
                    turtle.drop()  -- Drop item into the barrel
                    print("Dropped item in " .. category .. " barrel")
                end
                
                -- Return to input barrel
                returnToStart()
            else
                print("No category found for: " .. item.name)
            end
        end
    end
end

-- Main loop: Check for new items and sort them
while true do
    if turtle.suck() then  -- Take items from input barrel
        print("Took items from input barrel")
        sortItems()         -- Sort and place them
    end
    sleep(2)               -- Wait before checking again
end