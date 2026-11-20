local run = function(func)
	func()
end
local cloneref = cloneref or function(obj)
	return obj
end
local vapeEvents = setmetatable({}, {
	__index = function(self, index)
		self[index] = Instance.new('BindableEvent')
		return self[index]
	end
})

local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local runService = cloneref(game:GetService('RunService'))
local inputService = cloneref(game:GetService('UserInputService'))
local tweenService = cloneref(game:GetService('TweenService'))
local httpService = cloneref(game:GetService('HttpService'))
local collectionService = cloneref(game:GetService('CollectionService'))
local guiService = cloneref(game:GetService('GuiService'))
local coreGui = cloneref(game:GetService('CoreGui'))

local isnetworkowner = identifyexecutor and table.find({'AWP', 'Nihon'}, ({identifyexecutor()})[1]) and isnetworkowner or function()
	return true
end
local gameCamera = workspace.CurrentCamera
local lplr = playersService.LocalPlayer

local vape = shared.vape
local entitylib = vape.Libraries.entity
local targetinfo = vape.Libraries.targetinfo
local sessioninfo = vape.Libraries.sessioninfo
local whitelist = vape.Libraries.whitelist
local prediction = vape.Libraries.prediction
local getfontbounds = vape.Libraries.getfontbounds

local mc = {
	Config = nil, Physics = nil, Items = nil, Net = nil, Controller = nil, World = nil,
	Hands = nil, Input = nil, UIKit = nil, FX = nil, Skins = nil, WeaponSkins = nil,
	WeaponSkinFX = nil, Visuals = nil, Effects = nil, Assets = nil, Action = nil, State = nil
}
local store = {
	attackReach = 0,
	attackReachUpdate = 0,
	hand = {},
	inventory = {inventory = {}, hotbar = {}, selected = 1, offhand = nil},
	killauraTarget = nil,
	matchState = 0,
	tools = {}
}
local Reach = {}
local NoSlowdown = {}
local Killaura = {}
local BLOCK = 16



store.attackHooks = {}
store.attackPostHooks = {}
store.netHooks = {}
local attackHookInstalled = false
local netHookInstalled = false

local function getShared()
	return replicatedStorage:FindFirstChild('MC')
end

local function getClient()
	local scripts = lplr:FindFirstChild('PlayerScripts')
	return scripts and scripts:FindFirstChild('MC')
end



local function requireModule(folder, name)
	local module = folder and folder:WaitForChild(name, 30)
	if not module then return nil end
	local success, returned = pcall(require, module)
	return success and returned or nil
end

local requiredEngine = {'Config', 'Items', 'Net', 'Controller', 'World', 'Hands', 'Input'}

local function missingEngine()
	local missing = {}

	for _, name in requiredEngine do
		if not mc[name] then
			table.insert(missing, name)
		end
	end

	return missing
end

local function fillEngine()
	local sharedFolder = getShared()
	local clientFolder = getClient()

	if sharedFolder then
		mc.Config = mc.Config or requireModule(sharedFolder, 'Config')
		mc.Physics = mc.Physics or requireModule(sharedFolder, 'Physics')
		mc.Items = mc.Items or requireModule(sharedFolder, 'Items')
		mc.Effects = mc.Effects or requireModule(sharedFolder, 'Effects')
		mc.Skins = mc.Skins or requireModule(sharedFolder, 'Skins')
		mc.WeaponSkins = mc.WeaponSkins or requireModule(sharedFolder, 'WeaponSkins')
		mc.Assets = mc.Assets or sharedFolder:FindFirstChild('Assets')

		local remotes = sharedFolder:FindFirstChild('Remotes')
		if remotes then
			mc.Action = mc.Action or remotes:FindFirstChild('Action')
			mc.State = mc.State or remotes:FindFirstChild('State')
		end
	end

	if clientFolder then
		mc.Net = mc.Net or requireModule(clientFolder, 'Net')
		mc.Controller = mc.Controller or requireModule(clientFolder, 'Controller')
		mc.World = mc.World or requireModule(clientFolder, 'World')
		mc.Hands = mc.Hands or requireModule(clientFolder, 'Hands')
		mc.Input = mc.Input or requireModule(clientFolder, 'Input')
		mc.UIKit = mc.UIKit or requireModule(clientFolder, 'UIKit')
		mc.FX = mc.FX or requireModule(clientFolder, 'FX')
		mc.Visuals = mc.Visuals or requireModule(clientFolder, 'Visuals')
		mc.WeaponSkinFX = mc.WeaponSkinFX or requireModule(clientFolder, 'WeaponSkinFX')
	end

	if mc.Config and mc.Config.BLOCK then
		BLOCK = mc.Config.BLOCK
	end
end

run(function()
	fillEngine()

	
	
	
	if #missingEngine() == 0 then return end

	task.spawn(function()
		local deadline = os.clock() + 120

		while os.clock() < deadline do
			task.wait(1)
			fillEngine()

			if #missingEngine() == 0 then
				if store.installAttackHook then store.installAttackHook() end
				if store.installNetHook then store.installNetHook() end
				pcall(vape.CreateNotification, vape, 'unstable smp', 'Engine connected, features are live', 4)
				return
			end
		end

		store.missingEngine = missingEngine()
		pcall(vape.CreateNotification, vape, 'unstable smp', 'Engine modules missing: ' .. table.concat(store.missingEngine, ', '), 30, 'alert')
	end)
end)

local function readItem(raw)
	if type(raw) ~= 'string' or raw == '' then return nil end
	local success, decoded = pcall(function()
		return httpService:JSONDecode(raw)
	end)
	return success and type(decoded) == 'table' and decoded or nil
end

local function getHealth(char)
	local hp = char:GetAttribute('Health')
	if type(hp) == 'number' then
		local max = char:GetAttribute('MaxHealth')
		return hp, type(max) == 'number' and max or math.max(hp, 20)
	end
	local hum = char:FindFirstChildOfClass('Humanoid')
	if hum then
		return hum.Health, hum.MaxHealth
	end
	return 0, 20
end

local function getShield(char)
	local total = 0
	for name, value in char:GetAttributes() do
		if name:find('Shield') and type(value) == 'number' and value > 0 then
			total += value
		end
	end
	return total
end

local function isFriend(plr, recolor)
	if vape.Categories.Friends.Options['Use friends'].Enabled then
		local friend = table.find(vape.Categories.Friends.ListEnabled, plr.Name) and true
		if recolor then
			friend = friend and vape.Categories.Friends.Options['Recolor visuals'].Enabled
		end
		return friend
	end
	return nil
end

local function isTarget(plr)
	return table.find(vape.Categories.Targets.ListEnabled, plr.Name) and true
end

local function removeTags(str)
	str = str:gsub('<br%s*/>', '\n')
	return (str:gsub('<[^<>]->', ''))
end

local function getTableSize(tab)
	local index = 0
	for _ in tab do
		index += 1
	end
	return index
end

local frictionTable, oldfrict = {}, {}
local frictionConnection
local frictionState

