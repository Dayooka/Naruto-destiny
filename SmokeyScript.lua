local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local updateStatus
local getChakraValues
local getChakraData
local getHealthRatio
local getChakraRatio
local useHealthRefillInternal

-- ======= CONFIGURATION =======
local CONFIG = {
	AutofarmActive = false,
	TargetNPCs = {},
	MoveMode = "Teleport",
	AutoAbility = true,
	AntiAFK = true,
	SearchRadius = 5000,
	ActionCooldown = 0.1,
	ReturnDelay = 2,
	HealthTeleportCFrame = CFrame.new(-1687.72339, 2370.01538, 830.461548, -0.094668448, -9.03159574e-08, 0.99550885, -4.07600531e-08, 1, 8.6847308e-08, -0.99550885, -3.23552953e-08, -0.094668448),
	HealthEnabled = false,
	AutoHealthThreshold = 0.3,
	AutoChakraThreshold = 0.2,
	LowChakraThreshold = 0.15,
	MinAbilityChakraRatio = 0.2,
	HealthButtonCooldown = 2,
	TeleportOffset = Vector3.new(0, 6, 0),
	HealDuration = 5,                       -- ennyi ideig marad a spawnnál gyógyulni
	MaxTeleportDistance = 1000,             -- ennél messzebb lévő NPC-hez sétál, hogy betöltődjön
	HealDuringCombat = false                -- ha true, harc közben is elteleportál gyógyulni (kísérleti, a játék mechanikájától függ)
}

local myTurn = false
local availableNPCs = {}
local scriptRunning = true
local allConnections = {}
local savedReturnCFrame = nil
local lastCombatState = false
local fightStartedAt = 0
local abilityCooldownMemory = {}
local healthActionBusy = false
local lastHealthUse = 0
local returnTaskId = 0
local autofarmPausedForHealth = false

-- Remotes
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
local turnEvent = remoteEvents and remoteEvents:WaitForChild("TurnEvent", 5)
local combatRemoteEvent = remoteEvents and remoteEvents:WaitForChild("CombatRemoteEvent", 5)

-- ======= NPC SCANNER =======
local function scanNPCNames()
	local names = {}
	local npcsFolder = Workspace:FindFirstChild("NPCs")
	if npcsFolder then
		for _, npc in ipairs(npcsFolder:GetChildren()) do
			if npc:IsA("Model") and npc:GetAttribute("IsNPC") == true then
				if not table.find(names, npc.Name) then
					table.insert(names, npc.Name)
				end
			end
		end
	end
	table.sort(names)
	availableNPCs = names
end

-- ======= UI SYSTEM =======
local uiElements = {}
local isDragging = false
local dragInput = nil
local dragStart = nil
local startPos = nil

updateStatus = function(text)
	if uiElements.StatusLabel then
		uiElements.StatusLabel.Text = "Status: " .. tostring(text)
	end
end

getChakraValues = function()
	local data = player:FindFirstChild("Data")
	local stats = data and data:FindFirstChild("Stats")
	local mana = stats and stats:FindFirstChild("Mana")
	local maxMana = stats and stats:FindFirstChild("MaxMana")
	local currentChakra = (mana and mana.Value) or 0
	local maxChakra = (maxMana and maxMana.Value) or 100
	return currentChakra, maxChakra, mana, maxMana
end

getChakraData = function()
	local current, max = getChakraValues()
	return current, max
end

getHealthRatio = function()
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.MaxHealth <= 0 then
		return 1
	end
	return humanoid.Health / humanoid.MaxHealth
end

getChakraRatio = function()
	local currentChakra, maxChakra = getChakraData()
	if maxChakra <= 0 then
		return 1
	end
	return currentChakra / maxChakra
end

