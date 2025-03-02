-- Define the sorting turtle module
local sortingTurtle = {}

-- Import the LLM module
local llm = require("llm")

-- Store information about discovered barrels
sortingTurtle.barrels = {}
sortingTurtle.numBarrels = 0

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
                displayName = item.displayName
            }
        end
        -- Put the item back
        turtle.drop(1)
    end
    
    -- Restore selected slot
    turtle.select(currentSlot)
    return contents
end

-- Function to scan and map barrels
function sortingTurtle.scanBarrels()
    print("Scanning for barrels...")
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
                contents = contents
            })
            sortingTurtle.numBarrels = sortingTurtle.numBarrels + 1
            print("Found barrel " .. steps .. " containing: " .. (contents.displayName or "empty"))
        end
        
        -- Move to next position
        if not turtle.forward() then
            break
        end
    end
    
    -- Return to start and face original direction
    for i = 1, steps do
        turtle.back()
    end
    turtle.turnLeft()
    
    print("Found " .. sortingTurtle.numBarrels .. " barrels")
end

-- Function to determine which barrel slot to use based on item name using LLM
function sortingTurtle.getBarrelSlot(itemName)
    -- Create a detailed context for the LLM
    local barrelContext = "Current barrel setup:\n"
    for i, barrel in ipairs(sortingTurtle.barrels) do
        barrelContext = barrelContext .. "Barrel " .. i .. ": " .. 
            (barrel.contents.displayName or "empty") .. "\n"
    end
    
    -- Construct a more specific prompt
    local prompt = [[
Based on the following barrel setup, determine the best barrel number (1-]] .. sortingTurtle.numBarrels .. [[) 
for the item: "]] .. itemName .. [[".

]] .. barrelContext .. [[

Rules:
1. If a barrel already contains this exact item, return that barrel's number
2. If there's an empty barrel, prefer that
3. If items are similar (like different wood types), group them together
4. ONLY respond with a single number between 1 and ]] .. sortingTurtle.numBarrels .. [[
5. Do not include any other text in your response

Barrel number:]]

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
    -- Ensure we have scanned barrels first
    if sortingTurtle.numBarrels == 0 then
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
                print("Processing item: " .. itemDetail.displayName)
                -- Determine which barrel to place the item in
                local barrelSlot = sortingTurtle.getBarrelSlot(itemDetail.name)
                if barrelSlot then
                    print("Moving to barrel " .. barrelSlot)
                    -- Move to the correct barrel
                    sortingTurtle.moveToBarrel(barrelSlot)
                    -- Place the item in the barrel
                    turtle.drop()
                    -- Update barrel contents
                    sortingTurtle.barrels[barrelSlot].contents = {
                        name = itemDetail.name,
                        displayName = itemDetail.displayName
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
print("Starting sorting turtle...")
print("Place the turtle in front of the input chest")
print("Ensure barrels are placed in a line to the right of the turtle")

while true do
    sortingTurtle.sortItems()
    os.sleep(5)  -- Wait for a few seconds before checking again
end

return sortingTurtle

