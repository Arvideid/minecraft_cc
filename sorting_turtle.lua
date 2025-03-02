-- Define the sorting turtle module
local sortingTurtle = {}

-- Import the LLM module
local llm = require("llm")

-- Store information about discovered barrels
sortingTurtle.barrels = {}
sortingTurtle.numBarrels = 0
sortingTurtle.lastScanTime = 0
sortingTurtle.SCAN_INTERVAL = 300  -- Rescan every 5 minutes

-- Function to check if a block is a barrel
function sortingTurtle.isBarrel()
    local success, data = turtle.inspect()
    if success and data then
        -- Print detected block for debugging
        print("Detected block:", data.name)
        -- Check for various barrel types
        return data.name == "minecraft:barrel" or 
               data.name:find("barrel") or 
               data.name:find("storage")
    end
    return false
end

-- Function to read barrel contents
function sortingTurtle.readBarrel()
    local contents = {
        name = "empty",
        displayName = "empty",
        category = "none"
    }
    
    -- Save current selected slot
    local currentSlot = turtle.getSelectedSlot()
    
    -- Try to suck one item to get its details
    if turtle.suck(1) then
        local item = turtle.getItemDetail()
        if item then
            contents = {
                name = item.name or "unknown",
                displayName = item.displayName or item.name or "unknown",
                category = sortingTurtle.getItemCategory(item.name or "unknown")
            }
            -- Put the item back
            turtle.drop(1)
        end
    end
    
    -- Restore selected slot
    turtle.select(currentSlot)
    return contents
end

-- Function to categorize items (helps with grouping similar items)
function sortingTurtle.getItemCategory(itemName)
    if not itemName then return "unknown" end
    
    local categories = {
        wood = {"log", "plank", "wood"},
        stone = {"stone", "cobble", "granite", "diorite", "andesite"},
        ore = {"ore", "ingot", "raw_"},
        crop = {"seed", "sapling", "flower", "wheat", "carrot", "potato"},
        tool = {"pickaxe", "axe", "shovel", "hoe", "sword"},
        redstone = {"redstone", "repeater", "comparator", "piston"},
    }
    
    for category, keywords in pairs(categories) do
        for _, keyword in ipairs(keywords) do
            if itemName:find(keyword) then
                return category
            end
        end
    end
    return "misc"
end

-- Function to scan and map barrels
function sortingTurtle.scanBarrels()
    print("\n=== Starting Barrel Scan ===")
    sortingTurtle.barrels = {}
    sortingTurtle.numBarrels = 0
    local steps = 0
    
    -- Turn right to start scanning
    print("Turning right to scan...")
    turtle.turnRight()
    
    -- First pass: Move forward and count barrels
    print("First pass: Counting barrels...")
    while steps < 16 do  -- Limit to 16 blocks
        if sortingTurtle.isBarrel() then
            steps = steps + 1
            print(string.format("Found barrel at position %d", steps))
            -- Just count for now, don't read contents
            table.insert(sortingTurtle.barrels, {
                position = steps,
                contents = {
                    name = "unknown",
                    displayName = "unknown",
                    category = "unknown"
                }
            })
            sortingTurtle.numBarrels = sortingTurtle.numBarrels + 1
        end
        
        if not turtle.forward() then
            print("Path blocked at step " .. steps)
            break
        end
    end
    
    -- Return to start
    print("Returning to start position...")
    for i = 1, steps do
        if not turtle.back() then
            print("Error returning to start!")
            break
        end
    end
    
    -- If we found barrels, do a second pass to read contents
    if sortingTurtle.numBarrels > 0 then
        print("\nSecond pass: Reading barrel contents...")
        for i = 1, sortingTurtle.numBarrels do
            -- Move to barrel
            for j = 1, sortingTurtle.barrels[i].position do
                if not turtle.forward() then
                    print("Error reaching barrel " .. i)
                    break
                end
            end
            
            -- Read contents
            local contents = sortingTurtle.readBarrel()
            sortingTurtle.barrels[i].contents = contents
            print(string.format("Barrel %d contains: %s (%s)", 
                i, 
                contents.displayName or "empty", 
                contents.category or "none"))
            
            -- Return to start
            for j = 1, sortingTurtle.barrels[i].position do
                if not turtle.back() then
                    print("Error returning from barrel " .. i)
                    break
                end
            end
        end
    end
    
    -- Return to original orientation
    turtle.turnLeft()
    
    sortingTurtle.lastScanTime = os.epoch("local")
    print(string.format("\nScan complete. Found %d barrels.", sortingTurtle.numBarrels))
    
    -- Print barrel summary
    print("\nBarrel Summary:")
    for i, barrel in ipairs(sortingTurtle.barrels) do
        print(string.format("Barrel %d (Position %d): %s (%s)", 
            i, 
            barrel.position, 
            barrel.contents.displayName, 
            barrel.contents.category))
    end
end

