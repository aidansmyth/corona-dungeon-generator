--[[----------------------------------------------------------------------------
	Dungeon Generator - digging Algorithm Module

	File: dungeon_gen_dig.lua
	
	Description: 
	

	Date: 12/11/2013

	Authors: Aidan Smyth

	Notes: 
	Corona SDK version used: 2012.971
	
	
------------------------------------------------------------------------------]]


-- #############################################################################
-- Load modules
-- #############################################################################
local appGlobals = require("globalData")					-- Load Global data
local utils = require("modules.tools.utilities")			-- Load utilities


-- #############################################################################
-- Setup variables
-- #############################################################################

----------------------------------------
-- Setup dungeon container data
----------------------------------------
local dungeon = {}
local dungeon_mt = { __index = dungeon}						-- metatable
-- Size of the map
dungeon.width = 0											-- Actual map width in columns (1 column = 32px), 0 by default
dungeon.height = 0											-- Actual map height in rows of (1 row = 32px), 0 by default
-- the dungeon map data
dungeon.map = {}											-- Table to hold the map data
dungeon.rooms = {}											-- Table to hold the map data
	
-- Maximum size of the map
local xmax = 70												-- Maximum map width in columns (1 column = 32px)
local ymax = 25												-- Maximum map height in rows of (1 row = 32px)


----------------------------------------
-- Setup dungeon generation variables
----------------------------------------

-- Number of "objects" to generate
local objects = 0
local rooms = 0
local hiddenRooms = 0
local chests = 0
local enemies = 0

-- Define the %chance to generate either a room or a corridor on the map
-- BTW, rooms are 1st priority so actually it's enough to just define the chance
-- of generating a room
local chanceRoom = 75										-- % chance for adding a room
local chanceCorridor = 20									-- % chance for adding a corridor
local chanceHidden = 5										-- % chance for adding a corridor

-- we will store the old random seed here
local oldseed = 0

--a list of tile types we're using
local tileUnused = 0
local tileDirtWall = 1										-- not in use
local tileDirtCorner = 2									-- not in use
local tileDirtFloor = 3
local tileStoneWall = 4
local tileStoneCorner = 5									-- not in use
local tileCorridor = 6
local tileDoor = 7
local tileUpStairs = 8
local tileDownStairs = 9
local tileChest = 10

-- Nim/max room sizes
local roomMin = 4
local romMax = 20

-- misc. messages to print
local msgXSize = "X size of dungeon: "
local msgYSize = "Y size of dungeon: "
local msgMaxObjects = "max # of objects: "
local msgNumObjects = "# of objects made: "
local msgHelp = ""
local msgDetailedHelp = ""

local dunGenFinished = false

-- #############################################################################
-- PRIVATE FUNCTIONS
-- #############################################################################

-- setting a tile's type
local function setCell(x, y, cellType)
	dungeon.map[x + dungeon.width * y] = cellType
end

-- returns the type of a tile
local function getCell(x, y)
	-- print("cell value: " .. dungeon.map[x + dungeon.width * y])
	return dungeon.map[x + dungeon.width * y]
end

-- The RNG. the seed is based on seconds from the OS date/time
local function getRand(min, max)
	-- the seed is based on current date/time and the old, already used seed
	-- local now = os.time()
	local r1 = math.random(1500, 3000)
	local r2 = math.random(10)
	-- print("os.time is: " .. now)
	-- print("Oldseed is: " .. oldseed)
	-- local seed = now + oldseed
	local seed = math.floor(r1 / r2)
	-- print("seed is: " .. seed)
	oldseed = seed
	
	math.randomseed(seed)
	-- math.randomseed( os.time() )

	local rand = math.random(min, max)
	-- print("rand is: " .. rand)

	if (rand < 0) then
		rand = -rand
	end

	-- utils.dbprint("rand: " .. rand)
	return rand
end

