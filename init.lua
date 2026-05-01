-- Menotics Delivery Drone Mod
menotics_delivery_drone = {}
menotics_delivery_drone.lamps = {}

local function pos_to_key(pos)
    if not pos then return nil end
    return minetest.pos_to_string(vector.round(pos))
end

local function count_lamps()
    local c = 0
    for _ in pairs(menotics_delivery_drone.lamps) do c = c + 1 end
    return c
end

local function find_nearest_lamp(current_pos, exclude_pos)
    local nearest, nearest_dist = nil, math.huge
    local lamp_positions = {}
    
    for lamp_pos_str, _ in pairs(menotics_delivery_drone.lamps) do
        local lamp_pos = minetest.string_to_pos(lamp_pos_str)
        if lamp_pos then table.insert(lamp_positions, lamp_pos) end
    end
    
    for _, lamp_pos in ipairs(lamp_positions) do
        local dist = vector.distance(current_pos, lamp_pos)
        
        -- Always skip the lamp we're currently at or very close to
        if dist > 2 then  -- Must be at least 2 blocks away
            -- Also skip the previous lamp if we have more than 2 lamps
            if exclude_pos and count_lamps() > 2 then
                if vector.equals(lamp_pos, exclude_pos) then goto continue end
            end
            
            if dist < nearest_dist then
                nearest, nearest_dist = lamp_pos, dist
            end
        end
        ::continue::
    end
    return nearest
end

local function get_sounds()
    local def = rawget(_G, "default")
    if def and def.node_sound_wood_defaults then
        return def.node_sound_wood_defaults()
    end
    return nil
end

