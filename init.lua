-- Menotics Delivery Drone Mod - Drone flies between lamps with inventory
menotics_delivery_drone = {}

local function get_sounds()
    local def = rawget(_G, "default")
    if def and def.node_sound_wood_defaults then
        return def.node_sound_wood_defaults()
    end
    return nil
end

-- Helper function to find all lamps in the world
local function find_all_lamps()
    local lamps = {}
    local entities = minetest.get_objects_inside_radius({x=0, y=0, z=0}, 99999)
    
    for _, obj in ipairs(entities) do
        local luaentity = obj:get_luaentity()
        if luaentity and luaentity.name == "menotics_delivery_drone:lamp" then
            local pos = obj:get_pos()
            if pos then
                table.insert(lamps, {object=obj, pos=pos, entity=luaentity})
            end
        end
    end
    
    return lamps
end

-- REGISTER DRONE ENTITY
minetest.register_entity("menotics_delivery_drone:drone", {
    initial_properties = {
        hp_max = 10,
        physical = false,
        collisionbox = {-0.3, -0.3, -0.3, 0.3, 0.3, 0.3},
        visual = "cube",
        textures = {
            "menotics-drone.png^[transformFY",
            "menotics-drone.png^[transformFY",
            "menotics-drone-top-animated.png",
            "menotics-drone-bottom-animated.png",
            "menotics-drone.png^[transformFY",
            "menotics-drone.png^[transformFY"
        },
        visual_size = {x=1, y=1},
        stepheight = 0,
        automatic_rotate = 0,
        gravity = 0,
        animation = {
            range_start = 0,
            range_end = 1,
            frame_speed = 2,
            loop = true
        },
        spritediv = {x=1, y=2},
        initial_sprite_basepos = {x=0, y=0}
    },
    
    on_activate = function(self, staticdata, dtime_s)
        self.inv_name = "drone_" .. tostring(self.object):gsub("[^%w]", "")
        
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
        
        -- Initialize state
        self.state = "idle"  -- idle, moving, waiting
        self.target_pos = nil
        self.current_lamp = nil
        self.previous_lamp = nil
        self.wait_timer = 0
        self.move_timer = 0
        
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
                if data.current_lamp then
                    self.current_lamp = data.current_lamp
                end
                if data.previous_lamp then
                    self.previous_lamp = data.previous_lamp
                end
            end
        end
        
        -- Set infotext
        self.object:set_properties({
            infotext = "Menotics Delivery Drone\nFlying between lamps\nRight-click to access inventory"
        })
    end,
    
    on_rightclick = function(self, clicker)
        if not clicker:is_player() then return end
        
        local player_name = clicker:get_player_name()
        
        -- Ensure inventory exists
        if not self.inv or not self.inv_name then
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
            
            -- Reload saved inventory data if available
            local staticdata = self.object:get_staticdata()
            if staticdata and staticdata ~= "" then
                local data = minetest.deserialize(staticdata)
                if data and data.inv_data then
                    for i=1, 32 do
                        if data.inv_data[i] then
                            self.inv:set_stack("main", i, ItemStack(data.inv_data[i]))
                        end
                    end
                end
            end
        end
        
        -- Show the inventory formspec with visual separation
        local formspec = "size[8,9;]" ..
            "label[0.2,0.2;Drone Storage]" ..
            "list[detached:" .. self.inv_name .. ";main;0,0.5;8,4;]" ..
            "box[0,4.3;8,0.1;#666666]" ..
            "label[0.2,4.5;Player Inventory]" ..
            "list[current_player;main;0,4.7;8,4;]" ..
            "listring[]"
        
        minetest.show_formspec(player_name, "drone:inv", formspec)
    end,
    
    on_step = function(self, dtime)
        local pos = self.object:get_pos()
        if not pos then return end
        
        local lamps = find_all_lamps()
        
        -- If no lamps, just hover in place
        if #lamps == 0 then
            local hover_y = math.sin(minetest.get_us_time() / 500000) * 0.3
            self.object:set_velocity({x=0, y=hover_y, z=0})
            return
        end
        
        -- State machine
        if self.state == "idle" or self.state == "waiting" then
            self.wait_timer = self.wait_timer + dtime
            
            -- Wait 20 seconds before moving to next lamp
            if self.wait_timer >= 20 then
                self.wait_timer = 0
                self.state = "moving"
                
                -- Find next lamp (not the previous one unless only 2 lamps)
                local next_lamp = nil
                local available_lamps = {}
                
                for _, lamp in ipairs(lamps) do
                    -- Skip the current lamp
                    if lamp.object ~= self.current_lamp then
                        -- Skip the previous lamp unless there are only 2 lamps total
                        if #lamps > 2 and lamp.object == self.previous_lamp then
                            -- Skip previous lamp when more than 2 lamps exist
                        else
                            table.insert(available_lamps, lamp)
                        end
                    end
                end
                
                -- If no available lamps (shouldn't happen), use any lamp except current
                if #available_lamps == 0 then
                    for _, lamp in ipairs(lamps) do
                        if lamp.object ~= self.current_lamp then
                            table.insert(available_lamps, lamp)
                        end
                    end
                end
                
                -- Pick a random lamp from available
                if #available_lamps > 0 then
                    local idx = math.random(1, #available_lamps)
                    next_lamp = available_lamps[idx]
                end
                
                if next_lamp then
                    self.previous_lamp = self.current_lamp
                    self.current_lamp = next_lamp.object
                    self.target_pos = next_lamp.pos
                    self.move_timer = 0
                    
                    -- Start moving towards target
                    local dx = self.target_pos.x - pos.x
                    local dy = self.target_pos.y - pos.y
                    local dz = self.target_pos.z - pos.z
                    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                    
                    if dist > 1.5 then
                        local speed = 5
                        self.velocity = {
                            x = (dx / dist) * speed,
                            y = (dy / dist) * speed,
                            z = (dz / dist) * speed
                        }
                    else
                        self.velocity = {x=0, y=0, z=0}
                        self.state = "waiting"
                    end
                else
                    self.state = "waiting"
                    self.velocity = {x=0, y=0, z=0}
                end
            else
                -- Hover while waiting
                local hover_y = math.sin(minetest.get_us_time() / 500000) * 0.3
                self.object:set_velocity({x=0, y=hover_y, z=0})
            end
            
        elseif self.state == "moving" then
            if self.target_pos then
                local dx = self.target_pos.x - pos.x
                local dy = self.target_pos.y - pos.y
                local dz = self.target_pos.z - pos.z
                local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                
                if dist < 1.5 then
                    -- Arrived at lamp (stop further away to avoid collision)
                    self.velocity = {x=0, y=0, z=0}
                    self.state = "waiting"
                    self.wait_timer = 0
                else
                    -- Continue moving
                    local speed = 5
                    self.velocity = {
                        x = (dx / dist) * speed,
                        y = (dy / dist) * speed,
                        z = (dz / dist) * speed
                    }
                end
                
                self.object:set_velocity(self.velocity)
            else
                self.state = "waiting"
                self.wait_timer = 0
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
        -- Save inventory items and state
        local inv_data = {}
        for i=1, 32 do
            local stack = self.inv:get_stack("main", i)
            if not stack:is_empty() then
                inv_data[i] = stack:to_string()
            end
        end
        
        local current_lamp_id = nil
        if self.current_lamp then
            current_lamp_id = tostring(self.current_lamp):gsub("[^%w]", "")
        end
        
        local previous_lamp_id = nil
        if self.previous_lamp then
            previous_lamp_id = tostring(self.previous_lamp):gsub("[^%w]", "")
        end
        
        local data = {
            inv_data = inv_data,
            current_lamp = current_lamp_id,
            previous_lamp = previous_lamp_id
        }
        
        return minetest.serialize(data)
    end,
    
    on_deactivate = function(self, removal)
        if removal then
            minetest.remove_detached_inventory(self.inv_name)
        end
    end,
})

-- REGISTER LAMP ENTITY (waypoint for drones)
minetest.register_entity("menotics_delivery_drone:lamp", {
    initial_properties = {
        hp_max = 10,
        physical = false,
        collisionbox = {-0.3, 0, -0.3, 0.3, 0.8, 0.3},
        visual = "cube",
        textures = {"default_lamp.png", "default_lamp.png", "default_lamp.png", "default_lamp.png", "default_lamp.png", "default_lamp.png"},
        visual_size = {x=1, y=1},
        glow = 8,
        gravity = 0,
    },
    
    on_activate = function(self, staticdata, dtime_s)
        self.object:set_properties({
            infotext = "Delivery Lamp\nDrone waypoint"
        })
    end,
    
    on_step = function(self, dtime)
        -- Lamp stays stationary, just glows
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

-- REGISTER LAMP ITEM
minetest.register_craftitem("menotics_delivery_drone:lamp_item", {
    description = "Delivery Lamp\nDrone waypoint\nRight-click to place",
    inventory_image = "default_lamp.png",
    
    on_place = function(itemstack, placer, pointed_thing)
        if not pointed_thing then return itemstack end
        
        local pos = pointed_thing.above
        if not pos then return itemstack end
        
        minetest.add_entity(pos, "menotics_delivery_drone:lamp")
        itemstack:take_item()
        minetest.chat_send_all("[Lamp] Placed!")
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
    output = "menotics_delivery_drone:lamp_item 2",
    recipe = {
        {"default:glass", "default:torch", "default:glass"},
        {"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
    }
})