local function modifyVelocity(part)
	if part:IsA('BasePart') and part.Name ~= 'HumanoidRootPart' and not oldfrict[part] then
		oldfrict[part] = part.CustomPhysicalProperties or 'none'
		part.CustomPhysicalProperties = PhysicalProperties.new(0.0001, 0.2, 0.5, 1, 1)
	end
end

local function updateVelocity(force)
	local newState = getTableSize(frictionTable) > 0
	if frictionState ~= newState or force then
		if frictionConnection then
			frictionConnection:Disconnect()
		end

		if newState then
			if entitylib.isAlive then
				for _, part in entitylib.character.Character:GetDescendants() do
					modifyVelocity(part)
				end
				frictionConnection = entitylib.character.Character.DescendantAdded:Connect(modifyVelocity)
			end
		else
			for part, value in oldfrict do
				if part.Parent then
					part.CustomPhysicalProperties = value ~= 'none' and value or nil
				end
			end
			table.clear(oldfrict)
		end
	end
	frictionState = newState
end

local function getInventory()
	return mc.Hands and mc.Hands.inv or store.inventory
end

local function syncStore()
	local inventory = getInventory()
	if inventory then
		store.inventory = inventory
		local item = inventory.hotbar and inventory.hotbar[inventory.selected or 1]
		store.hand = {
			item = item,
			tool = item,
			toolType = item and item.id or 'none',
			toolName = item and item.id or 'none'
		}
	end
end

local function installAttackHook()
	local hands = mc.Hands
	if attackHookInstalled or not hands or type(hands.attack) ~= 'function' then return end
	attackHookInstalled = true

	local oldattack = hands.attack
	hands.attack = function(target, ...)
		for _, hook in store.attackHooks do
			local success, allowed = pcall(hook, target)
			if success and allowed == false then return false end
		end

		local args = table.pack(...)
		local result = oldattack(target, table.unpack(args, 1, args.n))

		for _, hook in store.attackPostHooks do
			task.spawn(hook, target)
		end

		return result
	end
end



local function installNetHook()
	local net = mc.Net
	if netHookInstalled or not net or type(net.send) ~= 'function' then return end
	netHookInstalled = true

	local oldsend = net.send
	net.send = function(payload)
		if type(payload) == 'table' then
			for _, hook in store.netHooks do
				pcall(hook, payload)
			end
		end

		return oldsend(payload)
	end
end

local function removeHook(list, hook)
	local index = table.find(list, hook)
	if index then
		table.remove(list, index)
	end
end

local function netSend(payload)
	local net = mc.Net
	if not net or type(net.send) ~= 'function' then return false end
	return pcall(net.send, payload)
end

local function itemDef(item)
	if type(item) ~= 'table' or not mc.Items or type(mc.Items.def) ~= 'function' then return nil end
	local success, def = pcall(mc.Items.def, item)
	return success and type(def) == 'table' and def or nil
end

local function handsRefresh()
	local hands = mc.Hands
	if not hands or type(hands.onChanged) ~= 'table' then return end
	for _, func in hands.onChanged do
		task.spawn(func)
	end
end

local function selectSlot(slot)
	local hands = mc.Hands
	if not hands or type(hands.select) ~= 'function' then return false end
	return pcall(hands.select, slot)
end

local function hotbarSlot(id)
	local inventory = getInventory()
	local hotbar = inventory and inventory.hotbar
	if not hotbar then return nil end

	for slot = 1, 9 do
		local item = hotbar[slot]
		if item and tostring(item.id):lower():find(id, 1, true) then
			return slot
		end
	end
end

local function inventorySlot(id)
	local inventory = getInventory()
	local storage = inventory and inventory.inventory
	if not storage then return nil end

	for slot, item in storage do
		if item and tostring(item.id):lower():find(id, 1, true) then
			return slot
		end
	end
end

local function freeHotbarSlot()
	local inventory = getInventory()
	local hotbar = inventory and inventory.hotbar
	if not hotbar then return nil end

	for slot = 1, 9 do
		if not hotbar[slot] then return slot end
	end

	for slot = 1, 9 do
		local item = hotbar[slot]
		local def = itemDef(item)
		local kind = def and def.kind
		if item and kind ~= 'sword' and kind ~= 'axe' and kind ~= 'mace' then
			return slot
		end
	end

	return 9
end

local function moveToHotbar(source, target)
	local inventory = getInventory()
	if not inventory or not inventory.hotbar or not inventory.inventory then return false end

	local item = inventory.inventory[source]
	if not item then return false end

	inventory.inventory[source] = inventory.hotbar[target]
	inventory.hotbar[target] = item

	netSend({a = 'inv', op = 'open'})
	task.defer(function()
		netSend({a = 'inv', op = 'key', slot = source + 10, target = target})
		task.defer(function()
			netSend({a = 'inv', op = 'close'})
		end)
	end)
	handsRefresh()
	return true
end

local function swapOffhandSlot(slot)
	local inventory = getInventory()
	if not inventory or not inventory.hotbar then return false end

	local selected = inventory.selected or 1
	if slot and slot ~= selected then
		return selectSlot(slot)
	end

	local previous = inventory.hotbar[selected]
	inventory.hotbar[selected] = inventory.offhand
	inventory.offhand = previous
	netSend({a = 'swap'})
	handsRefresh()
	return true
end

store.installAttackHook = installAttackHook
store.installNetHook = installNetHook

installAttackHook()
installNetHook()

