--[[

  Oneblock mod for MineClone 2

  Copyright (C) 2021 Dmitry Kostenko

  License: MIT

]]--

-- Translation
local S
if minetest.get_translator ~= nil then
	S = minetest.get_translator("oneblock")
else
	-- mock the translator function for MT 0.4
	S = function(str, ...)
		local args={...}
		return str:gsub(
			"@%d+",
			function(match) return args[tonumber(match:sub(2))]	end
		)
	end
end

--Definitions
--  Every 150 nodes a block is added to random selection
--  Items from the block get picked according to their weights
--  Supported types of items:
--    node - placeable node e.g. dirt or stone
--    entity - entity e.g. a mod
--  TODO:
--    support items e.g. pickaxes, food etc.
--    support chests, which is even more fun
local loot = {
	{
		{node="mcl_core:dirt_with_grass", weight=100},
		{node="mcl_core:tree", weight=40},
		{node="mcl_core:sapling", weight=20},
		{entity="mobs_mc:pig", weight=2},
	},
	{
		{node="mcl_core:stone", weight=100},
		{node="mcl_core:tree", weight=40},
		{node="mcl_core:birchsapling", weight=10},
		{entity="mobs_mc:chicken", weight=2},
		{entity="mobs_mc:cow", weight=2}
	},
	{
		{node="mcl_core:stone_with_coal", weight=100},
		{node="mcl_core:stone", weight=30},
		{node="mcl_core:dirt_with_grass", weight=30},
		{node="mcl_core:gravel", weight=10},
		{node="mcl_flowers:tallgrass", weight=10},
	},
	{
		{node="mcl_core:stone_with_iron", weight=80},
		{node="mcl_core:stone", weight=30},
		{node="mcl_core:clay", weight=30},
		{node="mcl_core:granite", weight=10},
		{node="mcl_core:junglesapling", weight=2}
	},
	{
		{node="mcl_core:stone_with_lapis", weight=60},
		{node="mcl_core:snowblock", weight=30},
		{node="mcl_core:water_source", weight=30},
		{node="mcl_core:andesite", weight=10},
		{node="mcl_flowers:tallgrass", weight=5},
		{node="mcl_flowers:rose_bush", weight=2}
	},
	{
		{node="mcl_core:stone_with_gold", weight=40},
		{node="mcl_core:stone", weight=30},
		{node="mcl_core:diorite", weight=20},
		{node="mcl_core:cobweb", weight=10},
		{node="mcl_flowers:dandelion", weight=2},
		{entity="mobs_mc:zombie", weight=1}
	},
	{
		{node="mcl_core:dirt_with_grass_snow", weight=40},
		{node="mcl_core:granite", weight=30},
		{node="mcl_farming:wheat", weight=5},
		{node="mcl_flowers:oxeye_daisy", weight=2},
		{entity="mobs_mc:baby_zombie", weight=1}
	},
	{
		{node="mcl_core:stone_with_redstone", weight=30},
		{node="mcl_core:granite", weight=30},
		{node="mcl_core:cactus", weight=10},
		{node="mcl_flowers:tallgrass", weight=10},
		{node="mcl_flowers:poppy", weight=2},
		{entity="mobs_mc:skeleton", weight=1}
	},
	{
		{node="mcl_flowers:tallgrass", weight=30},
		{node="mcl_core:dirt", weight=30},
		{node="mcl_core:dirt_with_grass", weight=30},
		{node="mcl_farming:carrot", weight=2},
		{node="mcl_farming:pumpkin", weight=5},
		{node="mcl_farming:beetroot", weight=2},
		{entity="mobs_mc:husk", weight=1}
	},
	{
		{node="mcl_flowers:tallgrass", weight=30},
		{node="mcl_core:dirt", weight=30},
		{node="mcl_core:stone", weight=30},
		{node="mcl_farming:potato", weight=5},
		{node="mcl_farming:melon", weight=5},
		{entity="mobs_mc:baby_husk", weight=1}
	},
	{
		{node="mcl_core:stone_with_diamond", weight=30},
		{node="mcl_core:lava_source", weight=20},
		{node="mcl_core:dirt", weight=48},
		{entity="mobs_mc:villager_zombie", weight=2}
	},
	{
		{node="mcl_core:stone"},
		{node="mcl_flowers:tallgrass"},
		{node="mcl_flowers:tulip_pink"},
		{node="mcl_core:dirt_with_grass"},
		{node="mcl_core:stone"},
		{node="mcl_flowers:oxeye_daisy"}
	}
}

