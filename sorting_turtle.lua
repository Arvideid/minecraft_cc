-- Define the sorting turtle module
local sortingTurtle = {}

-- Import the LLM module
local llm = require("llm")

-- Configuration
sortingTurtle.config = {
    SCAN_INTERVAL = 300,  -- Rescan every 5 minutes
    MIN_FUEL_LEVEL = 100,  -- Minimum fuel level before refueling
    MAX_STEPS = 16,  -- Maximum steps to search for barrels
    FUEL_ITEMS = {  -- Items that can be used as fuel
        ["minecraft:coal"] = true,
        ["minecraft:charcoal"] = true,
        ["minecraft:coal_block"] = true,
        ["minecraft:lava_bucket"] = true
    },
    INITIAL_FUEL_CHECK = true  -- Flag to track if initial fuel check has been done
}

-- Store information about discovered barrels
sortingTurtle.barrels = {}
sortingTurtle.numBarrels = 0
sortingTurtle.lastScanTime = 0
sortingTurtle.position = { x = 0, y = 0, z = 0, facing = 0 }  -- 0=north, 1=east, 2=south, 3=west
sortingTurtle.moveHistory = {}  -- Track movement history

-- Runtime-only category system
sortingTurtle.categories = {}  -- Will store category definitions
sortingTurtle.barrelAssignments = {}  -- Will store barrel -> category mappings

-- Add barrel layout configuration
sortingTurtle.layout = {
    maxHorizontalSteps = 16,  -- Maximum horizontal steps to search
    maxVerticalSteps = 3,     -- Maximum vertical levels to search
    currentLevel = 0          -- Current vertical level being scanned
}

-- Function to add movement to history
function sortingTurtle.addToHistory(movement)
    table.insert(sortingTurtle.moveHistory, movement)
end

-- Function to get reverse movement
function sortingTurtle.getReverseMovement(movement)
    if movement == "forward" then return "back"
    elseif movement == "back" then return "forward"
    elseif movement == "turnLeft" then return "turnRight"
    elseif movement == "turnRight" then return "turnLeft"
    elseif movement == "up" then return "down"
    elseif movement == "down" then return "up"
    else return nil end
end

-- Function to return to initial position using movement history
function sortingTurtle.returnToInitial()
    print("Returning to initial position...")
    
    -- Reverse through movement history
    for i = #sortingTurtle.moveHistory, 1, -1 do
        local reverseMove = sortingTurtle.getReverseMovement(sortingTurtle.moveHistory[i])
        if reverseMove then
            if not turtle[reverseMove]() then
                print("Warning: Could not complete reverse movement!")
                break
            end
            -- Update position for the reverse movement
            if reverseMove == "forward" or reverseMove == "back" or 
               reverseMove == "up" or reverseMove == "down" or
               reverseMove == "turnLeft" or reverseMove == "turnRight" then
                sortingTurtle.updatePosition(reverseMove)
            end
        end
    end
    
    -- Clear movement history after returning
    sortingTurtle.moveHistory = {}
    print("Returned to initial position")
end

-- After the configuration section, add new environment tracking
sortingTurtle.environment = {
    blocks = {},  -- Will store block information in a 3D grid
    lastScan = {},  -- Last scan results
    SCAN_RADIUS = 4  -- How far to scan in each direction
}

-- Function to check if a block is a barrel
function sortingTurtle.isBarrel()
    local success, data = turtle.inspect()
    if success and data then
        return data.name == "minecraft:barrel" or 
               data.name:find("barrel") or 
               data.name:find("storage")
    end
    return false
end

-- Function to read barrel contents
function sortingTurtle.readBarrel()
    local contents = {
        items = {},
        isEmpty = true
    }
    
    -- Save current selected slot
    local currentSlot = turtle.getSelectedSlot()
    if not currentSlot then
        print("Error: Could not get current slot!")
        return contents
    end
    
    -- First, try to suck one item to check if barrel is empty
    if not turtle.suck() then
        turtle.select(currentSlot)
        return contents  -- Barrel is empty
    end
    turtle.drop()  -- Put it back
    
    print("Reading barrel contents...")
    
    -- First phase: Get ALL items from the barrel
    local startingEmptySlots = sortingTurtle.countEmptySlots()
    local itemsGrabbed = false
    
    -- Keep sucking until we can't get any more items or inventory is full
    while turtle.suck() do
        itemsGrabbed = true
        -- If inventory is full, stop
        if sortingTurtle.countEmptySlots() == 0 then
            break
        end
    end
    
    if itemsGrabbed then
        contents.isEmpty = false
        
        -- Second phase: Scan our inventory for unique items
        for slot = 1, 16 do
            local item = turtle.getItemDetail(slot)
            if item and item.name then  -- Ensure both item and item.name exist
                -- Check if we already have this item type recorded
                local found = false
                for _, existingItem in ipairs(contents.items) do
                    if existingItem.name == item.name then
                        found = true
                        break
                    end
                end
                
                -- If it's a new item type, add it to our list
                if not found then
                    table.insert(contents.items, {
                        name = item.name,
                        displayName = item.displayName or item.name  -- Fallback to name if displayName is nil
                    })
                    print("Found item type:", item.displayName or item.name)
                end
            end
        end
        
        -- Third phase: Return ALL items to the barrel
        for slot = 1, 16 do
            if turtle.getItemCount(slot) > 0 then
                turtle.select(slot)
                if not turtle.drop() then
                    print("Warning: Could not return item to barrel!")
                end
            end
        end
    end
    
    -- Restore original selected slot
    if not turtle.select(currentSlot) then
        print("Warning: Could not restore original slot!")
    end
    
    -- Debug output
    if not contents.isEmpty then
        print("\nBarrel contains:")
        for _, item in ipairs(contents.items) do
            print("- " .. (item.displayName or item.name))
        end
    else
        print("Barrel is empty")
    end
    
    return contents
end