run(function()
	local oldstart = entitylib.start
	local function customEntity(ent)
		if ent:HasTag('inventory-entity') or ent:HasTag('Corpse') then
			return
		end

		entitylib.addEntity(ent, playersService:GetPlayerFromCharacter(ent), nil)
	end

	entitylib.start = function()
		oldstart()
		if entitylib.Running then
			for _, ent in collectionService:GetTagged('entity') do
				customEntity(ent)
			end
			table.insert(entitylib.Connections, collectionService:GetInstanceAddedSignal('entity'):Connect(customEntity))
			table.insert(entitylib.Connections, collectionService:GetInstanceRemovedSignal('entity'):Connect(function(ent)
				entitylib.removeEntity(ent)
			end))
		end
	end

	entitylib.targetCheck = function(entity)
		if entity.TeamCheck then
			return entity:TeamCheck()
		end
		if entity.NPC then return true end
		if isFriend(entity.Player) then return false end
		if not select(2, whitelist:get(entity.Player)) then return false end
		return lplr:GetAttribute('Team') ~= entity.Player:GetAttribute('Team')
	end

	entitylib.getUpdateConnections = function(entity)
		local char = entity.Character
		local list = {
			char:GetAttributeChangedSignal('Health'),
			char:GetAttributeChangedSignal('MaxHealth'),
			{
				Connect = function()
					entity.Friend = entity.Player and isFriend(entity.Player) or nil
					entity.Target = entity.Player and isTarget(entity.Player) or nil
					return {Disconnect = function() end}
				end
			}
		}

		for name, value in char:GetAttributes() do
			if name:find('Shield') and type(value) == 'number' then
				table.insert(list, char:GetAttributeChangedSignal(name))
			end
		end

		return list
	end

	entitylib.addEntity = function(char, plr, teamfunc)
		if not char then return end

		entitylib.EntityThreads[char] = task.spawn(function()
			local hum = char:WaitForChild('Humanoid', 10)
			local humrootpart = hum and hum:WaitForChild('RootPart', workspace.StreamingEnabled and math.huge or 10) or char:WaitForChild('PrimaryPart', 10)
			local head = char:WaitForChild('Head', 10) or humrootpart

			if hum and humrootpart then
				local entity = {
					Connections = {},
					Character = char,
					Health = getHealth(char) + getShield(char),
					Head = head,
					Humanoid = hum,
					HumanoidRootPart = humrootpart,
					HipHeight = (hum.HipHeight or 0.5) + (humrootpart.Size.Y / 2) + (hum.RigType == Enum.HumanoidRigType.R6 and 2 or 0),
					MaxHealth = char:GetAttribute('MaxHealth') or 100,
					NPC = plr == nil,
					Player = plr,
					RootPart = humrootpart,
					TeamCheck = teamfunc
				}

				if plr == lplr then
					entity.AirTime = tick()
					entitylib.character = entity
					entitylib.isAlive = true
					entitylib.Events.LocalAdded:Fire(entity)
				else
					entity.Targetable = entitylib.targetCheck(entity)

					for _, connection in entitylib.getUpdateConnections(entity) do
						table.insert(entity.Connections, connection:Connect(function()
							entity.Health = getHealth(char) + getShield(char)
							entity.MaxHealth = char:GetAttribute('MaxHealth') or entity.MaxHealth
							entitylib.Events.EntityUpdated:Fire(entity)
						end))
					end

					table.insert(entitylib.List, entity)
					entitylib.Events.EntityAdded:Fire(entity)
				end
			end

			entitylib.EntityThreads[char] = nil
		end)
	end

	vape:Clean(entitylib.Events.LocalAdded:Connect(updateVelocity))
end)
entitylib.start()

run(function()
	local function refresh()
		syncStore()
		if mc.Controller and mc.Controller.state then
			store.matchState = mc.Controller.state.inMatch and 2 or 0
		end
	end

	local function bindHands()
		if mc.Hands and mc.Hands.onChanged then
			table.insert(mc.Hands.onChanged, refresh)
		end
		refresh()
	end

	bindHands()
	vape:Clean(entitylib.Events.LocalAdded:Connect(bindHands))
	vape:Clean(runService.Heartbeat:Connect(refresh))
end)

run(function()
	local kills = sessioninfo:AddItem('Kills')
	local deaths = sessioninfo:AddItem('Deaths')
	local wasAlive = true

	vape:Clean(runService.Heartbeat:Connect(function()
		if not entitylib.isAlive then
			if wasAlive then
				wasAlive = false
				deaths:Increment()
			end
			return
		end

		wasAlive = true
		local health = getHealth(entitylib.character.Character)
		if health <= 0 then
			entitylib.isAlive = false
		end
	end))
end)

for _, name in {'Fly', 'LongJump', 'Jesus', 'AutoRejoin', 'Disabler', 'MurderMystery', 'Parkour', 'Wallhop', 'Invisible'} do
	vape:Remove(name)
end