local function createGUI()
	local targetParent = (type(gethui) == "function" and gethui()) or game:GetService("CoreGui") or player:WaitForChild("PlayerGui")

	local existing = targetParent:FindFirstChild("GlassFarmPro")
	if existing then existing:Destroy() end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "GlassFarmPro"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 999 
	screenGui.Parent = targetParent

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 300, 0, 480)
	frame.Position = UDim2.new(0, 30, 0.5, -240)
	frame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 16)

	local stroke = Instance.new("UIStroke", frame)
	stroke.Color = Color3.fromRGB(100, 200, 255)
	stroke.Transparency = 0.3
	stroke.Thickness = 2

	-- ======= TITLEBAR =======
	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 50)
	titleBar.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	titleBar.BackgroundTransparency = 0
	titleBar.BorderSizePixel = 0
	titleBar.Parent = frame
	Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 16)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -80, 1, 0)
	title.BackgroundTransparency = 1
	title.Text = "AUTOFARM PRO"
	title.TextColor3 = Color3.fromRGB(100, 200, 255)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 16
	title.Parent = titleBar

	-- Hide Button
	local hideBtn = Instance.new("TextButton")
	hideBtn.Size = UDim2.new(0, 30, 0, 30)
	hideBtn.Position = UDim2.new(1, -70, 0.5, -15)
	hideBtn.BackgroundColor3 = Color3.fromRGB(100, 150, 200)
	hideBtn.BackgroundTransparency = 0.4
	hideBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	hideBtn.Font = Enum.Font.GothamBold
	hideBtn.TextSize = 14
	hideBtn.Text = "-"
	hideBtn.Parent = titleBar
	Instance.new("UICorner", hideBtn).CornerRadius = UDim.new(0, 6)

	-- Close Button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 30, 0, 30)
	closeBtn.Position = UDim2.new(1, -35, 0.5, -15)
	closeBtn.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
	closeBtn.BackgroundTransparency = 0.4
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.Text = "X"
	closeBtn.Parent = titleBar
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(0.9, 0, 0, 1)
	divider.Position = UDim2.new(0.05, 0, 0, 50)
	divider.BackgroundColor3 = Color3.fromRGB(100, 200, 255)
	divider.BackgroundTransparency = 0.5
	divider.BorderSizePixel = 0
	divider.Parent = frame

	-- ======= SCROLLING CONTENT =======
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Size = UDim2.new(1, -20, 1, -180)
	scrollFrame.Position = UDim2.new(0, 10, 0, 60)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 3
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 200, 255)
	scrollFrame.Parent = frame

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = scrollFrame

	local padding = Instance.new("UIPadding", scrollFrame)
	padding.PaddingLeft = UDim.new(0, 5)
	padding.PaddingRight = UDim.new(0, 5)

	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y)
	end)

	local function createButton(text, callback)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, -10, 0, 35)
		btn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
		btn.BackgroundTransparency = 0.4
		btn.TextColor3 = Color3.fromRGB(200, 220, 255)
		btn.Font = Enum.Font.GothamSemibold
		btn.TextSize = 12
		btn.Text = text
		btn.Parent = scrollFrame
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

		local btnStroke = Instance.new("UIStroke", btn)
		btnStroke.Color = Color3.fromRGB(100, 200, 255)
		btnStroke.Transparency = 0.6
		btnStroke.Thickness = 1

		btn.MouseButton1Click:Connect(function()
			local result = callback()
			if typeof(result) == "string" and result ~= "" then
				btn.Text = result
			end
		end)
		return btn
	end

	local function createToggle(text, configKey)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, -10, 0, 35)
		btn.BackgroundColor3 = CONFIG[configKey] and Color3.fromRGB(80, 200, 100) or Color3.fromRGB(50, 50, 70)
		btn.BackgroundTransparency = CONFIG[configKey] and 0.3 or 0.4
		btn.TextColor3 = Color3.fromRGB(200, 220, 255)
		btn.Font = Enum.Font.GothamSemibold
		btn.TextSize = 12
		btn.Text = text .. ": " .. (CONFIG[configKey] and "ON" or "OFF")
		btn.Parent = scrollFrame
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

		local btnStroke = Instance.new("UIStroke", btn)
		btnStroke.Color = Color3.fromRGB(100, 200, 255)
		btnStroke.Transparency = 0.6
		btnStroke.Thickness = 1

		btn.MouseButton1Click:Connect(function()
			CONFIG[configKey] = not CONFIG[configKey]
			TweenService:Create(btn, TweenInfo.new(0.25), {
				BackgroundColor3 = CONFIG[configKey] and Color3.fromRGB(80, 200, 100) or Color3.fromRGB(50, 50, 70),
				BackgroundTransparency = CONFIG[configKey] and 0.3 or 0.4
			}):Play()
			btn.Text = text .. ": " .. (CONFIG[configKey] and "ON" or "OFF")
		end)
		return btn
	end

	-- Target Selection Label
	local targetLabel = Instance.new("TextLabel")
	targetLabel.Size = UDim2.new(1, -10, 0, 25)
	targetLabel.BackgroundTransparency = 1
	targetLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
	targetLabel.Font = Enum.Font.GothamMedium
	targetLabel.TextSize = 11
	targetLabel.Text = "Targets: None Selected"
	targetLabel.TextXAlignment = Enum.TextXAlignment.Left
	targetLabel.Parent = scrollFrame
	uiElements.TargetLabel = targetLabel

	-- Multi-Target Selection Button
	createButton("Select Targets", function()
		scanNPCNames()
		uiElements.ShowTargetMenu()
		return "Select Targets"
	end)

	createButton("Movement: " .. CONFIG.MoveMode, function()
		CONFIG.MoveMode = (CONFIG.MoveMode == "Walk") and "Teleport" or "Walk"
		return "Movement: " .. CONFIG.MoveMode
	end)

	createButton("Return Delay: " .. tostring(CONFIG.ReturnDelay) .. "s", function()
		CONFIG.ReturnDelay += 1
		if CONFIG.ReturnDelay > 10 then
			CONFIG.ReturnDelay = 0
		end
		return "Return Delay: " .. tostring(CONFIG.ReturnDelay) .. "s"
	end)

	createToggle("Health Refill", "HealthEnabled")

	createToggle("Heal During Combat", "HealDuringCombat")

	createButton("HP Threshold: " .. tostring(math.floor(CONFIG.AutoHealthThreshold * 100)) .. "%", function()
		CONFIG.AutoHealthThreshold += 0.1
		if CONFIG.AutoHealthThreshold > 0.9 then
			CONFIG.AutoHealthThreshold = 0.1
		end
		return "HP Threshold: " .. tostring(math.floor(CONFIG.AutoHealthThreshold * 100)) .. "%"
	end)

	createButton("Chakra Threshold: " .. tostring(math.floor(CONFIG.AutoChakraThreshold * 100)) .. "%", function()
		CONFIG.AutoChakraThreshold += 0.1
		if CONFIG.AutoChakraThreshold > 0.9 then
			CONFIG.AutoChakraThreshold = 0.1
		end
		return "Chakra Threshold: " .. tostring(math.floor(CONFIG.AutoChakraThreshold * 100)) .. "%"
	end)

	createButton("Use Health Now", function()
		local healthRefillFn = _G.GlassFarmProUseHealthRefill
		if type(healthRefillFn) ~= "function" then
			updateStatus("Health function unavailable")
			return "Use Health Now"
		end

		local ok, message = healthRefillFn()
		if not ok then
			updateStatus(message)
			return "Use Health Now"
		end
		return message
	end)

	createToggle("Use Abilities", "AutoAbility")
	createToggle("Anti AFK", "AntiAFK")

	-- ======= BOTTOM PANEL =======
	local bottomPanel = Instance.new("Frame")
	bottomPanel.Size = UDim2.new(1, 0, 0, 120)
	bottomPanel.Position = UDim2.new(0, 0, 1, -120)
	bottomPanel.BackgroundTransparency = 1
	bottomPanel.Parent = frame

	uiElements.StatusLabel = Instance.new("TextLabel")
	uiElements.StatusLabel.Size = UDim2.new(1, -20, 0, 30)
	uiElements.StatusLabel.Position = UDim2.new(0, 10, 0, 5)
	uiElements.StatusLabel.BackgroundTransparency = 1
	uiElements.StatusLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
	uiElements.StatusLabel.Text = "Status: Idle"
	uiElements.StatusLabel.Font = Enum.Font.GothamMedium
	uiElements.StatusLabel.TextSize = 11
	uiElements.StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	uiElements.StatusLabel.Parent = bottomPanel

	uiElements.ToggleBtn = Instance.new("TextButton")
	uiElements.ToggleBtn.Size = UDim2.new(0.9, 0, 0, 40)
	uiElements.ToggleBtn.Position = UDim2.new(0.05, 0, 0, 40)
	uiElements.ToggleBtn.BackgroundColor3 = Color3.fromRGB(80, 150, 60)
	uiElements.ToggleBtn.BackgroundTransparency = 0.3
	uiElements.ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	uiElements.ToggleBtn.Text = "START AUTOFARM"
	uiElements.ToggleBtn.Font = Enum.Font.GothamBlack
	uiElements.ToggleBtn.TextSize = 13
	uiElements.ToggleBtn.Parent = bottomPanel
	Instance.new("UICorner", uiElements.ToggleBtn).CornerRadius = UDim.new(0, 10)

	-- ======= TARGET SELECTION MENU =======
	local function createTargetMenu()
		local existing = targetParent:FindFirstChild("TargetMenu")
		if existing then existing:Destroy() end

		local menuGui = Instance.new("ScreenGui")
		menuGui.Name = "TargetMenu"
		menuGui.ResetOnSpawn = false
		menuGui.DisplayOrder = 1000
		menuGui.Parent = targetParent

		local menuFrame = Instance.new("Frame")
		menuFrame.Size = UDim2.new(0, 300, 0, 400)
		menuFrame.Position = UDim2.new(0.5, -150, 0.5, -200)
		menuFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
		menuFrame.BackgroundTransparency = 0.05
		menuFrame.BorderSizePixel = 0
		menuFrame.Parent = menuGui
		Instance.new("UICorner", menuFrame).CornerRadius = UDim.new(0, 12)

		local menuStroke = Instance.new("UIStroke", menuFrame)
		menuStroke.Color = Color3.fromRGB(100, 200, 255)
		menuStroke.Transparency = 0.3
		menuStroke.Thickness = 2

		local menuTitle = Instance.new("TextLabel")
		menuTitle.Size = UDim2.new(1, 0, 0, 40)
		menuTitle.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
		menuTitle.BackgroundTransparency = 0
		menuTitle.TextColor3 = Color3.fromRGB(100, 200, 255)
		menuTitle.Font = Enum.Font.GothamBlack
		menuTitle.TextSize = 14
		menuTitle.Text = "SELECT TARGETS"
		menuTitle.BorderSizePixel = 0
		menuTitle.Parent = menuFrame
		Instance.new("UICorner", menuTitle).CornerRadius = UDim.new(0, 12)

		local menuScroll = Instance.new("ScrollingFrame")
		menuScroll.Size = UDim2.new(1, -10, 1, -100)
		menuScroll.Position = UDim2.new(0, 5, 0, 45)
		menuScroll.BackgroundTransparency = 1
		menuScroll.BorderSizePixel = 0
		menuScroll.ScrollBarThickness = 3
		menuScroll.ScrollBarImageColor3 = Color3.fromRGB(100, 200, 255)
		menuScroll.Parent = menuFrame

		local menuLayout = Instance.new("UIListLayout")
		menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
		menuLayout.Padding = UDim.new(0, 5)
		menuLayout.Parent = menuScroll

		local menuPadding = Instance.new("UIPadding", menuScroll)
		menuPadding.PaddingLeft = UDim.new(0, 5)
		menuPadding.PaddingRight = UDim.new(0, 5)

		menuLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			menuScroll.CanvasSize = UDim2.new(0, 0, 0, menuLayout.AbsoluteContentSize.Y)
		end)

		-- Create checkboxes for each NPC
		for _, npcName in ipairs(availableNPCs) do
			local checkboxBtn = Instance.new("TextButton")
			checkboxBtn.Size = UDim2.new(1, -10, 0, 35)
			checkboxBtn.BackgroundColor3 = table.find(CONFIG.TargetNPCs, npcName) and Color3.fromRGB(80, 200, 100) or Color3.fromRGB(50, 50, 70)
			checkboxBtn.BackgroundTransparency = 0.4
			checkboxBtn.TextColor3 = Color3.fromRGB(200, 220, 255)
			checkboxBtn.Font = Enum.Font.GothamSemibold
			checkboxBtn.TextSize = 12
			checkboxBtn.Text = (table.find(CONFIG.TargetNPCs, npcName) and "✓ " or "  ") .. npcName
			checkboxBtn.Parent = menuScroll
			Instance.new("UICorner", checkboxBtn).CornerRadius = UDim.new(0, 6)

			local cbStroke = Instance.new("UIStroke", checkboxBtn)
			cbStroke.Color = Color3.fromRGB(100, 200, 255)
			cbStroke.Transparency = 0.6
			cbStroke.Thickness = 1

			checkboxBtn.MouseButton1Click:Connect(function()
				local idx = table.find(CONFIG.TargetNPCs, npcName)
				if idx then
					table.remove(CONFIG.TargetNPCs, idx)
				else
					table.insert(CONFIG.TargetNPCs, npcName)
				end

				local isSelected = table.find(CONFIG.TargetNPCs, npcName)
				TweenService:Create(checkboxBtn, TweenInfo.new(0.15), {
					BackgroundColor3 = isSelected and Color3.fromRGB(80, 200, 100) or Color3.fromRGB(50, 50, 70),
					BackgroundTransparency = 0.4
				}):Play()
				checkboxBtn.Text = (isSelected and "✓ " or "  ") .. npcName
				uiElements.UpdateTargetLabel()
			end)
		end

		-- Buttons
		local buttonContainer = Instance.new("Frame")
		buttonContainer.Size = UDim2.new(1, 0, 0, 50)
		buttonContainer.Position = UDim2.new(0, 0, 1, -50)
		buttonContainer.BackgroundTransparency = 1
		buttonContainer.BorderSizePixel = 0
		buttonContainer.Parent = menuFrame

		local confirmBtn = Instance.new("TextButton")
		confirmBtn.Size = UDim2.new(0.5, -3, 1, 0)
		confirmBtn.BackgroundColor3 = Color3.fromRGB(80, 200, 100)
		confirmBtn.BackgroundTransparency = 0.3
		confirmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		confirmBtn.Font = Enum.Font.GothamBlack
		confirmBtn.TextSize = 12
		confirmBtn.Text = "CONFIRM"
		confirmBtn.BorderSizePixel = 0
		confirmBtn.Parent = buttonContainer
		Instance.new("UICorner", confirmBtn).CornerRadius = UDim.new(0, 8)

		local cancelBtn = Instance.new("TextButton")
		cancelBtn.Size = UDim2.new(0.5, -3, 1, 0)
		cancelBtn.Position = UDim2.new(0.5, 3, 0, 0)
		cancelBtn.BackgroundColor3 = Color3.fromRGB(200, 80, 80)
		cancelBtn.BackgroundTransparency = 0.3
		cancelBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		cancelBtn.Font = Enum.Font.GothamBlack
		cancelBtn.TextSize = 12
		cancelBtn.Text = "CANCEL"
		cancelBtn.BorderSizePixel = 0
		cancelBtn.Parent = buttonContainer
		Instance.new("UICorner", cancelBtn).CornerRadius = UDim.new(0, 8)

		confirmBtn.MouseButton1Click:Connect(function()
			menuGui:Destroy()
		end)

		cancelBtn.MouseButton1Click:Connect(function()
			scanNPCNames()
			menuGui:Destroy()
		end)
	end

	uiElements.ShowTargetMenu = createTargetMenu

	uiElements.UpdateTargetLabel = function()
		if #CONFIG.TargetNPCs == 0 then
			targetLabel.Text = "Targets: None Selected"
		else
			targetLabel.Text = "Targets: " .. table.concat(CONFIG.TargetNPCs, ", ")
		end
	end

	-- ======= DRAGGING FUNCTIONALITY =======
	titleBar.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			isDragging = true
			dragStart = input.Position
			startPos = frame.Position
			dragInput = input
		end
	end)

	titleBar.InputChanged:Connect(function(input)
		if input == dragInput and isDragging then
			local delta = input.Position - dragStart
			frame.Position = startPos + UDim2.new(0, delta.X, 0, delta.Y)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input == dragInput then
			isDragging = false
		end
	end)

	-- ======= HIDE/CLOSE BUTTONS =======
	hideBtn.MouseButton1Click:Connect(function()
		local isVisible = frame.Visible
		frame.Visible = not isVisible
		TweenService:Create(hideBtn, TweenInfo.new(0.2), {
			BackgroundColor3 = isVisible and Color3.fromRGB(100, 150, 200) or Color3.fromRGB(80, 200, 100)
		}):Play()
	end)

	closeBtn.MouseButton1Click:Connect(function()
		uiElements.Cleanup()
	end)

	return screenGui, frame