-- Function to categorize items (helps with grouping similar items)
function sortingTurtle.getItemCategory(itemName)
    if not itemName then return "unknown" end
    
    -- Convert itemName to lowercase for case-insensitive matching
    itemName = string.lower(itemName)
    
    -- Extract mod prefix and base name
    local modPrefix, baseName = itemName:match("^([^:]+):(.+)$")
    if not modPrefix then return "unknown" end
    
    -- Just return the mod prefix and base name for the LLM to handle categorization
    return modPrefix .. "_" .. baseName
end

-- Function to check and maintain fuel levels
function sortingTurtle.checkFuel()
    local fuelLevel = turtle.getFuelLevel()
    if fuelLevel == "unlimited" then return true end
    
    -- Only print fuel level during initial check
    if sortingTurtle.config.INITIAL_FUEL_CHECK then
        print(string.format("Initial fuel level: %d", fuelLevel))
        sortingTurtle.config.INITIAL_FUEL_CHECK = false
    end
    
    if fuelLevel < sortingTurtle.config.MIN_FUEL_LEVEL then
        print("Fuel level low, attempting to refuel...")
        -- Check inventory for fuel items
        for slot = 1, 16 do
            turtle.select(slot)
            local item = turtle.getItemDetail()
            if item and sortingTurtle.config.FUEL_ITEMS[item.name] then
                if turtle.refuel(1) then
                    print(string.format("Refueled with %s", item.name))
                    return true
                end
            end
        end
        print("WARNING: No fuel items found!")
        return false
    end
    return true
end

-- Function to update position after movement
function sortingTurtle.updatePosition(movement)
    if movement == "forward" then
        if sortingTurtle.position.facing == 0 then
            sortingTurtle.position.z = sortingTurtle.position.z - 1
        elseif sortingTurtle.position.facing == 1 then
            sortingTurtle.position.x = sortingTurtle.position.x + 1
        elseif sortingTurtle.position.facing == 2 then
            sortingTurtle.position.z = sortingTurtle.position.z + 1
        else
            sortingTurtle.position.x = sortingTurtle.position.x - 1
        end
    elseif movement == "back" then
        if sortingTurtle.position.facing == 0 then
            sortingTurtle.position.z = sortingTurtle.position.z + 1
        elseif sortingTurtle.position.facing == 1 then
            sortingTurtle.position.x = sortingTurtle.position.x - 1
        elseif sortingTurtle.position.facing == 2 then
            sortingTurtle.position.z = sortingTurtle.position.z - 1
        else
            sortingTurtle.position.x = sortingTurtle.position.x + 1
        end
    elseif movement == "up" then
        sortingTurtle.position.y = sortingTurtle.position.y + 1
    elseif movement == "down" then
        sortingTurtle.position.y = sortingTurtle.position.y - 1
    elseif movement == "turnRight" then
        sortingTurtle.position.facing = (sortingTurtle.position.facing + 1) % 4
    elseif movement == "turnLeft" then
        sortingTurtle.position.facing = (sortingTurtle.position.facing - 1) % 4
    end
end

-- Optimized movement function with minimal scanning
function sortingTurtle.safeMove(movement)
    if not sortingTurtle.checkFuel() then
        print("Cannot move: Insufficient fuel!")
        return false
    end
    
    local success = false
    if movement == "forward" then
        success = turtle.forward()
    elseif movement == "back" then
        success = turtle.back()
    elseif movement == "up" then
        success = turtle.up()
    elseif movement == "down" then
        success = turtle.down()
    elseif movement == "turnRight" then
        turtle.turnRight()
        success = true
    elseif movement == "turnLeft" then
        turtle.turnLeft()
        success = true
    end
    
    if success then
        sortingTurtle.updatePosition(movement)
        sortingTurtle.addToHistory(movement)
        return true
    end
    return false
end

-- Function to return to home position
function sortingTurtle.returnHome()
    print("Returning to home position...")
    
    -- First, handle Y position
    while sortingTurtle.position.y > 0 do
        if not sortingTurtle.safeMove("down") then break end
    end
    while sortingTurtle.position.y < 0 do
        if not sortingTurtle.safeMove("up") then break end
    end
    
    -- Turn to face the right direction for X movement
    if sortingTurtle.position.x > 0 then
        while sortingTurtle.position.facing ~= 3 do  -- Face west
            sortingTurtle.safeMove("turnLeft")
        end
    elseif sortingTurtle.position.x < 0 then
        while sortingTurtle.position.facing ~= 1 do  -- Face east
            sortingTurtle.safeMove("turnLeft")
        end
    end
    
    -- Move in X direction
    while sortingTurtle.position.x ~= 0 do
        if sortingTurtle.position.x > 0 then
            if not sortingTurtle.safeMove("forward") then break end
        else
            if not sortingTurtle.safeMove("forward") then break end
        end
    end
    
    -- Turn to face the right direction for Z movement
    if sortingTurtle.position.z > 0 then
        while sortingTurtle.position.facing ~= 0 do  -- Face north
            sortingTurtle.safeMove("turnLeft")
        end
    elseif sortingTurtle.position.z < 0 then
        while sortingTurtle.position.facing ~= 2 do  -- Face south
            sortingTurtle.safeMove("turnLeft")
        end
    end
    
    -- Move in Z direction
    while sortingTurtle.position.z ~= 0 do
        if sortingTurtle.position.z > 0 then
            if not sortingTurtle.safeMove("forward") then break end
        else
            if not sortingTurtle.safeMove("forward") then break end
        end
    end
    
    -- Face north (default position)
    while sortingTurtle.position.facing ~= 0 do
        sortingTurtle.safeMove("turnLeft")
    end
    
    if sortingTurtle.position.x == 0 and sortingTurtle.position.y == 0 and 
       sortingTurtle.position.z == 0 and sortingTurtle.position.facing == 0 then
        print("Successfully returned home!")
        return true
    else
        print("Warning: Could not return to exact home position!")
        print(string.format("Current position: x=%d, y=%d, z=%d, facing=%d",
            sortingTurtle.position.x, sortingTurtle.position.y,
            sortingTurtle.position.z, sortingTurtle.position.facing))
        return false
    end
end

-- Function to check inventory space
function sortingTurtle.hasInventorySpace()
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            return true
        end
    end
    return false
end

-- Function to count empty slots
function sortingTurtle.countEmptySlots()
    local count = 0
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            count = count + 1
        end
    end
    return count
