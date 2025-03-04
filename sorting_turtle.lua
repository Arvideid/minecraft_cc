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

-- Add after sortingTurtle initialization
sortingTurtle.problematicItems = {}  -- Track items that couldn't be sorted

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
        if item then
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
                        displayName = item.displayName or item.name
                    })
                    print("Found item type:", item.displayName or item.name)
                end
            end
        end
        
        -- Third phase: Return ALL items to the barrel
        for slot = 1, 16 do
            if turtle.getItemCount(slot) > 0 then
                turtle.select(slot)
                turtle.drop()
            end
        end
    end
    
    -- Restore original selected slot
    turtle.select(currentSlot)
    
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
    
    -- Extract item parts from the name
    -- Format typically: modname:itemname or modname:itemtype_material
    local itemNameLower = itemName:lower()
    
    -- Extract the actual item name without the mod prefix
    local actualItemName = itemNameLower:match("^[^:]+:(.+)$") or itemNameLower
    
    -- Return the simplified item name for better word matching in categorization
    return actualItemName
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
    local barrel = sortingTurtle.barrels[barrelNumber]
    if not barrel then
        print("Invalid barrel number!")
        return false
    end
    
    -- Turn left to face the barrels if not already facing them
    while sortingTurtle.position.facing ~= 3 do  -- 3 is west (left)
        turtle.turnLeft()
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
        if turtle.forward() then
            sortingTurtle.addToHistory("forward")
            sortingTurtle.updatePosition("forward")
            currentStep = currentStep + 1
        else
            return false
        end
    end
    
    -- Then move vertically to the correct level
    local targetLevel = barrel.level or 0
    local currentLevel = sortingTurtle.position.y
    
    -- Move up or down as needed
    while currentLevel < targetLevel do
        if turtle.up() then
            sortingTurtle.addToHistory("up")
            sortingTurtle.updatePosition("up")
            currentLevel = currentLevel + 1
        else
            return false
        end
    end
    while currentLevel > targetLevel do
        if turtle.down() then
            sortingTurtle.addToHistory("down")
            sortingTurtle.updatePosition("down")
            currentLevel = currentLevel - 1
        else
            return false
        end
    end
    
    -- Turn right to face the barrel
    turtle.turnRight()
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

