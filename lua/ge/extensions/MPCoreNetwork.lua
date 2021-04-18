--====================================================================================
-- All work by Titch2000, jojos38 & 20dka.
-- You have no permission to edit, redistribute or upload. Contact BeamMP for more info!
--====================================================================================



local M = {}
print("Loading MPCoreNetwork...")



-- ============= VARIABLES =============
local l = "CoreNetwork"
local TCPLauncherSocket -- Launcher socket

local currentServer = {} -- Store the server we are on
local currentMap = ""

local launcherConnectionStatus = 0 -- Status: 0 not connected | 1 connecting or connected
local launcherConnectionTimer = 0
local status = ""
local launcherVersion
local loggedIn = false
local mapLoaded = false
local isMultiplayer = 0
local launcherTimeout = 0
local connectionFailed = false
local packetReceivedYet = false
local socket = require('socket')
local downloading = false
local reconnectAttempt = 1
--[[
Z  -> The client asks the launcher its version
B  -> The client asks the launcher for the servers list
QG -> The client tells the launcher that it's is leaving
C  -> The client asks for the server's mods
--]]
function string.starts(fullString, start)
   return string.sub(fullString, 1, string.len(start)) == start
end
-- ============= VARIABLES =============




-- ============= LAUNCHER RELATED =============
local function send(s)
	if not TCPLauncherSocket then return end
	local r = TCPLauncherSocket:send(string.len(s)..'>'..s)
	-- if settings.getValue("showDebugOutput") then
		log('M', l, '[MPCoreNetwork] Sending Data ('..r..'): '..s)
	-- end
end

local function connectToLauncher()
	if launcherConnectionStatus == 0 then -- If launcher is not connected yet
		log('M', l, "Connecting to launcher")
		TCPLauncherSocket = socket.tcp()
		TCPLauncherSocket:setoption("keepalive", true) -- Keepalive to avoid connection closing too quickly
		TCPLauncherSocket:settimeout(0) -- Set timeout to 0 to avoid freezing
		TCPLauncherSocket:connect('127.0.0.1', (settings.getValue("launcherPort") or 4444));
		launcherConnectionStatus = 1
	end
end

local function disconnectLauncher(reconnect)
	if launcherConnectionStatus > 0 then -- If player was connected
		log('M', l, "Disconnecting from launcher")
		TCPLauncherSocket:close()-- Disconnect from server
		launcherConnectionStatus = 0
		launcherConnectionTimer = 0
		isGoingMpSession = false
	end
	if reconnect then connectToLauncher() end
end

local function onLauncherConnectionFailed()
	--[[ disconnectLauncher()
	MPModManager.restoreLoadedMods() -- Attempt to restore the mods before deleting BeamMP
	local modsList = core_modmanager.getModList()
	local beammpMod = modsList["beammp"] or modsList["multiplayerbeammp"]
	if (beammpMod) then
		if beammpMod.active and not beammpMod.unpackedPath then
			core_modmanager.deleteMod(beammpMod.modname)
			Lua:requestReload()
		end
	end --]]
end

-- This is called everytime we receive a heartbeat from the launcher
local function checkLauncherConnection()
	launcherConnectionTimer = 0
	if launcherConnectionStatus ~= 2 then
		launcherConnectionStatus = 2
		guihooks.trigger('launcherConnected', nil)
		-- Get the launcher version
		send('Z')
		-- Log-in
		send('Nc')
	end
end
-- ============= LAUNCHER RELATED =============



-- ============= SERVER RELATED =============
local function backupCurrentServer(server)
	-- Backup the current server
	jsonWriteFile("settings/last-server.json", server, true)
	print("Backed up current server")
end

-- Tell the launcher to open the connection to the server so the MPMPGameNetwork can connect to the launcher once ready
local function connectToServer(ip, port, server)
	-- Disconnect from an existing server connection
	if isMultiplayer > 0 then
		MPGameNetwork.disconnectLauncher() -- Reset connection
	end
	isMultiplayer = 1 -- Connecting

	-- Check if ip or port isn't empty
	if not ip or not port then
		log('M', l, "The ip or the port is empty, can't connect")
		if UI.updateLoading then UI.updateLoading("lThe ip or the port is empty, can't connect") end
		return
	end

	if server then
		currentServer = server
	else
		currentServer = {ip = ip, port = port}
	end
	core_modmanager.disableAutoMount()
	local ipString = ip..':'..port
	send('C'..ipString) -- Connection packet
	downloading = true -- The mods will start downloading
	log('M', l, "Connecting to server "..ipString)
	backupCurrentServer({ip, port})