end

-- Function to get total items in inventory
function sortingTurtle.getTotalItems()
    local total = 0
    for slot = 1, 16 do
        total = total + turtle.getItemCount(slot)
    end
    return total
end

-- Function to move to a specific barrel position
function sortingTurtle.moveToBarrel(barrelNumber)
    local barrel = sortingTurtle.barrels[barrelNumber]
    if not barrel then
        print("Invalid barrel number!")
        return false
    end
    
    -- Validate barrel position
    if not barrel.position or not barrel.level then
        print("Invalid barrel position data!")
        return false
    end
    
    -- Validate position is within bounds
    if barrel.position < 0 or barrel.position >= sortingTurtle.layout.maxHorizontalSteps or
       barrel.level < 0 or barrel.level >= sortingTurtle.layout.maxVerticalSteps then
        print("Barrel position out of bounds!")
        return false
    end
    
    -- Turn left to face the barrels if not already facing them
    while sortingTurtle.position.facing ~= 3 do  -- 3 is west (left)
        if not turtle.turnLeft() then
            print("Error: Could not turn left!")
            return false
        end
        sortingTurtle.addToHistory("turnLeft")
        sortingTurtle.updatePosition("turnLeft")
    end
    
    -- Move forward one step to be in line with barrels
    if not turtle.forward() then
        print("Cannot move forward to barrel line!")
        return false
    end
    sortingTurtle.addToHistory("forward")
    sortingTurtle.updatePosition("forward")
    
    -- First move horizontally to the correct position
    local horizontalSteps = barrel.position
    local currentStep = 0
    
    while currentStep < horizontalSteps do
        if not turtle.forward() then
            print(string.format("Cannot move forward to step %d!", currentStep + 1))
            return false
        end
        sortingTurtle.addToHistory("forward")
        sortingTurtle.updatePosition("forward")
        currentStep = currentStep + 1
    end
    
    -- Then move vertically to the correct level
    local targetLevel = barrel.level or 0
    local currentLevel = sortingTurtle.position.y
    
    -- Move up or down as needed
    while currentLevel < targetLevel do
        if not turtle.up() then
            print(string.format("Cannot move up to level %d!", currentLevel + 1))
            return false
        end
        sortingTurtle.addToHistory("up")
        sortingTurtle.updatePosition("up")
        currentLevel = currentLevel + 1
    end
    while currentLevel > targetLevel do
        if not turtle.down() then
            print(string.format("Cannot move down to level %d!", currentLevel - 1))
            return false
        end
        sortingTurtle.addToHistory("down")
        sortingTurtle.updatePosition("down")
        currentLevel = currentLevel - 1
    end
    
    -- Turn right to face the barrel
    if not turtle.turnRight() then
        print("Error: Could not turn to face barrel!")
        return false
    end
    sortingTurtle.addToHistory("turnRight")
    sortingTurtle.updatePosition("turnRight")
    
    return true
end

-- Function to return to the input chest
function sortingTurtle.returnToChest()
    -- First turn back to face the path (west)
    while sortingTurtle.position.facing ~= 3 do  -- 3 is west (left)
        turtle.turnLeft()
        sortingTurtle.updatePosition("turnLeft")
    end
    
    -- Move back to the chest position
    while sortingTurtle.position.x < 0 do
        if turtle.forward() then
            sortingTurtle.updatePosition("forward")
        else
            break
        end
    end
    
    -- Move back one step to be behind the input storage
    turtle.back()
    sortingTurtle.updatePosition("back")
    
    -- Turn to face the input storage (north)
    while sortingTurtle.position.facing ~= 0 do
        turtle.turnLeft()
        sortingTurtle.updatePosition("turnLeft")
    end
end

-- Function to check if the turtle is facing a valid input storage
function sortingTurtle.checkInputStorage()
    -- Ensure the turtle is facing north
    while sortingTurtle.position.facing ~= 0 do
        turtle.turnLeft()
        sortingTurtle.updatePosition("turnLeft")
    end
    
    -- Check if there's a valid storage block in front
    local success, data = turtle.inspect()
    if success and data then
        if data.name == "minecraft:chest" or data.name == "minecraft:barrel" then
            return true
        end
    end
    return false
end

-- Function to scan for barrels
function sortingTurtle.scanBarrels()
    print("Scanning for barrels...")
    
    -- Initialize barrel count
    sortingTurtle.numBarrels = 0
    sortingTurtle.barrels = {}
    
    -- Turn left to face the barrels
    while sortingTurtle.position.facing ~= 3 do  -- 3 is west (left)
        sortingTurtle.safeMove("turnLeft")
    end
    
    -- Move forward one step to be in line with barrels
    sortingTurtle.safeMove("forward")
    
    -- Scan each level
    for level = 0, sortingTurtle.layout.maxVerticalSteps - 1 do
        -- Scan each horizontal step
        for step = 0, sortingTurtle.layout.maxHorizontalSteps - 1 do
            -- Check if we've reached the end of the row
            if not sortingTurtle.safeMove("forward") then
                break
            end
            
            -- Check if there's a barrel in front
            if sortingTurtle.isBarrel() then
                sortingTurtle.numBarrels = sortingTurtle.numBarrels + 1
                sortingTurtle.barrels[sortingTurtle.numBarrels] = {
                    position = step,
                    level = level,
                    contents = sortingTurtle.readBarrel()
                }
            end
        end
        
        -- Move back to the start of the row
        for _ = 0, sortingTurtle.layout.maxHorizontalSteps - 1 do
            sortingTurtle.safeMove("back")
        end
        
        -- Move up to the next level
        if level < sortingTurtle.layout.maxVerticalSteps - 1 then
            sortingTurtle.safeMove("up")
        end
    end
    
    -- Return to the starting position
    sortingTurtle.returnHome()
    
    -- Update last scan time
    sortingTurtle.lastScanTime = os.epoch("local")
    
    print(string.format("Found %d barrels", sortingTurtle.numBarrels))
end