-- REGISTER DRONE ENTITY
minetest.register_entity("menotics_delivery_drone:drone", {
    initial_properties = {
        hp_max = 10,
        physical = false,
        collisionbox = {-0.3, -0.3, -0.3, 0.3, 0.3, 0.3},
        visual = "cube",
        textures = {"menotics.png", "menotics.png", "menotics.png", "menotics.png", "menotics.png", "menotics.png"},
        visual_size = {x=1, y=1},
        stepheight = 0,
        automatic_rotate = 0,
        gravity = 0,
    },
    
    on_activate = function(self, staticdata, dtime_s)
        self.state = "idle"
        self.wait_timer = 0
        self.target = nil
        self.last_lamp = nil
        self.speed = 3
        self.hover_timer = 0
        self.inv_name = "drone_" .. tostring(self.object):gsub("[^%w]", "")
        self.current_lamp_pos = nil -- Track which lamp we're currently at
        
        -- Create persistent inventory
        self.inv = minetest.create_detached_inventory(self.inv_name, {
            allow_move = function(inv, from_list, from_index, to_list, to_index, count, player)
                return count
            end,
            allow_put = function(inv, listname, index, stack, player)
                return stack:get_count()
            end,
            allow_take = function(inv, listname, index, stack, player)
                return stack:get_count()
            end,
        })
        self.inv:set_size("main", 32)
        
        -- Load saved data
        if staticdata and staticdata ~= "" then
            local data = minetest.deserialize(staticdata)
            if data then
                if data.inv_data then
                    for i=1, 32 do
                        if data.inv_data[i] then
                            self.inv:set_stack("main", i, ItemStack(data.inv_data[i]))
                        end
                    end
                end
                self.state = data.state or "idle"
                self.wait_timer = data.wait_timer or 0
                self.current_lamp_pos = data.current_lamp_pos
            end
        end
        
        minetest.chat_send_all("[Drone] Activated. Lamps: " .. count_lamps())
    end,
    
    on_rightclick = function(self, clicker)
        if not clicker:is_player() then return end
        
        local player_name = clicker:get_player_name()
        
        -- Ensure inventory exists
        if not self.inv then
            self.inv_name = "drone_" .. tostring(self.object):gsub("[^%w]", "")
            self.inv = minetest.create_detached_inventory(self.inv_name, {
                allow_move = function(inv, from_list, from_index, to_list, to_index, count, player)
                    return count
                end,
                allow_put = function(inv, listname, index, stack, player)
                    return stack:get_count()
                end,
                allow_take = function(inv, listname, index, stack, player)
                    return stack:get_count()
                end,
            })
            self.inv:set_size("main", 32)
        end
        
        -- Show the inventory formspec
        local formspec = "size[8,9;]" ..
            "label[0,-0.2;Drone Inventory]" ..
            "list[detached:" .. self.inv_name .. ";main;0,0.5;8,4;]" ..
            "list[current_player;main;0,4.5;8,4;]" ..
            "listring[]"
        
        minetest.show_formspec(player_name, "drone:inv", formspec)
    end,
    
    on_step = function(self, dtime)
        local pos = self.object:get_pos()
        if not pos then return end
        
        self.hover_timer = self.hover_timer + dtime
        
        -- Update status text
        local status_text = "Menotics Delivery Drone\n[" .. self.state:upper() .. "] Lamps: " .. count_lamps()
        if self.state == "waiting" then
            status_text = status_text .. "\nWaiting: " .. math.ceil(20 - self.wait_timer) .. "s"
        elseif self.state == "moving" and self.target then
            local dist = vector.distance(pos, self.target)
            status_text = status_text .. "\nDistance: " .. math.floor(dist) .. "m"
        end
        self.object:set_properties({infotext = status_text})
        
        if self.state == "idle" then
            self.object:set_velocity({x=0, y=0, z=0})
            self.target = find_nearest_lamp(pos, self.last_lamp)
            
            if self.target then
                minetest.chat_send_all("[Drone] Flying to " .. minetest.pos_to_string(self.target))
                self.state = "moving"
            else
                minetest.chat_send_all("[Drone] No lamps found to fly to!")
            end
            
        elseif self.state == "moving" then
            if not self.target then
                self.state = "idle"
                return
            end
            
            local dir = vector.subtract(self.target, pos)
            local dist = vector.length(dir)
            
            if dist < 1.5 then
                self.state = "waiting"
                self.wait_timer = 0
                self.last_lamp = pos
                self.current_lamp_pos = pos_to_key(self.target) -- Remember which lamp we're at
                self.object:set_velocity({x=0, y=0, z=0})
                minetest.chat_send_all("[Drone] Arrived at checkpoint!")
                return
            end
            
            -- Calculate desired height (above the target lamp)
            local target_height = self.target.y + 2 -- Hover 2 blocks above the lamp
            
            -- Create a target position with the correct height
            local adjusted_target = {
                x = self.target.x,
                y = target_height,
                z = self.target.z
            }
            
            -- Calculate direction to the adjusted target (at proper height)
            local dir_to_target = vector.subtract(adjusted_target, pos)
            local dist_to_target = vector.length(dir_to_target)
            
            -- Normalize and scale velocity
            local vel = vector.normalize(dir_to_target)
            vel = vector.multiply(vel, self.speed)
            
            -- Add hover effect
            local hover_y = math.sin(self.hover_timer * 3) * 0.3
            vel.y = vel.y + hover_y
            
            -- Raycast to check for obstacles in the path
            local current_pos = pos
            local step_size = 1
            local max_steps = math.ceil(dist_to_target / step_size)
            local has_obstacle = false
            local obstacle_pos = nil
            
            for i = 1, max_steps do
                local check_pos = vector.add(current_pos, vector.multiply(vector.normalize(dir_to_target), i * step_size))
                local node = minetest.get_node(check_pos)
                if node and not minetest.registered_nodes[node.name] then
                    has_obstacle = true
                    obstacle_pos = check_pos
                    break
                end
                -- Check if node is solid
                local node_def = minetest.registered_nodes[node.name]
                if node_def and node_def.walkable then
                    has_obstacle = true
                    obstacle_pos = check_pos
                    break
                end
            end
            
            -- If there's an obstacle, try to go around it by increasing Y
            if has_obstacle then
                -- Try to find a clear path by going higher
                local test_height = target_height + 1
                while test_height < self.target.y + 20 do
                    local test_pos = {x = self.target.x, y = test_height, z = self.target.z}
                    local path_clear = true
                    
                    -- Check if this height is clear
                    for dy = 0, 2 do
                        local check_pos = {x = self.target.x, y = test_pos.y + dy, z = self.target.z}
                        local node = minetest.get_node(check_pos)
                        local node_def = minetest.registered_nodes[node.name]
                        if node_def and node_def.walkable then
                            path_clear = false
                            break
                        end
                    end
                    
                    if path_clear then
                        adjusted_target.y = test_height
                        dir_to_target = vector.subtract(adjusted_target, pos)
                        vel = vector.normalize(dir_to_target)
                        vel = vector.multiply(vel, self.speed)
                        vel.y = vel.y + hover_y
                        break
                    end
                    test_height = test_height + 1
                end
            end
            
            self.object:set_velocity(vel)
            
            local yaw = math.atan2(dir_to_target.x, dir_to_target.z)
            self.object:set_yaw(yaw)
            
        elseif self.state == "waiting" then
            -- Always stay positioned above the current lamp when waiting
            if self.current_lamp_pos then
                local lamp_pos = minetest.string_to_pos(self.current_lamp_pos)
                if lamp_pos then
                    -- Calculate the ideal hover position (2 blocks above the lamp)
                    local ideal_pos = {
                        x = lamp_pos.x,
                        y = lamp_pos.y + 2,
                        z = lamp_pos.z
                    }
                    
                    -- Check if we're at the correct position
                    local dist_from_ideal = vector.distance(pos, ideal_pos)
                    
                    -- If we've drifted too far, move back to the ideal position
                    if dist_from_ideal > 0.5 then
                        local dir_to_ideal = vector.subtract(ideal_pos, pos)
                        local vel = vector.normalize(dir_to_ideal)
                        vel = vector.multiply(vel, self.speed * 0.5) -- Move slower when repositioning
                        
                        -- Add small hover effect
                        local hover_y = math.sin(self.hover_timer * 3) * 0.3
                        vel.y = vel.y + hover_y
                        
                        self.object:set_velocity(vel)
                        
                        local yaw = math.atan2(dir_to_ideal.x, dir_to_ideal.z)
                        self.object:set_yaw(yaw)
                    else
                        -- Just hover in place
                        local hover_y = math.sin(self.hover_timer * 3) * 0.3
                        self.object:set_velocity({x=0, y=hover_y, z=0})
                    end
                else
                    -- Lamp position lost, just hover
                    local hover_y = math.sin(self.hover_timer * 3) * 0.3
                    self.object:set_velocity({x=0, y=hover_y, z=0})
                end
            else
                -- No lamp position tracked, just hover
                local hover_y = math.sin(self.hover_timer * 3) * 0.3
                self.object:set_velocity({x=0, y=hover_y, z=0})
            end
            
            self.wait_timer = self.wait_timer + dtime
            
            if self.wait_timer >= 20 then
                self.state = "idle"
                minetest.chat_send_all("[Drone] Resuming delivery route...")
            end
        end
    end,
    
    on_punch = function(self, puncher)
        if puncher and puncher:is_player() then
            -- Drop all items from inventory
            local drop_pos = self.object:get_pos()
            drop_pos.y = drop_pos.y + 1
            
            for i=1, 32 do
                local stack = self.inv:get_stack("main", i)
                if not stack:is_empty() then
                    minetest.add_item(drop_pos, stack)
                end
            end
            
            minetest.chat_send_all("[Drone] Removed - items dropped")
            minetest.remove_detached_inventory(self.inv_name)
            self.object:remove()
        end
    end,
    
    get_staticdata = function(self)
        -- Save inventory items
        local inv_data = {}
        for i=1, 32 do
            local stack = self.inv:get_stack("main", i)
            if not stack:is_empty() then
                inv_data[i] = stack:to_string()
            end
        end
        
        local data = {
            inv_data = inv_data,
            state = self.state,
            wait_timer = self.wait_timer,
            current_lamp_pos = self.current_lamp_pos
        }
        
        -- Clean up inventory
        minetest.remove_detached_inventory(self.inv_name)
        
        return minetest.serialize(data)
    end,
    
    on_deactivate = function(self, removal)
        if removal then
            minetest.remove_detached_inventory(self.inv_name)
        end
    end,
})