-- Storage
local storage = minetest.get_mod_storage()

local function get_digcount()
	return storage:get_int("digcount") or 0
end

local function set_digcount(count)
	storage:set_int("digcount", count)
end

-- HUD
local hud = {}
local function hud_add_player(player)
	hud[player:get_player_name()] = player:hud_add({
		type="text",
		scale={x=100,y=100},
		position={x=1,y=0.5},
		alignment={x=-1,y=0},
		offset={x=-50,y=0},
		number=0x40FF80,
		size={x=1},
		text=tostring(get_digcount())
	})
end

local function hud_remove_player(player)
	hud[player:get_player_name()] = nil
end

local function update_digcount(count)
	for k,v in pairs(hud) do
		minetest.get_player_by_name(k):hud_change(v, "text", tostring(count))
	end
end

-- Class WeightedChoice
-- implements random selection from a pool of weighted values
local function WeightedChoice(rng)
	return {
		_rng = rng,
		_total_weight = function(self, pool)
			if pool._total_weight ~= nil then return pool._total_weight end
			local weight = 0
			for i,v in ipairs(pool) do
				weight = weight + v.weight
			end
			pool._total_weight = weight
			return weight
		end,

		_map_weight = function(self, pool, weight)
			for i,v in ipairs(pool) do
				if weight <= v.weight then return v end
				weight = weight - v.weight
			end
		end,

		random_choice = function (self, pool)
			if pool[1].weight == nil then
				return pool[self._rng:next(1,#pool)]
			else
				return self:_map_weight(pool, self._rng:next(1,self:_total_weight(pool)))
			end
		end
	}
end

-- Lucky block
choice = WeightedChoice(PcgRandom(math.random()))
local function spawn_lucky_block(digcount)
	digcount = digcount or get_digcount()

	local block = loot[math.random(1,math.min(math.ceil(digcount / 150), #loot))]
	local item = choice:random_choice(block)
	if item.node ~= nil then
		minetest.set_node({x=0,y=0,z=0}, {name=item.node})
	elseif item.entity ~= nil then
		minetest.set_node({x=0,y=0,z=0}, {name="mcl_core:ice"})
		minetest.add_entity({x=0,y=1,z=0}, item.entity)
	end
end

-- Events
minetest.register_on_dignode(function(pos, oldnode, digger)
	if pos.x == 0 and pos.y == 0 and pos.z == 0 then
		digcount = get_digcount()
		digcount = digcount + 1
		set_digcount(digcount)

		spawn_lucky_block(digcount)
		update_digcount(digcount)
	end
end)

minetest.register_on_respawnplayer(function(p)
    if (p:get_meta():get_string("mcl_beds:spawn") or "") == "" then
        p:set_pos({x=0,y=2,z=0})
        return true
    end
    return false
end)

minetest.register_on_newplayer(function(p)
	p:set_pos({x=0,y=4,z=0})
end)

minetest.register_on_joinplayer(function(p)
	hud_add_player(p)
end)

minetest.register_on_leaveplayer(function(p)
	hud_remove_player(p)
end)

minetest.register_on_generated(function(minp, maxp, seed)
    if minp.x > 0 or minp.y > 0 or minp.z > 0 or
        maxp.x < 0 or maxp.y < 0 or maxp.z < 0 then
        return
    end
	local node
	node = minetest.get_node({x=0,y=0,z=0}) 
	if node.name == "air" or node.name == "ignore" then
		--magic block
		minetest.set_node({x=0,y=0,z=0},{name="mcl_core:dirt_with_grass"})
		--bedrock immediately under
		minetest.set_node({x=0,y=-1,z=0},{name="mcl_core:bedrock"})
	end
end)

-- Validate integrity
minetest.after(0, function()
	for i,g in ipairs(loot) do
		for j,n in ipairs(g) do
			assert(n.node == nil or minetest.registered_nodes[n.node] ~= nil, "node " .. (n.node or "") .. " not found")
			assert(n.entity == nil or minetest.registered_entities[n.entity] ~= nil, "entity " .. (n.entity or "") .. " not found")
		end
	end
end)