-- Function to sort items
function sortingTurtle.sortItems()
    local totalItems = sortingTurtle.getTotalItems()
    local sortedItems = 0
    local errorCount = 0
    local maxErrors = 3
    
    -- Process items until inventory is empty or max errors reached
    while sortingTurtle.getTotalItems() > 0 and errorCount < maxErrors do
        -- Save current selected slot
        local currentSlot = turtle.getSelectedSlot()
        if not currentSlot then
            print("Error: Could not get current slot!")
            errorCount = errorCount + 1
            break
        end
        
        -- Suck one item from the input storage
        if not turtle.suck() then
            print("Error: Could not suck item from input storage!")
            errorCount = errorCount + 1
            break
        end
        
        -- Get item details
        local itemDetail = turtle.getItemDetail()
        if not itemDetail or not itemDetail.name then
            print("Error: Invalid item details!")
            errorCount = errorCount + 1
            break
        end
        
        -- Categorize the item
        local category = sortingTurtle.getItemCategory(itemDetail.name)
        if not category then
            print("Error: Could not categorize item!")
            errorCount = errorCount + 1
            break
        end
        
        -- Find a barrel for this category
        local targetBarrel = nil
        for _, barrel in ipairs(sortingTurtle.barrels) do
            if barrel.contents.isEmpty or (barrel.contents.category == category) then
                targetBarrel = barrel
                break
            end
        end
        
        -- If no suitable barrel found, try to find an empty one
        if not targetBarrel then
            for _, barrel in ipairs(sortingTurtle.barrels) do
                if barrel.contents.isEmpty then
                    targetBarrel = barrel
                    break
                end
            end
        end
        
        -- If still no barrel found, try to resort and find an empty one
        if not targetBarrel then
            print("No suitable barrel found, resorting items...")
            sortingTurtle.resort()
            
            for _, barrel in ipairs(sortingTurtle.barrels) do
                if barrel.contents.isEmpty then
                    targetBarrel = barrel
                    break
                end
            end
        end
        
        -- If still no barrel found, give up
        if not targetBarrel then
            print("Error: Could not find a suitable barrel!")
            errorCount = errorCount + 1
            break
        end
        
        -- Move to the target barrel
        if not sortingTurtle.moveToBarrel(targetBarrel.position) then
            print("Error: Could not move to barrel!")
            errorCount = errorCount + 1
            break
        end
        
        -- Drop the item into the barrel
        if not turtle.drop() then
            print("Error: Could not drop item into barrel!")
            errorCount = errorCount + 1
            break
        end
        
        -- Update barrel contents
        table.insert(targetBarrel.contents.items, {
            name = itemDetail.name,
            displayName = itemDetail.displayName or itemDetail.name
        })
        targetBarrel.contents.isEmpty = false
        targetBarrel.contents.category = category
        
        -- Restore original selected slot
        if not turtle.select(currentSlot) then
            print("Warning: Could not restore original slot!")
        end
        
        -- Update sorted item count
        sortedItems = sortedItems + 1
    end
    
    -- Return to the input chest
    sortingTurtle.returnToChest()
    
    -- Print summary
    print(string.format("Sorted %d items out of %d (Errors: %d)", sortedItems, totalItems, errorCount))
end

-- Function to resort items between barrels
function sortingTurtle.resort()
    print("Resorting items between barrels...")
    
    local totalItemsMoved = 0
    local barrelsProcessed = 0
    
    -- Process each barrel
    for _, barrel in ipairs(sortingTurtle.barrels) do
        -- Skip empty barrels
        if not barrel.contents.isEmpty then
            barrelsProcessed = barrelsProcessed + 1
            
            -- Process each item in the barrel
            for _, item in ipairs(barrel.contents.items) do
                -- Categorize the item
                local category = sortingTurtle.getItemCategory(item.name)
                if not category then
                    print("Error: Could not categorize item!")
                    break
                end
                
                -- Find a barrel for this category
                local targetBarrel = nil
                for _, otherBarrel in ipairs(sortingTurtle.barrels) do
                    if otherBarrel.contents.isEmpty or (otherBarrel.contents.category == category) then
                        targetBarrel = otherBarrel
                        break
                    end
                end
                
                -- If no suitable barrel found, try to find an empty one
                if not targetBarrel then
                    for _, otherBarrel in ipairs(sortingTurtle.barrels) do
                        if otherBarrel.contents.isEmpty then
                            targetBarrel = otherBarrel
                            break
                        end
                    end
                end
                
                -- If still no barrel found, give up
                if not targetBarrel then
                    print("Error: Could not find a suitable barrel!")
                    break
                end
                
                -- Move to the target barrel
                if not sortingTurtle.moveToBarrel(targetBarrel.position) then
                    print("Error: Could not move to barrel!")
                    break
                end
                
                -- Suck the item from the current barrel
                local currentSlot = turtle.getSelectedSlot()
                if not currentSlot then
                    print("Error: Could not get current slot!")
                    break
                end
                
                if not turtle.suck() then
                    print("Error: Could not suck item from barrel!")
                    break
                end
                
                -- Drop the item into the target barrel
                if not turtle.drop() then
                    print("Error: Could not drop item into barrel!")
                    break
                end
                
                -- Update barrel contents
                table.insert(targetBarrel.contents.items, {
                    name = item.name,
                    displayName = item.displayName
                })
                targetBarrel.contents.isEmpty = false
                targetBarrel.contents.category = category
                
                -- Restore original selected slot
                if not turtle.select(currentSlot) then
                    print("Warning: Could not restore original slot!")
                end
                
                -- Update item count
                totalItemsMoved = totalItemsMoved + 1
            end
        end
    end
    
    -- Return to the input chest
    sortingTurtle.returnToChest()
    
    -- Print summary
    print(string.format("Moved %d items across %d barrels", totalItemsMoved, barrelsProcessed))
end

-- Main loop
print("=== Smart Sorting Turtle v3.2 ===")
print("Setup Instructions:")
print("1. Place input storage (chest or barrel)")
print("2. Place sorting barrels in rows to the left of the input storage")
print("3. You can stack barrels vertically (up to 3 levels high)")
print("4. Place turtle directly behind the input storage, facing it")
print("5. Ensure all barrels are accessible")
print("\nLayout can look like this:")
print("Level 2:  [B][B][B]...")
print("Level 1:  [B][B][B]...")
print("Level 0:  [S][B][B][B]...")
print("          [T]")
print("Where: T=Turtle (facing up), S=Input Storage, B=Sorting Barrels")

