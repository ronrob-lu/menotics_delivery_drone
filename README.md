# Menotics Delivery Drone Mod

A Minetest mod that adds autonomous delivery drones that navigate between mese lamps.

## Features

- **Autonomous Navigation**: Drones automatically fly between placed mese lamps in a patrol pattern
- **Persistent Inventory**: 32-slot inventory that saves items even when the drone is deactivated
- **Obstacle Avoidance**: Smart pathfinding that detects and avoids obstacles by adjusting altitude
- **Hover Effect**: Smooth hovering animation when waiting at lamp positions
- **Status Display**: Real-time status information showing current state and distance to target

## Requirements

- Minetest 5.0+
- Default game (for mese block textures and sounds)

## Installation

1. Clone or download this mod into your Minetest mods directory:
   ```
   ~/.minetest/mods/menotics_delivery_drone/
   ```

2. Enable the mod in your world's `world.mt` file or through the Minetest UI:
   ```
   load_mod_menotics_delivery_drone = true
   ```

## Usage

### Placing Lamps

Craft and place `menotics_delivery_drone:lamp` nodes (Mese Lamps) at desired waypoints. The drone will automatically detect and navigate between all placed lamps.

```
Crafting Recipe:
[Default Mese Block] + [Steel Ingot] = Mese Lamp
```

### Spawning a Drone

Use the `menotics_delivery_drone:drone_item` to place a drone in the world. Right-click on a surface to spawn it.

### Operating the Drone

- **Right-click**: Open the drone's inventory to load/unload items
- **Punch**: Remove the drone (all items will be dropped)
- **Automatic Operation**: Once placed, the drone will automatically:
  1. Find the nearest lamp
  2. Fly to it while avoiding obstacles
  3. Wait for 20 seconds
  4. Move to the next nearest lamp
  5. Repeat the cycle

### Drone States

- **IDLE**: Searching for the next lamp to visit
- **MOVING**: Traveling to a target lamp
- **WAITING**: Hovering at a lamp location (20-second countdown)

## Technical Details

### Entity Properties

- **Health**: 10 HP
- **Speed**: 3 nodes/second
- **Collision Box**: 0.6 × 0.6 × 0.6 nodes
- **Visual**: Textured cube using `menotics.png`

### Inventory System

The drone uses a detached inventory system that persists across activations:
- 32 main slots
- Automatic save/load on deactivation/activation
- Items are preserved when the drone is punched and re-spawned

### Navigation Algorithm

1. Calculates distances to all registered lamps
2. Skips the current lamp and recently visited lamps
3. Selects the nearest valid target (>2 nodes away)
4. Uses raycasting to detect obstacles
5. Adjusts altitude to clear obstacles when necessary
6. Maintains a hover position 2 nodes above each lamp

## File Structure

```
menotics_delivery_drone/
├── init.lua              # Main mod code
├── mod.conf.md           # Mod configuration documentation
├── README.md             # This file
├── textures/
│   └── menotics.png      # Drone texture
└── sounds/
    └── menotics_engine.ogg  # Engine sound (future use)
```

## Commands

No special commands required. All interaction is through:
- Placing/breaking lamp nodes
- Right-clicking the drone for inventory
- Punching the drone to remove it

## Chat Messages

The mod provides feedback through chat messages:
- `[Drone] Activated/Removed` - Drone lifecycle events
- `[Drone] Lamp placed/removed` - Lamp count updates
- `[Drone] Flying to [position]` - Navigation updates
- `[Drone] Arrived at checkpoint!` - Arrival confirmation
- `[Drone] Resuming delivery route...` - Cycle continuation

## Troubleshooting

**Drone not moving:**
- Ensure at least 2 lamps are placed
- Check that lamps are more than 2 nodes apart
- Verify no obstacles are blocking the path

**Inventory not saving:**
- This should work automatically; items persist through deactivation
- If items are lost, check server logs for errors

**Drone stuck:**
- Punch and respawn the drone
- Add more lamps to provide alternative routes
- Clear obstacles between lamps

## License

This mod is provided as-is for educational and entertainment purposes.

## Credits

Created for the Menotics Delivery Drone challenge in Minetest.