run(function()
	local Backtrack
	local BufferSlider
	local HoldSlider
	local Visualize
	local VisualizeColor
	local HoldKey
	local Buffer = {}
	local SpoofPosition
	local SpoofUntil
	local OldState
	local Lines = {}
	local LastSample = 0

	local function spoof(position)
		if not SpoofPosition or not SpoofUntil then return position end

		local remain = (SpoofUntil - os.clock()) / math.max(HoldSlider.Value / 20, 0.001)
		if remain <= 0 then
			SpoofPosition = nil
			SpoofUntil = nil
			return position
		end

		return position:Lerp(SpoofPosition, math.clamp(remain, 0, 1))
	end

	local function installStateHook()
		local net = mc.Net
		if OldState or not net or type(net.state) ~= 'function' then return end

		OldState = net.state
		net.state = function(state)
			if SpoofPosition and type(state) == 'table' and typeof(state.p) == 'Vector3' then
				local clone = table.clone(state)
				clone.p = spoof(clone.p)
				return OldState(clone)
			end

			return OldState(state)
		end
	end

	local function removeStateHook()
		local net = mc.Net
		if net and OldState then
			if net.state == OldState then
				OldState = nil
				return
			end

			net.state = OldState
		end

		OldState = nil
	end

	local function clearLines()
		for _, line in Lines do
			line.Visible = false
		end
	end

	local function updateVisuals()
		clearLines()
		if not Visualize.Enabled or not SpoofPosition then return end

		local camera = workspace.CurrentCamera
		local point, visible = camera and camera:WorldToViewportPoint(SpoofPosition)
		if not visible then return end

		local center = Vector2.new(point.X, point.Y)
		local size = 10
		local offsets = {Vector2.new(-size, -size), Vector2.new(size, -size), Vector2.new(size, size), Vector2.new(-size, size)}
		local color = Color3.fromHSV(VisualizeColor.Hue, VisualizeColor.Sat, VisualizeColor.Value)

		for index, line in Lines do
			line.From = center + offsets[index]
			line.To = center + offsets[index % 4 + 1]
			line.Color = color
			line.Thickness = 1
			line.Transparency = 1
			line.Visible = true
		end
	end

	Backtrack = vape.Categories.Combat:CreateModule({
		Name = 'Backtrack',
		Function = function(callback)
			if not callback then
				removeStateHook()
				clearLines()
				table.clear(Buffer)
				SpoofPosition = nil
				SpoofUntil = nil
				return
			end

			if Drawing then
				for _ = 1, 4 do
					local line = Drawing.new('Line')
					line.Visible = false
					table.insert(Lines, line)
				end
			end

			local hook = function(payload)
				if SpoofPosition and payload.a == 'state' and typeof(payload.p) == 'Vector3' then
					payload.p = spoof(payload.p)
				end
			end

			store.installNetHook()
			installStateHook()
			table.insert(store.netHooks, hook)

			Backtrack:Clean(HoldKey.Triggered:Connect(function(isDown)
				if not isDown then
					SpoofUntil = nil
					return
				end

				if #Buffer == 0 then return end

				SpoofPosition = Buffer[#Buffer]
				SpoofUntil = os.clock() + (HoldSlider.Value / 20)
			end))

			Backtrack:Clean(runService.Heartbeat:Connect(function()
				if not entitylib.isAlive then return end
				if os.clock() - LastSample < 0.05 then return end

				local character = entitylib.character
				local root = character and character.RootPart
				if not root then return end

				LastSample = os.clock()
				table.insert(Buffer, 1, root.Position)

				while #Buffer > BufferSlider.Value do
					table.remove(Buffer)
				end
			end))

			Backtrack:Clean(runService.RenderStepped:Connect(updateVisuals))
			Backtrack:Clean(function()
				removeHook(store.netHooks, hook)
				removeStateHook()
				clearLines()
				table.clear(Buffer)
				SpoofPosition = nil
				SpoofUntil = nil
			end)
		end,
		Tooltip = 'Keeps a small position buffer and replays it while\nyou hold the key, pulling your hitbox back'
	})
	BufferSlider = Backtrack:CreateSlider({
		Name = 'Buffer',
		Min = 2,
		Max = 10,
		Default = 5,
		Suffix = 't'
	})
	HoldSlider = Backtrack:CreateSlider({
		Name = 'Hold',
		Min = 1,
		Max = 8,
		Default = 3,
		Suffix = 't'
	})
	Visualize = Backtrack:CreateToggle({
		Name = 'Visualize',
		Function = function(callback)
			VisualizeColor.Object.Visible = callback
		end
	})
	VisualizeColor = Backtrack:CreateColorSlider({
		Name = 'Visualize color',
		Darker = true,
		Visible = false
	})
	HoldKey = Backtrack:CreateBind({
		Name = 'Hold key',
		Default = {'X'},
		Hold = true
	})
end)


run(function()
	local HitSelect
	local Ratio
	local MinStrength

	HitSelect = vape.Categories.Combat:CreateModule({
		Name = 'HitSelect',
		Function = function(callback)
			if not callback then return end

			local hook = function(target)
				if not entitylib.isAlive or not target then return end

				local character = entitylib.character
				local root = character and character.RootPart
				local part = target.RootPart
				if not root or not part then return end

				
				
				local reach = (mc.Controller and mc.Controller.reach) or 3
				if (part.Position - root.Position).Magnitude > reach * Ratio.Value then
					return false
				end

				local hands = mc.Hands
				if hands and type(hands.strength) == 'function' then
					local success, strength = pcall(hands.strength)
					if success and type(strength) == 'number' and strength < MinStrength.Value then
						return false
					end
				end
			end

			store.installAttackHook()
			table.insert(store.attackHooks, hook)
			HitSelect:Clean(function()
				removeHook(store.attackHooks, hook)
			end)
		end,
		Tooltip = 'Holds your attacks back until the target is in\nrange and your cooldown is almost full'
	})
	Ratio = HitSelect:CreateSlider({
		Name = 'Range ratio',
		Min = 0.5,
		Max = 1,
		Default = 0.9,
		Decimal = 100
	})
	MinStrength = HitSelect:CreateSlider({
		Name = 'Min strength',
		Min = 0.5,
		Max = 1,
		Default = 0.95,
		Decimal = 100
	})
end)


run(function()
	local HitSwap
	local HoldTicks
	local PreviousSlot
	local RestoreAt

	local function findAxe()
		local inventory = getInventory()
		local hotbar = inventory and inventory.hotbar
		if not hotbar then return nil end

		for slot = 1, 9 do
			local def = itemDef(hotbar[slot])
			if def and (def.kind == 'axe' or def.disablesShield) then
				return slot
			end
		end
	end

	HitSwap = vape.Categories.Combat:CreateModule({
		Name = 'HitSwap',
		Function = function(callback)
			if not callback then return end

			local hook = function()
				if RestoreAt then return end

				local inventory = getInventory()
				if not inventory or not inventory.hotbar then return end

				local selected = inventory.selected or 1
				local def = itemDef(inventory.hotbar[selected])
				if not def or def.kind ~= 'sword' then return end

				local slot = findAxe()
				if not slot or slot == selected then return end

				PreviousSlot = selected
				if not selectSlot(slot) then
					PreviousSlot = nil
					return
				end

				RestoreAt = os.clock() + (HoldTicks.Value / 20)
			end

			store.installAttackHook()
			table.insert(store.attackPostHooks, hook)
			HitSwap:Clean(runService.Heartbeat:Connect(function()
				if not RestoreAt or os.clock() < RestoreAt then return end

				if PreviousSlot then
					selectSlot(PreviousSlot)
				end

				PreviousSlot = nil
				RestoreAt = nil
			end))
			HitSwap:Clean(function()
				removeHook(store.attackPostHooks, hook)

				if RestoreAt and PreviousSlot then
					selectSlot(PreviousSlot)
				end

				PreviousSlot = nil
				RestoreAt = nil
			end)
		end,
		Tooltip = 'Swaps to a shield breaking axe right after a sword\nhit and swaps back a few ticks later'
	})
	HoldTicks = HitSwap:CreateSlider({
		Name = 'Hold ticks',
		Min = 1,
		Max = 6,
		Default = 2,
		Suffix = 't'
	})
end)


run(function()
	local ShieldBreaker

	ShieldBreaker = vape.Categories.Combat:CreateModule({
		Name = 'ShieldBreaker',
		Function = function(callback)
			if not callback then return end

			local hook = function(payload)
				
				
				if payload.a == 'attack' then
					if type(payload.st) == 'table' then
						payload.st.swap = true
						payload.st.predicted = true
					else
						payload.swap = true
					end
				end
			end

			store.installNetHook()
			table.insert(store.netHooks, hook)
			ShieldBreaker:Clean(function()
				removeHook(store.netHooks, hook)
			end)
		end,
		Tooltip = 'Flags your attacks as shield breaking strikes so they\ngo through raised shields'
	})
end)


run(function()
	local SilentProjectile
	local Targets
	local Range
	local Angle
	local Charge
	local Speed
	local Predict
	local AutoShoot
	local CircleColor
	local CircleTransparency
	local CircleFilled
	local CircleObject
	local UsingSince

	local projectiles = {'arrow', 'ender_pearl', 'splash', 'trident', 'egg', 'snowball'}

	local function isProjectile(id)
		local name = tostring(id):lower()
		for _, part in projectiles do
			if name:find(part, 1, true) then
				return true
			end
		end
		return false
	end

	local function getEye()
		local character = entitylib.character
		if character and character.Head then
			return character.Head.Position
		end

		local camera = workspace.CurrentCamera
		return camera and camera.CFrame.Position
	end

	local function getTarget()
		local camera = workspace.CurrentCamera
		local eye = getEye()
		if not camera or not eye or not entitylib.isAlive then return end

		
		local look = camera.CFrame.LookVector
		local limit = math.cos(math.rad(Angle.Value))
		local best, bestScore

		for _, entity in entitylib.List do
			local part = entity.RootPart
			if not part or not entity.Targetable then continue end
			if not Targets.Players.Enabled and entity.Player then continue end
			if not Targets.NPCs.Enabled and entity.NPC then continue end

			local delta = part.Position - eye
			local distance = delta.Magnitude
			if distance < 0.5 or distance > Range.Value then continue end
			if delta.Unit:Dot(look) < limit then continue end
			if Targets.Walls.Enabled and entitylib.Wallcheck(eye, part.Position) then continue end

			local score = delta.Unit:Dot(look) * 2 - distance / Range.Value
			if not bestScore or score > bestScore then
				best, bestScore = entity, score
			end
		end

		return best
	end

	local function getAimPoint(entity)
		local part = entity.RootPart
		local eye = getEye()
		local speed = Speed.Value
		local position = part.Position
		if not eye or speed <= 0 then return position end

		if Predict.Enabled then
			local travel = (position - eye).Magnitude / speed
			position = position + part.AssemblyLinearVelocity * travel
		end

		local config = mc.Config
		local tick = config and config.TICK
		local gravity = config and config.GRAVITY

		
		if tick and gravity and tick > 0 then
			local ticks = ((position - eye).Magnitude / speed) / tick
			position = position + Vector3.new(0, 0.5 * gravity * ticks * ticks, 0)
		end

		return position
	end

	local function getRedirect()
		local entity = getTarget()
		local eye = getEye()
		if not entity or not eye then return end

		local direction = getAimPoint(entity) - eye
		if direction.Magnitude < 0.1 then return end
		return direction.Unit
	end

	local function isCharged(hands, using, elapsed)
		if using.kind == 'crossbow' then
			local inventory = hands.inv
			local held = inventory and inventory.hotbar and inventory.hotbar[inventory.selected or 1]
			local def = itemDef(held)
			local quick = def and type(def.ench) == 'table' and tonumber(def.ench.quick_charge) or 0
			return elapsed >= (25 - 5 * quick) / 20
		end

		local power = math.min((elapsed * elapsed + elapsed * 2) / 3, 1)
		return power >= Charge.Value
	end

	local function updateCircle()
		if not CircleObject then return end

		local camera = workspace.CurrentCamera
		if not camera then return end

		local half = math.tan(math.rad(camera.FieldOfView / 2))
		local radius = (camera.ViewportSize.Y / 2) * math.tan(math.rad(Angle.Value)) / half
		CircleObject.Radius = math.max(radius, 1)
		CircleObject.Position = inputService:GetMouseLocation()
	end

	SilentProjectile = vape.Categories.Combat:CreateModule({
		Name = 'SilentProjectile',
		Function = function(callback)
			if CircleObject then
				CircleObject.Visible = callback
			end

			if not callback then
				UsingSince = nil
				return
			end

			local hook = function(payload)
				if payload.a == 'use' and payload.item and isProjectile(payload.item) then
					local redirect = getRedirect()
					if redirect then
						payload.look = redirect
					end
				end
			end

			store.installNetHook()
			table.insert(store.netHooks, hook)

			SilentProjectile:Clean(runService.RenderStepped:Connect(updateCircle))
			SilentProjectile:Clean(runService.Heartbeat:Connect(function()
				local hands = mc.Hands
				local using = hands and hands.using
				if not using or (using.kind ~= 'bow' and using.kind ~= 'crossbow') then
					UsingSince = nil
					return
				end

				if not AutoShoot.Enabled then return end
				UsingSince = UsingSince or os.clock()

				if isCharged(hands, using, os.clock() - UsingSince) and type(hands.stopUsing) == 'function' then
					UsingSince = nil
					pcall(hands.stopUsing, false)
				end
			end))
			SilentProjectile:Clean(function()
				removeHook(store.netHooks, hook)
				UsingSince = nil
			end)
		end,
		Tooltip = 'Aims projectiles at the closest target in your\nfield of view and releases bows at full charge'
	})
	Targets = SilentProjectile:CreateTargets({
		Players = true,
		NPCs = true
	})
	Range = SilentProjectile:CreateSlider({
		Name = 'Range',
		Min = 4,
		Max = 48,
		Default = 16,
		Suffix = function(val)
			return val == 1 and 'block' or 'blocks'
		end
	})
	Angle = SilentProjectile:CreateSlider({
		Name = 'Angle',
		Min = 5,
		Max = 180,
		Default = 40,
		Suffix = '°',
		Function = updateCircle
	})
	Charge = SilentProjectile:CreateSlider({
		Name = 'Min charge',
		Min = 0.1,
		Max = 1,
		Default = 0.9,
		Decimal = 100
	})
	Speed = SilentProjectile:CreateSlider({
		Name = 'Projectile speed',
		Min = 10,
		Max = 200,
		Default = 60,
		Suffix = 'b/s'
	})
	Predict = SilentProjectile:CreateToggle({
		Name = 'Predict movement',
		Default = true,
		Darker = true
	})
	AutoShoot = SilentProjectile:CreateToggle({
		Name = 'Auto shoot',
		Tooltip = 'Releases the bow or crossbow once it is fully charged'
	})
	SilentProjectile:CreateToggle({
		Name = 'Range circle',
		Function = function(callback)
			if callback then
				CircleObject = Drawing.new('Circle')
				CircleObject.Filled = CircleFilled.Enabled
				CircleObject.Color = Color3.fromHSV(CircleColor.Hue, CircleColor.Sat, CircleColor.Value)
				CircleObject.NumSides = 100
				CircleObject.Thickness = 1
				CircleObject.Transparency = 1 - CircleTransparency.Value
				CircleObject.Visible = SilentProjectile.Enabled
				updateCircle()
			else
				pcall(function()
					CircleObject.Visible = false
					CircleObject:Remove()
				end)
				CircleObject = nil
			end

			CircleColor.Object.Visible = callback
			CircleTransparency.Object.Visible = callback
			CircleFilled.Object.Visible = callback
		end
	})
	CircleColor = SilentProjectile:CreateColorSlider({
		Name = 'Circle color',
		Function = function(hue, sat, val)
			if CircleObject then
				CircleObject.Color = Color3.fromHSV(hue, sat, val)
			end
		end,
		Darker = true,
		Visible = false
	})
	CircleTransparency = SilentProjectile:CreateSlider({
		Name = 'Transparency',
		Min = 0,
		Max = 1,
		Default = 0.5,
		Decimal = 10,
		Function = function(val)
			if CircleObject then
				CircleObject.Transparency = 1 - val
			end
		end,
		Darker = true,
		Visible = false
	})
	CircleFilled = SilentProjectile:CreateToggle({
		Name = 'Circle filled',
		Function = function(callback)
			if CircleObject then
				CircleObject.Filled = callback
			end
		end,
		Darker = true,
		Visible = false
	})
end)


run(function()
	local Surround
	local Material

	local offsets = {
		Vector3.new(1, 0, 0),
		Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, -1)
	}
	local lastPlace = 0

	local function place()
		local character = entitylib.character
		local root = character and character.RootPart
		if not root then return end

		local controller = mc.Controller
		local state = controller and controller.state
		if state and not state.onGround then return end

		local id = Material.Value == 'Obsidian' and 'obsidian' or 'cobweb'
		local slot = hotbarSlot(id)
		if not slot then return end

		local inventory = getInventory()
		local previous = inventory and inventory.selected
		if not selectSlot(slot) then return end

		local origin = root.Position
		task.defer(function()
			for _, offset in offsets do
				local cell = Vector3.new(math.floor(origin.X + offset.X), math.floor(origin.Y - 1), math.floor(origin.Z + offset.Z))
				local look = (cell + Vector3.new(0.5, 0.5, 0.5) - origin).Unit
				netSend({a = 'use', hand = 'main', look = look, item = id, cell = cell})
			end

			task.delay(0.05, function()
				if previous then
					selectSlot(previous)
				end
			end)
		end)
	end

	Surround = vape.Categories.Combat:CreateModule({
		Name = 'Surround',
		Function = function(callback)
			if not callback then return end

			Surround:Clean(runService.Heartbeat:Connect(function()
				if not entitylib.isAlive then return end
				if os.clock() - lastPlace < 0.3 then return end

				lastPlace = os.clock()
				place()
			end))
		end,
		Tooltip = 'Places blocks around your feet to trap whoever\nis pushing you'
	})
	Material = Surround:CreateDropdown({
		Name = 'Material',
		List = {'Obsidian', 'Cobweb'}
	})
end)