-- Function to determine which barrel slot to use based on item name using LLM
function sortingTurtle.getBarrelSlot(itemName, itemCategory)
    if sortingTurtle.numBarrels == 0 then
        return nil
    end

    -- Create a detailed context for the LLM
    local barrelContext = "Current barrel contents:\n"
    for i, barrel in ipairs(sortingTurtle.barrels) do
        barrelContext = barrelContext .. string.format("Barrel %d: %s (category: %s)\n", 
            i, 
            barrel.contents.displayName or "empty", 
            barrel.contents.category or "none")
    end
    
    -- Construct a more specific prompt
    local prompt = string.format([[
Return ONLY a number between 1 and %d.
Item to sort: "%s" (category: %s)
%s
Rules:
- If exact item match exists, use that barrel number
- If empty barrel exists, use first empty barrel
- If similar category exists, use that barrel
- ONLY return the number, no other text

Number:]], 
        sortingTurtle.numBarrels,
        itemName, 
        itemCategory,
        barrelContext)

    local response = llm.getGeminiResponse(prompt)
    
    if response then
        -- Clean up response to ensure we only get a number
        response = response:match("^%s*(%d+)%s*$")
        local barrelSlot = tonumber(response)
        if barrelSlot and barrelSlot >= 1 and barrelSlot <= sortingTurtle.numBarrels then
            return barrelSlot
        else
            print("Invalid barrel number from LLM: " .. (response or "nil"))
        end
    else
        print("No response received from LLM.")
    end
    return nil
end

-- Function to move items from input chest to barrels
function sortingTurtle.sortItems()
    -- Check if we need to rescan barrels
    local currentTime = os.epoch("local")
    if sortingTurtle.numBarrels == 0 or 
       (currentTime - sortingTurtle.lastScanTime) > sortingTurtle.SCAN_INTERVAL then
        sortingTurtle.scanBarrels()
        if sortingTurtle.numBarrels == 0 then
            print("No barrels found! Please set up barrels and restart.")
            return
        end
    end
    
    print("\nChecking input chest...")
    -- Move to the input chest
    if not turtle.forward() then
        print("Cannot reach input chest!")
        return
    end

    -- Check each slot in the turtle's inventory
    for slot = 1, 16 do
        turtle.select(slot)
        if turtle.suck() then  -- Attempt to take items from the chest
            local itemDetail = turtle.getItemDetail()
            if itemDetail then
                local itemCategory = sortingTurtle.getItemCategory(itemDetail.name)
                print(string.format("\nProcessing: %s (Category: %s)", 
                    itemDetail.displayName or "unknown", 
                    itemCategory))
                
                -- Determine which barrel to place the item in
                local barrelSlot = sortingTurtle.getBarrelSlot(itemDetail.name, itemCategory)
                if barrelSlot then
                    print("Moving to barrel " .. barrelSlot)
                    -- Move to the correct barrel
                    sortingTurtle.moveToBarrel(barrelSlot)
                    -- Place the item in the barrel
                    if turtle.drop() then
                        print("Successfully placed item in barrel " .. barrelSlot)
                        -- Update barrel contents in memory
                        sortingTurtle.barrels[barrelSlot].contents = {
                            name = itemDetail.name,
                            displayName = itemDetail.displayName,
                            category = itemCategory
                        }
                    else
                        print("Failed to place item in barrel " .. barrelSlot)
                    end
                    -- Return to the input chest
                    sortingTurtle.returnToChest()
                else
                    print("No suitable barrel found, returning item to chest")
                    -- Drop item back in chest
                    turtle.drop()
                end
            end
        end
    end
    
    -- Return to starting position
    if not turtle.back() then
        print("Warning: Could not return to starting position!")
    end
end

-- Function to move to a specific barrel
function sortingTurtle.moveToBarrel(slot)
    if not sortingTurtle.barrels[slot] then
        print("Invalid barrel slot: " .. slot)
        return false
    end
    
    print(string.format("Moving to barrel %d at position %d", 
        slot, sortingTurtle.barrels[slot].position))
    
    turtle.turnRight()
    for i = 1, sortingTurtle.barrels[slot].position do
        if not turtle.forward() then
            print("Failed to reach barrel!")
            return false
        end
    end
    turtle.turnLeft()
    return true
end

-- Function to return to the input chest
function sortingTurtle.returnToChest()
    turtle.turnLeft()
    for i = 1, sortingTurtle.numBarrels do
        if not turtle.back() then
            print("Warning: Failed to return completely!")
            break
        end
    end
    turtle.turnRight()
end

-- Main loop
print("=== Smart Sorting Turtle v2.1 ===")
print("Setup Instructions:")
print("1. Place turtle in front of input chest")
print("2. Place barrels in a line to the right")
print("3. Ensure all barrels are accessible")
print("\nStarting initial barrel scan...")

-- Do initial barrel scan
sortingTurtle.scanBarrels()

if sortingTurtle.numBarrels == 0 then
    print("\nNo barrels found! Please set up barrels and restart the program.")
    return sortingTurtle
end

print("\nReady to sort items!")
print("Monitoring input chest...")

while true do
    sortingTurtle.sortItems()
    os.sleep(5)  -- Wait for a few seconds before checking again
end

return sortingTurtle