-- REGISTER LAMP NODE
minetest.register_node("menotics_delivery_drone:lamp", {
    description = "Menotics Mese Lamp",
    tiles = {"default_mese_block.png"},
    groups = {snappy=2, choppy=2, oddly_breakable_by_hand=2},
    light_source = 7,
    sounds = get_sounds(),
    
    on_construct = function(pos)
        menotics_delivery_drone.lamps[pos_to_key(pos)] = true
        minetest.chat_send_all("[Drone] Lamp placed (Total: " .. count_lamps() .. ")")
    end,
    
    on_destruct = function(pos)
        menotics_delivery_drone.lamps[pos_to_key(pos)] = nil
        minetest.chat_send_all("[Drone] Lamp removed (Total: " .. count_lamps() .. ")")
    end,
})

-- REGISTER DRONE ITEM
minetest.register_craftitem("menotics_delivery_drone:drone_item", {
    description = "Menotics Delivery Drone\nRight-click to place",
    inventory_image = "menotics.png",
    
    on_place = function(itemstack, placer, pointed_thing)
        if not pointed_thing then return itemstack end
        
        local pos = pointed_thing.above
        if not pos then return itemstack end
        
        pos.y = pos.y + 1
        
        minetest.add_entity(pos, "menotics_delivery_drone:drone")
        itemstack:take_item()
        minetest.chat_send_all("[Drone] Deployed!")
        return itemstack
    end,
})

-- RECIPES
minetest.register_craft({
    output = "menotics_delivery_drone:drone_item",
    recipe = {
        {"default:steel_ingot", "default:mese_crystal", "default:steel_ingot"},
        {"default:steel_ingot", "default:chest", "default:steel_ingot"},
        {"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
    }
})

minetest.register_craft({
    output = "menotics_delivery_drone:lamp",
    recipe = {
        {"default:glass", "default:glass", "default:glass"},
        {"default:glass", "default:mese_crystal", "default:glass"},
        {"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
    }
})