run(function()
	local WTap
	local Ticks
	local ResetUntil = 0

	WTap = vape.Categories.Combat:CreateModule({
		Name = 'WTap',
		Function = function(callback)
			if not callback then
				ResetUntil = 0
				return
			end

			local hook = function()
				ResetUntil = os.clock() + (Ticks.Value / 20)
			end

			store.installAttackHook()
			table.insert(store.attackPostHooks, hook)
			WTap:Clean(runService.Heartbeat:Connect(function()
				if os.clock() >= ResetUntil then return end

				local controller = mc.Controller
				local state = controller and controller.state
				if state then
					state.sprinting = false
				end
			end))
			WTap:Clean(function()
				removeHook(store.attackPostHooks, hook)
				ResetUntil = 0
			end)
		end,
		Tooltip = 'Resets your sprint for a few ticks after every hit'
	})
	Ticks = WTap:CreateSlider({
		Name = 'Ticks',
		Min = 1,
		Max = 4,
		Default = 1,
		Suffix = 't'
	})
end)


run(function()
	local AntiVoid
	local Height
	local Safe = Vector3.zero
	local LastAction = 0

	AntiVoid = vape.Categories.Blatant:CreateModule({
		Name = 'AntiVoid',
		Function = function(callback)
			if not callback then
				Safe = Vector3.zero
				return
			end

			AntiVoid:Clean(runService.Heartbeat:Connect(function()
				if not entitylib.isAlive then return end

				local character = entitylib.character
				local root = character and character.RootPart
				local controller = mc.Controller
				local state = controller and controller.state
				if not root or not state then return end

				local position = typeof(state.pos) == 'Vector3' and state.pos or root.Position
				if state.onGround and position.Y > Height.Value then
					Safe = position
					return
				end

				if position.Y > Height.Value then return end
				if os.clock() - LastAction < 0.5 then return end
				LastAction = os.clock()

				if typeof(state.pos) == 'Vector3' and Safe.Y > Height.Value then
					state.pos = Safe + Vector3.new(0, 3, 0)
					state.prev = state.pos
					state.fallDistance = 0

					if typeof(state.vel) == 'Vector3' then
						state.vel = Vector3.zero
					end
				elseif typeof(state.vel) == 'Vector3' then
					state.vel = Vector3.new(state.vel.X, 4, state.vel.Z)
				end
			end))
		end,
		Tooltip = 'Puts you back on the last block you stood on\nbefore you drop out of the world'
	})
	Height = AntiVoid:CreateSlider({
		Name = 'Height',
		Min = -64,
		Max = 32,
		Default = -20
	})
end)


