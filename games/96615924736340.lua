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

-- Attack dispatch shared by the modules: features such as hit select, hit swap
-- and wtap have to see every attack, whether it came from aura, triggerbot or a click.
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

-- The MC engine lives under ReplicatedStorage.MC (shared) and PlayerScripts.MC (client).
-- Both are required before any module touches engine state, so everything waits on this.
local function requireModule(folder, name)
	local module = folder and folder:WaitForChild(name, 30)
	if not module then return nil end
	local success, returned = pcall(require, module)
	return success and returned or nil
end

run(function()
	local sharedFolder = getShared()
	local clientFolder = getClient()
	if not sharedFolder or not clientFolder then return end

	mc.Config = requireModule(sharedFolder, 'Config')
	mc.Physics = requireModule(sharedFolder, 'Physics')
	mc.Items = requireModule(sharedFolder, 'Items')
	mc.Effects = requireModule(sharedFolder, 'Effects')
	mc.Skins = requireModule(sharedFolder, 'Skins')
	mc.WeaponSkins = requireModule(sharedFolder, 'WeaponSkins')
	mc.Assets = sharedFolder:FindFirstChild('Assets')
	mc.Net = requireModule(clientFolder, 'Net')
	mc.Controller = requireModule(clientFolder, 'Controller')
	mc.World = requireModule(clientFolder, 'World')
	mc.Hands = requireModule(clientFolder, 'Hands')
	mc.Input = requireModule(clientFolder, 'Input')
	mc.UIKit = requireModule(clientFolder, 'UIKit')
	mc.FX = requireModule(clientFolder, 'FX')
	mc.Visuals = requireModule(clientFolder, 'Visuals')
	mc.WeaponSkinFX = requireModule(clientFolder, 'WeaponSkinFX')

	local remotes = sharedFolder:FindFirstChild('Remotes')
	if remotes then
		mc.Action = remotes:FindFirstChild('Action')
		mc.State = remotes:FindFirstChild('State')
	end

	if mc.Config and mc.Config.BLOCK then
		BLOCK = mc.Config.BLOCK
	end
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

-- Outgoing payloads go through one wrapper as well, so several modules can
-- rewrite the same packet without fighting over the Net.send reference.
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
	local AimAssist
	local Targets
	local Mode
	local Part
	local FOV
	local Speed
	local CircleColor
	local CircleTransparency
	local CircleFilled
	local CircleObject
	local RightClick
	local KeyToggle
	local Key
	local ShowTarget
	local moveConst = Vector2.new(1, 0.77) * math.rad(0.5)
	
	local function wrapAngle(num)
		return ((num + math.pi) % math.tau) - math.pi
	end
	
	AimAssist = vape.Categories.Combat:CreateModule({
		Name = 'AimAssist',
		Function = function(callback)
			if CircleObject then
				CircleObject.Visible = callback
			end
	
			if callback then
				local entity
				local rightClicked = inputService:IsMouseButtonPressed(1)
				local pressed = false
	
				AimAssist:Clean(runService.RenderStepped:Connect(function(dt)
					if CircleObject then
						CircleObject.Position = inputService:GetMouseLocation()
					end
	
					if not vape.gui.ScaledGui.ClickGui.Visible and inputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
						if RightClick.Enabled and not rightClicked then
							return
						end
	
						if KeyToggle.Enabled and not pressed then
							return
						end
	
						entity = entitylib['Entity'..Mode.Value]({
							Range = FOV.Value,
							Part = Part.Value,
							Players = Targets.Players.Enabled,
							NPCs = Targets.NPCs.Enabled,
							Wallcheck = Targets.Walls.Enabled,
							Origin = Mode.Value == 'Mouse' and gameCamera.CFrame.Position or nil
						})
	
						if entity then
							local facing = gameCamera.CFrame.LookVector
							local new = CFrame.lookAt(gameCamera.CFrame.Position, entity[Part.Value].Position).LookVector
	
							if ShowTarget.Enabled then
								targetinfo.Targets[entity] = os.clock() + 1
							end
	
							if new ~= Vector3.zero then
								local diffYaw = wrapAngle(math.atan2(facing.X, facing.Z) - wrapAngle(math.atan2(new.X, new.Z)))
								local diffPitch = math.asin(facing.Y) - math.asin(new.Y)
								local angle = Vector2.new(diffYaw, diffPitch) // (moveConst * UserSettings():GetService('UserGameSettings').MouseSensitivity)
	
								angle *= math.min(Speed.Value * dt, 1)
								mousemoverel(angle.X, angle.Y)
							end
						end
					end
				end))
	
				AimAssist:Clean(Key.Triggered:Connect(function(isDown)
					pressed = KeyToggle.Enabled and isDown
				end))
	
				AimAssist:Clean(inputService.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton2 then
						rightClicked = true
					end
				end))
	
				AimAssist:Clean(inputService.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton2 then
						rightClicked = false
					end
				end))
			end
		end,
		Tooltip = 'Smoothly aims to closest valid target'
	})
	Targets = AimAssist:CreateTargets({
		Players = true
	})
	Mode = AimAssist:CreateDropdown({
		Name = 'Mode',
		List = {'Mouse', 'Position'}
	})
	Part = AimAssist:CreateDropdown({
		Name = 'Part',
		List = {'RootPart', 'Head'}
	})
	FOV = AimAssist:CreateSlider({
		Name = 'FOV',
		Min = 0,
		Max = 1000,
		Default = 100,
		Function = function(val)
			if CircleObject then
				CircleObject.Radius = val
			end
		end
	})
	Speed = AimAssist:CreateSlider({
		Name = 'Speed',
		Min = 0,
		Max = 30,
		Default = 15
	})
	AimAssist:CreateToggle({
		Name = 'Range Circle',
		Function = function(callback)
			if callback then
				CircleObject = Drawing.new('Circle')
				CircleObject.Filled = CircleFilled.Enabled
				CircleObject.Color = Color3.fromHSV(CircleColor.Hue, CircleColor.Sat, CircleColor.Value)
				CircleObject.Position = vape.gui.AbsoluteSize / 2
				CircleObject.Radius = FOV.Value
				CircleObject.NumSides = 100
				CircleObject.Transparency = 1 - CircleTransparency.Value
				CircleObject.Visible = AimAssist.Enabled
			else
				pcall(function()
					CircleObject.Visible = false
					CircleObject:Remove()
				end)
			end
			CircleColor.Object.Visible = callback
			CircleTransparency.Object.Visible = callback
			CircleFilled.Object.Visible = callback
		end
	})
	CircleColor = AimAssist:CreateColorSlider({
		Name = 'Circle Color',
		Function = function(hue, sat, val)
			if CircleObject then
				CircleObject.Color = Color3.fromHSV(hue, sat, val)
			end
		end,
		Darker = true,
		Visible = false
	})
	CircleTransparency = AimAssist:CreateSlider({
		Name = 'Transparency',
		Min = 0,
		Max = 1,
		Decimal = 10,
		Default = 0.5,
		Function = function(val)
			if CircleObject then
				CircleObject.Transparency = 1 - val
			end
		end,
		Darker = true,
		Visible = false
	})
	CircleFilled = AimAssist:CreateToggle({
		Name = 'Circle Filled',
		Function = function(callback)
			if CircleObject then
				CircleObject.Filled = callback
			end
		end,
		Darker = true,
		Visible = false
	})
	RightClick = AimAssist:CreateToggle({
		Name = 'Require right click',
		Tooltip = 'Only activate when holding down right click'
	})
	KeyToggle = AimAssist:CreateToggle({
		Name = 'Require key',
		Function = function(callback)
			Key.Object.Visible = callback
		end,
		Tooltip = 'Only activate when holding down a certain key'
	})
	Key = AimAssist:CreateBind({
		Name = 'Hold Key',
		Default = {'G'},
		Hold = true,
		Darker = true,
		Visible = false
	})
	ShowTarget = AimAssist:CreateToggle({
		Name = 'Show target info'
	})
	