-- Initialize state
local lastCheckTime = os.epoch("local")
local lastMessageTime = lastCheckTime
local IDLE_CHECK_INTERVAL = 2  -- Check for items every 2 seconds
local MESSAGE_INTERVAL = 30    -- Show waiting message every 30 seconds
local hasScanned = false

-- Main processing loop
while true do
    local currentTime = os.epoch("local")
    
    -- Check for items in input storage
    if sortingTurtle.checkInputStorage() then
        -- First-time setup
        if not hasScanned then
            print("\nFirst items detected! Performing initial scan...")
            sortingTurtle.scanBarrels()
            
            if sortingTurtle.numBarrels == 0 then
                print("Error: No barrels found during scan!")
                print("Please check barrel setup and restart the program.")
                break
            end
            
            hasScanned = true
            print("\nPerforming initial resort of existing items...")
            sortingTurtle.resort()
        end
        
        -- Regular operation
        print("\nProcessing items from input storage...")
        
        -- Check if we need to rescan
        if currentTime - sortingTurtle.lastScanTime > sortingTurtle.config.SCAN_INTERVAL then
            print("Performing periodic barrel rescan...")
            sortingTurtle.scanBarrels()
            
            if sortingTurtle.numBarrels == 0 then
                print("Error: Lost connection to barrels!")
                print("Please check barrel setup and restart the program.")
                break
            end
            
            print("\nResorting items after scan...")
            sortingTurtle.resort()
        end
        
        -- Sort new items
        sortingTurtle.sortItems()
        lastCheckTime = currentTime
        lastMessageTime = currentTime
        
    else
        -- Show periodic waiting message
        if currentTime - lastMessageTime >= MESSAGE_INTERVAL then
            if not hasScanned then
                print("Waiting for first items... (Press Ctrl+T to exit)")
            else
                print("Waiting for more items... (Press Ctrl+T to exit)")
            end
            lastMessageTime = currentTime
        end
        
        -- Wait before next check
        os.sleep(IDLE_CHECK_INTERVAL)
    end
end

-- Function to define categories
function sortingTurtle.defineCategories()
    local prompt = [[
Define a list of Minecraft item categories for sorting items into barrels.
IMPORTANT: The list MUST start with 'unknown' category.

Guidelines for creating categories:
1. Focus on clear patterns in item names and usage
2. Look for common prefixes and suffixes in item names
3. Group items by their primary material or function
4. Consider how items are used together in crafting and gameplay

Examples of good pattern-based categories:
- Items ending in "_log" or containing "log"
- Items ending in "_planks" or containing "plank"
- Items containing "stone" or "cobble"
- Items ending in "_ore" or "_ingot"
- Items containing "dirt" or "grass"
- Items ending in "_seeds" or containing "seed"
- Items containing "redstone" or related to redstone
- Items ending in "_sword", "_axe", "_pickaxe", etc.

Return ONLY category names, one per line, nothing else.
Keep categories concise and pattern-based.
The first category MUST be 'unknown'.]]

    print("Requesting categories...")
    local response = llm.getGeminiResponse(prompt)
    
    if not response then
        print("Error: No response received")
        return false
    end
    
    -- Split response into lines and clean each category
    sortingTurtle.categories = {}
    for line in response:gmatch("[^\r\n]+") do
        -- Clean up each line (remove quotes, spaces)
        local category = line:gsub('"', ''):gsub("^%s*(.-)%s*$", "%1")
        if category ~= "" then
            table.insert(sortingTurtle.categories, category)
        end
    end
    
    -- Ensure unknown is first
    if sortingTurtle.categories[1] ~= "unknown" then
        table.insert(sortingTurtle.categories, 1, "unknown")
    end
    
    print("\nDefined categories:")
    for _, category in ipairs(sortingTurtle.categories) do
        print("- " .. category)
    end
    return true
end

-- Function to assign categories to barrels
function sortingTurtle.assignBarrelCategories()
    if sortingTurtle.numBarrels == 0 then return false end
    
    -- Create simple context of barrel contents
    local barrelContext = "Barrel contents:\n"
    for i, barrel in ipairs(sortingTurtle.barrels) do
        barrelContext = barrelContext .. string.format("\nBarrel %d: ", i)
        if barrel.contents.isEmpty then
            barrelContext = barrelContext .. "EMPTY"
        else
            local items = {}
            for _, item in ipairs(barrel.contents.items) do
                table.insert(items, item.displayName)
            end
            barrelContext = barrelContext .. table.concat(items, ", ")
        end
    end
    
    local categoriesText = table.concat(sortingTurtle.categories, "\n")
    local prompt = string.format([[
Assign ONE category to each barrel based on its contents.
IMPORTANT: The first barrel (Barrel 1) MUST be assigned to 'unknown' category.
Use ONLY categories from this list:
%s

Barrel Contents:
%s

Return ONLY category assignments, one per line.
Example format:
unknown
stone
ores

One category per line, matching the number of barrels.]], 
        categoriesText, barrelContext)

    local response = llm.getGeminiResponse(prompt)
    if not response then
        print("Error: No category assignments received")
        return false
    end
    
    -- Split response into lines and assign categories
    local assignments = {}
    for line in response:gmatch("[^\r\n]+") do
        -- Clean up each line (remove spaces, quotes)
        local category = line:gsub('"', ''):gsub("^%s*(.-)%s*$", "%1")
        table.insert(assignments, category)
    end
    
    -- Ensure first barrel is assigned to unknown
    if #assignments > 0 then
        assignments[1] = "unknown"
    end
    
    -- Verify all assignments are valid categories
    for i, category in ipairs(assignments) do
        local isValid = false
        for _, validCategory in ipairs(sortingTurtle.categories) do
            if category == validCategory then
                isValid = true
                break
            end
        end
        if not isValid then
            print(string.format("Warning: Invalid category '%s' assigned to barrel %d", category, i))
            return false
        end
    end
    
    -- Clear existing assignments
    sortingTurtle.barrelAssignments = {}
    
    -- Assign categories to barrels
    for i, category in ipairs(assignments) do
        if i <= sortingTurtle.numBarrels then
            sortingTurtle.barrelAssignments[i] = category
            print(string.format("Barrel %d -> %s", i, category))
        end
    end
    
    return true