end

local function restoreServerConnection()
	if getMissionFilename() ~= "" then
		local server = jsonReadFile("settings/last-server.json")
		os.remove("settings/last-server.json")
		if server then
			log('M', 'restoreServerConnection', "Restoring connection to server")
			connectToServer(server[1], server[2])
		end
	end
end

local function modsReady()
	log('M', l, "Mods downloaded, loading them...")
	core_modmanager.initDB()
	send('R')
end

local function loadLevel(map)
	log('M', l, "Mods loaded successfully")
	currentMap = map
	if getMissionFilename() == map then
		MPCoreNetwork.onClientStartMission(map)
		return
	end
	if not core_levels.expandMissionFileName(map) then
		UI.updateLoading("lMap "..map.." not found")
		MPCoreNetwork.resetSession(false)
		return
	end
	freeroam_freeroam.startFreeroam(map)
end
-- ============= SERVER RELATED =============



-- ============= OTHERS =============
local function handleU(params)
	UI.updateLoading(params)
	local code = string.sub(params, 1, 1)
	local data = string.sub(params, 2)
	if params == "lDone" then
		send('M')
		downloading = false
	elseif params == "lModsReady" then
		modsReady()
	elseif params == "lConnection Failed!" then
		if reconnectAttempt > 10 then
			os.remove("settings/last-server.json")
			MPCoreNetwork.resetSession()
			UI.showNotification("You are now back in singleplayer")
			reconnectAttempt = 1
		end
		UI.showNotification("Reconnection failed, retrying... ("..reconnectAttempt.."/10)")
		restoreServerConnection()
		reconnectAttempt = reconnectAttempt + 1
	elseif string.starts(params, "lDisconnected") then
		MPCoreNetwork.resetSession()
	end
	if code == "p" then
		UI.setPing(data.."")
		positionGE.setPing(data)
	end
end

local function loginReceived(params)
	log('M', l, 'Logging result received')
	local result = jsonDecode(params)
	if (result.success == true or result.Auth == 1) then
		log('M', l, 'Logged successfully')
		loggedIn = true
		guihooks.trigger('LoggedIn', result.message or '')
		-- If the user was connected to a server, reconnect him
		restoreServerConnection()
	else
		log('M', l, 'Logging credentials incorrect')
		loggedIn = false
		guihooks.trigger('LoginError', result.message or '')
	end
end

local function resetSession(reconnect)
	isMultiplayer = 0
	print("Reset Session Called!")
	send('QS') -- Tell the launcher that we quit server / session
	disconnectLauncher()
	MPGameNetwork.disconnectLauncher()
	MPVehicleGE.onDisconnect()
	connectToLauncher()
	status = "" -- Reset status
	if reconnect then
		print(currentServer)
		connectToServer(currentServer.ip, currentServer.port)
	end
	MPModManager.cleanUpSessionMods()
end

local function isMP()
	return isMultiplayer
end

-- This is called by UI and lua
local function quitMP(reason)
	isMultiplayer = 0
	print("Quit MP Called!")
	print("reason: "..tostring(reason))
	send('QG') -- Quit game
end
-- ============= OTHERS =============



local HandleNetwork = {
	['A'] = function(params) checkLauncherConnection() end, -- Connection Alive Checking
	['B'] = function(params) guihooks.trigger('onServersReceived', params) end, -- Serverlist received
	['U'] = function(params) handleU(params) end, -- UI
	['M'] = function(params) loadLevel(params) end,
	['N'] = function(params) loginReceived(params) end, -- Login system
	['V'] = function(params) MPVehicleGE.handle(params) end, -- Vehicle spawn/edit/reset/remove/coupler related event
	['L'] = function(params) MPModManager.setMods(params) end,
	['K'] = function(params) quitMP(params) end, -- Player Kicked Event
	['Z'] = function(params) launcherVersion = params end -- Tell the UI what the launcher version is
}



-- ====================================== EVENTS ======================================
local function onMPStatusChanged(status)
	if status == 0 then
		core_gamestate.setGameState('freeroam', 'freeroam', 'freeroam')
	else
		core_gamestate.setGameState('multiplayer', 'multiplayer', 'multiplayer')
	end
end

