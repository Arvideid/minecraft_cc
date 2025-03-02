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
    return success and (data.name == "minecraft:barrel" or data.name:find("barrel"))
end

-- Function to read barrel contents
function sortingTurtle.readBarrel()
    local contents = {}
    -- Save current selected slot
    local currentSlot = turtle.getSelectedSlot()
    
    -- Try to suck one item to get its details
    if turtle.suck(1) then
        local item = turtle.getItemDetail()
        if item then
            contents = {
                name = item.name,
                displayName = item.displayName,
                category = sortingTurtle.getItemCategory(item.name)
            }
        end
        -- Put the item back
        turtle.drop(1)
    end
    
    -- Restore selected slot
    turtle.select(currentSlot)
    return contents
end

-- Function to categorize items (helps with grouping similar items)
function sortingTurtle.getItemCategory(itemName)
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
    print("Starting barrel scan...")
    local oldBarrels = sortingTurtle.barrels  -- Save old barrel data
    sortingTurtle.barrels = {}
    sortingTurtle.numBarrels = 0
    
    -- Turn right to start scanning
    turtle.turnRight()
    
    -- Move forward and check for barrels
    local steps = 0
    while steps < 16 do  -- Limit to 16 blocks
        if sortingTurtle.isBarrel() then
            steps = steps + 1
            local contents = sortingTurtle.readBarrel()
            table.insert(sortingTurtle.barrels, {
                position = steps,
                contents = contents,
                category = contents.category or "empty"
            })
            sortingTurtle.numBarrels = sortingTurtle.numBarrels + 1
            print(string.format("Barrel %d: %s (%s)", 
                steps, 
                contents.displayName or "empty", 
                contents.category or "none"))
        end
        
        if not turtle.forward() then
            break
        end
    end
    
    -- Return to start and face original direction
    for i = 1, steps do
        turtle.back()
    end
    turtle.turnLeft()
    
    sortingTurtle.lastScanTime = os.epoch("local")
    print(string.format("Scan complete. Found %d barrels.", sortingTurtle.numBarrels))
end

-- Function to determine which barrel slot to use based on item name using LLM
function sortingTurtle.getBarrelSlot(itemName, itemCategory)
    -- Create a detailed context for the LLM
    local barrelContext = "Current barrel contents:\n"
    for i, barrel in ipairs(sortingTurtle.barrels) do
        local status = "empty"
        if barrel.contents.displayName then
            status = string.format("%s (category: %s)", 
                barrel.contents.displayName,
                barrel.contents.category or "none")
        end
        barrelContext = barrelContext .. string.format("Barrel %d: %s\n", i, status)
    end
    
    -- Construct a more specific prompt
    local prompt = string.format([[
I need to sort the item "%s" (category: %s) into one of %d barrels.
%s
Instructions:
1. Analyze the current barrel contents above
2. Return ONLY a single number (1-%d) representing the best barrel choice based on these rules:
   - If a barrel already has this exact item, use that barrel number
   - If there's an empty barrel, use the first empty barrel number
   - If there are similar items (same category), use that barrel number
3. DO NOT include any words or explanation, just the number

Response (just the number):]], 
        itemName, 
        itemCategory,
        sortingTurtle.numBarrels,
        barrelContext,
        sortingTurtle.numBarrels)

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
    end
    
    -- Move to the input chest
    turtle.forward()

    -- Check each slot in the turtle's inventory
    for slot = 1, 16 do
        turtle.select(slot)
        if turtle.suck() then  -- Attempt to take items from the chest
            local itemDetail = turtle.getItemDetail()
            if itemDetail then
                local itemCategory = sortingTurtle.getItemCategory(itemDetail.name)
                print(string.format("Processing: %s (Category: %s)", 
                    itemDetail.displayName, 
                    itemCategory))
                
                -- Determine which barrel to place the item in
                local barrelSlot = sortingTurtle.getBarrelSlot(itemDetail.name, itemCategory)
                if barrelSlot then
                    print("Moving to barrel " .. barrelSlot)
                    -- Move to the correct barrel
                    sortingTurtle.moveToBarrel(barrelSlot)
                    -- Place the item in the barrel
                    turtle.drop()
                    -- Update barrel contents in memory
                    sortingTurtle.barrels[barrelSlot].contents = {
                        name = itemDetail.name,
                        displayName = itemDetail.displayName,
                        category = itemCategory
                    }
                    -- Return to the input chest
                    sortingTurtle.returnToChest()
                else
                    print("Could not determine barrel for: " .. itemDetail.displayName)
                    -- Drop item back in chest
                    turtle.drop()
                end
            end
        end
    end
end

-- Function to move to a specific barrel
function sortingTurtle.moveToBarrel(slot)
    turtle.turnRight()
    for i = 1, slot do
        turtle.forward()
    end
    turtle.turnLeft()
end

-- Function to return to the input chest
function sortingTurtle.returnToChest()
    turtle.turnLeft()
    for i = 1, sortingTurtle.numBarrels do
        turtle.back()
    end
    turtle.turnRight()
end

-- Main loop
print("=== Smart Sorting Turtle v2.0 ===")
print("Setup Instructions:")
print("1. Place turtle in front of input chest")
print("2. Place barrels in a line to the right")
print("3. Ensure all barrels are accessible")
print("\nStarting initial barrel scan...")

-- Do initial barrel scan
sortingTurtle.scanBarrels()

print("\nReady to sort items!")
print("Monitoring input chest...")

while true do
    sortingTurtle.sortItems()
    os.sleep(5)  -- Wait for a few seconds before checking again
end

return sortingTurtle