--- showDungeon: Displays grid in the console
-- Used to print the map on the console
-- 
local function showDungeon() 
	-- print("showDungeon called")

	print(" ")
	local decRow = "             1         2         3         4         5         6         7"
	print(decRow)
	local topRow = "top 1234567890123456789012345678901234567890123456789012345678901234567890"
	print(topRow)

	local mapRow

	for y = 1, dungeon.height do

		if y < 10 then
			mapRow = "0" .. y .. "| "
		else
			mapRow = y .. "| "
		end

		for x = 1, dungeon.width do
			-- System.out.print(getCell(x, y));
			local cell = getCell(x, y)

			if cell == tileUnused then
				mapRow = mapRow .. " "						-- empty cell, change to '%' to see the cell
			elseif cell == tileDirtWall then
				mapRow = mapRow .. "#"
			elseif cell == tileDirtCorner then
				mapRow = mapRow .. "&"
			elseif cell == tileDirtFloor then
				mapRow = mapRow .. "."
			elseif cell == tileStoneWall then
				mapRow = mapRow .. "N"
			elseif cell == tileCorridor then
				mapRow = mapRow .. ","
			elseif cell == tileDoor then
				mapRow = mapRow .. "D"
			elseif cell == tileUpStairs then
				mapRow = mapRow .. "<"
			elseif cell == tileDownStairs then
				mapRow = mapRow .. ">"
			elseif cell == tileChest then
				mapRow = mapRow .. "*"
			end
			
			x = x + 1
		end

		if (dungeon.width <= xmax) then
			print(mapRow)
		end

		y = y + 1
	end
end