run(function()
	local BunnyHop
	local Mode
	local OldIsDown

	local function wantsJump()
		if not entitylib.isAlive then return false end

		local controller = mc.Controller
		local state = controller and controller.state
		if not state or not state.onGround or state.gliding or state.inWater then return false end
		if Mode.Value == 'Sprint' and not state.sprinting then return false end

		return true
	end

	BunnyHop = vape.Categories.Blatant:CreateModule({
		Name = 'BunnyHop',
		Function = function(callback)
			local input = mc.Input

			if not callback then
				if input and OldIsDown and input.isDown ~= OldIsDown then
					input.isDown = OldIsDown
				end

				OldIsDown = nil
				return
			end

			if OldIsDown or not input or type(input.isDown) ~= 'function' then return end
			OldIsDown = input.isDown

			input.isDown = function(name)
				if name == 'jump' and wantsJump() then
					return true
				end

				return OldIsDown(name)
			end
		end,
		Tooltip = 'Jumps again the moment you touch the ground'
	})
	Mode = BunnyHop:CreateDropdown({
		Name = 'Mode',
		List = {'Always', 'Sprint'}
	})
end)


run(function()
	local FastUse
	local Speed
	local Last = 0

	FastUse = vape.Categories.Blatant:CreateModule({
		Name = 'FastUse',
		Function = function(callback)
			if not callback then return end
			Last = os.clock()

			FastUse:Clean(runService.Heartbeat:Connect(function()
				local now = os.clock()
				local delta = now - Last
				Last = now
				if delta <= 0 or delta > 0.5 then return end

				local hands = mc.Hands
				local using = hands and hands.using
				if not using or type(using.start) ~= 'number' then return end
				if using.kind ~= 'eat' and using.kind ~= 'drink' then return end

				
				
				using.start = using.start - (Speed.Value - 1) * delta * 20
			end))
		end,
		Tooltip = 'Consumes food and potions faster'
	})
	Speed = FastUse:CreateSlider({
		Name = 'Speed',
		Min = 1,
		Max = 4,
		Default = 1.5,
		Decimal = 10
	})
end)


run(function()
	local NoJumpDelay

	NoJumpDelay = vape.Categories.Blatant:CreateModule({
		Name = 'NoJumpDelay',
		Function = function(callback)
			if not callback then return end

			NoJumpDelay:Clean(runService.Heartbeat:Connect(function()
				local controller = mc.Controller
				local state = controller and controller.state
				if not state then return end

				state.jumpDelay = 0
			end))
		end,
		Tooltip = 'Removes the short delay between two jumps'
	})
end)