end

-- Enhanced getBarrelSlot function that uses category assignments
function sortingTurtle.getBarrelSlot(itemName, itemDisplayName)
    if sortingTurtle.numBarrels == 0 then return nil end
    
    -- First, determine which category this item belongs to
    local categoriesText = table.concat(sortingTurtle.categories, "\n")
    local prompt = string.format([[
Categorize this Minecraft item into one of the available categories.
If you're unsure or the item doesn't clearly fit any specific category, use 'unknown'.

Item Details:
Name: %s
Display Name: %s

Available Categories (in order of priority):
%s

IMPORTANT RULES:
1. Return ONLY the category name, nothing else
2. If unsure, ALWAYS use 'unknown' category
3. Only use 'problematic_items' if the item is causing system issues
4. The category MUST be from the list above, no exceptions

Return just the category name:]], 
        itemName,
        itemDisplayName,
        categoriesText)
    
    local itemCategory = llm.getGeminiResponse(prompt)
    if not itemCategory then 
        print("No category response received, defaulting to unknown")
        return 1  -- Return first barrel (unknown) if no response
    end
    
    -- Clean up the response (remove any quotes or whitespace)
    itemCategory = itemCategory:gsub('"', ''):gsub("^%s*(.-)%s*$", "%1")
    
    -- Verify the category is valid
    local isValidCategory = false
    for _, category in ipairs(sortingTurtle.categories) do
        if category == itemCategory then
            isValidCategory = true
            break
        end
    end
    
    if not isValidCategory then
        print(string.format("Warning: Invalid category '%s' returned for item %s, using unknown", 
            itemCategory, itemDisplayName or itemName))
        return 1  -- Return first barrel (unknown) if invalid category
    end
    
    -- First, try to find a barrel already assigned to this category that has items
    for barrelNum, category in pairs(sortingTurtle.barrelAssignments) do
        if category == itemCategory and not sortingTurtle.barrels[barrelNum].contents.isEmpty then
            return barrelNum
        end
    end
    
    -- If no existing barrel with items found, try to find an empty barrel assigned to this category
    for barrelNum, category in pairs(sortingTurtle.barrelAssignments) do
        if category == itemCategory and sortingTurtle.barrels[barrelNum].contents.isEmpty then
            return barrelNum
        end
    end
    
    -- If no barrel found for the specific category, use unknown (first barrel)
    if itemCategory ~= "unknown" then
        print(string.format("No barrel available for category '%s', using unknown", itemCategory))
        return 1
    end
    
    -- If we get here and the item category is unknown but we can't find an unknown barrel,
    -- something is wrong with our barrel assignments
    print("Warning: Could not find unknown barrel! This should never happen!")
    return 1  -- Still try the first barrel as a last resort
end

-- Function to check if block in front is a valid storage
function sortingTurtle.isValidInputStorage()
    local success, data = turtle.inspect()
    if success and data then
        return data.name == "minecraft:chest" or 
               data.name == "minecraft:barrel" or 
               data.name:find("chest") or 
               data.name:find("barrel") or 
               data.name:find("storage")
    end
    return false
end

-- Function to handle problematic items by assigning them to the problematic_items category
function sortingTurtle.handleProblematicItem(itemName, itemDisplayName)
    print(string.format("\nHandling problematic item: %s", itemDisplayName or itemName))
    
    -- Find a barrel assigned to problematic_items category
    for barrelNum, category in pairs(sortingTurtle.barrelAssignments) do
        if category == "problematic_items" then
            -- Add item to problematic items list if not already there
            if not sortingTurtle.problematicItems[itemName] then
                sortingTurtle.problematicItems[itemName] = {
                    name = itemName,
                    displayName = itemDisplayName,
                    attempts = 1
                }
            end
            
            print(string.format("Assigning to problematic items barrel %d", barrelNum))
            return true
        end
    end
    
    -- If no problematic_items barrel found, try to find an empty barrel to assign
    for barrelNum, barrel in ipairs(sortingTurtle.barrels) do
        if barrel.contents.isEmpty then
            -- Assign this barrel to problematic_items category
            sortingTurtle.barrelAssignments[barrelNum] = "problematic_items"
            print(string.format("Assigned empty barrel %d to problematic items", barrelNum))
            return true
        end
    end
    
    print("No available barrel for problematic items!")
    return false
end