end)

run(function()
	local AutoClicker
	local CPS
	local Swing
	local Thread
	
	local function AutoClick()
		if Thread then
			task.cancel(Thread)
		end
	
		Thread = task.spawn(function()
			repeat
				local hands = mc.Hands
				if hands and not hands.using then
					local target = mc.Controller and mc.Controller.target
					if target then
						pcall(function()
							hands.attack(target)
						end)
					elseif Swing.Enabled then
						pcall(function()
							hands.swing = os.clock()
						end)
					end
				end
	
				task.wait(1 / CPS.GetRandomValue())
			until not AutoClicker.Enabled
		end)
	end
	
	AutoClicker = vape.Categories.Combat:CreateModule({
		Name = 'AutoClicker',
		Function = function(callback)
			if callback then
				AutoClicker:Clean(inputService.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						AutoClick()
					end
				end))
	
				AutoClicker:Clean(inputService.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						if Thread then
							task.cancel(Thread)
							Thread = nil
						end
					end
				end))
			else
				if Thread then
					task.cancel(Thread)
					Thread = nil
				end
			end
		end,
		Tooltip = 'Hold attack to automatically click'
	})
	CPS = AutoClicker:CreateTwoSlider({
		Name = 'CPS',
		Min = 1,
		Max = 20,
		DefaultMin = 8,
		DefaultMax = 12
	})
	Swing = AutoClicker:CreateToggle({
		Name = 'Swing when idle',
		Tooltip = 'Swings even when no target is in range'
	})
	