run(function()
	local HitMarker
	local Color
	local CritColor
	local Size
	local Thickness
	local Gap
	local Duration
	local Lines = {}
	local ShownUntil = 0
	local Critical = false

	local offsets = {
		Vector2.new(-1, -1),
		Vector2.new(1, -1),
		Vector2.new(1, 1),
		Vector2.new(-1, 1)
	}

	local function ensureLines()
		if not Drawing then return end

		for index = #Lines + 1, 4 do
			local line = Drawing.new('Line')
			line.Visible = false
			Lines[index] = line
		end
	end

	local function hideLines()
		for _, line in Lines do
			line.Visible = false
			pcall(function()
				line:Remove()
			end)
		end

		table.clear(Lines)
	end

	local function show()
		local hands = mc.Hands
		local controller = mc.Controller
		local state = controller and controller.state
		local strength = 0

		if hands and type(hands.strength) == 'function' then
			local success, value = pcall(hands.strength)
			strength = success and tonumber(value) or 0
		end

		local falling = state and type(state.fallDistance) == 'number' and state.fallDistance > 0
		Critical = falling or strength >= 0.99
		ShownUntil = os.clock() + Duration.Value
		ensureLines()
	end

	local function update()
		if not Drawing then return end

		local remain = ShownUntil - os.clock()
		local visible = remain > 0
		local center = inputService:GetMouseLocation()
		local pick = Critical and CritColor or Color
		local color = Color3.fromHSV(pick.Hue, pick.Sat, pick.Value)

		for index, line in Lines do
			line.Visible = visible
			if visible then
				local direction = offsets[index]
				line.From = center + direction * Gap.Value
				line.To = center + direction * (Gap.Value + Size.Value)
				line.Color = color
				line.Thickness = Thickness.Value
				line.Transparency = math.clamp(remain / math.max(Duration.Value, 0.001), 0, 1)
			end
		end
	end

	HitMarker = vape.Categories.Render:CreateModule({
		Name = 'HitMarker',
		Function = function(callback)
			if not callback then
				hideLines()
				return
			end

			local hook = function(target)
				if not target then return end

				show()
			end

			store.installAttackHook()
			table.insert(store.attackPostHooks, hook)
			HitMarker:Clean(runService.RenderStepped:Connect(update))
			HitMarker:Clean(function()
				removeHook(store.attackPostHooks, hook)
				hideLines()
			end)
		end,
		Tooltip = 'Draws a marker around the crosshair every time\nyour attack lands'
	})
	Color = HitMarker:CreateColorSlider({
		Name = 'Color'
	})
	CritColor = HitMarker:CreateColorSlider({
		Name = 'Crit color',
		Darker = true
	})
	Size = HitMarker:CreateSlider({
		Name = 'Size',
		Min = 2,
		Max = 20,
		Default = 8
	})
	Thickness = HitMarker:CreateSlider({
		Name = 'Thickness',
		Min = 1,
		Max = 4,
		Default = 2
	})
	Gap = HitMarker:CreateSlider({
		Name = 'Gap',
		Min = 0,
		Max = 20,
		Default = 4
	})
	Duration = HitMarker:CreateSlider({
		Name = 'Duration',
		Min = 0.05,
		Max = 1,
		Default = 0.15,
		Decimal = 100
	})
end)


run(function()
	local AutoEat
	local Hunger
	local SearchInventory
	local LastAction = 0

	local function score(item)
		local def = itemDef(item)
		if def and def.kind == 'food' and type(def.food) == 'number' then
			return def.food
		end
	end

	local function findBest()
		local inventory = getInventory()
		local hotbar = inventory and inventory.hotbar
		if not hotbar then return end

		local bestItem, bestScore, source, slot

		local function consider(item, from, index)
			local value = item and score(item)
			if value and (not bestScore or value > bestScore) then
				bestItem, bestScore, source, slot = item, value, from, index
			end
		end

		for index = 1, 9 do
			consider(hotbar[index], 'hotbar', index)
		end

		if SearchInventory.Enabled and inventory.inventory then
			for index, item in inventory.inventory do
				consider(item, 'inventory', index)
			end
		end

		return bestItem, source, slot
	end

	AutoEat = vape.Categories.Inventory:CreateModule({
		Name = 'AutoEat',
		Function = function(callback)
			if not callback then return end

			AutoEat:Clean(runService.Heartbeat:Connect(function()
				if not entitylib.isAlive then return end
				if os.clock() - LastAction < 0.4 then return end

				local hands = mc.Hands
				if hands and hands.using then return end

				local food = lplr:GetAttribute('Food')
				if type(food) ~= 'number' or food > Hunger.Value then return end

				local item, source, slot = findBest()
				if not item then return end
				LastAction = os.clock()

				if source == 'inventory' then
					local target = freeHotbarSlot()
					if target then moveToHotbar(slot, target) end
					return
				end

				if not selectSlot(slot) then return end

				local camera = workspace.CurrentCamera
				local look = camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)
				local controller = mc.Controller

				if hands then
					hands.using = {
						kind = 'eat',
						hand = 'main',
						start = (controller and controller.tickCount) or 0,
						id = item.id
					}
				end

				netSend({a = 'useStart', hand = 'main', look = look, item = item.id})
				handsRefresh()
			end))
		end,
		Tooltip = 'Eats the best food in your inventory when you\nare getting hungry'
	})
	Hunger = AutoEat:CreateSlider({
		Name = 'Hunger',
		Min = 1,
		Max = 20,
		Default = 15
	})
	SearchInventory = AutoEat:CreateToggle({
		Name = 'Search inventory',
		Default = true
	})
end)


run(function()
	local AutoGapple
	local Health
	local SearchInventory
	local LastAction = 0

	local function score(item)
		local id = tostring(item.id):lower()
		if id:find('enchanted_golden_apple', 1, true) or id:find('enchanted_gapple', 1, true) then return 100 end
		if id:find('golden_apple', 1, true) or id:find('gapple', 1, true) then return 50 end
		return nil
	end

	local function findBest()
		local inventory = getInventory()
		local hotbar = inventory and inventory.hotbar
		if not hotbar then return end

		local bestItem, bestScore, source, slot

		local function consider(item, from, index)
			local value = item and score(item)
			if value and (not bestScore or value > bestScore) then
				bestItem, bestScore, source, slot = item, value, from, index
			end
		end

		for index = 1, 9 do
			consider(hotbar[index], 'hotbar', index)
		end

		if SearchInventory.Enabled and inventory.inventory then
			for index, item in inventory.inventory do
				consider(item, 'inventory', index)
			end
		end

		return bestItem, source, slot
	end

	AutoGapple = vape.Categories.Inventory:CreateModule({
		Name = 'AutoGapple',
		Function = function(callback)
			if not callback then return end

			AutoGapple:Clean(runService.Heartbeat:Connect(function()
				if not entitylib.isAlive then return end
				if os.clock() - LastAction < 0.4 then return end

				local hands = mc.Hands
				if hands and hands.using then return end

				local character = entitylib.character
				if character and (character.Health / math.max(character.MaxHealth, 1)) * 100 > Health.Value then return end

				local item, source, slot = findBest()
				if not item then return end
				LastAction = os.clock()

				if source == 'inventory' then
					local target = freeHotbarSlot()
					if target then moveToHotbar(slot, target) end
					return
				end

				if not selectSlot(slot) then return end

				local camera = workspace.CurrentCamera
				local look = camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)
				local controller = mc.Controller

				if hands then
					hands.using = {
						kind = 'eat',
						hand = 'main',
						start = (controller and controller.tickCount) or 0,
						id = item.id
					}
				end

				netSend({a = 'useStart', hand = 'main', look = look, item = item.id})
				handsRefresh()
			end))
		end,
		Tooltip = 'Eats a golden apple when your health gets low'
	})
	Health = AutoGapple:CreateSlider({
		Name = 'Health',
		Min = 1,
		Max = 100,
		Default = 50,
		Suffix = '%'
	})
	SearchInventory = AutoGapple:CreateToggle({
		Name = 'Search inventory',
		Default = true
	})
end)


