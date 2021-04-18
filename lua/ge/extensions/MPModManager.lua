--====================================================================================
-- All work by Titch2000 and jojos38.
-- You have no permission to edit, redistribute or upload. Contact BeamMP for more info!
--====================================================================================



local M = {}
print("Loading MPModManager...")
local mods = {"beammp"}



function string.starts(fullString, start)
   return string.sub(fullString, 1, string.len(start)) == start
end



--[[ local function IsModAllowed(modname)
	for _, v in pairs(mods) do
		if v == modname then
			return true
		end
	end
	return false
end ]]



--[[ local function checkMod(mod)
	local modname = mod.modname
	local modAllowed = IsModAllowed(modname)
	if not modAllowed and mod.active then -- This mod is not allowed to be running
		print("This mod should not be running: "..modname)
		core_modmanager.deactivateMod(modname)
		if string.match(string.lower(modname), 'multiplayer') then
			core_modmanager.deleteMod(modname)
		end
	elseif modAllowed then
		if mod.active then -- this mod just got enabled for MP, run modscript
			local dir, basefilename, ext = path.splitWithoutExt(mod.fullpath)

			local modscriptpath = "/scripts/"..basefilename.."/modScript.lua"
			print(mod.filename)
			print("Loaded mod " .. basefilename)
			
			
			local f = io.open(modscriptpath, "r")
			if f == nil or not io.close(f) then return end
			
			local status, ret = pcall(dofile, modscriptpath)
			if not status then
				log('E', 'initDB.modScript', 'Failed to execute ' .. modscriptpath)
				log('E', 'initDB.modScript', dumps(ret))
			end

			loadCoreExtensions()
		else
			print("Inactive Mod but Should be Active: "..modname)
			core_modmanager.activateMod(modname)--'/mods/'..string.lower(v)..'.zip')
			MPCoreNetwork.modLoaded(modname)
		end
	end
end ]]



--[[ local function checkAllMods()
	for modname, mod in pairs(readJsonFile("/mods/db.json").mods) do
		print(modname)
		checkMod(mod)
		print("Checking mod "..mod.modname)
	end
end ]]



local function cleanUpSessionMods()
	log('M', "cleanUpSessionMods", "Deleting all multiplayer mods")
	local modsDB = jsonReadFile("mods/db.json")
	if modsDB then
		local modsFound = false
		for modname, mod in pairs(modsDB.mods) do
			if mod.dirname == "/mods/multiplayer/" and modname ~= "multiplayerbeammp" then
				core_modmanager.deleteMod(modname)
				modsFound = true
			end
		end
		if modsFound then Lua:requestReload() end -- reload Lua to make sure we don't have any leftover GE files
	end
end



local function backupLoadedMods()
	-- Backup the current mods before joining the server
	local modsDB = jsonReadFile("mods/db.json")
	if modsDB then
		os.remove("settings/db-backup.json")
		jsonWriteFile("settings/db-backup.json", modsDB, true)
		print("Backed up db.json file")
	else
		print("No db.json file found")
	end
end



local function restoreLoadedMods()
	-- Backup the current mods before joining the server
	local modsDBBackup = jsonReadFile("settings/db-backup.json")
	if modsDBBackup then
		os.remove("mods/db.json")
		jsonWriteFile("mods/db.json", modsDBBackup, true)
		-- And delete the backup file because we don't need it anymore
		os.remove("settings/db-backup.json")
		print("Restored db.json backup")
	else
		print("No db.json backup found")
	end
end



-- Called from beammp\lua\ge\extensions\core
--[[ local function onFileChanged(file)
	if file == "/mods/db.json" then -- and MPCoreNetwork.isMP() == 2 then
		checkAllMods()
	end
end ]]



--[[ local function onClientStartMission(mission)
	if MPCoreNetwork.isMP() == 2 then
		checkAllMods() -- Checking all the mods
	end
	-- Checking all the mods again because BeamNG.drive have a bug with mods not deactivating
end ]]



local function setMods(modsString)
	log('M', "setMods", "Mods string received "..modsString)
	if (modsString) then
		for mod in string.gmatch(modsString, "([^;]+)") do
			local modFileName = string.lower(mod:gsub("Resources/Client/",""):gsub(".zip",""):gsub(";",""))
			table.insert(mods, modFileName)
		end
	end
end



local function onInit()
	cleanUpSessionMods()
	print("MPModManager loaded")
end



--[[ Called when the user exits the game ]]
local function onExit()
	restoreLoadedMods() -- Restore the mods and delete db-backup.json when we quit the game
	-- Don't add isMPSession checking because onClientEndMission is called before!
end



M.setMods = setMods
M.onFileChanged = onFileChanged
M.backupLoadedMods = backupLoadedMods
M.restoreLoadedMods = restoreLoadedMods
M.cleanUpSessionMods = cleanUpSessionMods
M.setServerMods = setServerMods
M.onExit = onExit
M.onInit = onInit



return M