--- makeRoom
-- Builds a room based on based on a set of parameters. It checks to see if
-- there is enough space, if there is it then builds the room
--
-- @param x The starting x position
-- @param y The starting y position
-- @param xlength The width if the room
-- @param ylength The heigth of the room
-- @param direction The direction to build in
--
local function makeRoom(x, y, xlength, ylength, direction)
	utils.dbprint("\nStart room building")
	-- define the dimensions of the room, it should be at least 4x4 tiles (2x2 
	-- for walking on, the rest is walls)

	-- saves room data to roomLib table
	function createRoomData(room)
		dungeon.rooms[room] = {} 							-- 
		dungeon.rooms[room].xStart = xStart 				-- 
		dungeon.rooms[room].yStart = yStart 				-- 
		dungeon.rooms[room].xEnd = xEnd 					-- 
		dungeon.rooms[room].yEnd = yEnd 					-- 
		dungeon.rooms[room].width = roomWidth 				-- 
		dungeon.rooms[room].height = roomHeight 			-- 
		-- wall cell Coordinates
		dungeon.rooms[room].wallCoords = {
			{},												-- north
			{},												-- east
			{},												-- south
			{}												-- west
		}
		dungeon.rooms[room].doors = {0,0,0,0} 				-- doors(north,east,south,west)
		dungeon.rooms[room].chests = 0 						-- number of chests in the room
	end
	-- debug print room data
	-- utils.dbprint("Room data test [x: " .. roomLib[roomLibLen].xStart .. ", y: " .. roomLib[roomLibLen].yStart .. ", width: " .. roomLib[roomLibLen].width .. ", height: " .. roomLib[roomLibLen].height .. "]")

	local roomNum = #dungeon.rooms
	-- Detrmine position in roomLib then call saveRoomData
	if roomNum == nil then
		roomNum = 1
		createRoomData(roomNum)
	else
		roomNum = roomNum+1
		createRoomData(roomNum)
	end
	utils.dbprint("no. of rooms: " .. roomNum)
	
	local room = dungeon.rooms[roomNum]

	room.width = getRand(roomMin, xlength)					-- the width of the room
	room.height = getRand(roomMin, ylength)					-- the height of the room
	-- utils.dbprint("Map center: " .. math.floor(x) .. " X " .. math.floor(y))
	-- utils.dbprint("Room size: " .. room.width .. "X" .. room.height)

	local xtemp 											-- the current x position to check
	local ytemp 											-- the current y position to check

	--the tile type it's going to be filled with
	local floor = tileDirtFloor
	local wall = tileDirtWall
	local corner = tileDirtCorner

	-- choose the way it's pointing at
	local dir = 0 											-- 1,2,3,4 (north,east,south,west)

	if direction > 1 or direction < 5 then
		dir = direction
	end

	-- dir = 2

	if dir == 1 then		-- Build north

		room.xStart = math.floor(x - (room.width / 2))
		room.yStart = math.floor(y)
		room.xEnd = math.floor(room.xStart + room.width - 1)
		room.yEnd = math.floor(y - room.height + 1)
		xtemp = room.xStart
		ytemp = room.yStart

		-- Check if there is enough space for the room to the north
		-- utils.dbprint("Start north space check loops")
		for i = 1, room.height do
			-- utils.dbprint("ytemp: "..ytemp)
			if ytemp < 1 or ytemp > dungeon.height then
				-- utils.dbprint("Room hits left or right walls")
				return false 								-- if ytemp is the start or end wall, stop. 
			end
			for j = 1, room.width do
				-- utils.dbprint("xtemp: "..xtemp)
				if xtemp <= 1 or xtemp >= dungeon.width then 
					-- utils.dbprint("Room hits top or bottom walls")
					return false 							-- if xtemp is the start or end wall, stop.
				end 
				if getCell(xtemp, ytemp) ~= tileUnused then 
					-- utils.dbprint("Room hits a filled cell")
					return false 							-- if cell is not emptey, stop.
				end 
				xtemp = xtemp + 1
				j = j + 1
			end
			xtemp = room.xStart
			ytemp = ytemp - 1
			i = i + 1
		end
		-- utils.dbprint("End north space check loops")
 		
		-- we're still here, build
		-- utils.dbprint("Start build loops")
		xtemp = room.xStart
		ytemp = room.yStart

		for i = 1, room.height do
			-- utils.dbprint("ytemp: ".. ytemp.." yEnd:"..room.yEnd)
			for j = 1, room.width do
				-- start with the walls
				if xtemp == room.xStart then 									-- Build first wall
					if ytemp == room.yStart then
						-- print("build first corner")
						setCell(xtemp, ytemp, corner)							-- Build first corner
					elseif ytemp == room.yEnd then								
						-- print("build first corner")
						setCell(xtemp, ytemp, corner) 							-- Build third corner
					else 
						setCell(xtemp, ytemp, wall)
					end
				elseif xtemp == room.xEnd then 									-- Build south wall
					if ytemp == room.yStart then								
						-- print("build second corner")
						setCell(xtemp, ytemp, corner)							-- Build second corner
					elseif ytemp == room.yEnd then								
						-- print("build second corner")
						setCell(xtemp, ytemp, corner)							-- Build fourth corner
					else 
						setCell(xtemp, ytemp, wall)
					end 
				elseif ytemp == room.yStart then 
					setCell(xtemp, ytemp, wall)
				elseif ytemp == room.yEnd then 
					setCell(xtemp, ytemp, wall)
				else -- and then fill with the floor
					setCell(xtemp, ytemp, floor) 
				end
				xtemp = xtemp + 1
				j = j + 1
			end
			xtemp = room.xStart
			ytemp = ytemp - 1
			i = i + 1
		end
		-- utils.dbprint("End build loops")
		
	elseif dir == 2 then -- Build east
		
		room.xStart = math.floor(x)
		room.yStart = math.floor(y - (room.height/2))
		room.xEnd = math.floor(room.xStart + room.width - 1)
		room.yEnd = math.floor(room.yStart + room.height - 1)
		xtemp = room.xStart
		ytemp = room.yStart
		
		-- Check if there is enough space for the room to the east
		-- utils.dbprint("Start east space check loops")
		for i = 1, room.height do
			-- utils.dbprint("ytemp: "..ytemp)
			if ytemp < 1 or ytemp > dungeon.height then
				-- utils.dbprint("Room hits left or right walls")
				return false 								-- if ytemp is the start or end wall, stop. 
			end
			for j = 1, room.width do
				-- utils.dbprint("xtemp: "..xtemp)
				if xtemp <= 1 or xtemp >= dungeon.width then 
					-- utils.dbprint("Room hits top or bottom walls")
					return false 							-- if xtemp is the start or end wall, stop.
				end 
				if getCell(xtemp, ytemp) ~= tileUnused then 
					-- utils.dbprint("Room hits a filled cell")
					return false 							-- if cell is not emptey, stop.
				end 
				xtemp = xtemp + 1
				j = j + 1
			end
			xtemp = room.xStart
			ytemp = ytemp + 1
			i = i + 1
		end
		-- utils.dbprint("End space check loops")
 		
		-- we're still here, build
		-- utils.dbprint("Start build loops")
		xtemp = room.xStart
		ytemp = room.yStart

		for i = 1, room.height do
			-- utils.dbprint("ytemp: ".. ytemp.." yEnd:"..room.yEnd)
			for j = 1, room.width do
				-- start with the walls
				if xtemp == room.xStart then 									-- Build first wall
					if ytemp == room.yStart then
						-- print("build first corner")
						setCell(xtemp, ytemp, corner)							-- Build first corner
					elseif ytemp == room.yEnd then								
						-- print("build first corner")
						setCell(xtemp, ytemp, corner) 							-- Build third corner
					else 
						setCell(xtemp, ytemp, wall)
					end
				elseif xtemp == room.xEnd then 									-- Build south wall
					if ytemp == room.yStart then								
						-- print("build second corner")
						setCell(xtemp, ytemp, corner)							-- Build second corner
					elseif ytemp == room.yEnd then								
						-- print("build second corner")
						setCell(xtemp, ytemp, corner)							-- Build fourth corner
					else 
						setCell(xtemp, ytemp, wall)
					end 
				elseif ytemp == room.yStart then 
					setCell(xtemp, ytemp, wall)
				elseif ytemp == room.yEnd then 
					setCell(xtemp, ytemp, wall)
				else -- and then fill with the floor
					setCell(xtemp, ytemp, floor) 
				end
				xtemp = xtemp + 1
				j = j + 1
			end
			xtemp = room.xStart
			ytemp = ytemp + 1
			i = i + 1
		end
		-- utils.dbprint("End build loops")
		
	elseif dir == 3 then -- Build south

		room.xStart = math.floor(x - (room.width / 2))
		room.yStart = math.floor(y)
		room.xEnd = math.floor((room.xStart + room.width) - 1)
		room.yEnd = math.floor(y + room.height - 1)
		xtemp = room.xStart
		ytemp = room.yStart
		
		-- Check if there is enough space for the room to the south
		-- utils.dbprint("Start south space check loops")
		for i = 1, room.height do
			-- utils.dbprint("ytemp: "..ytemp)
			if ytemp < 1 or ytemp > dungeon.height then
				-- utils.dbprint("Room hits left or right walls")
				return false 								-- if ytemp is the start or end wall, stop. 
			end
			for j = 1, room.width do
				-- utils.dbprint("xtemp: "..xtemp)
				if xtemp <= 1 or xtemp >= dungeon.width then 
					-- utils.dbprint("Room hits top or bottom walls")
					return false 							-- if xtemp is the start or end wall, stop.
				end 
				if getCell(xtemp, ytemp) ~= tileUnused then 
					-- utils.dbprint("Room hits a filled cell")
					return false 							-- if cell is not emptey, stop.
				end 
				xtemp = xtemp + 1
				j = j + 1
			end
			xtemp = room.xStart
			ytemp = ytemp - 1
			i = i + 1
		end
		-- utils.dbprint("End space check loops")
 		
		-- we're still here, build
		-- utils.dbprint("Start build loops")
		xtemp = room.xStart
		ytemp = room.yStart

		for i = 1, room.height do
			-- utils.dbprint("ytemp: ".. ytemp.." yEnd:"..room.yEnd)
			for j = 1, room.width do
				-- start with the walls
				if xtemp == room.xStart then 									-- Build first wall
					if ytemp == room.yStart then
						-- print("build first corner")
						setCell(xtemp, ytemp, corner)							-- Build first corner
					elseif ytemp == room.yEnd then								
						-- print("build first corner")
						setCell(xtemp, ytemp, corner) 							-- Build third corner
					else 
						setCell(xtemp, ytemp, wall)
					end
				elseif xtemp == room.xEnd then 									-- Build south wall
					if ytemp == room.yStart then								
						-- print("build second corner")
						setCell(xtemp, ytemp, corner)							-- Build second corner
					elseif ytemp == room.yEnd then								
						-- print("build second corner")
						setCell(xtemp, ytemp, corner)							-- Build fourth corner
					else 
						setCell(xtemp, ytemp, wall)
					end 
				elseif ytemp == room.yStart then 
					setCell(xtemp, ytemp, wall)
				elseif ytemp == room.yEnd then 
					setCell(xtemp, ytemp, wall)
				else -- and then fill with the floor
					setCell(xtemp, ytemp, floor) 
				end
				xtemp = xtemp + 1
				j = j + 1
			end
			xtemp = room.xStart
			ytemp = ytemp + 1
			i = i + 1
		end
		-- utils.dbprint("End build south loops")
		
	elseif dir == 4 then 	-- Build west

		room.xStart = math.floor(x)
		room.yStart = math.floor(y - (room.height / 2))
		room.xEnd = math.floor(x - room.width + 1)
		room.yEnd = math.floor(room.yStart + room.height - 1)
		xtemp = room.xStart
		ytemp = room.yStart
		
		-- Check if there is enough space for the room to the east
		-- utils.dbprint("Start east space check loops")
		for i = 1, room.height do
			-- utils.dbprint("ytemp: "..ytemp)
			if ytemp < 1 or ytemp > dungeon.height then
				-- utils.dbprint("Room hits left or right walls")
				return false 								-- if ytemp is the start or end wall, stop. 
			end
			for j = 1, room.width do
				-- utils.dbprint("xtemp: "..xtemp)
				if xtemp <= 1 or xtemp >= dungeon.width then 
					-- utils.dbprint("Room hits top or bottom walls")
					return false 							-- if xtemp is the start or end wall, stop.
				end 
				if getCell(xtemp, ytemp) ~= tileUnused then 
					-- utils.dbprint("Room hits a filled cell")
					return false 							-- if cell is not emptey, stop.
				end 
				xtemp = xtemp - 1
				j = j + 1
			end
			xtemp = room.xStart
			ytemp = ytemp + 1
			i = i + 1
		end
		-- utils.dbprint("End space check loops")
 		
		-- we're still here, build
		-- utils.dbprint("Start build loops")
		xtemp =room.xStart
		ytemp = room.yStart

		for i = 1, room.height do
			-- utils.dbprint("ytemp: ".. ytemp.." yEnd:"..room.yEnd)
			for j = 1, room.width do
				-- start with the walls
				if xtemp == room.xStart then 									-- Build first wall
					if ytemp == room.yStart then
						-- print("build first corner")
						setCell(xtemp, ytemp, corner)							-- Build first corner
					elseif ytemp == room.yEnd then								
						-- print("build first corner")
						setCell(xtemp, ytemp, corner) 							-- Build third corner
					else 
						setCell(xtemp, ytemp, wall)
					end
				elseif xtemp == room.xEnd then 									-- Build south wall
					if ytemp == room.yStart then								
						-- print("build second corner")
						setCell(xtemp, ytemp, corner)							-- Build second corner
					elseif ytemp == room.yEnd then								
						-- print("build second corner")
						setCell(xtemp, ytemp, corner)							-- Build fourth corner
					else 
						setCell(xtemp, ytemp, wall)
					end 
				elseif ytemp == room.yStart then 
					setCell(xtemp, ytemp, wall)
				elseif ytemp == room.yEnd then 
					setCell(xtemp, ytemp, wall)
				else -- and then fill with the floor
					setCell(xtemp, ytemp, floor) 
				end
				xtemp = xtemp - 1
				j = j + 1
			end
			xtemp = room.xStart
			ytemp = ytemp + 1
			i = i + 1
		end
		-- utils.dbprint("End build south loops")
	end

	utils.dbprint("Built a "..room.width.."x"..room.height.." room, dir: " .. dir .. ", coords: x" .. room.xStart  .. ", y" .. room.yStart .. " / x" .. room.xEnd .. ", y" .. room.yEnd )
	
	-- utils.dbprint("End all build loops")

	-- yay, all done
	return true