end

local screenGui, mainFrame = createGUI()

-- ======= CLEANUP FUNCTION =======
function uiElements.Cleanup()
	scriptRunning = false
	CONFIG.AutofarmActive = false

	-- Disconnect all custom connections
	for _, connection in ipairs(allConnections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	allConnections = {}

	-- Stop character movement
	local char = player.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:MoveTo(char:GetPivot().Position)
		end
	end

	-- Destroy UI
	if screenGui and screenGui.Parent then
		screenGui:Destroy()
	end

	local targetMenu = player.Parent:FindFirstChild("TargetMenu")
	if targetMenu then
		targetMenu:Destroy()
	end

	print("Autofarm script cleaned up and disabled!")
end

-- ======= DATA RECOVERY UTILITIES =======
local function isInCombat() return player:GetAttribute("CS_InCombat") == true end
local function hasActed() return player:GetAttribute("ClientActedThisTurn") == true end

local function saveCurrentPosition()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and not healthActionBusy then
		savedReturnCFrame = hrp.CFrame
	end
end

local function teleportBackToSavedPosition()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if char and hrp and savedReturnCFrame then
		char:PivotTo(savedReturnCFrame)
		return true
	end
	return false
end

local function resetAbilityCooldownTracking()
	abilityCooldownMemory = {}
	fightStartedAt = os.clock()
end


local function setAutofarmPausedForHealth(isPaused)
	autofarmPausedForHealth = isPaused
	if isPaused then
		myTurn = false
		player:SetAttribute("ClientActedThisTurn", false)
	end
end

-- ====== HEALTH REFILL ======
useHealthRefillInternal = function(ignoreEnabledCheck)
	if not ignoreEnabledCheck and not CONFIG.HealthEnabled then
		return false, "Health refill is OFF"
	end

	if healthActionBusy then
		return false, "Health action busy"
	end

	local now = os.clock()
	if now - lastHealthUse < CONFIG.HealthButtonCooldown then
		return false, "Health cooldown"
	end

	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")

	if not char or not hrp or not humanoid then
		return false, "Health: Character Missing"
	end

	if not CONFIG.HealthTeleportCFrame then
		warn("HealthTeleportCFrame not set in CONFIG")
		return false, "Health: Target Missing"
	end

	local safeCFrame = CONFIG.HealthTeleportCFrame * CFrame.new(CONFIG.TeleportOffset)

	healthActionBusy = true
	lastHealthUse = now
	returnTaskId += 1
	local currentTaskId = returnTaskId

	if CONFIG.AutofarmActive then
		setAutofarmPausedForHealth(true)
	end

	-- Teleportálás a gyógyulási pontra
	local success, result = pcall(function()
		if humanoid.Sit then
			humanoid.Sit = false
		end
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

		savedReturnCFrame = hrp.CFrame

		char:PivotTo(safeCFrame)
		task.wait(0.2)

		local movedDistance = (hrp.Position - safeCFrame.Position).Magnitude
		if movedDistance > 12 then
			hrp.CFrame = safeCFrame
			task.wait(0.15)
		end
	end)

	if not success then
		healthActionBusy = false
		setAutofarmPausedForHealth(false)
		warn("Health button error:", result)
		return false, "Health: Failed"
	end

	updateStatus("Teleported to health spawn")

	-- Várakozás a gyógyulásra, majd visszatérés
	task.delay(math.max(CONFIG.HealDuration, 0), function()
		if currentTaskId ~= returnTaskId then
			healthActionBusy = false
			setAutofarmPausedForHealth(false)
			return
		end

		local returnChar = player.Character
		local returnHrp = returnChar and returnChar:FindFirstChild("HumanoidRootPart")
		if not returnChar or not returnHrp then
			healthActionBusy = false
			setAutofarmPausedForHealth(false)
			return
		end

		if savedReturnCFrame then
			returnChar:PivotTo(savedReturnCFrame)
			task.wait(0.15)
			local returnDistance = (returnHrp.Position - savedReturnCFrame.Position).Magnitude
			if returnDistance > 12 then
				returnHrp.CFrame = savedReturnCFrame
			end
			updateStatus("Returned to saved position")
		end

		healthActionBusy = false
		setAutofarmPausedForHealth(false)
	end)

	return true, "Use Health Now"
end

_G.GlassFarmProUseHealthRefill = function()
	return useHealthRefillInternal(true)
end

local function onFightStarted()
	saveCurrentPosition()
	resetAbilityCooldownTracking()
	updateStatus("Fight started")
end

local function onFightEnded()
	returnTaskId += 1
	local currentTaskId = returnTaskId

	if CONFIG.HealthEnabled and not healthActionBusy then
		local lowHealth = getHealthRatio() <= CONFIG.AutoHealthThreshold
		local lowChakra = getChakraRatio() <= CONFIG.AutoChakraThreshold
		if lowHealth or lowChakra then
			updateStatus("Low HP/Chakra after combat, heading to spawn...")
			useHealthRefillInternal(false)
			return
		end
	end

	if CONFIG.ReturnDelay > 0 then
		updateStatus("Returning in " .. tostring(CONFIG.ReturnDelay) .. "s")
		task.delay(CONFIG.ReturnDelay, function()
			if currentTaskId ~= returnTaskId then return end
			if scriptRunning and not isInCombat() and not healthActionBusy then
				teleportBackToSavedPosition()
			end
		end)
	else
		if not healthActionBusy then
			teleportBackToSavedPosition()
		end
	end
end

local function isDead()
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	return not humanoid or humanoid.Health <= 0
end

local function fireActionSignal(action)
	local playerGui = player:FindFirstChild("PlayerGui")
	local attacks = playerGui and playerGui:FindFirstChild("Attacks")
	local bindable = attacks and attacks:FindFirstChild("ClientActionTaken")
	if bindable and bindable:IsA("BindableEvent") then
		bindable:Fire(action)
	end
end

-- ======= COMBAT EXECUTION ENGINE =======
local function processTurnActions()
	if not CONFIG.AutofarmActive or not scriptRunning or healthActionBusy or autofarmPausedForHealth then return end
	if not turnEvent or not combatRemoteEvent then return end

	player:SetAttribute("ClientActedThisTurn", true)

	local currentChakra, maxChakra = getChakraData()
	local chakraRatio = maxChakra > 0 and (currentChakra / maxChakra) or 0
	local abilityUsed = false

	if CONFIG.AutoAbility and chakraRatio >= CONFIG.MinAbilityChakraRatio then
		local data = player:FindFirstChild("Data")
		local equipped = data and data:FindFirstChild("EquippedAbilities")
		if equipped then
			local bestSlot = nil
			local bestScore = -math.huge

			for slotIndex = 1, 8 do
				local slot = equipped:FindFirstChild(tostring(slotIndex))
				if slot and slot.Value ~= "" and slot.Value ~= "None" then
					local cooldown = slot:GetAttribute("Cooldown") or 0
					local lastKnownCooldown = abilityCooldownMemory[slotIndex] or math.huge
					local becameReady = cooldown <= 0 and lastKnownCooldown > 0
					abilityCooldownMemory[slotIndex] = cooldown

					if cooldown <= 0 then
						local score = 10 - slotIndex
						if becameReady then
							score += 5
						end
						if slotIndex <= 3 then
							score += 2
						end
						if score > bestScore then
							bestScore = score
							bestSlot = slotIndex
						end
					end
				end
			end

			if bestSlot then
				fireActionSignal("Ability")
				combatRemoteEvent:FireServer("Ability", bestSlot)
				abilityUsed = true
			end
		end
	end

	if not abilityUsed then
		if currentChakra < (maxChakra * CONFIG.LowChakraThreshold) then
			fireActionSignal("Attack")
			turnEvent:FireServer("Attack")
			return
		end

		fireActionSignal("Attack")
		turnEvent:FireServer("Attack")
	end
end

-- Turn Event Hook
if turnEvent then
	local conn = turnEvent.OnClientEvent:Connect(function(message, scope)
		if not CONFIG.AutofarmActive or not scriptRunning then return end

		if message == "Your Turn" then
			myTurn = (scope == nil or scope == player or scope == player.Character)
			if myTurn then
				task.spawn(processTurnActions)
			end
		elseif message == "Enemy Turn" or message == "BattleEnded" then
			myTurn = false
		end
	end)
	table.insert(allConnections, conn)
end

-- ======= OVERWORLD OPERATIONS =======
local function findOptimalNPC()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	local npcsFolder = Workspace:FindFirstChild("NPCs")
	if not npcsFolder then return nil end

	local bestTarget, minimumDistance = nil, CONFIG.SearchRadius

	for _, npc in ipairs(npcsFolder:GetChildren()) do
		if npc:IsA("Model") and npc:GetAttribute("IsNPC") == true then
			if #CONFIG.TargetNPCs > 0 and not table.find(CONFIG.TargetNPCs, npc.Name) then
				continue
			end

			local humanoid = npc:FindFirstChildOfClass("Humanoid")
			local npcHrp = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart

			if humanoid and humanoid.Health > 0 and npcHrp then
				local currentDistance = (npcHrp.Position - hrp.Position).Magnitude
				if currentDistance < minimumDistance then
					bestTarget = npc
					minimumDistance = currentDistance
				end
			end
		end
	end
	return bestTarget
end

local function travelToNPC(npc)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local npcHrp = npc and (npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart)
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")

	if hrp and npcHrp and humanoid then
		local distance = (npcHrp.Position - hrp.Position).Magnitude
		local useWalk = (CONFIG.MoveMode == "Walk") or (distance > CONFIG.MaxTeleportDistance)

		if useWalk then
			humanoid:MoveTo(npcHrp.Position)
			updateStatus("Walking to " .. npc.Name .. " (" .. math.floor(distance) .. " studs)")
		else
			hrp.CFrame = npcHrp.CFrame
			updateStatus("Hunting: " .. npc.Name)
		end
	end
end

-- ======= MAIN LOOP =======
local function mainControlLoop()
	while CONFIG.AutofarmActive and scriptRunning do
		task.wait(0.15)

		local nowInCombat = isInCombat()
		if nowInCombat and not lastCombatState then
			onFightStarted()
		elseif not nowInCombat and lastCombatState then
			onFightEnded()
		end
		lastCombatState = nowInCombat

		if healthActionBusy or autofarmPausedForHealth then
			updateStatus("Using health spot...")
			continue
		end

		-- Gyógyulás engedélyezése harc közben, ha a HealDuringCombat aktív
		local canHeal = not nowInCombat or CONFIG.HealDuringCombat
		if canHeal and CONFIG.HealthEnabled then
			local lowHealth = getHealthRatio() <= CONFIG.AutoHealthThreshold
			local lowChakra = getChakraRatio() <= CONFIG.AutoChakraThreshold
			if lowHealth or lowChakra then
				local ok = useHealthRefillInternal(false)
				if ok then
					continue
				end
			end
		end

		if isDead() then
			updateStatus("Recovering...")
			task.wait(2)
			continue
		end

		if nowInCombat then
			if myTurn and not hasActed() then
				processTurnActions()
				task.wait(CONFIG.ActionCooldown)
			else
				updateStatus("Waiting on Enemy...")
			end
		else
			if #CONFIG.TargetNPCs == 0 then
				updateStatus("Select targets to start farming")
			else
				local targetNPC = findOptimalNPC()
				if targetNPC then
					travelToNPC(targetNPC)
				else
					updateStatus("Searching for targets...")
				end
			end
		end
	end
end

-- ======= INITIALIZATION =======
uiElements.ToggleBtn.MouseButton1Click:Connect(function()
	if #CONFIG.TargetNPCs == 0 and not CONFIG.AutofarmActive then
		updateStatus("Please select targets first!")
		return
	end

	CONFIG.AutofarmActive = not CONFIG.AutofarmActive
	if CONFIG.AutofarmActive then
		uiElements.ToggleBtn.Text = "STOP AUTOFARM"
		TweenService:Create(uiElements.ToggleBtn, TweenInfo.new(0.25), {BackgroundColor3 = Color3.fromRGB(255, 80, 80)}):Play()
		scanNPCNames()
		lastCombatState = isInCombat()
		if not lastCombatState then
			saveCurrentPosition()
			resetAbilityCooldownTracking()
		end
		task.spawn(mainControlLoop)
	else
		uiElements.ToggleBtn.Text = "START AUTOFARM"
		TweenService:Create(uiElements.ToggleBtn, TweenInfo.new(0.25), {BackgroundColor3 = Color3.fromRGB(80, 150, 60)}):Play()
		updateStatus("Idle")

		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then hum:MoveTo(char:GetPivot().Position) end
		teleportBackToSavedPosition()
	end
end)

local conn = player.Idled:Connect(function()
	if CONFIG.AntiAFK and CONFIG.AutofarmActive then
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end
end)
table.insert(allConnections, conn)

task.spawn(function()
	task.wait(1.5)
	scanNPCNames()
	uiElements.UpdateTargetLabel()
end)