end)

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
	local Criticals
	local OnlyFalling
	
	Criticals = vape.Categories.Combat:CreateModule({
		Name = 'Criticals',
		Function = function(callback)
			if callback then
				Criticals:Clean(runService.Heartbeat:Connect(function()
					if not entitylib.isAlive then return end
					local controller = mc.Controller
					if not controller or not controller.state then return end
					local state = controller.state
	
					if OnlyFalling.Enabled and state.onGround then return end
					if state.vel and state.vel.Y > -0.1 and not state.onGround then return end
					Criticals.falling = true
				end))
			end
		end,
		Tooltip = 'Keeps your attacks counted as critical hits',
	})
	OnlyFalling = Criticals:CreateToggle({
		Name = 'Only falling'
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

				-- Hold the swing back while the target is still outside the reach
				-- envelope we would actually connect at.
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
	local Killaura
	local Targets
	local Sort
	local Range
	local AngleSlider
	local MaxTargets
	local Mouse
	local GUI
	local BoxAttackColor
	local Face
	local AttackDelay = 0
	local Boxes = {}
	
	local sortmethods = {
		Distance = function(origin, entity)
			return (entity.RootPart.Position - origin).Magnitude
		end,
		Health = function(_, entity)
			return entity.Health
		end,
		Angle = function(origin, entity, facing)
			local delta = (entity.RootPart.Position - origin) * Vector3.new(1, 0, 1)
			return math.acos(facing:Dot(delta.Unit))
		end
	}
	
	local function collectTargets(facing)
		local selfpos = entitylib.character.RootPart.Position
		local list = {}
	
		for _, entity in entitylib.List do
			if not entity.Targetable then continue end
			if not Targets.Players.Enabled and entity.Player then continue end
			if not Targets.NPCs.Enabled and entity.NPC then continue end
	
			local delta = entity.RootPart.Position - selfpos
			if delta.Magnitude > Range.Value then continue end
			if Targets.Walls.Enabled and entitylib.Wallcheck(selfpos, entity.RootPart.Position) then continue end
	
			local angle = math.acos(facing:Dot((delta * Vector3.new(1, 0, 1)).Unit))
			if angle > (math.rad(AngleSlider.Value) / 2) then continue end
	
			table.insert(list, entity)
		end
	
		local method = sortmethods[Sort.Value]
		if method then
			table.sort(list, function(a, b)
				return method(selfpos, a, facing) < method(selfpos, b, facing)
			end)
		end
	
		while #list > MaxTargets.Value do
			table.remove(list)
		end
	
		return list
	end
	
	Killaura = vape.Categories.Combat:CreateModule({
		Name = 'Killaura',
		Function = function(callback)
			if callback then
				repeat
					local attacked = {}
					local hands, controller = mc.Hands, mc.Controller
	
					if entitylib.isAlive and hands and controller and not hands.using then
						local pressed = not Mouse.Enabled or inputService:IsMouseButtonPressed(0)
						local blocked = GUI.Enabled and controller.locked
	
						if pressed and not blocked then
							local facing = entitylib.character.RootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
							local targets = collectTargets(facing)
	
							if #targets > 0 then
								table.insert(attacked, {Entity = targets[1], Check = BoxAttackColor})
								targetinfo.Targets[targets[1]] = os.clock() + 1
	
								if AttackDelay < tick() then
									AttackDelay = tick() + 0.11
									if vape.ThreadFix then
										setthreadidentity(8)
									end
	
									pcall(function()
										hands.attack(targets[1])
									end)
	
									if Face.Enabled then
										local pos = targets[1].RootPart.Position * Vector3.new(1, 0, 1)
										entitylib.character.RootPart.CFrame = CFrame.lookAt(entitylib.character.RootPart.Position, Vector3.new(pos.X, entitylib.character.RootPart.Position.Y + 0.001, pos.Z))
									end
								end
							end
						end
					end
	
					for index, box in Boxes do
						box.Adornee = attacked[index] and attacked[index].Entity.RootPart or nil
						if box.Adornee then
							box.Color3 = Color3.fromHSV(attacked[index].Check.Hue, attacked[index].Check.Sat, attacked[index].Check.Value)
							box.Transparency = 1 - attacked[index].Check.Opacity
						end
					end
	
					task.wait(#attacked > 0 and #attacked * 0.05 or 0.016)
				until not Killaura.Enabled
			else
				for _, box in Boxes do
					box.Adornee = nil
				end
			end
		end,
		Tooltip = 'Attack players around you\nwithout aiming at them.'
	})
	Targets = Killaura:CreateTargets({
		Players = true,
		NPCs = true
	})
	Range = Killaura:CreateSlider({
		Name = 'Attack range',
		Min = 1,
		Max = 8,
		Default = 4.5,
		Decimal = 10,
		Suffix = function(val)
			return val == 1 and 'block' or 'blocks'
		end
	})
	AngleSlider = Killaura:CreateSlider({
		Name = 'Max angle',
		Min = 1,
		Max = 360,
		Default = 360
	})
	MaxTargets = Killaura:CreateSlider({
		Name = 'Max targets',
		Min = 1,
		Max = 5,
		Default = 1
	})
	Sort = Killaura:CreateDropdown({
		Name = 'Target Mode',
		List = {'Distance', 'Health', 'Angle'}
	})
	Mouse = Killaura:CreateToggle({Name = 'Require mouse down'})
	GUI = Killaura:CreateToggle({Name = 'GUI check'})
	Face = Killaura:CreateToggle({Name = 'Face target'})
	Killaura:CreateToggle({
		Name = 'Show target',
		Function = function(callback)
			BoxAttackColor.Object.Visible = callback
			if callback then
				for index = 1, 5 do
					local box = Instance.new('BoxHandleAdornment')
					box.Adornee = nil
					box.AlwaysOnTop = true
					box.Size = Vector3.new(3, 5, 3)
					box.CFrame = CFrame.new(0, -0.5, 0)
					box.ZIndex = 0
					box.Parent = vape.holder
					Boxes[index] = box
				end
			else
				for _, box in Boxes do
					box:Destroy()
				end
				table.clear(Boxes)
			end
		end
	})
	BoxAttackColor = Killaura:CreateColorSlider({
		Name = 'Attack Color',
		Darker = true,
		DefaultOpacity = 0.5,
		Visible = false
	})
	
end)

run(function()
	local Reach
	local Value
	
	Reach = vape.Categories.Combat:CreateModule({
		Name = 'Reach',
		Function = function(callback)
			if not (mc.Controller and mc.Controller.state) then return end
			local base = (mc.Items and mc.Items.SWORD_REACH) or 3.0
			mc.Controller.reach = callback and (base + Value.Value) or base
		end,
		Tooltip = 'Extends melee attack reach'
	})
	Value = Reach:CreateSlider({
		Name = 'Range',
		Min = 0,
		Max = 4,
		Default = 2,
		Decimal = 10,
		Function = function(val)
			if Reach.Enabled and mc.Controller then
				local base = (mc.Items and mc.Items.SWORD_REACH) or 3.0
				mc.Controller.reach = base + val
			end
		end,
		Suffix = function(val)
			return val == 1 and 'block' or 'blocks'
		end
	})
	
end)

run(function()
	local ShieldBreaker

	ShieldBreaker = vape.Categories.Combat:CreateModule({
		Name = 'ShieldBreaker',
		Function = function(callback)
			if not callback then return end

			local hook = function(payload)
				-- The server drops the shield check when an attack is flagged as a
				-- swap, which is what an axe hit looks like from its side.
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

		-- The angle slider is the half angle of the cone we are willing to fire into.
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

		-- Compensate the arc the projectile falls through over its flight time.
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
	local TriggerBot
	local Range
	local Strength
	local Crosshair
	local Delay = 0
	
	TriggerBot = vape.Categories.Combat:CreateModule({
		Name = 'TriggerBot',
		Function = function(callback)
			if callback then
				TriggerBot:Clean(runService.Heartbeat:Connect(function()
					if not entitylib.isAlive or Delay > os.clock() then return end
					local hands, controller = mc.Hands, mc.Controller
					if not hands or not controller or hands.using then return end
	
					local best
					local eye = entitylib.character.RootPart.Position
					local facing = workspace.CurrentCamera.CFrame.LookVector
	
					for _, entity in entitylib.List do
						if not entity.Targetable then continue end
						local delta = entity.RootPart.Position - eye
						if delta.Magnitude > Range.Value then continue end
	
						local dot = facing:Dot(delta.Unit)
						if Crosshair.Enabled and dot < 0.995 then continue end
						if not best or delta.Magnitude < (best.RootPart.Position - eye).Magnitude then
							best = entity
						end
					end
	
					if best and hands.strength and hands.strength() >= Strength.Value then
						Delay = os.clock() + 0.05
						pcall(function()
							hands.attack(best)
						end)
					end
				end))
			end
		end,
		Tooltip = 'Attacks the entity under your crosshair'
	})
	Range = TriggerBot:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 8,
		Default = 4.5,
		Decimal = 10,
		Suffix = function(val)
			return val == 1 and 'block' or 'blocks'
		end
	})
	Strength = TriggerBot:CreateSlider({
		Name = 'Min strength',
		Min = 0.1,
		Max = 1,
		Default = 0.9,
		Decimal = 100,
		Darker = true
	})
	Crosshair = TriggerBot:CreateToggle({
		Name = 'Require crosshair',
		Default = true
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
	local FastFall
	local Speed
	
	FastFall = vape.Categories.Blatant:CreateModule({
		Name = 'FastFall',
		Function = function(callback)
			if callback then
				FastFall:Clean(runService.Heartbeat:Connect(function()
					if not entitylib.isAlive then return end
					local controller = mc.Controller
					if not controller or not controller.state then return end
					local state = controller.state
					if state.onGround or state.gliding or state.inWater then return end
					if not state.vel or state.vel.Y > -0.1 then return end
	
					state.vel = Vector3.new(state.vel.X, math.min(state.vel.Y, -Speed.Value), state.vel.Z)
				end))
			end
		end,
		Tooltip = 'Increases fall speed'
	})
	Speed = FastFall:CreateSlider({
		Name = 'Speed',
		Min = 0.5,
		Max = 10,
		Default = 3,
		Decimal = 10
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

				-- using.start counts engine ticks, so pulling it back by the frame
				-- delta advances the consume timer at the chosen rate.
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
	local KeepSprint
	
	KeepSprint = vape.Categories.Blatant:CreateModule({
		Name = 'KeepSprint',
		Function = function(callback)
			if callback then
				KeepSprint:Clean(runService.Heartbeat:Connect(function()
					if not entitylib.isAlive then return end
					local controller = mc.Controller
					if not controller or not controller.state then return end
	
					if not controller.state.sprinting then
						controller.state.sprinting = true
					end
				end))
			end
		end,
		Tooltip = 'Keeps sprint applied while attacking'
	})
	
end)

run(function()
	local NoFall
	local LastTick = 0
	
	NoFall = vape.Categories.Blatant:CreateModule({
		Name = 'NoFall',
		Function = function(callback)
			if callback then
				NoFall:Clean(runService.Heartbeat:Connect(function()
					if not entitylib.isAlive then return end
					local controller = mc.Controller
					if not controller or not controller.state then return end
					local state = controller.state
					if os.clock() - LastTick < 0.1 then return end
	
					LastTick = os.clock()
					if state.fallDistance then
						state.fallDistance = 0
					end
				end))
			end
		end,
		Tooltip = 'Prevents fall damage'
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
	local NoSlowdown
	local Sneak
	local UseItem
	local Web
	local OldMultiplier
	
	NoSlowdown = vape.Categories.Blatant:CreateModule({
		Name = 'NoSlowdown',
		Function = function(callback)
			frictionTable.NoSlowdown = callback or nil
			updateVelocity()
	
			local controller = mc.Controller
			if not controller then return end
	
			if callback then
				OldMultiplier = controller.useSpeedMultiplier
				controller.useSpeedMultiplier = function()
					return 1
				end
	
				NoSlowdown:Clean(runService.Heartbeat:Connect(function()
					if not entitylib.isAlive then return end
					local state = controller.state
					if not state then return end
	
					if Sneak.Enabled and state.sneaking then
						state.sneaking = false
					end
	
					if UseItem.Enabled and state.usingItem then
						state.slowMultiplier = 1
					end
				end))
			else
				if OldMultiplier then
					controller.useSpeedMultiplier = OldMultiplier
					OldMultiplier = nil
				end
			end
		end,
		Tooltip = 'Removes movement slowdown from using items'
	})
	Sneak = NoSlowdown:CreateToggle({
		Name = 'Sneak',
		Default = true
	})
	UseItem = NoSlowdown:CreateToggle({
		Name = 'Use item',
		Default = true
	})
	Web = NoSlowdown:CreateToggle({
		Name = 'Cobweb',
		Default = true
	})
	
end)

run(function()
	local Velocity
	local Horizontal
	local Vertical
	
	Velocity = vape.Categories.Blatant:CreateModule({
		Name = 'Velocity',
		Function = function(callback)
			if callback then
				Velocity:Clean(runService.Heartbeat:Connect(function()
					if not entitylib.isAlive then return end
					local controller = mc.Controller
					if not controller or not controller.state then return end
					local state = controller.state
	
					local vel = state.knockback
					if not vel then return end
	
					state.knockback = Vector3.new(
						vel.X * Horizontal.Value,
						vel.Y * Vertical.Value,
						vel.Z * Horizontal.Value
					)
				end))
			end
		end,
		Tooltip = 'Reduces knockback taken'
	})
	Horizontal = Velocity:CreateSlider({
		Name = 'Horizontal',
		Min = 0,
		Max = 1,
		Default = 0,
		Decimal = 100
	})
	Vertical = Velocity:CreateSlider({
		Name = 'Vertical',
		Min = 0,
		Max = 1,
		Default = 0,
		Decimal = 100
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
	local NameTags
	local Targets
	local Color
	local Background
	local Health
	local Distance
	local Teammates
	local Reference = {}
	local Folder = Instance.new('Folder')
	Folder.Parent = vape.gui
	
	local function build(entity)
		local tag = Instance.new('BillboardGui')
		tag.Name = 'VapeNameTag'
		tag.Size = UDim2.fromOffset(180, 40)
		tag.StudsOffset = Vector3.new(0, 2.1, 0)
		tag.AlwaysOnTop = true
		tag.LightInfluence = 0
		tag.Adornee = entity.Head
		tag.Parent = entity.Character
	
		local frame = Instance.new('Frame')
		frame.BackgroundColor3 = Color3.new()
		frame.BackgroundTransparency = 1 - Background.Value
		frame.BorderSizePixel = 0
		frame.Size = UDim2.fromOffset(160, 32)
		frame.AnchorPoint = Vector2.new(0.5, 1)
		frame.Position = UDim2.new(0.5, 0, 1, 0)
		frame.Parent = tag
	
		local name = Instance.new('TextLabel')
		name.BackgroundTransparency = 1
		name.TextSize = 12
		name.TextColor3 = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
		name.TextStrokeTransparency = 0
		name.TextStrokeColor3 = Color3.new()
		name.Size = UDim2.new(1, -4, 0, 14)
		name.Position = UDim2.new(0, 2, 0, 1)
		name.Text = ''
		name.Parent = frame
	
		local hpBg = Instance.new('Frame')
		hpBg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
		hpBg.BorderSizePixel = 0
		hpBg.Size = UDim2.new(1, -4, 0, 4)
		hpBg.Position = UDim2.new(0, 2, 0, 17)
		hpBg.Parent = frame
	
		local hpFill = Instance.new('Frame')
		hpFill.BorderSizePixel = 0
		hpFill.Size = UDim2.new(1, 0, 1, 0)
		hpFill.Parent = hpBg
	
		local info = Instance.new('TextLabel')
		info.BackgroundTransparency = 1
		info.TextSize = 9
		info.TextColor3 = Color3.fromRGB(200, 200, 200)
		info.TextStrokeTransparency = 0
		info.TextStrokeColor3 = Color3.new()
		info.Size = UDim2.new(1, -4, 0, 10)
		info.Position = UDim2.new(0, 2, 0, 22)
		info.Text = ''
		info.Parent = frame
	
		Reference[entity] = {gui = tag, name = name, hpBg = hpBg, hpFill = hpFill, info = info, frame = frame}
	end
	
	local function remove(entity)
		local tag = Reference[entity]
		if tag then
			tag.gui:Destroy()
			Reference[entity] = nil
		end
	end
	
	NameTags = vape.Categories.Render:CreateModule({
		Name = 'NameTags',
		Function = function(callback)
			if callback then
				NameTags:Clean(entitylib.Events.EntityRemoved:Connect(remove))
				NameTags:Clean(entitylib.Events.EntityAdded:Connect(function(entity)
					if Reference[entity] then remove(entity) end
					if Teammates.Enabled and (not entity.Targetable) and (not entity.Friend) then return end
					build(entity)
				end))
				NameTags:Clean(runService.Heartbeat:Connect(function()
					if not entitylib.isAlive then return end
					local origin = entitylib.character.RootPart.Position
	
					for entity, tag in Reference do
						if not entity.Character.Parent then
							remove(entity)
							continue
						end
	
						local pct = math.clamp(entity.Health / math.max(entity.MaxHealth, 1), 0, 1)
						tag.name.Text = entity.Player and entity.Player.DisplayName or entity.Character.Name
						tag.name.TextColor3 = entitylib.getEntityColor(entity) or Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
	
						if Health.Enabled then
							tag.hpBg.Visible = true
							tag.hpFill.Size = UDim2.new(pct, 0, 1, 0)
							tag.hpFill.BackgroundColor3 = Color3.fromHSV(math.clamp(pct, 0, 1) / 2.5, 0.89, 0.75)
						else
							tag.hpBg.Visible = false
						end
	
						local parts = {}
						if Distance.Enabled then
							table.insert(parts, math.floor((entity.RootPart.Position - origin).Magnitude) .. 'm')
						end
						tag.info.Text = table.concat(parts, ' · ')
						tag.info.Visible = #parts > 0
					end
				end))
	
				for _, entity in entitylib.List do
					if Reference[entity] then remove(entity) end
					if Teammates.Enabled and (not entity.Targetable) and (not entity.Friend) then continue end
					build(entity)
				end
			else
				for entity in Reference do
					remove(entity)
				end
			end
		end,
		Tooltip = 'Renders nametags on entities through walls'
	})
	Targets = NameTags:CreateTargets({
		Players = true,
		Function = function()
			if NameTags.Enabled then
				NameTags:Toggle()
				NameTags:Toggle()
			end
		end
	})
	Color = NameTags:CreateColorSlider({
		Name = 'Player Color',
		DefaultSat = 0
	})
	Background = NameTags:CreateSlider({
		Name = 'Transparency',
		Min = 0,
		Max = 1,
		Default = 0.35,
		Decimal = 100
	})
	Health = NameTags:CreateToggle({
		Name = 'Health',
		Default = true
	})
	Distance = NameTags:CreateToggle({
		Name = 'Distance',
		Default = true
	})
	Teammates = NameTags:CreateToggle({
		Name = 'Priority Only',
		Default = true,
		Tooltip = 'Hides teammates & non targetable entities'
	})
	
end)

run(function()
	local Tracers
	local Targets
	local NearColor
	local FarColor
	local Fade
	local FromBottom
	local Range
	local Folder = Instance.new('Folder')
	Folder.Parent = vape.gui
	local Lines = {}
	
	local function getLine()
		for _, line in Lines do
			if not line.Visible then return line end
		end
		local line = Drawing.new('Line')
		line.Thickness = 1
		line.Transparency = 1
		table.insert(Lines, line)
		return line
	end
	
	local function hideAll()
		for _, line in Lines do
			line.Visible = false
		end
	end
	
	Tracers = vape.Categories.Render:CreateModule({
		Name = 'Tracers',
		Function = function(callback)
			if callback then
				Tracers:Clean(runService.RenderStepped:Connect(function()
					hideAll()
					if not entitylib.isAlive or not Drawing then return end
	
					local cam = workspace.CurrentCamera
					local origin = entitylib.character.RootPart.Position
					local screen = cam.ViewportSize
	
					for _, entity in entitylib.List do
						if not entity.Targetable then continue end
						if not Targets.Players.Enabled and entity.Player then continue end
						if not Targets.NPCs.Enabled and entity.NPC then continue end
	
						local distance = (entity.RootPart.Position - origin).Magnitude
						if distance > Range.Value then continue end
	
						local point, visible = cam:WorldToViewportPoint(entity.RootPart.Position)
						if not visible then continue end
	
						local line = getLine()
						if not line then break end
	
						line.Visible = true
						line.From = Vector2.new(screen.X / 2, FromBottom.Enabled and screen.Y or screen.Y / 2)
						line.To = Vector2.new(point.X, point.Y)
	
						local near = Color3.fromHSV(NearColor.Hue, NearColor.Sat, NearColor.Value)
						local far = Color3.fromHSV(FarColor.Hue, FarColor.Sat, FarColor.Value)
						line.Color = Fade.Enabled and near:Lerp(far, math.clamp(distance / Range.Value, 0, 1)) or near
					end
				end))
			else
				hideAll()
			end
		end,
		Tooltip = 'Draws lines from the screen to entities'
	})
	Targets = Tracers:CreateTargets({
		Players = true
	})
	NearColor = Tracers:CreateColorSlider({
		Name = 'Near Color'
	})
	FarColor = Tracers:CreateColorSlider({
		Name = 'Far Color',
		Darker = true
	})
	Fade = Tracers:CreateToggle({
		Name = 'Fade by distance',
		Default = true
	})
	FromBottom = Tracers:CreateToggle({
		Name = 'From bottom',
		Default = true
	})
	Range = Tracers:CreateSlider({
		Name = 'Range',
		Min = 16,
		Max = 500,
		Default = 128
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


run(function()
	local HitSound
	local SoundId
	local Volume
	local Pitch
	local Player
	
	local function build()
		if Player then return end
		Player = Instance.new('Sound')
		Player.Volume = Volume.Value
		Player.PlaybackSpeed = Pitch.Value
		Player.SoundId = SoundId.Value
		Player.Parent = vape.holder
	end
	
	HitSound = vape.Categories.Legit:CreateModule({
		Name = 'HitSound',
		Function = function(callback)
			if callback then
				build()
				HitSound:Clean(Player)
			else
				if Player then
					Player:Destroy()
					Player = nil
				end
			end
		end,
		Tooltip = 'Plays a sound when you hit an entity'
	})
	SoundId = HitSound:CreateTextBox({
		Name = 'Sound',
		Default = 'rbxassetid://131847726193504',
		Function = function(value)
			if Player then
				Player.SoundId = value
			end
		end,
		Darker = true
	})
	Volume = HitSound:CreateSlider({
		Name = 'Volume',
		Min = 0,
		Max = 5,
		Default = 1,
		Decimal = 10,
		Function = function(value)
			if Player then Player.Volume = value end
		end,
		Darker = true
	})
	Pitch = HitSound:CreateSlider({
		Name = 'Pitch',
		Min = 0.5,
		Max = 2,
		Default = 1,
		Decimal = 100,
		Function = function(value)
			if Player then Player.PlaybackSpeed = value end
		end,
		Darker = true
	})
	HitSound.Play = function()
		if HitSound.Enabled and Player then
			Player:Play()
		end
	end
	
end)

run(function()
	local SkinChanger
	local Skin
	
	local lastApply = 0
	local original = {}
	local parts = {'Skin_head', 'Skin_body', 'Skin_arm_r', 'Skin_arm_l', 'Skin_leg_r', 'Skin_leg_l'}
	
	local function getSkinNames()
		local names = {}
		local skins = mc.Skins
	
		if type(skins) == 'table' then
			for name, entry in skins do
				if type(entry) == 'table' and entry.tex then
					table.insert(names, name)
				end
			end
		end
	
		if #names == 0 then
			table.insert(names, 'STEVE')
		end
	
		table.sort(names)
		return names
	end
	
	local function paintPart(part, texture)
		if not part then return end
	
		if not original[part] then
			original[part] = {
				textureId = part:IsA('MeshPart') and part.TextureID or nil,
				decal = part:FindFirstChildOfClass('Decal') or part:FindFirstChildOfClass('Texture')
			}
		end
	
		if part:IsA('MeshPart') then
			part.TextureID = texture
			return
		end
	
		local decal = part:FindFirstChild('SkinOverride')
		if not decal then
			decal = Instance.new('Decal')
			decal.Name = 'SkinOverride'
			decal.Face = Enum.NormalId.Front
			decal.Parent = part
		end
		decal.Texture = texture
	end
	
	local function restore()
		local character = lplr.Character
		if not character then
			table.clear(original)
			return
		end
	
		for part, values in original do
			if part.Parent then
				pcall(function()
					if values.textureId and part:IsA('MeshPart') then
						part.TextureID = values.textureId
					end
	
					local decal = part:FindFirstChild('SkinOverride')
					if decal then
						decal:Destroy()
					end
	
					if values.decal and values.decal.Parent then
						values.decal.Texture = values.decal.Texture
					end
				end)
			end
		end
	
		table.clear(original)
	end
	
	local function apply(skinName)
		local entry = mc.Skins and mc.Skins[skinName]
		if type(entry) ~= 'table' or not entry.tex then return end
	
		local character = lplr.Character
		if not character then return end
	
		for _, name in parts do
			local part = character:FindFirstChild(name, true)
			if part then
				paintPart(part, entry.tex)
			end
		end
	
		for _, descendant in character:GetDescendants() do
			if descendant.Name == 'SkinOverride' and descendant:IsA('Decal') then
				descendant.Texture = entry.tex
			end
		end
	end
	
	SkinChanger = vape.Categories.Legit:CreateModule({
		Name = 'SkinChanger',
		Function = function(callback)
			if not callback then
				restore()
				return
			end
	
			lastApply = 0
			SkinChanger:Clean(lplr.CharacterAdded:Connect(function()
				task.wait(0.5)
				if SkinChanger.Enabled then
					table.clear(original)
					lastApply = 0
				end
			end))
	
			SkinChanger:Clean(runService.Heartbeat:Connect(function()
				if os.clock() - lastApply < 0.5 then return end
				lastApply = os.clock()
				apply(Skin.Value)
			end))
		end,
		Tooltip = 'Applies a client side skin to your character'
	})
	Skin = SkinChanger:CreateDropdown({
		Name = 'Skin',
		List = getSkinNames(),
		Function = function()
			table.clear(original)
			lastApply = 0
		end
	})
	
end)