local lastIsMultiplayer = -1
local function onUpdate(dt)
	if launcherConnectionStatus > 0 then -- If player is connecting or connected
		-- Receive network packets
		while (true) do
			local received, stat, partial = TCPLauncherSocket:receive()
			if not received or received == "" then break end
			if string.len(received) < 250 then print("Core: "..received) end
			local code = string.sub(received, 1, 1)
			local data = string.sub(received, 2)
			HandleNetwork[code](data)
		end

		-- Heartbeat the launcher
		launcherConnectionTimer = launcherConnectionTimer + dt -- Time in seconds
		if launcherConnectionTimer > 0.5 then
			send('A') -- Launcher heartbeat
			 -- Server heartbeat
			if downloading then send('Ul') -- Ask the launcher for a loading screen update
			else send('Up') end -- Server heartbeat
		end
		
		-- Check the launcher connection
		if launcherConnectionTimer > 2 then
			log('M', l, "Connection to launcher was lost")
			guihooks.trigger('LauncherConnectionLost')
			resetSession()
			launcherConnectionTimer = 0
		end
	end

	if lastIsMultiplayer ~= isMultiplayer then
		onMPStatusChanged(isMultiplayer)
		lastIsMultiplayer = isMultiplayer
	end
end

local function onClientStartMission(mission)
	if isMP() == 2 and currentMap ~= getMissionFilename() then
		print("The user has loaded another mission!")
		Lua:requestReload()
	elseif isMP() == 1 and currentMap == getMissionFilename() then
		for i = 0, be:getObjectCount()-1 do be:getObject(i):delete() end -- Remove all vehicles
		MPGameNetwork.connectToLauncher()
		isMultiplayer = 2
		log('M', l, "Connected successfully to the server")
	end
end

local function onClientEndMission(mission)
	if isMP() then
		resetSession()
	end
end

local function onUiChangedState(to, from)
	if to == "menu.mainmenu" then
		
	end
end
-- ====================================== EVENTS ======================================



-- ================ UI ================
-- Called from multiplayer.js UI
local function getLauncherVersion()
	return launcherVersion
end
local function isLoggedIn()
	return loggedIn
end
local function isLauncherConnected()
	return launcherConnectionStatus == 2
end
local function login(identifiers)
	log('M', l, 'Attempting login')
	send('N:'..identifiers)
end
local function autoLogin()
	send('Nc')
end
local function logout()
	log('M', l, 'Attempting logout')
	send('N:LO')
	loggedIn = false
end
local function getServers()
	log('M', l, "Getting the servers list")
	send('B') -- Ask for the servers list
end
local function getCurrentServer()
	return currentServer
end
-- ================ UI ================



-- ====================================== ENTRY POINT ======================================
local function onExtensionLoaded()
	core_modmanager.enableAutoMount()
	
	--Preston (Cobalt) insert the custom multiplayer layout inside the game's layout file
	-- First check that the game's layout file exists
	local layouts = jsonReadFile("settings/uiapps-layouts.json")
	if not layouts then
		layouts = jsonReadFile("settings/uiapps-defaultLayout.json")
		jsonWriteFile("settings/uiapps-layouts.json", layouts)
		log("M", l, "default UI layout added")
	end
	-- Then check that multiplayer layout is inside
	if not layouts.multiplayer then
		layouts.multiplayer = jsonReadFile("settings/uiapps-defaultMultiplayerLayout.json")
		jsonWriteFile("settings/uiapps-layouts.json", layouts)
		log("M", l, "multiplayer UI layout added")
	end

	-- First we connect to the launcher
	connectToLauncher()
	-- We reload the UI to load our custom layout
	reloadUI()
end
-- ====================================== ENTRY POINT ======================================




M.getLauncherVersion   = getLauncherVersion
M.isLoggedIn 		   = isLoggedIn
M.isLauncherConnected  = isLauncherConnected
M.onExtensionLoaded    = onExtensionLoaded
M.onUpdate             = onUpdate
M.disconnectLauncher   = disconnectLauncher
M.autoLogin			   = autoLogin
M.onUiChangedState	   = onUiChangedState
M.onClientEndMission   = onClientEndMission
M.onClientStartMission = onClientStartMission
M.login                = login
M.logout               = logout
M.quitMP               = quitMP
M.modLoaded            = modLoaded
M.getServers           = getServers
M.isMP        = isMP
M.resetSession         = resetSession
M.connectToServer      = connectToServer
M.getCurrentServer     = getCurrentServer
M.setCurrentServer     = setCurrentServer
M.connectionStatus     = launcherConnectionStatus

print("MPCoreNetwork loaded")

return M
