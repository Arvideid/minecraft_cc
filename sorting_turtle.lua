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

-- Function to detect surroundings
function sortingTurtle.detectSurroundings()
    local surroundings = {
        front = { exists = turtle.detect(), block = nil },
        up = { exists = turtle.detectUp(), block = nil },
        down = { exists = turtle.detectDown(), block = nil }
    }
    
    -- Get block information
    if surroundings.front.exists then
        local success, data = turtle.inspect()
        if success then surroundings.front.block = data end
    end
    if surroundings.up.exists then
        local success, data = turtle.inspectUp()
        if success then surroundings.up.block = data end
    end
    if surroundings.down.exists then
        local success, data = turtle.inspectDown()
        if success then surroundings.down.block = data end
    end
    
    return surroundings
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

-- Function to perform a 360-degree scan
function sortingTurtle.scan360()
    local scan = {
        north = {},
        east = {},
        south = {},
        west = {},
        up = turtle.detectUp(),
        down = turtle.detectDown(),
        upBlock = nil,
        downBlock = nil
    }
    
    -- Get up/down block data
    if scan.up then
        local success, data = turtle.inspectUp()
        if success then scan.upBlock = data end
    end
    if scan.down then
        local success, data = turtle.inspectDown()
        if success then scan.downBlock = data end
    end
    
    -- Store original facing direction
    local originalFacing = sortingTurtle.position.facing
    
    -- Scan in all four directions
    for i = 0, 3 do
        local direction = ({"north", "east", "south", "west"})[i + 1]
        local success, data = turtle.inspect()
        scan[direction] = {
            exists = success,
            block = data
        }
        sortingTurtle.safeMove("turnRight")
    end
    
    -- Return to original facing direction
    while sortingTurtle.position.facing ~= originalFacing do
        sortingTurtle.safeMove("turnRight")
    end
    
    sortingTurtle.lastScan = scan
    return scan
end

-- Function to analyze surroundings and find interesting blocks
function sortingTurtle.analyzeSurroundings()
    local scan = sortingTurtle.scan360()
    local findings = {
        barrels = {},
        chests = {},
        obstacles = {},
        interesting = {}
    }
    
    -- Helper function to categorize a block
    local function categorizeBlock(block, direction, distance)
        if not block then return end  -- Early return if block is nil
        
        -- Create info table with safe access to block properties
        local info = {
            name = block.name or "unknown",
            direction = direction or "unknown",
            distance = distance or 1
        }
        
        -- Skip processing if we don't have a valid name
        if not info.name or info.name == "unknown" then
            return
        end
        
        -- Check for storage blocks
        if string.find(info.name, "barrel") or string.find(info.name, "storage") then
            table.insert(findings.barrels, info)
        elseif string.find(info.name, "chest") then
            table.insert(findings.chests, info)
        elseif info.name ~= "minecraft:air" then
            table.insert(findings.obstacles, info)
        end
        
        -- Check for special blocks
        if string.find(info.name, "diamond") or string.find(info.name, "chest") or
           string.find(info.name, "furnace") or string.find(info.name, "crafting") then
            table.insert(findings.interesting, info)
        end
    end
    
    -- Analyze each direction with nil checks
    for direction, data in pairs(scan) do
        if direction ~= "up" and direction ~= "down" then
            if type(data) == "table" and data.block then  -- Add type check
                categorizeBlock(data.block, direction)
            end
        end
    end
    
    -- Analyze up/down with nil checks
    if scan.upBlock then 
        categorizeBlock(scan.upBlock, "up") 
    end
    if scan.downBlock then 
        categorizeBlock(scan.downBlock, "down") 
    end
    
    return findings
end

-- Function to map current position
function sortingTurtle.mapPosition()
    local surroundings = sortingTurtle.analyzeSurroundings()
    local pos = sortingTurtle.position
    local key = string.format("%d,%d,%d", pos.x, pos.y, pos.z)
    
    sortingTurtle.environment.blocks[key] = {
        position = {x = pos.x, y = pos.y, z = pos.z},
        surroundings = surroundings,
        timestamp = os.epoch("local")
    }
    
    return surroundings
end

-- Add a new function for step-by-step movement with 360 scanning
function sortingTurtle.moveWithScan(movement)
    -- Only scan if we're moving forward, not for turns
    local needsScan = (movement == "forward")
    
    -- Perform the movement first
    local success = sortingTurtle.safeMove(movement)
    
    if success and needsScan then
        -- Do a single scan after moving forward
        local scan = sortingTurtle.mapPosition()
        
        -- Report only if we found something
        if #scan.barrels > 0 or #scan.obstacles > 0 or #scan.interesting > 0 then
            print("Environment scan results:")
            if #scan.barrels > 0 then print("  - Found " .. #scan.barrels .. " barrels") end
            if #scan.obstacles > 0 then print("  - Found " .. #scan.obstacles .. " obstacles") end
            if #scan.interesting > 0 then print("  - Found " .. #scan.interesting .. " interesting blocks") end
        end
    end
    
    return success
end