-- Function to resort items between barrels after a scan
function sortingTurtle.resort()
    print("\n=== Starting Resort Operation ===")
    
    -- Clear movement history before starting
    sortingTurtle.moveHistory = {}
    
    -- Check if we have barrels to work with
    if sortingTurtle.numBarrels == 0 then
        print("No barrels found! Please scan first.")
        return
    end
    
    -- Track statistics
    local itemsMoved = 0
    local barrelsProcessed = 0
    
    -- Process each barrel
    for barrelNum = 1, sortingTurtle.numBarrels do
        local barrel = sortingTurtle.barrels[barrelNum]
        if not barrel.contents.isEmpty then
            print(string.format("\nChecking barrel %d...", barrelNum))
            
            -- Move to the barrel
            if sortingTurtle.moveToBarrel(barrelNum) then
                -- Get all items from the barrel
                local items = {}
                while turtle.suck() do
                    local item = turtle.getItemDetail()
                    if item then
                        table.insert(items, item)
                    end
                end
                
                -- If we got any items, process them
                if #items > 0 then
                    print(string.format("Found %d items to resort", #items))
                    
                    -- Process each item
                    for _, item in ipairs(items) do
                        -- Get the correct barrel for this item
                        local targetBarrel = sortingTurtle.getBarrelSlot(item.name, item.displayName)
                        
                        -- If target barrel is different from current barrel
                        if targetBarrel ~= barrelNum then
                            print(string.format("Moving %s to barrel %d", 
                                item.displayName or item.name, targetBarrel))
                            
                            -- Move to target barrel
                            if sortingTurtle.moveToBarrel(targetBarrel) then
                                if turtle.drop() then
                                    itemsMoved = itemsMoved + 1
                                else
                                    print("Warning: Could not store item in target barrel!")
                                    -- Try to put it in unknown barrel if we can't store it
                                    if sortingTurtle.moveToBarrel(1) then
                                        if not turtle.drop() then
                                            print("Error: Could not store in unknown barrel!")
                                        end
                                    end
                                end
                            end
                        else
                            -- Item belongs in current barrel, return it
                            if sortingTurtle.moveToBarrel(barrelNum) then
                                turtle.drop()
                            end
                        end
                    end
                end
                barrelsProcessed = barrelsProcessed + 1
            end
            
            -- Return to initial position after processing each barrel
            sortingTurtle.returnToInitial()
        end
    end
    
    -- Print summary
    print("\nResort complete:")
    print(string.format("- Barrels processed: %d", barrelsProcessed))
    print(string.format("- Items moved: %d", itemsMoved))
end

-- Function to sort items from input storage
function sortingTurtle.sortItems()
    -- Clear movement history before starting to sort
    sortingTurtle.moveHistory = {}
    
    -- Do initial scan if we haven't done one yet
    if sortingTurtle.numBarrels == 0 then
        print("No barrels found, performing initial scan...")
        sortingTurtle.scanBarrels()
        if sortingTurtle.numBarrels == 0 then 
            print("Error: No barrels found during scan!")
            return 
        end
    end
    
    print("\nChecking input storage...")
    
    -- Check if we're facing a valid storage block
    if not sortingTurtle.checkInputStorage() then
        print("No valid input storage detected!")
        return
    end

    -- Process items in the storage
    local itemsMoved = false
    local itemsSorted = 0
    local itemsToUnknown = 0
    local errorCount = 0
    
    while errorCount < 3 do  -- Allow up to 3 errors before giving up
        -- Clear movement history before processing each item
        sortingTurtle.moveHistory = {}
        
        -- Try to get an item
        if not turtle.suck() then
            break  -- No more items to sort
        end
        
        local itemDetail = turtle.getItemDetail()
        if not itemDetail or not itemDetail.name then
            print("Warning: Invalid item data!")
            errorCount = errorCount + 1
            continue
        end
        
        local itemCategory = sortingTurtle.getItemCategory(itemDetail.name)
        print(string.format("\nProcessing: %s (Category: %s)", 
            itemDetail.displayName or itemDetail.name,
            itemCategory))
        
        local barrelSlot = sortingTurtle.getBarrelSlot(itemDetail.name, itemDetail.displayName)
        if not barrelSlot then
            print("Error: Could not determine barrel slot!")
            -- Try to return item to input
            turtle.drop()
            errorCount = errorCount + 1
            continue
        end
        
        print(string.format("Moving to barrel %d...", barrelSlot))
        -- Move to barrel and drop item
        if sortingTurtle.moveToBarrel(barrelSlot) then
            if turtle.drop() then
                itemsMoved = true
                if barrelSlot == 1 then
                    itemsToUnknown = itemsToUnknown + 1
                else
                    itemsSorted = itemsSorted + 1
                end
                print(string.format("Stored in barrel %d", barrelSlot))
                errorCount = 0  -- Reset error count on success
            else
                print("Warning: Could not store item in barrel!")
                -- If we can't store in target barrel, use unknown barrel
                sortingTurtle.returnToInitial()
                if sortingTurtle.moveToBarrel(1) then
                    if turtle.drop() then
                        itemsToUnknown = itemsToUnknown + 1
                        print("Stored in unknown barrel")
                        errorCount = 0  -- Reset error count on successful fallback
                    else
                        print("Error: Could not store in unknown barrel!")
                        errorCount = errorCount + 1
                    end
                else
                    print("Error: Could not reach unknown barrel!")
                    errorCount = errorCount + 1
                end
            end
        else
            print("Error: Could not reach target barrel!")
            -- Try to return item to input
            sortingTurtle.returnToInitial()
            turtle.drop()
            errorCount = errorCount + 1
        end
        
        -- Return to initial position using movement history
        if not sortingTurtle.returnToInitial() then
            print("Warning: Could not return to initial position!")
            -- Try emergency return procedure
            sortingTurtle.returnHome()
        end
        
        -- Check if there are more items to process
        if not sortingTurtle.checkInputStorage() then
            break
        end
    end
    
    if errorCount >= 3 then
        print("\nWarning: Stopped sorting due to multiple errors!")
    end
    
    -- Print summary
    if itemsMoved then
        print("\nSorting complete:")
        print(string.format("- Items sorted to categories: %d", itemsSorted))
        print(string.format("- Items sent to unknown: %d", itemsToUnknown))
        if errorCount > 0 then
            print(string.format("- Errors encountered: %d", errorCount))
        end
    else
        print("\nNo items were sorted")
    end
end

-- Optimized scan function that scans both horizontally and vertically
function sortingTurtle.scanBarrels()
    print("\n=== Starting Barrel Scan ===")
    sortingTurtle.barrels = {}
    sortingTurtle.numBarrels = 0
    
    -- Clear movement history at start of scan
    sortingTurtle.moveHistory = {}
    
    -- Check fuel before starting
    if not sortingTurtle.checkFuel() then
        print("Cannot scan: Insufficient fuel!")
        return
    end
    
    -- Turn left to face the path (west)
    while sortingTurtle.position.facing ~= 3 do  -- 3 is west (left)
        turtle.turnLeft()
        sortingTurtle.addToHistory("turnLeft")
        sortingTurtle.updatePosition("turnLeft")
    end
    
    -- Move forward one step to be in line with barrels
    if turtle.forward() then
        sortingTurtle.addToHistory("forward")
        sortingTurtle.updatePosition("forward")
    else
        print("Cannot move forward to start scanning!")
        return
    end
    
    -- Scan each vertical level
    for level = 0, sortingTurtle.layout.maxVerticalSteps - 1 do
        local horizontalSteps = 0
        sortingTurtle.layout.currentLevel = level
        
        print(string.format("\nScanning level %d...", level))
        
        -- Forward scan - check barrels while moving forward
        while horizontalSteps < sortingTurtle.layout.maxHorizontalSteps do
            -- Turn right to face potential barrel
            turtle.turnRight()
            sortingTurtle.addToHistory("turnRight")
            sortingTurtle.updatePosition("turnRight")
            
            -- Check for barrel
            local success, data = turtle.inspect()
            if success and data then
                if string.find(data.name or "", "barrel") or string.find(data.name or "", "storage") then
                    -- Read barrel contents immediately
                    local contents = sortingTurtle.readBarrel()
                    local barrelInfo = {
                        position = horizontalSteps,
                        level = level,
                        contents = contents,
                        blockData = data
                    }
                    
                    table.insert(sortingTurtle.barrels, barrelInfo)
                    sortingTurtle.numBarrels = sortingTurtle.numBarrels + 1
                    
                    -- Print basic barrel info
                    print(string.format("\nFound barrel %d:", sortingTurtle.numBarrels))
                    print(string.format("- Position: Level %d, Step %d", level, horizontalSteps))
                    print(string.format("- Contents: %s", contents.isEmpty and "EMPTY" or "Items present"))
                end
            end
            
            -- Turn back to face the path
            turtle.turnLeft()
            sortingTurtle.addToHistory("turnLeft")
            sortingTurtle.updatePosition("turnLeft")
            
            -- Try to move forward
            if turtle.forward() then
                sortingTurtle.addToHistory("forward")
                sortingTurtle.updatePosition("forward")
                horizontalSteps = horizontalSteps + 1
            else
                break
            end
        end
        
        -- Quick return - just move back without checking barrels
        while horizontalSteps > 0 do
            turtle.back()
            sortingTurtle.addToHistory("back")
            sortingTurtle.updatePosition("back")
            horizontalSteps = horizontalSteps - 1
        end
        
        -- If not at last level, move up for next scan
        if level < sortingTurtle.layout.maxVerticalSteps - 1 then
            if turtle.up() then
                sortingTurtle.addToHistory("up")
                sortingTurtle.updatePosition("up")
            else
                print(string.format("Cannot move up to level %d!", level + 1))
                break
            end
        end
    end
    
    -- Return to initial position
    sortingTurtle.returnToInitial()
    
    -- Print barrel summary
    if sortingTurtle.numBarrels > 0 then
        print(string.format("\nFound %d barrels across %d levels", 
            sortingTurtle.numBarrels, sortingTurtle.layout.currentLevel + 1))
        
        -- Define categories if this is the first scan
        if next(sortingTurtle.categories) == nil then
            print("\nDefining storage categories...")
            if sortingTurtle.defineCategories() then
                print("Categories defined successfully!")
            else
                print("Error: Could not define categories!")
                return
            end
        end
        
        -- Assign categories to barrels
        print("\nAssigning categories to barrels...")
        if sortingTurtle.assignBarrelCategories() then
            print("Category assignment complete!")
            -- Print category assignments
            for barrel, category in pairs(sortingTurtle.barrelAssignments) do
                print(string.format("Barrel %d: %s", barrel, category))
            end
        else
            print("Warning: Could not assign categories to barrels")
        end
    else
        print("\nNo barrels found! Please set up barrels and restart.")
    end
    
    sortingTurtle.lastScanTime = os.epoch("local")
end

-- Main loop
print("=== Smart Sorting Turtle v3.2 ===")
print("Setup Instructions:")
print("1. Place input storage (chest or barrel)")
print("2. Place sorting barrels in rows to the left of the input storage")
print("3. You can stack barrels vertically (up to 3 levels high)")
print("4. Place turtle directly behind the input storage, facing it")
print("5. Ensure all barrels are accessible")
print("\nLayout can look like this:")
print("Level 2:  [B][B][B]...")
print("Level 1:  [B][B][B]...")
print("Level 0:  [S][B][B][B]...")
print("          [T]")
print("Where: T=Turtle (facing up), S=Input Storage, B=Sorting Barrels")

-- Initialize state
local lastCheckTime = os.epoch("local")
local lastMessageTime = lastCheckTime
local IDLE_CHECK_INTERVAL = 2  -- Check for items every 2 seconds
local MESSAGE_INTERVAL = 30    -- Show waiting message every 30 seconds
local hasScanned = false

-- Main processing loop
while true do
    local currentTime = os.epoch("local")
    
    -- Check for items in input storage
    if sortingTurtle.checkInputStorage() then
        -- First-time setup
        if not hasScanned then
            print("\nFirst items detected! Performing initial scan...")
            sortingTurtle.scanBarrels()
            
            if sortingTurtle.numBarrels == 0 then
                print("Error: No barrels found during scan!")
                print("Please check barrel setup and restart the program.")
                break
            end
            
            hasScanned = true
            print("\nPerforming initial resort of existing items...")
            sortingTurtle.resort()
        end
        
        -- Regular operation
        print("\nProcessing items from input storage...")
        
        -- Check if we need to rescan
        if currentTime - sortingTurtle.lastScanTime > sortingTurtle.config.SCAN_INTERVAL then
            print("Performing periodic barrel rescan...")
            sortingTurtle.scanBarrels()
            
            if sortingTurtle.numBarrels == 0 then
                print("Error: Lost connection to barrels!")
                print("Please check barrel setup and restart the program.")
                break
            end
            
            print("\nResorting items after scan...")
            sortingTurtle.resort()
        end
        
        -- Sort new items
        sortingTurtle.sortItems()
        lastCheckTime = currentTime
        lastMessageTime = currentTime
        
    else
        -- Show periodic waiting message
        if currentTime - lastMessageTime >= MESSAGE_INTERVAL then
            if not hasScanned then
                print("Waiting for first items... (Press Ctrl+T to exit)")
            else
                print("Waiting for more items... (Press Ctrl+T to exit)")
            end
            lastMessageTime = currentTime
        end
        
        -- Wait before next check
        os.sleep(IDLE_CHECK_INTERVAL)
    end
end

-- Return the module
return sortingTurtle