run(function()
	local AutoPearl
	local Health
	local Distance
	local SearchInventory
	local LastAction = 0

	local function isPearl(item)
		local id = tostring(item.id):lower()
		return id:find('ender_pearl', 1, true) or id:find('enderpearl', 1, true)
	end

	local function findPearl()
		local inventory = getInventory()
		local hotbar = inventory and inventory.hotbar
		if not hotbar then return end

		for index = 1, 9 do
			if isPearl(hotbar[index]) then
				return hotbar[index], 'hotbar', index
			end
		end

		if SearchInventory.Enabled and inventory.inventory then
			for index, item in inventory.inventory do
				if isPearl(item) then
					return item, 'inventory', index
				end
			end
		end
	end

	local function closestTarget()
		local character = entitylib.character
		local root = character and character.RootPart
		if not root then return nil end

		local closest
		for _, entity in entitylib.List do
			local part = entity.RootPart
			if part and entity.Targetable then
				local distance = (part.Position - root.Position).Magnitude
				if not closest or distance < closest then
					closest = distance
				end
			end
		end

		return closest
	end

	AutoPearl = vape.Categories.Inventory:CreateModule({
		Name = 'AutoPearl',
		Function = function(callback)
			if not callback then return end

			AutoPearl:Clean(runService.Heartbeat:Connect(function()
				if not entitylib.isAlive then return end
				if os.clock() - LastAction < 0.5 then return end

				local hands = mc.Hands
				if hands and hands.using then return end

				local character = entitylib.character
				local low = character and (character.Health / math.max(character.MaxHealth, 1)) * 100 <= Health.Value
				local closest = closestTarget()

				if not low and not (closest and closest > Distance.Value) then return end

				local item, source, slot = findPearl()
				if not item then return end
				LastAction = os.clock()

				if source == 'inventory' then
					local target = freeHotbarSlot()
					if target then moveToHotbar(slot, target) end
					return
				end

				if not selectSlot(slot) then return end

				local camera = workspace.CurrentCamera
				local look = camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)
				netSend({a = 'use', hand = 'main', look = Vector3.new(look.X, look.Y + 0.4, look.Z).Unit, item = item.id})
			end))
		end,
		Tooltip = 'Throws an ender pearl away from a fight when your\nhealth gets low or the enemy is far away'
	})
	Health = AutoPearl:CreateSlider({
		Name = 'Health',
		Min = 1,
		Max = 100,
		Default = 40,
		Suffix = '%'
	})
	Distance = AutoPearl:CreateSlider({
		Name = 'Distance',
		Min = 5,
		Max = 60,
		Default = 20,
		Suffix = function(val)
			return val == 1 and 'block' or 'blocks'
		end
	})
	SearchInventory = AutoPearl:CreateToggle({
		Name = 'Search inventory',
		Default = true
	})
end)


run(function()
	local AutoPotion
	local Health
	local SearchInventory
	local LastAction = 0
	local harmful = {'poison', 'harming', 'weakness', 'slowness', 'blindness', 'decay'}

	local function score(item)
		local id = tostring(item.id):lower()
		for _, word in harmful do
			if id:find(word, 1, true) then return nil end
		end

		local value
		if id:find('instant_health', 1, true) then
			value = 100
		elseif id:find('healing', 1, true) then
			value = 95
		elseif id:find('regeneration', 1, true) then
			value = 80
		elseif id:find('absorption', 1, true) then
			value = 60
		end

		if not value then return nil end
		if id:find('splash', 1, true) then value = value - 10 end
		if id:find('lingering', 1, true) then value = value - 30 end
		return value
	end

	local function findBest()
		local inventory = getInventory()
		local hotbar = inventory and inventory.hotbar
		if not hotbar then return end

		local bestItem, bestScore, source, slot

		local function consider(item, from, index)
			local value = item and score(item)
			if value and (not bestScore or value > bestScore) then
				bestItem, bestScore, source, slot = item, value, from, index
			end
		end

		for index = 1, 9 do
			consider(hotbar[index], 'hotbar', index)
		end

		if SearchInventory.Enabled and inventory.inventory then
			for index, item in inventory.inventory do
				consider(item, 'inventory', index)
			end
		end

		return bestItem, source, slot
	end

	local function lookVector()
		local camera = workspace.CurrentCamera
		return camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)
	end

	local function startDrinking(item)
		local hands = mc.Hands
		local controller = mc.Controller
		if hands then
			hands.using = {
				kind = 'eat',
				hand = 'main',
				start = (controller and controller.tickCount) or 0,
				id = item.id
			}
		end

		netSend({a = 'useStart', hand = 'main', look = lookVector(), item = item.id})
		handsRefresh()
	end

	AutoPotion = vape.Categories.Inventory:CreateModule({
		Name = 'AutoPotion',
		Function = function(callback)
			if not callback then return end

			AutoPotion:Clean(runService.Heartbeat:Connect(function()
				if not entitylib.isAlive then return end
				if os.clock() - LastAction < 0.4 then return end

				local hands = mc.Hands
				if hands and hands.using then return end

				local character = entitylib.character
				if character and (character.Health / math.max(character.MaxHealth, 1)) * 100 > Health.Value then return end

				local item, source, slot = findBest()
				if not item then return end
				LastAction = os.clock()

				if source == 'inventory' then
					local target = freeHotbarSlot()
					if target then moveToHotbar(slot, target) end
					return
				end

				if not selectSlot(slot) then return end

				if tostring(item.id):lower():find('splash', 1, true) then
					netSend({a = 'use', hand = 'main', look = lookVector(), item = item.id})
				else
					startDrinking(item)
				end
			end))
		end,
		Tooltip = 'Drinks or throws a healing potion when you get low'
	})
	Health = AutoPotion:CreateSlider({
		Name = 'Health',
		Min = 1,
		Max = 100,
		Default = 50,
		Suffix = '%'
	})
	SearchInventory = AutoPotion:CreateToggle({
		Name = 'Search inventory',
		Default = true
	})
end)


run(function()
	local AutoTotem
	local Health
	local SearchInventory
	local LastAction = 0

	local function healthPercent()
		local character = entitylib.character
		if not character then return 100 end
		return (character.Health / math.max(character.MaxHealth, 1)) * 100
	end

	AutoTotem = vape.Categories.Inventory:CreateModule({
		Name = 'AutoTotem',
		Function = function(callback)
			if not callback then return end

			AutoTotem:Clean(runService.Heartbeat:Connect(function()
				if not entitylib.isAlive then return end
				if os.clock() - LastAction < 0.15 then return end

				local inventory = getInventory()
				if not inventory or not inventory.hotbar then return end

				local offhand = inventory.offhand
				if offhand and tostring(offhand.id):lower() == 'totem_of_undying' then return end
				if healthPercent() > Health.Value then return end

				local slot = hotbarSlot('totem_of_undying')
				if slot then
					LastAction = os.clock()

					if inventory.selected == slot then
						swapOffhandSlot(nil)
					else
						swapOffhandSlot(slot)
					end

					return
				end

				if not SearchInventory.Enabled then return end

				local stored = inventorySlot('totem_of_undying')
				if not stored then return end

				local target = freeHotbarSlot()
				if target then
					LastAction = os.clock()
					moveToHotbar(stored, target)
				end
			end))
		end,
		Tooltip = 'Moves a totem of undying into your offhand\nwhen your health gets low'
	})
	Health = AutoTotem:CreateSlider({
		Name = 'Health',
		Min = 1,
		Max = 100,
		Default = 100,
		Suffix = '%'
	})
	SearchInventory = AutoTotem:CreateToggle({
		Name = 'Search inventory',
		Default = true
	})
end)