-- Function to move to a specific barrel position
function sortingTurtle.moveToBarrel(barrelNumber)
    -- Back away from chest first
    turtle.back()
    
    -- Turn left to face the barrels if not already facing them
    if sortingTurtle.position.facing ~= 3 then  -- 3 is west (left)
        while sortingTurtle.position.facing ~= 3 do
            turtle.turnLeft()
            sortingTurtle.updatePosition("turnLeft")
        end
    end
    
    -- Move forward to the barrel position
    local stepsNeeded = sortingTurtle.barrels[barrelNumber].position
    local currentStep = 0
    
    while currentStep < stepsNeeded do
        if turtle.forward() then
            sortingTurtle.updatePosition("forward")
            currentStep = currentStep + 1
        else
            return false
        end
    end
    return true
end

-- Function to return to the input chest
function sortingTurtle.returnToChest()
    -- Turn around to face east (opposite of barrels)
    while sortingTurtle.position.facing ~= 1 do  -- 1 is east (right)
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
    
    -- Turn to face the chest (north)
    while sortingTurtle.position.facing ~= 0 do
        turtle.turnLeft()
        sortingTurtle.updatePosition("turnLeft")
    end
    
    -- Move forward to the chest
    turtle.forward()
end

-- Optimized scan function that only scans in the direction of barrels
function sortingTurtle.scanBarrels()
    print("\n=== Starting Barrel Scan ===")
    sortingTurtle.barrels = {}
    sortingTurtle.numBarrels = 0
    local steps = 0
    
    -- Check fuel before starting
    if not sortingTurtle.checkFuel() then
        print("Cannot scan: Insufficient fuel!")
        return
    end
    
    -- Back away from chest
    turtle.back()
    
    -- Turn left to face the barrels
    while sortingTurtle.position.facing ~= 3 do  -- 3 is west (left)
        turtle.turnLeft()
        sortingTurtle.updatePosition("turnLeft")
    end
    
    -- Single pass: Move forward and scan barrels
    print("Scanning for barrels...")
    while steps < sortingTurtle.config.MAX_STEPS do
        -- Check what's in front
        local success, data = turtle.inspect()
        if success and data then
            if string.find(data.name or "", "barrel") or string.find(data.name or "", "storage") then
                steps = steps + 1
                
                -- Read barrel contents immediately
                local contents = sortingTurtle.readBarrel()
                table.insert(sortingTurtle.barrels, {
                    position = steps,
                    contents = contents,
                    blockData = data
                })
                sortingTurtle.numBarrels = sortingTurtle.numBarrels + 1
                print(string.format("Found barrel %d: %s (%s)", 
                    sortingTurtle.numBarrels, 
                    contents.displayName or "empty",
                    contents.category or "none"))
            end
        end
        
        -- Try to move forward
        if not turtle.forward() then
            break
        end
        sortingTurtle.updatePosition("forward")
        steps = steps + 1
    end
    
    -- Return to start using optimized return function
    sortingTurtle.returnToChest()
    
    sortingTurtle.lastScanTime = os.epoch("local")
    
    -- Print barrel summary
    if sortingTurtle.numBarrels > 0 then
        print(string.format("\nFound %d barrels", sortingTurtle.numBarrels))
    else
        print("\nNo barrels found! Please set up barrels and restart.")
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

-- Optimized sort items function with improved movement
function sortingTurtle.sortItems()
    -- Check if we need to rescan barrels
    local currentTime = os.epoch("local")
    if sortingTurtle.numBarrels == 0 or 
       (currentTime - sortingTurtle.lastScanTime) > sortingTurtle.config.SCAN_INTERVAL then
        sortingTurtle.scanBarrels()
        if sortingTurtle.numBarrels == 0 then return end
    end
    
    -- Move to the input chest
    if not turtle.forward() then
        print("Cannot reach input chest!")
        return
    end

    -- Check each slot in the turtle's inventory
    local itemsMoved = false
    for slot = 1, 16 do
        turtle.select(slot)
        if turtle.suck() then
            local itemDetail = turtle.getItemDetail()
            if itemDetail then
                local itemCategory = sortingTurtle.getItemCategory(itemDetail.name)
                local barrelSlot = sortingTurtle.getBarrelSlot(itemDetail.name, itemCategory)
                
                if barrelSlot then
                    -- Move to barrel and drop item
                    if sortingTurtle.moveToBarrel(barrelSlot) then
                        if turtle.drop() then
                            itemsMoved = true
                            -- Update barrel contents in memory
                            sortingTurtle.barrels[barrelSlot].contents = {
                                name = itemDetail.name,
                                displayName = itemDetail.displayName,
                                category = itemCategory
                            }
                        end
                        -- Return to the input chest
                        sortingTurtle.returnToChest()
                    else
                        -- If we couldn't reach the barrel, drop item back in chest
                        turtle.drop()
                    end
                else
                    -- Return item to chest if no suitable barrel
                    turtle.drop()
                end
            end
        end
    end
    
    -- Only print status if items were actually moved
    if itemsMoved then
        print("Items sorted successfully")
    end
    
    -- Return to starting position
    turtle.back()
end

-- Main loop
print("=== Smart Sorting Turtle v2.3 ===")
print("Setup Instructions:")
print("1. Place turtle behind input chest, facing the chest")
print("2. Place barrels in a line to the left of the chest")
print("3. Ensure all barrels are accessible")

-- Do initial barrel scan
sortingTurtle.scanBarrels()

if sortingTurtle.numBarrels == 0 then
    print("\nNo barrels found! Please set up barrels and restart the program.")
    return sortingTurtle
end

print("\nReady to sort items!")

while true do
    sortingTurtle.sortItems()
    os.sleep(5)
end

return sortingTurtle