-- Function to get LLM analysis of barrel contents
function sortingTurtle.analyzeBarrelContents(barrel)
    if not barrel or not barrel.contents then return nil end
    
    local prompt = string.format([[
Analyze this Minecraft barrel's contents to determine its purpose and suggest what other items would fit well in it.

Current Contents:
Name: %s
Display Name: %s
Category: %s

Consider:
1. What is the main theme/purpose of this barrel?
2. What types of items would logically belong here?
3. Are there related items from the same mod that should go here?
4. What crafting or gameplay relationships exist with these items?

Return a brief, one-line description of the barrel's purpose.]], 
        barrel.contents.name,
        barrel.contents.displayName,
        barrel.contents.category)
    
    return llm.getGeminiResponse(prompt)
end

-- Function to analyze all barrels at once using LLM
function sortingTurtle.analyzeBulkBarrels()
    if #sortingTurtle.barrels == 0 then return false end
    
    -- Count how many non-empty barrels we have
    local nonEmptyBarrels = 0
    for _, barrel in ipairs(sortingTurtle.barrels) do
        if not barrel.contents.isEmpty then
            nonEmptyBarrels = nonEmptyBarrels + 1
        end
    end
    
    if nonEmptyBarrels == 0 then
        print("All barrels are empty, skipping bulk analysis")
        return true
    end
    
    print(string.format("Analyzing %d barrels with contents...", nonEmptyBarrels))
    
    -- Create a detailed context of all barrels and their contents
    local barrelContext = "Current barrel setup:\n"
    
    for i, barrel in ipairs(sortingTurtle.barrels) do
        barrelContext = barrelContext .. string.format("\nBarrel %d:", i)
        if barrel.contents.isEmpty then
            barrelContext = barrelContext .. " EMPTY"
        else
            barrelContext = barrelContext .. "\nContains:"
            for _, item in ipairs(barrel.contents.items) do
                -- Determine if this is a block, material, tool, or equipable
                local itemType = "unknown"
                local itemName = item.name:lower()
                
                -- Check if it's a block (most blocks end with identifiable patterns)
                if itemName:match("planks$") or itemName:match("log$") or itemName:match("stone$") or 
                   itemName:match("dirt$") or itemName:match("sand$") or itemName:match("grass") or
                   itemName:match("glass") or itemName:match("wool") then
                    itemType = "BLOCK"
                -- Check if it's a material
                elseif itemName:match("stick") or itemName:match("string") or itemName:match("dust") or
                       itemName:match("ingot") or itemName:match("nugget") or itemName:match("paper") then
                    itemType = "MATERIAL"
                -- Check if it's a tool
                elseif itemName:match("pickaxe") or itemName:match("shovel") or itemName:match("axe$") or
                       itemName:match("hoe") or itemName:match("shears") or itemName:match("bucket") then
                    itemType = "TOOL"
                -- Check if it's equipment
                elseif itemName:match("helmet") or itemName:match("chestplate") or itemName:match("leggings") or
                       itemName:match("boots") or itemName:match("sword") or itemName:match("shield") then
                    itemType = "EQUIPABLE"
                end
                
                barrelContext = barrelContext .. string.format("\n- %s (%s) [Type: %s]", 
                    item.displayName or item.name,
                    item.name,
                    itemType)
            end
        end
    end
    
    -- Create a structured analysis prompt
    local prompt = string.format([[
You are a Minecraft storage system analyzer. Your task is to analyze this storage system and output a STRICT JSON response.
Focus on organizing items by their logical relationships, crafting connections, and gameplay usage.

IMPORTANT CLASSIFICATION GUIDE:
- BLOCKS: Place-able in the world (planks, stone, dirt, etc.) - group by material type
- MATERIALS: Crafting ingredients (sticks, string, redstone dust) - group by function
- TOOLS: Items that perform functions (pickaxes, axes, etc.) - keep together
- EQUIPABLES: Wearable items (armor, etc.) - keep together

Current Storage System:
%s

Analysis Guidelines:
1. Group items based on their natural relationships and common usage
2. Consider crafting recipes and how items are used together in-game
3. Look for patterns in existing barrel contents
4. Think about what players would logically look for together
5. Identify mods present in the system and their typical item categories
6. CRUCIAL: Keep blocks separate from their crafting materials (don't mix planks with sticks)
7. Preserve existing organizational patterns where they make sense

Your task is to determine the most logical category for each barrel based on its contents.
]], barrelContext)

    local response = llm.getGeminiResponse(prompt)
    if response then
        -- Print the raw response for debugging
        print("\nRaw LLM response for barrel analysis:")
        print(response:sub(1, 500) .. (response:len() > 500 and "..." or ""))
        
        -- Parse the JSON response and update barrel information
        local success, analysisData = pcall(textutils.unserializeJSON, response)
        if success and analysisData then
            for _, analysis in ipairs(analysisData) do
                if analysis.barrel and analysis.purpose then
                    if analysis.barrel <= #sortingTurtle.barrels then
                    sortingTurtle.barrels[analysis.barrel].analysis = {
                        purpose = analysis.purpose,
                            category = analysis.category,
                            suggested_items = analysis.suggested_items,
                            organization_tip = analysis.organization_tip
                    }
                    end
                end
            end
            return true
        else
            print("Failed to parse LLM response as JSON. Response may be improperly formatted.")
            -- Try to extract at least part of the JSON using a more lenient approach
            -- Look for array pattern and try to fix common issues
            local cleanedResponse = response:match("%[(.+)%]")
            if cleanedResponse then
                cleanedResponse = "[" .. cleanedResponse .. "]"
                success, analysisData = pcall(textutils.unserializeJSON, cleanedResponse)
                if success and analysisData then
                    print("Successfully parsed partial JSON response after cleaning")
                    for _, analysis in ipairs(analysisData) do
                        if analysis.barrel and analysis.purpose and analysis.barrel <= #sortingTurtle.barrels then
                            sortingTurtle.barrels[analysis.barrel].analysis = {
                                purpose = analysis.purpose,
                                category = analysis.category or "unknown",
                                suggested_items = analysis.suggested_items or {},
                                organization_tip = analysis.organization_tip or ""
                            }
                        end
                    end
                    return true
                end
            end
            print("Failed to extract any usable data from LLM response")
        end
    else
        print("No response received from LLM for barrel analysis")
    end
    return false
end

-- Function to define categories and assign them to barrels
function sortingTurtle.defineAndAssignCategories()
    -- First, analyze barrel contents to inform category creation
    local itemsFound = {}
    
    -- Collect all unique items from barrels
    for _, barrel in ipairs(sortingTurtle.barrels) do
        if not barrel.contents.isEmpty then
            for _, item in ipairs(barrel.contents.items) do
                -- Get the actual item name without mod prefix
                local actualItemName = item.name:match("^[^:]+:(.+)$") or item.name
                itemsFound[actualItemName] = item.displayName or item.name
            end
        end
    end
    
    -- Convert to lists for the prompt
    local itemsList = ""
    
    for name, displayName in pairs(itemsFound) do
        itemsList = itemsList .. "- " .. displayName .. " (" .. name .. ")\n"
    end
    
    -- If no items found, use just the unknown category
    if itemsList == "" then
        print("No items found in barrels, using only 'unknown' category")
        sortingTurtle.categories = {
            "unknown"
        }
        
        print("\nDefault categories:")
        for _, category in ipairs(sortingTurtle.categories) do
            print("- " .. category)
        end
        
        -- Assign the unknown category to the first barrel, leave others unassigned
        sortingTurtle.barrelAssignments = {}
        if sortingTurtle.numBarrels > 0 then
            sortingTurtle.barrelAssignments[1] = "unknown"
            print("Assigned barrel 1 to 'unknown' category")
        end
        
        return true
    end
    
    -- Step 1: Define Categories
    local prompt = string.format([[
You are a Minecraft storage system expert creating a categorization system. Your task is to define logical categories for sorting Minecraft items.

CONTEXT:
These items are present in the environment:
%s

TASK:
Define up to 30 logical Minecraft item categories that would make sense for sorting items into barrels.

IMPORTANT CATEGORIZATION GUIDELINES:
- Focus on the actual item types found in the scan above - be adaptive
- Create categories based on what makes sense for sorting these specific items
- Avoid creating a generic "building_blocks" category - instead create more specific categories like "stone_blocks", "wooden_planks", "wooden_logs", "decorative_blocks", etc.
- Create a balanced system that makes practical sense for a Minecraft player

REQUIREMENTS:
1. The list MUST start with "unknown" as the first category
2. Use specific, descriptive category names (1-5 words, lowercase with underscores)
3. Categories should be based on item properties, function, or usage patterns
4. You can create up to 30 categories (including "unknown")
5. Analyze the actual items from the scan to determine the best categorization system

FORMAT INSTRUCTIONS:
Return ONLY the category names, one per line.
No numbers, explanations, or additional text.
Example format:
unknown
dirt_blocks
stone_blocks
wooden_planks
logs
seeds
foraging
mob_drops
monster_drops
unique_items
nether_items
ores
natural_resources
etc.
]], itemsList)

    print("Requesting categories based on environment analysis...")
    local response = llm.getGeminiResponse(prompt)
    
    if not response then
        print("Error: No response received, using only 'unknown' category")
        sortingTurtle.categories = {"unknown"}
        
        -- Assign the unknown category to the first barrel, leave others unassigned
        sortingTurtle.barrelAssignments = {}
        sortingTurtle.barrelAssignments[1] = "unknown"
        return true
    end
    
    print("\nRaw LLM response for categories:")
    print(response)
    
    -- Split response into lines and clean each category
    sortingTurtle.categories = {}
    for line in response:gmatch("[^\r\n]+") do
        -- Clean up each line (remove quotes, spaces, numbers)
        local category = line:gsub('"', ''):gsub("^%s*(.-)%s*$", "%1"):gsub("^%d+[%.:%)]%s*", "")
        
        -- Skip empty lines or lines with explanations (too long)
        if category ~= "" and #category <= 30 and category:find("^[%a_]+$") then
            table.insert(sortingTurtle.categories, category)
        else
            print(string.format("Skipping invalid category: '%s'", category))
        end
    end
    
    -- Ensure we have at least some categories
    if #sortingTurtle.categories == 0 then
        print("No valid categories found in response, using only 'unknown' category")
        sortingTurtle.categories = {
            "unknown"
        }
    end
    
    -- Ensure unknown is first category
    local hasUnknown = false
    
    for _, category in ipairs(sortingTurtle.categories) do
        if category == "unknown" then hasUnknown = true end
    end
    
    -- If unknown category is missing, add it at the start
    if not hasUnknown then
        table.insert(sortingTurtle.categories, 1, "unknown")
    end
    
    -- Display final categories
    print("\nFinal categories:")
    for _, category in ipairs(sortingTurtle.categories) do
        print("- " .. category)
    end
    
    -- Step 2: Now assign categories to barrels
    if sortingTurtle.numBarrels == 0 then 
        print("No barrels found, cannot assign categories")
        return false 
    end
    
    -- Create detailed context of barrel contents with item names and display names
    local barrelContext = "Barrel contents:\n"
    for i, barrel in ipairs(sortingTurtle.barrels) do
        barrelContext = barrelContext .. string.format("\nBarrel %d: ", i)
        if barrel.contents.isEmpty then
            barrelContext = barrelContext .. "EMPTY"
        else
            barrelContext = barrelContext .. "\n"
            for _, item in ipairs(barrel.contents.items) do
                -- Extract just the item name without mod prefix for better categorization
                local actualItemName = item.name:match("^[^:]+:(.+)$") or item.name
                
                barrelContext = barrelContext .. string.format("- %s (%s)\n", 
                    item.displayName or item.name, 
                    actualItemName)
            end
        end
    end
    
    local categoriesText = table.concat(sortingTurtle.categories, "\n")
    local assignmentPrompt = string.format([[
You are a Minecraft storage system expert. Assign the most appropriate category to each barrel based on its contents.

BARREL CONTENTS:
%s

AVAILABLE CATEGORIES:
%s

TASK:
Assign ONE category to each barrel based on its contents or leave it empty for future use.

ASSIGNMENT RULES:
1. The first barrel (Barrel 1) MUST be assigned to 'unknown' category
2. Each barrel should get exactly ONE category from the list above
3. For barrels with items, assign a category that best matches ALL items in the barrel
4. For empty barrels, assign categories that aren't yet assigned
5. Prioritize assigning all categories before duplicating any
6. If a barrel has mixed contents, choose the category that best represents the majority

CATEGORIZATION GUIDELINES:
- Consider the contents of each barrel and how they would be most logically organized
- Group items by material, function, or type as appropriate
- Create a storage system that would be intuitive for a Minecraft player
- Allow flexibility in category assignments based on what makes most sense for these specific items

RESPONSE FORMAT:
Return ONLY category assignments, one per line, with exactly %d lines (one for each barrel).
EXAMPLE OUTPUT for %d barrels:
unknown
stone_blocks
wooden_planks
decorative_blocks
crafting_materials
etc.
]], barrelContext, categoriesText, sortingTurtle.numBarrels, sortingTurtle.numBarrels)

    print("Assigning categories to barrels based on contents analysis...")
    local assignResponse = llm.getGeminiResponse(assignmentPrompt)
    if not assignResponse then
        print("Error: No category assignments received")
        -- Just assign unknown to barrel 1 and leave others empty
        sortingTurtle.barrelAssignments = {}
        sortingTurtle.barrelAssignments[1] = "unknown"
        return true
    end
    
    print("\nRaw LLM response for barrel assignments:")
    print(assignResponse)
    
    -- Split response into lines and assign categories
    local assignments = {}
    for line in assignResponse:gmatch("[^\r\n]+") do
        -- Clean up each line (remove spaces, quotes)
        local category = line:gsub('"', ''):gsub("^%s*(.-)%s*$", "%1")
        if category ~= "" then
            table.insert(assignments, category)
        end
    end
    
    print(string.format("\nParsed %d category assignments from response", #assignments))
    
    -- If we didn't get enough assignments, fill in with unknown
    if #assignments < sortingTurtle.numBarrels then
        print(string.format("WARNING: Only got %d assignments for %d barrels", 
            #assignments, sortingTurtle.numBarrels))
        for i = #assignments + 1, sortingTurtle.numBarrels do
            table.insert(assignments, "unknown")
        end
    end
    
    -- If we got too many assignments, trim the extras
    if #assignments > sortingTurtle.numBarrels then
        print(string.format("WARNING: Got %d assignments for %d barrels, trimming extras", 
            #assignments, sortingTurtle.numBarrels))
        while #assignments > sortingTurtle.numBarrels do
            table.remove(assignments)
        end
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
            print(string.format("Warning: Invalid category '%s' assigned to barrel %d, using unknown", 
                category, i))
            assignments[i] = "unknown"
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

-- Modify sortItems function to handle problematic items
function sortingTurtle.sortItems()
    -- Clear movement history before starting to sort
    sortingTurtle.moveHistory = {}
    
    -- Do initial scan if we haven't done one yet
    if sortingTurtle.numBarrels == 0 then
        sortingTurtle.scanBarrels()
        if sortingTurtle.numBarrels == 0 then 
            print("Error: No barrels found during scan!")
            return 
        end
    end
    
    print("\nChecking input storage...")
    
    -- Check if we're facing a valid storage block
    if not sortingTurtle.isValidInputStorage() then
        print("No chest or barrel detected in front! Please ensure the turtle is facing the input storage.")
        return
    end

    -- Try to access the storage
    local hasItems = false
    for slot = 1, 16 do
        if turtle.suck() then
            hasItems = true
            turtle.drop() -- Put it back for now
            break
        end
    end

    -- If no items to sort, return to initial position
    if not hasItems then
        print("No items found in input storage.")
        return
    end

    print("Found items to sort!")
    
    -- Process items in the storage
    local itemsMoved = false
    local itemsSorted = 0
    local itemsToUnknown = 0
    
    while true do
        -- Clear movement history before processing each item
        sortingTurtle.moveHistory = {}
        
        -- Try to get an item
        if not turtle.suck() then
            break  -- No more items to sort
        end
        
        local itemDetail = turtle.getItemDetail()
        if itemDetail then
            local itemCategory = sortingTurtle.getItemCategory(itemDetail.name)
            print(string.format("\nProcessing: %s (Category: %s)", 
                itemDetail.displayName or itemDetail.name,
                itemCategory))
            
            -- Get barrel slot - this might return unknown (1) if categorization fails
            local barrelSlot = sortingTurtle.getBarrelSlot(itemDetail.name, itemDetail.displayName)
            
            print(string.format("Moving to barrel %d...", barrelSlot))
            -- Move to barrel and drop item
            if sortingTurtle.moveToBarrel(barrelSlot) then
                if turtle.drop() then
                    itemsMoved = true
                    if barrelSlot == 1 then
                        itemsToUnknown = itemsToUnknown + 1
                        print("Stored in unknown barrel")
                    else
                        itemsSorted = itemsSorted + 1
                    print(string.format("Stored in barrel %d", barrelSlot))
                    end
                else
                    print("Warning: Could not store item in barrel! Moving to unknown barrel instead.")
                    -- If item can't be stored in target barrel, go straight to unknown
                    sortingTurtle.returnToInitial()
                    if sortingTurtle.moveToBarrel(1) then  -- Move to unknown barrel
                        if turtle.drop() then
                            itemsToUnknown = itemsToUnknown + 1
                            print("Stored in unknown barrel")
                        else
                            print("CRITICAL ERROR: Could not store item in unknown barrel!")
                            -- Drop the item in front of the turtle
                            sortingTurtle.returnToInitial()
                            turtle.drop()
                        end
                    end
                end
            else
                -- If we can't move to the target barrel, try unknown barrel
                print("Warning: Could not move to target barrel! Trying unknown barrel.")
                sortingTurtle.returnToInitial()
                if sortingTurtle.moveToBarrel(1) then  -- Move to unknown barrel
                    if turtle.drop() then
                        itemsToUnknown = itemsToUnknown + 1
                        print("Stored in unknown barrel")
                    else
                        print("CRITICAL ERROR: Could not store item in unknown barrel!")
                        sortingTurtle.returnToInitial()
                        turtle.drop()
                    end
                else
                    print("CRITICAL ERROR: Could not move to any barrel!")
                    sortingTurtle.returnToInitial()
                    turtle.drop()
                end
            end
            
            -- Return to initial position using movement history
            sortingTurtle.returnToInitial()
        end
        
        -- Check if there are more items to process
        local hasMoreItems = false
        for slot = 1, 16 do
            if turtle.suck() then
                hasMoreItems = true
                turtle.drop() -- Put it back for now
                break
            end
        end
        
        -- If no more items, break the loop
        if not hasMoreItems then
            break
        end
    end
    
    -- Print summary
    if itemsMoved then
        print("\nSorting complete:")
        print(string.format("- Items sorted to categories: %d", itemsSorted))
        print(string.format("- Items sent to unknown: %d", itemsToUnknown))
    else
        print("\nNo items were sorted")
    end
end

-- Function to check if there are items in the input storage without taking them
function sortingTurtle.hasItemsInStorage()
    -- Try to detect items without actually taking them
    local success, data = turtle.inspect()
    if success and data then
        -- Check if it's a valid storage block
        if data.name == "minecraft:chest" or 
           data.name == "minecraft:barrel" or 
           data.name:find("chest") or 
           data.name:find("barrel") or 
           data.name:find("storage") then
            
            -- Peek at the inventory without removing items
            if turtle.suck() then
                turtle.drop()  -- Put it right back
                return true
            end
        end
    end
    return false
end

-- Modify scanBarrels to use a batch analysis approach
function sortingTurtle.scanBarrels()
    print("\n=== Starting Barrel Scan ===")
    
    -- Save existing barrel assignments before clearing the barrels table
    local oldBarrelAssignments = {}
    if sortingTurtle.barrelAssignments then
        for barrelNum, category in pairs(sortingTurtle.barrelAssignments) do
            oldBarrelAssignments[barrelNum] = category
        end
    end
    
    local foundBarrels = 0
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
                if string.find(data.name or "", "barrel") or 
                   string.find(data.name or "", "storage") or
                   data.name == "minecraft:barrel" or
                   data.name == "minecraft:chest" then
                    
                    print(string.format("Found storage block: %s", data.name))
                    foundBarrels = foundBarrels + 1
                    
                    -- Read barrel contents immediately but don't analyze yet
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
                    if not contents.isEmpty then
                        for _, item in ipairs(contents.items) do
                            print(string.format("  * %s", item.displayName or item.name))
                        end
                    end
                else
                    print(string.format("Found non-barrel block: %s", data.name or "unknown"))
                end
            else
                print("No block detected")
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
                print("Cannot move forward, stopping scan at this level")
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
        
        -- Now that we've collected data on all barrels, analyze them together
        print("\nAnalyzing all barrel contents together...")
        if sortingTurtle.analyzeBulkBarrels() then
            print("Barrel analysis completed successfully!")
            
            for i, barrel in ipairs(sortingTurtle.barrels) do
                if barrel.analysis then
                    print(string.format("Barrel %d analysis: %s - %s", 
                        i, 
                        barrel.analysis.purpose or "Unknown purpose",
                        barrel.analysis.suggested_items and table.concat(barrel.analysis.suggested_items, ", ") or "No suggestions"))
                end
            end
        else
            print("Warning: Bulk barrel analysis failed")
        end
        
        -- Define categories if this is the first scan
        if next(sortingTurtle.categories) == nil then
            print("\nDefining storage categories...")
            if sortingTurtle.defineAndAssignCategories() then
                print("Categories defined successfully!")
            else
                print("Error: Could not define categories!")
                return
            end
        end
        
        -- Transfer old barrel assignments if possible
        if next(oldBarrelAssignments) ~= nil and not (#oldBarrelAssignments > sortingTurtle.numBarrels) then
            print("\nRestoring previous barrel assignments...")
            sortingTurtle.barrelAssignments = {}
            for barrelNum, category in pairs(oldBarrelAssignments) do
                if barrelNum <= sortingTurtle.numBarrels then
                    sortingTurtle.barrelAssignments[barrelNum] = category
                    print(string.format("Restored: Barrel %d -> %s", barrelNum, category))
                end
            end
            
            -- Ensure all barrels have an assignment
            for i = 1, sortingTurtle.numBarrels do
                if not sortingTurtle.barrelAssignments[i] then
                    sortingTurtle.barrelAssignments[i] = "unknown"
                    print(string.format("Assigned new barrel %d -> unknown", i))
                end
            end
            
            print("Barrel assignments restored successfully")
        else
            -- Use barrel analysis to inform category assignments
            local suggestedCategories = {}
            for i, barrel in ipairs(sortingTurtle.barrels) do
                if barrel.analysis and barrel.analysis.category then
                    -- Check if this is a new category we should consider
                    local category = barrel.analysis.category
                    if not suggestedCategories[category] then
                        -- Check if it's similar to an existing category
                        local isSimilar = false
                        for existingCategory, _ in pairs(suggestedCategories) do
                            -- Simple similarity check - could be improved
                            if string.find(category, existingCategory) or 
                               string.find(existingCategory, category) then
                                isSimilar = true
                                break
                            end
                        end
                        
                        if not isSimilar then
                            suggestedCategories[category] = {
                                description = barrel.analysis.description,
                                barrelNum = i
                            }
                        end
                    end
                end
            end
            
            -- Print suggested categories from barrel analysis
            if next(suggestedCategories) ~= nil then
                print("\nSuggested categories from barrel analysis:")
                for category, info in pairs(suggestedCategories) do
                    print(string.format("- %s: %s (Barrel %d)", 
                        category, info.description, info.barrelNum))
                end
            else
                print("\nNo suggested categories from barrel analysis")
        end
        
        -- Assign categories to barrels
        print("\nAssigning categories to barrels...")
        if sortingTurtle.defineAndAssignCategories() then
            print("Category assignment complete!")
            -- Print category assignments
            for barrel, category in pairs(sortingTurtle.barrelAssignments) do
                print(string.format("Barrel %d: %s", barrel, category))
            end
        else
            print("Warning: Could not assign categories to barrels")
                -- Emergency fallback - ensure at least unknown barrel exists
                if sortingTurtle.numBarrels > 0 and next(sortingTurtle.barrelAssignments) == nil then
                    sortingTurtle.barrelAssignments = {}
                    sortingTurtle.barrelAssignments[1] = "unknown"
                    print("EMERGENCY: Assigned Barrel 1 to unknown category")
                end
            end
        end
    else
        print("\nNo barrels found! Please set up barrels and restart.")
    end
    
    sortingTurtle.lastScanTime = os.epoch("local")
    return sortingTurtle.numBarrels > 0
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

-- Enhanced function to handle problematic items using LLM analysis
function sortingTurtle.handleProblematicItem(itemName, itemDisplayName)
    print(string.format("\nHandling problematic item: %s", itemDisplayName or itemName))
    
    -- Extract mod name and item type for better analysis
    local modName = itemName:match("^([^:]+):") or "unknown"
    local itemType = itemName:match("^[^:]+:([^_]+)") or "unknown"
    
    -- Check if we've already analyzed this item before
    if sortingTurtle.problematicItems[itemName] and sortingTurtle.problematicItems[itemName].analysis then
        print("Using previous analysis for problematic item")
        
        local analysis = sortingTurtle.problematicItems[itemName].analysis
        
        -- Check if the analysis has a suggested category
        if analysis.suggested_category then
            print(string.format("Previous analysis suggests category: %s", analysis.suggested_category))
            
            -- Look for a barrel with this category
            for barrelNum, category in pairs(sortingTurtle.barrelAssignments) do
                if category == analysis.suggested_category then
                    print(string.format("Found barrel %d for suggested category '%s'", 
                        barrelNum, category))
                    return barrelNum
                end
            end
        end
        
        -- If we have a problematic_items barrel, use that
        for barrelNum, category in pairs(sortingTurtle.barrelAssignments) do
            if category == "problematic_items" then
                print("Using problematic_items barrel")
                return barrelNum
            end
        end
        
        -- Fallback to unknown barrel
        print("No matching barrel found for problematic item, using unknown barrel")
        return 1  -- Unknown barrel
    end
    
    -- Record or update problematic item
    if not sortingTurtle.problematicItems[itemName] then
        sortingTurtle.problematicItems[itemName] = {
            name = itemName,
            displayName = itemDisplayName,
            attempts = 1
        }
    else
        -- Update existing entry
        sortingTurtle.problematicItems[itemName].attempts = 
            sortingTurtle.problematicItems[itemName].attempts + 1
    end
    
    -- Create a detailed prompt for LLM to analyze the problematic item
    local prompt = string.format([[
You are a Minecraft item analysis expert. Analyze this problematic item that cannot be sorted properly.

ITEM DETAILS:
Name: %s
Display Name: %s
Mod: %s
Item Type: %s
Sorting Attempts: %d

AVAILABLE CATEGORIES:
%s

TASK:
Analyze this item and provide suggestions for how to handle it. Consider item name patterns,
mod associations, and potential usage in Minecraft.

ANALYSIS QUESTIONS:
1. What is the likely purpose or function of this item based on its name?
2. Which mod does this item come from and what kinds of items does that mod add?
3. Does the item name suggest any special handling requirements?
4. Which category would be most appropriate for this item?
5. Should a new category be created for this type of item?

RESPONSE FORMAT:
Return a JSON object with these fields:
{
  "analysis": "Detailed analysis of the item and why it's problematic",
  "suggested_category": "most_appropriate_category",
  "special_handling": "Any special handling instructions",
  "create_new_category": false
}

The suggested_category MUST be one from the available categories list.
]], 
        itemName,
        itemDisplayName or itemName,
        modName,
        itemType,
        sortingTurtle.problematicItems[itemName].attempts,
        table.concat(sortingTurtle.categories, "\n"))
    
    print("Requesting analysis for problematic item...")
    local response = llm.getGeminiResponse(prompt)
    if not response then
        print("No analysis received, using unknown barrel")
        return 1  -- Return unknown barrel
    end
    
    print("\nProblematic item analysis received")
    
    -- Try to parse the JSON response
    local success, analysisData = pcall(textutils.unserializeJSON, response)
    if success and analysisData then
        -- Store the analysis with the problematic item
        sortingTurtle.problematicItems[itemName].analysis = analysisData
        
        print("\nAnalysis results:")
        print(string.format("- Analysis: %s", analysisData.analysis or "Not provided"))
        print(string.format("- Suggested category: %s", analysisData.suggested_category or "None"))
        print(string.format("- Special handling: %s", analysisData.special_handling or "None"))
        
        -- Check if the suggested category is valid
        local isValidCategory = false
        if analysisData.suggested_category then
            for _, category in ipairs(sortingTurtle.categories) do
                if category == analysisData.suggested_category then
                    isValidCategory = true
                    break
                end
            end
        end
        
        -- If we have a valid category suggestion, look for a matching barrel
        if isValidCategory then
            for barrelNum, category in pairs(sortingTurtle.barrelAssignments) do
                if category == analysisData.suggested_category then
                    print(string.format("Found barrel %d for suggested category '%s'", 
                        barrelNum, category))
                    return barrelNum
                end
            end
        end
        
        -- Look for a problematic_items barrel
        for barrelNum, category in pairs(sortingTurtle.barrelAssignments) do
            if category == "problematic_items" then
                print("Using problematic_items barrel")
                return barrelNum
            end
        end
    else
        print("Failed to parse analysis, response format incorrect")
        print("Raw response: " .. response)
    end
    
    -- Fallback to unknown barrel
    print("No specialized handling possible, using unknown barrel")
    return 1  -- Return unknown barrel
end

-- Main getBarrelSlot function - updated to use our combined categorization function
function sortingTurtle.getBarrelSlot(itemName, itemDisplayName)
    if sortingTurtle.numBarrels == 0 then 
        print("No barrels found, returning unknown barrel")
        return 1  -- Return unknown barrel
    end
    
    -- Print debugging information about barrel assignments
    print("\nDEBUG: Current barrel assignments:")
    local hasAssignments = false
    for barrelNum, category in pairs(sortingTurtle.barrelAssignments) do
        print(string.format("  Barrel %d -> %s", barrelNum, category))
        hasAssignments = true
    end
    
    if not hasAssignments then
        print("WARNING: No barrel assignments found! Running category assignment...")
        -- If we don't have any barrel assignments, try to run the assignment again
        if sortingTurtle.defineAndAssignCategories() then
            print("Successfully reassigned barrel categories")
            
            -- Print the updated assignments
            print("\nUPDATED barrel assignments:")
            for barrelNum, category in pairs(sortingTurtle.barrelAssignments) do
                print(string.format("  Barrel %d -> %s", barrelNum, category))
            end
        else
            print("ERROR: Failed to assign barrel categories, using unknown barrel")
            return 1  -- Return unknown barrel
        end
    end
    
    -- Initialize the item category cache if it doesn't exist
    if sortingTurtle.itemCategoryCache == nil then
        sortingTurtle.itemCategoryCache = {}
    end
    
    -- If we've seen this item before, use the cached category
    if sortingTurtle.itemCategoryCache[itemName] then
        local cachedCategory = sortingTurtle.itemCategoryCache[itemName]
        print(string.format("Using cached category '%s' for %s", 
            cachedCategory, itemDisplayName or itemName))
            
        -- Find a barrel with this category
        for barrelNum, category in pairs(sortingTurtle.barrelAssignments) do
            if category == cachedCategory then
                print(string.format("Found matching barrel %d for category '%s'", barrelNum, category))
                return barrelNum
            end
        end
        
        print(string.format("No barrel found for cached category '%s', checking for similar categories", cachedCategory))
        
        -- Try to find a barrel with a similar category (e.g., wooden_planks vs wooden_blocks)
        for barrelNum, category in pairs(sortingTurtle.barrelAssignments) do
            -- Check if the category is a more specific version or parent version
            if cachedCategory:match(category) or category:match(cachedCategory) then
                print(string.format("Found similar category barrel %d ('%s') for '%s'", 
                    barrelNum, category, cachedCategory))
                return barrelNum
            end
        end
        
        print(string.format("No similar barrel found for cached category '%s', using unknown barrel", cachedCategory))
        return 1  -- Return unknown barrel
    end

    -- If our cache size is large enough, batch process uncategorized items
    if sortingTurtle.uncategorizedItems == nil then
        sortingTurtle.uncategorizedItems = {}
    end
    
    -- Add this item to the uncategorized list
    sortingTurtle.uncategorizedItems[itemName] = {
        name = itemName,
        displayName = itemDisplayName or itemName,
        timestamp = os.epoch("local")
    }
    
    -- Only do batch categorization if we have enough uncategorized items
    -- or if it's been more than 30 seconds since we last encountered an uncategorized item
    local BATCH_SIZE = 5
    local TIME_THRESHOLD = 30 * 1000  -- 30 seconds in milliseconds
    local currentTime = os.epoch("local")
    local lastTimestamp = 0
    local itemCount = 0
    
    for _, itemData in pairs(sortingTurtle.uncategorizedItems) do
        itemCount = itemCount + 1
        if itemData.timestamp > lastTimestamp then
            lastTimestamp = itemData.timestamp
        end
    end
    
    if itemCount >= BATCH_SIZE or (currentTime - lastTimestamp > TIME_THRESHOLD and itemCount > 1) then
        print(string.format("\nBatch categorizing %d items...", itemCount))
        sortingTurtle.batchCategorizeItems()
        
        -- Check if our item was categorized in the batch
        if sortingTurtle.itemCategoryCache[itemName] then
            local cachedCategory = sortingTurtle.itemCategoryCache[itemName]
            print(string.format("Using newly assigned category '%s' for %s", 
                cachedCategory, itemDisplayName or itemName))
                
            -- Find a barrel with this category
            for barrelNum, category in pairs(sortingTurtle.barrelAssignments) do
                if category == cachedCategory then
                    print(string.format("Found matching barrel %d for category '%s'", barrelNum, category))
                    return barrelNum
                end
            end
        end
    else
        -- If we're not doing batch categorization, fall back to individual categorization
        -- Check if we should use single item or batch mode
        local doSingleItemMode = true
        
        if doSingleItemMode then
            -- Generate a prompt for this specific item
            local categoriesText = table.concat(sortingTurtle.categories, "\n")
            local prompt = string.format([[
You are a Minecraft item categorization expert who organizes storage systems. 

ITEM DETAILS:
Full Name: %s
Display Name: %s

AVAILABLE CATEGORIES:
%s

TASK:
1. ANALYZE this Minecraft item - you should use your knowledge of Minecraft and also search the internet/wiki for information about this item.
2. Consider what the item is used for, what materials it's made from, and how players typically organize it.
3. Choose the MOST appropriate category for this item from the available categories list.
4. Your goal is to place this item in the category where a player would most likely look for it.

CATEGORIZATION GUIDELINES:
- Research the item on the Minecraft Wiki if needed to understand its properties and usage
- Consider the item's material, function, and appearance
- Match with similar items that would logically be stored together
- Choose the most specific applicable category if multiple categories could work
- Consider how a player would organize their storage system
- If unsure after research, use the 'unknown' category

RESPONSE FORMAT:
Return ONLY the category name, nothing else, chosen from the AVAILABLE CATEGORIES list.
]], 
                itemName,
                itemDisplayName or itemName,
                categoriesText)
            
            print("Requesting category for individual item...")
            local itemCategory = llm.getGeminiResponse(prompt)
            if not itemCategory then 
                print("No category response received, using unknown barrel")
                return 1  -- Return unknown barrel
            end
            
            -- Clean up the response (remove any quotes or whitespace)
            itemCategory = itemCategory:gsub('"', ''):gsub("^%s*(.-)%s*$", "%1")
            print(string.format("Raw LLM response: '%s'", itemCategory))
            
            -- Check if response might be JSON (which would be incorrect format for individual item)
            if itemCategory:match("^%s*{") or itemCategory:match("^%s*%[") then
                print("Warning: LLM returned JSON instead of category name, attempting to extract category")
                -- Try to parse JSON and extract the category
                local success, parsedData = pcall(textutils.unserializeJSON, itemCategory)
                if success and parsedData and parsedData[1] and parsedData[1].category then
                    itemCategory = parsedData[1].category
                    print(string.format("Extracted category: '%s'", itemCategory))
                else
                    print("Failed to extract category from JSON, using unknown")
                    itemCategory = "unknown"
                end
            end
            
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
                itemCategory = "unknown"
            end
            
            -- Cache this category for future use
            sortingTurtle.itemCategoryCache[itemName] = itemCategory
            print(string.format("Categorized %s as '%s'", itemDisplayName or itemName, itemCategory))
            
            -- Also remove this item from the uncategorized list
            sortingTurtle.uncategorizedItems[itemName] = nil
            
            -- Now find a barrel for this category
            for barrelNum, category in pairs(sortingTurtle.barrelAssignments) do
                if category == itemCategory then
                    print(string.format("Found matching barrel %d for category '%s'", barrelNum, category))
                    return barrelNum
                end
            end
            
            -- If we didn't find an exact match, look for similar categories
            for barrelNum, category in pairs(sortingTurtle.barrelAssignments) do
                -- Check if the category is a more specific version or parent version
                if itemCategory:match(category) or category:match(itemCategory) then
                    print(string.format("Found similar category barrel %d ('%s') for '%s'", 
                        barrelNum, category, itemCategory))
                    return barrelNum
                end
            end
            
            print(string.format("No barrel found for category '%s', using unknown barrel", itemCategory))
            return 1  -- Return unknown barrel (first barrel)
        end
    end
    
    -- If no barrel found or categorization failed, use unknown barrel
    print("No category assigned, using unknown barrel")
    return 1  -- Return unknown barrel (first barrel)
end

-- Function to analyze barrel contents and detect patterns
function sortingTurtle.analyzeBarrelContents(barrel)
    -- No need for complex analysis if barrel is empty
    if barrel.contents.isEmpty then return "empty" end
    
    -- Track the number of items of each type
    local itemTypes = {}
    local itemMods = {}
    
    -- Check all items in the barrel
    for _, item in ipairs(barrel.contents.items) do
        -- Extract mod name and item name
        local mod, itemName = item.name:match("^([^:]+):(.+)$")
        
        -- Increment count for this mod
        if mod then
            itemMods[mod] = (itemMods[mod] or 0) + 1
        end
        
        -- Try to extract item type from name (e.g., "log" from "oak_log")
        local itemType = itemName:match("_(%w+)$")
        if itemType then
            itemTypes[itemType] = (itemTypes[itemType] or 0) + 1
        end
    end
    
    -- Find the most common mod
    local commonMod, modCount = nil, 0
    for mod, count in pairs(itemMods) do
        if count > modCount then
            commonMod = mod
            modCount = count
        end
    end
    
    -- Find the most common item type
    local commonType, typeCount = nil, 0
    for itemType, count in pairs(itemTypes) do
        if count > typeCount then
            commonType = itemType
            typeCount = count
        end
    end
    
    -- Return pattern information
    return {
        mod = commonMod,
        type = commonType,
        items = #barrel.contents.items
    }
end

-- New function for batch categorization of multiple items
function sortingTurtle.batchCategorizeItems()
    if not sortingTurtle.uncategorizedItems or next(sortingTurtle.uncategorizedItems) == nil then
        return  -- No items to categorize
    end
    
    -- Create a list of all uncategorized items
    local itemsList = ""
    local itemCount = 0
    local itemsToProcess = {}
    
    for itemName, itemData in pairs(sortingTurtle.uncategorizedItems) do
        -- Add this item to the list
        itemsList = itemsList .. string.format("\n%s (%s)", 
            itemData.displayName or itemName,
            itemName)
        itemCount = itemCount + 1
        table.insert(itemsToProcess, {
            name = itemName,
            displayName = itemData.displayName or itemName
        })
    end
    
    -- Only proceed if we have items to categorize
    if itemCount == 0 then return end
    
    -- Determine which category these items belong to
    local categoriesText = table.concat(sortingTurtle.categories, "\n")
    local prompt = string.format([[
You are a Minecraft storage system expert. Categorize these items into their most appropriate categories.

ITEMS TO CATEGORIZE:
%s

AVAILABLE CATEGORIES:
%s

TASK:
For each item, choose the MOST appropriate category from the available categories list.
Your goal is to place each item in the category where a player would most likely look for it.

CATEGORIZATION GUIDELINES:
- Consider each item's material, function, and appearance
- Match with similar items that would logically be stored together
- Choose the most specific applicable category if multiple categories could work
- Consider how a player would organize their storage system
- If unsure, use the 'unknown' category

RESPONSE FORMAT:
Return your answers in JSON format as an array of objects with 'item' and 'category' properties:
[
  {"item": "minecraft:dirt", "category": "appropriate_category_here"},
  {"item": "minecraft:oak_planks", "category": "appropriate_category_here"}
]
]], 
        itemsList,
        categoriesText)
    
    print("Requesting batch categorization for " .. itemCount .. " items...")
    local response = llm.getGeminiResponse(prompt)
    
    if not response then
        print("No response received for batch categorization")
        return
    end
    
    -- Try to parse the JSON response
    local success, categorizations = pcall(textutils.unserializeJSON, response)
    if success and categorizations then
        print("Successfully received batch categorizations")
        
        -- Update the item category cache with the new assignments
        local validAssignments = 0
        for _, assignment in ipairs(categorizations) do
            if assignment.item and assignment.category then
                -- Clean up category (remove quotes, spaces)
                local category = assignment.category:gsub('"', ''):gsub("^%s*(.-)%s*$", "%1")
                
                -- Verify the category is valid
                local isValidCategory = false
                for _, validCategory in ipairs(sortingTurtle.categories) do
                    if validCategory == category then
                        isValidCategory = true
                        break
                    end
                end
                
                if isValidCategory then
                    -- Cache this category for future use
                    sortingTurtle.itemCategoryCache[assignment.item] = category
                    print(string.format("Categorized '%s' as '%s'", assignment.item, category))
                    validAssignments = validAssignments + 1
                    
                    -- Remove from uncategorized list
                    sortingTurtle.uncategorizedItems[assignment.item] = nil
                else
                    print(string.format("Warning: Invalid category '%s' returned for item '%s'", 
                        category, assignment.item))
                    sortingTurtle.itemCategoryCache[assignment.item] = "unknown"
                    sortingTurtle.uncategorizedItems[assignment.item] = nil
                end
            else
                print("Warning: Invalid assignment format in response")
            end
        end
        
        print(string.format("Successfully categorized %d/%d items", validAssignments, itemCount))
        return validAssignments > 0
    else
        print("Failed to parse JSON response:")
        print(response:sub(1, 500) .. (response:len() > 500 and "..." or ""))
        return false
    end
end

-- Main loop
print("=== Smart Sorting Turtle v3.0 ===")
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
print("The turtle will scan and use all accessible barrels")

print("\nWaiting for items in input storage...")
print("First item detection will trigger initial barrel scan")

local lastCheckTime = 0
local IDLE_CHECK_INTERVAL = 2  -- Check for items every 2 seconds when idle
local hasScanned = false

while true do
    local currentTime = os.epoch("local")
    
    -- Check if there are items to sort
    if sortingTurtle.hasItemsInStorage() then
        -- If this is our first item detection, do initial setup
        if not hasScanned then
            print("\nFirst items detected! Performing initial barrel scan...")
            sortingTurtle.scanBarrels()
            if sortingTurtle.numBarrels == 0 then
                print("Error: No barrels found during scan!")
                print("Please check barrel setup and restart the program.")
                break
            end
            hasScanned = true
        else
            print("\nDetected items in storage!")
            -- Only rescan if it's been a while since last scan
            if currentTime - sortingTurtle.lastScanTime > sortingTurtle.config.SCAN_INTERVAL then
                print("Rescanning barrels for changes...")
                sortingTurtle.scanBarrels()
                if sortingTurtle.numBarrels == 0 then
                    print("Error: No barrels found during scan!")
                    print("Please check barrel setup and restart the program.")
                    break
                end
            end
        end
        
        -- Sort the items
        sortingTurtle.sortItems()
        print("\nWaiting for more items...")
        lastCheckTime = currentTime
    else
        -- If we haven't checked recently, update the idle message
        if currentTime - lastCheckTime > 30 then  -- Show message every 30 seconds
            if not hasScanned then
                print("Waiting for first items... (Press Ctrl+T to exit)")
            else
                print("Waiting for more items... (Press Ctrl+T to exit)")
            end
            lastCheckTime = currentTime
        end
        os.sleep(IDLE_CHECK_INTERVAL)  -- Wait before checking again
    end
end

return sortingTurtle