end




-- #############################################################################
-- PUBLIC FUNCTIONS
-- #############################################################################

-- dungeon.createDungeon(maxWidth, maxHeight, numRooms, numChests, numHiddenRooms, "algorithum")
function dungeon.createDungeon( intx, inty, numRooms, numChests, numHiddenRooms, algorithum )

	-- utils.dbprint("dunGen.createDungeon called")

	-- Check initial values for createDungeon parameters
	-- Check dungeon width parameter, if no value asign a min value
	if intx == nil then
		dungeon.width = 3
	elseif intx < 3 then 
		dungeon.width = 3
	elseif intx > xmax then 
		dungeon.width = xmax
	else 
		dungeon.width = intx 
	end
	-- Check dungeon height parameter, if no value asign a min value
	if inty == nil then
		dungeon.height = 3
	elseif inty < 3 then 
		dungeon.height = 3
	elseif inty > ymax then 
		dungeon.height = ymax
	else 
		dungeon.height = inty 
	end
	-- Check dungeon room count parameter, if no value asign a min value
	if numRooms == nil then
		rooms = 4
	elseif numRooms < 1 then 
		rooms = 4
	else
		rooms = numRooms
	end
	-- Check dungeon chest number parameter, if no value asign a min value
	if numChests == nil then
		chests = 10
	elseif numChests < 1 then 
		chests = 10
	else
		chests = numChests
	end
	-- Check dungeon hidden room parameter, if no value asign a min value
	if numHiddenRooms == nil then
		hiddenRooms = getRand(0,1)
	-- elseif numHiddenRooms < 1 then 
	-- 	hiddenRooms = getRand(0,1)
	else
		hiddenRooms = getRand(0,1)
	end

	enemies = getRand(1,10)

	utils.dbprint("Dungeon size is " .. dungeon.width .. "x" .. dungeon.height)
	-- utils.dbprint(msgMaxObjects .. rooms)
	-- utils.dbprint("Number of rooms: " .. rooms)
	-- utils.dbprint("Number of hidden rooms: " .. hiddenRooms)
	-- utils.dbprint("Number of chests: " .. chests)
	-- utils.dbprint("Number of enemies: " .. enemies)


	-- redefine the map var, so it's adjusted to our new map size
	-- for y=1, dungeon.height do
	-- 	for x=1,dungeon.width do
	-- 		dungeon.map[x + dungeon.width * y] = 0	-- [x + dungeon.width * y]
	-- 		x = x + 1
	-- 	end
	-- 	y = y + 1
	-- end

	-- print("Fill map table with default data")
	for y = 1, dungeon.height do
		-- print("y loop iteration: " .. y)
		for x = 1, dungeon.width do
			-- print("x loop iteration: " .. x)
			-- ie, making the borders of unwalkable walls
			if y == 1 then setCell(x, y, tileStoneWall)
			elseif y == dungeon.height then setCell(x, y, tileStoneWall)
			elseif x == 1 then setCell(x, y, tileStoneWall)
			elseif x == dungeon.width then setCell(x, y, tileStoneWall)
			-- and fill the rest with dirt
			else setCell(x, y, tileUnused) end

			x = x + 1
		end

		y = y + 1
	end

	--*******************************************************************************
	-- And now the code of the random-map-generation-algorithm begins!
	--*******************************************************************************/

	-- start with making a room in the middle, which we can start building upon
	-- makeRoom(startx, starty, width, height, direction)
	makeRoom(dungeon.width/2, dungeon.height/2, 6, 6, getRand(1,4))

	-- keep count of the number of "objects" we've made
	local currentRooms = 1; 			-- +1 for the first room we just made
	local roomPick = 0 					-- The room picked to dig from
	local roomsChecked = {} 			-- 

	--[[
	-- then we sart the main loop
	local countingTries = 0
	local testing = 0




	for countingTries = 0, 1000 do 	-- 0, 1000
		print("countingTries: " .. countingTries)

		-- check if we've reached our room quota
		if currentRooms == numRooms then
			break
		end

		-- start with a random wall
		local newx = 0  
		local newy = 0 
		local xmod = 0 
		local ymod = 0 
		local validTile = -1
		-- print("validTile is:" .. validTile)


		-- Try to find a suitable object (room or corridor)..
		-- (yea, i know it's kinda ugly with a for-loop... -_-')
		for testing = 1, 1000 do 	-- 0, 1000
			-- print("testing: " .. testing)

			-- Pick a random spot on the map
			newx = getRand(2, dungeon.width-1) 	-- randomly picked x pos
			newy = getRand(2, dungeon.width-1) 	-- randomly picked y pos
			-- print("newx: " .. newx .. " newy: " .. newy)
			validTile = -1 				-- Set validTile to -1 (invalid)

			-- If the randomly picked tile is wall or corridor
			if getCell(newx, newy) == tileDirtWall or getCell(newx, newy) == tileCorridor then
				-- check if we can reach the place
				if getCell(newx, newy+1) == tileDirtFloor or getCell(newx, newy+1) == tileCorridor then
					validTile = 0 		-- tile is to north
					xmod = 0 			-- x modifier does not change
					ymod = -1 			-- y modifier changes to 1 row above
					-- utils.dbprint("validTile is: " .. validTile)
				elseif getCell(newx-1, newy) == tileDirtFloor or getCell(newx-1, newy) == tileCorridor then
					validTile = 1 		-- tile is to east
					xmod = 1 			-- x modifier changes to 1 to the right
					ymod = 0 			-- y modifier does not change
					-- utils.dbprint("validTile is: " .. validTile)
				elseif getCell(newx, newy-1) == tileDirtFloor or getCell(newx, newy-1) == tileCorridor then
					validTile = 2 		-- tile is to the south
					xmod = 0 			-- x modifier does not change
					ymod = 1 			-- y modifier changes to 1 row bellow
					-- utils.dbprint("validTile is: " .. validTile)
				elseif getCell(newx+1, newy) == tileDirtFloor or getCell(newx+1, newy) == tileCorridor then
					validTile = 3 		-- tile is to the west
					xmod = -1 			-- x modifier changes to 1 to the left
					ymod = 0 			-- y modifier does not change
					-- utils.dbprint("validTile is: " .. validTile)
				end

				-- check that we haven't got another door nearby, so we won't get alot of openings besides
				-- each other
				if validTile > -1 then
					if getCell(newx, newy+1) == tileDoor then 		-- check north
						validTile = -1
					elseif getCell(newx-1, newy) == tileDoor then 	-- check east
						validTile = -1
					elseif getCell(newx, newy-1) == tileDoor then	-- check south
						validTile = -1
					elseif getCell(newx+1, newy) == tileDoor then	-- check west
						validTile = -1
					end
				end

				-- if we can, jump out of the loop and continue with the rest
				if validTile > -1 then
					break
				end
			end

			testing = testing + 1
		end -- end for testing loop

		-- If we found a tile/directon to build then...
		if validTile > -1 then
			-- choose what to build now at our newly found place, and at what direction
			local feature = math.random(0, 100)
			-- utils.dbprint("Feature is: " .. feature)

			if feature <= chanceRoom then -- a new room
				-- utils.dbprint("Make room")
				-- makeRoom(x, y, xlength, ylength, direction)
				if makeRoom((newx+xmod), (newy+ymod), roomMax, roomMax, validTile) then
					currentRooms = currentRooms + 1 -- add to our quota

					-- then we mark the wall opening with a door
					setCell(newx, newy, tileDoor)

					-- clean up infront of the door so we can reach it
					setCell((newx+xmod), (newy+ymod), tileDirtFloor)
				end
			elseif feature > chanceRoom then -- new corridor
				-- utils.dbprint("Make corridor")
				if makeCorridor((newx+xmod), (newy+ymod), 6, validTile) then
					-- same thing here, add to the quota and a door
					currentFeatures = currentFeatures + 1

					setCell(newx, newy, tileDoor)
				end
			end
		end

		countingTries = countingTries + 1
	end









	]]

	dunGenFinished = true

	if dunGenFinished == true then
		showDungeon()
		-- utils.tprint(dungeon.map)
	end

end

	

-- 
return dungeon
