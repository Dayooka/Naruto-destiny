local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

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
	HealDuration = 5,
	MaxTeleportDistance = 1000,
	HealDuringCombat = false
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

-- ======= PREMIUM UI SYSTEM =======
local uiElements = {}
local isDragging = false
local dragInput = nil
local dragStart = nil
local startPos = nil
local uiVisible = true
local mainFrame = nil
local screenGui = nil

-- Prémium Color Palette
local COLORS = {
	Primary = Color3.fromRGB(100, 200, 255),
	Secondary = Color3.fromRGB(70, 150, 220),
	Dark = Color3.fromRGB(15, 15, 25),
	DarkAlt = Color3.fromRGB(25, 25, 35),
	Success = Color3.fromRGB(80, 200, 100),
	Danger = Color3.fromRGB(255, 80, 80),
	Warning = Color3.fromRGB(255, 180, 60),
	Text = Color3.fromRGB(200, 220, 255),
	TextDim = Color3.fromRGB(150, 200, 255),
	Accent = Color3.fromRGB(150, 100, 255),
	Glow = Color3.fromRGB(100, 200, 255)
}

-- ======= ANIMATION UTILITIES =======
local function smoothTween(object, duration, targetProps)
	if TweenService then
		local tweenInfo = TweenInfo.new(
			duration,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.InOut
		)
		local tween = TweenService:Create(object, tweenInfo, targetProps)
		tween:Play()
		return tween
	end
end

local function createLoadingAnimation(parent)
	local loadingContainer = Instance.new("Frame")
	loadingContainer.BackgroundTransparency = 1
	loadingContainer.Size = UDim2.new(1, 0, 1, 0)
	loadingContainer.Parent = parent

	for i = 1, 4 do
		local dot = Instance.new("TextLabel")
		dot.BackgroundColor3 = COLORS.Primary
		dot.Size = UDim2.new(0, 10, 0, 10)
		dot.Position = UDim2.new(0.5, (i-2.5)*20, 0.5, -5)
		dot.TextTransparency = 1
		dot.Parent = loadingContainer

		Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

		task.spawn(function()
			while dot and dot.Parent do
				smoothTween(dot, 0.4, {BackgroundTransparency = 0.7})
				task.wait(0.4)
				if dot and dot.Parent then
					smoothTween(dot, 0.4, {BackgroundTransparency = 0})
					task.wait(0.4)
				end
			end
		end)
	end

	return loadingContainer
end

updateStatus = function(text)
	if uiElements.StatusLabel then
		uiElements.StatusLabel.Text = "⚡ " .. tostring(text)
		smoothTween(uiElements.StatusLabel, 0.3, {TextTransparency = 0})
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

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "GlassFarmPro"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 999
	screenGui.Parent = targetParent

	-- ======= LOADING SCREEN =======
	local loadingScreen = Instance.new("Frame")
	loadingScreen.Size = UDim2.new(1, 0, 1, 0)
	loadingScreen.BackgroundColor3 = COLORS.Dark
	loadingScreen.BackgroundTransparency = 0.3
	loadingScreen.BorderSizePixel = 0
	loadingScreen.Parent = screenGui
	loadingScreen.ZIndex = 10000

	local loadingBox = Instance.new("Frame")
	loadingBox.Size = UDim2.new(0, 300, 0, 150)
	loadingBox.Position = UDim2.new(0.5, -150, 0.5, -75)
	loadingBox.BackgroundColor3 = COLORS.DarkAlt
	loadingBox.BorderSizePixel = 0
	loadingBox.Parent = loadingScreen
	loadingBox.ZIndex = 10001

	Instance.new("UICorner", loadingBox).CornerRadius = UDim.new(0, 16)

	local loadingStroke = Instance.new("UIStroke", loadingBox)
	loadingStroke.Color = COLORS.Primary
	loadingStroke.Thickness = 2
	loadingStroke.Transparency = 0.3

	local loadingText = Instance.new("TextLabel")
	loadingText.Size = UDim2.new(1, 0, 0, 40)
	loadingText.Position = UDim2.new(0, 0, 0, 10)
	loadingText.BackgroundTransparency = 1
	loadingText.Text = "INITIALIZING..."
	loadingText.TextColor3 = COLORS.Primary
	loadingText.Font = Enum.Font.GothamBlack
	loadingText.TextSize = 16
	loadingText.Parent = loadingBox
	loadingText.ZIndex = 10002

	createLoadingAnimation(loadingBox)

	-- ======= MAIN FRAME =======
	mainFrame = Instance.new("Frame")
	mainFrame.Size = UDim2.new(0, 350, 0, 550)
	mainFrame.Position = UDim2.new(0, 30, 0.5, -275)
	mainFrame.BackgroundColor3 = COLORS.DarkAlt
	mainFrame.BackgroundTransparency = 0.05
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui
	mainFrame.ClipsDescendants = true

	Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 20)

	local stroke = Instance.new("UIStroke", mainFrame)
	stroke.Color = COLORS.Primary
	stroke.Transparency = 0.2
	stroke.Thickness = 2.5

	local gradient = Instance.new("UIGradient", mainFrame)
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLORS.Dark),
		ColorSequenceKeypoint.new(1, COLORS.DarkAlt)
	})
	gradient.Rotation = 45

	-- ======= TITLEBAR PREMIUM =======
	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 65)
	titleBar.BackgroundColor3 = COLORS.Dark
	titleBar.BackgroundTransparency = 0
	titleBar.BorderSizePixel = 0
	titleBar.Parent = mainFrame

	local titleGradient = Instance.new("UIGradient", titleBar)
	titleGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLORS.Primary),
		ColorSequenceKeypoint.new(1, COLORS.Secondary)
	})
	titleGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0.95)
	})

	Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 20)

	local titleIcon = Instance.new("TextLabel")
	titleIcon.Size = UDim2.new(0, 40, 0, 40)
	titleIcon.Position = UDim2.new(0, 12, 0.5, -20)
	titleIcon.BackgroundTransparency = 1
	titleIcon.Text = "⚡"
	titleIcon.TextSize = 28
	titleIcon.Parent = titleBar

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -120, 1, 0)
	title.Position = UDim2.new(0, 55, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "AUTOFARM PRO"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Parent = titleBar

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -120, 0, 20)
	subtitle.Position = UDim2.new(0, 55, 0, 35)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "✦ Premium Edition"
	subtitle.TextColor3 = COLORS.TextDim
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextSize = 10
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Parent = titleBar

	-- Minimize Button
	local minimizeBtn = Instance.new("TextButton")
	minimizeBtn.Size = UDim2.new(0, 35, 0, 35)
	minimizeBtn.Position = UDim2.new(1, -80, 0.5, -17.5)
	minimizeBtn.BackgroundColor3 = COLORS.Secondary
	minimizeBtn.BackgroundTransparency = 0.5
	minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	minimizeBtn.Font = Enum.Font.GothamBold
	minimizeBtn.TextSize = 16
	minimizeBtn.Text = "−"
	minimizeBtn.Parent = titleBar
	minimizeBtn.ZIndex = 10

	Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 10)

	local minimizeStroke = Instance.new("UIStroke", minimizeBtn)
	minimizeStroke.Color = COLORS.Primary
	minimizeStroke.Transparency = 0.4
	minimizeStroke.Thickness = 1.5

	-- Close Button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 35, 0, 35)
	closeBtn.Position = UDim2.new(1, -40, 0.5, -17.5)
	closeBtn.BackgroundColor3 = COLORS.Danger
	closeBtn.BackgroundTransparency = 0.5
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.Text = "✕"
	closeBtn.Parent = titleBar
	closeBtn.ZIndex = 10

	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 10)

	local closeStroke = Instance.new("UIStroke", closeBtn)
	closeStroke.Color = COLORS.Danger
	closeStroke.Transparency = 0.4
	closeStroke.Thickness = 1.5

	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(0.95, 0, 0, 1.5)
	divider.Position = UDim2.new(0.025, 0, 0, 65)
	divider.BackgroundColor3 = COLORS.Primary
	divider.BackgroundTransparency = 0.3
	divider.BorderSizePixel = 0
	divider.Parent = mainFrame

	-- ======= SCROLLING CONTENT =======
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Size = UDim2.new(1, -20, 1, -210)
	scrollFrame.Position = UDim2.new(0, 10, 0, 75)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = COLORS.Primary
	scrollFrame.ScrollBarImageTransparency = 0.3
	scrollFrame.Parent = mainFrame
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 10)
	listLayout.Parent = scrollFrame

	local padding = Instance.new("UIPadding", scrollFrame)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 8)

	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 16)
	end)

	-- ======= BUTTON FACTORY =======
	local function createButton(text, callback, buttonColor)
		buttonColor = buttonColor or COLORS.Secondary
		
		local btnContainer = Instance.new("Frame")
		btnContainer.Size = UDim2.new(1, 0, 0, 40)
		btnContainer.BackgroundTransparency = 1
		btnContainer.Parent = scrollFrame

		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, -10, 1, 0)
		btn.BackgroundColor3 = buttonColor
		btn.BackgroundTransparency = 0.4
		btn.TextColor3 = COLORS.Text
		btn.Font = Enum.Font.GothamSemibold
		btn.TextSize = 13
		btn.Text = text
		btn.Parent = btnContainer
		btn.ZIndex = 5

		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)

		local btnStroke = Instance.new("UIStroke", btn)
		btnStroke.Color = buttonColor
		btnStroke.Transparency = 0.5
		btnStroke.Thickness = 1.5

		btn.MouseEnter:Connect(function()
			smoothTween(btn, 0.2, {BackgroundTransparency = 0.2})
			smoothTween(btnStroke, 0.2, {Transparency = 0.1})
		end)

		btn.MouseLeave:Connect(function()
			smoothTween(btn, 0.2, {BackgroundTransparency = 0.4})
			smoothTween(btnStroke, 0.2, {Transparency = 0.5})
		end)

		btn.MouseButton1Click:Connect(function()
			smoothTween(btn, 0.1, {Size = UDim2.new(1, -8, 1, 0)})
			task.wait(0.1)
			smoothTween(btn, 0.15, {Size = UDim2.new(1, -10, 1, 0)})

			local result = callback()
			if typeof(result) == "string" and result ~= "" then
				btn.Text = result
				task.spawn(function()
					task.wait(1.5)
					btn.Text = text
				end)
			end
		end)

		return btn, btnContainer
	end

	-- ======= TOGGLE FACTORY =======
	local function createToggle(text, configKey)
		local toggleContainer = Instance.new("Frame")
		toggleContainer.Size = UDim2.new(1, 0, 0, 40)
		toggleContainer.BackgroundTransparency = 1
		toggleContainer.Parent = scrollFrame

		local bg = Instance.new("Frame")
		bg.Size = UDim2.new(1, -10, 1, 0)
		bg.BackgroundColor3 = CONFIG[configKey] and COLORS.Success or COLORS.Secondary
		bg.BackgroundTransparency = 0.5
		bg.Parent = toggleContainer

		Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 12)

		local bgStroke = Instance.new("UIStroke", bg)
		bgStroke.Color = CONFIG[configKey] and COLORS.Success or COLORS.Secondary
		bgStroke.Transparency = 0.3
		bgStroke.Thickness = 1.5

		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 1, 0)
		btn.BackgroundTransparency = 1
		btn.TextColor3 = COLORS.Text
		btn.Font = Enum.Font.GothamSemibold
		btn.TextSize = 13
		btn.Text = (CONFIG[configKey] and "✓ " or "○ ") .. text .. (CONFIG[configKey] and " [ON]" or " [OFF]")
		btn.Parent = bg

		btn.MouseEnter:Connect(function()
			smoothTween(bg, 0.2, {BackgroundTransparency = 0.3})
		end)

		btn.MouseLeave:Connect(function()
			smoothTween(bg, 0.2, {BackgroundTransparency = 0.5})
		end)

		btn.MouseButton1Click:Connect(function()
			CONFIG[configKey] = not CONFIG[configKey]
			
			smoothTween(bg, 0.25, {
				BackgroundColor3 = CONFIG[configKey] and COLORS.Success or COLORS.Secondary,
			})
			smoothTween(bgStroke, 0.25, {
				Color = CONFIG[configKey] and COLORS.Success or COLORS.Secondary,
			})
			
			btn.Text = (CONFIG[configKey] and "✓ " or "○ ") .. text .. (CONFIG[configKey] and " [ON]" or " [OFF]")
		end)

		return btn, toggleContainer
	end

	-- ======= STAT BAR =======
	local function createStatBar(label, getValue, getMax, color)
		local statContainer = Instance.new("Frame")
		statContainer.Size = UDim2.new(1, 0, 0, 50)
		statContainer.BackgroundTransparency = 1
		statContainer.Parent = scrollFrame

		local statLabel = Instance.new("TextLabel")
		statLabel.Size = UDim2.new(1, -10, 0, 18)
		statLabel.BackgroundTransparency = 1
		statLabel.TextColor3 = COLORS.TextDim
		statLabel.Font = Enum.Font.GothamMedium
		statLabel.TextSize = 11
		statLabel.Text = label .. ": --/-- "
		statLabel.TextXAlignment = Enum.TextXAlignment.Left
		statLabel.Parent = statContainer

		local barBg = Instance.new("Frame")
		barBg.Size = UDim2.new(1, -10, 0, 20)
		barBg.Position = UDim2.new(0, 5, 0, 24)
		barBg.BackgroundColor3 = COLORS.Dark
		barBg.BackgroundTransparency = 0.3
		barBg.Parent = statContainer

		Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 8)

		local barFill = Instance.new("Frame")
		barFill.Size = UDim2.new(0.5, 0, 1, 0)
		barFill.BackgroundColor3 = color
		barFill.BackgroundTransparency = 0
		barFill.BorderSizePixel = 0
		barFill.Parent = barBg

		Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 8)

		task.spawn(function()
			while statContainer and statContainer.Parent do
				local current, max = getValue(), getMax()
				local ratio = max > 0 and (current / max) or 0
				ratio = math.max(0, math.min(1, ratio))

				barFill.Size = UDim2.new(ratio, 0, 1, 0)
				statLabel.Text = label .. ": " .. math.floor(current) .. "/" .. math.floor(max)

				task.wait(0.2)
			end
		end)

		return statContainer
	end

	-- ======= UI ELEMENTS =======

	local targetLabel = Instance.new("TextLabel")
	targetLabel.Size = UDim2.new(1, -10, 0, 28)
	targetLabel.BackgroundColor3 = COLORS.Primary
	targetLabel.BackgroundTransparency = 0.8
	targetLabel.TextColor3 = COLORS.Text
	targetLabel.Font = Enum.Font.GothamMedium
	targetLabel.TextSize = 11
	targetLabel.Text = "Targets: None Selected"
	targetLabel.TextXAlignment = Enum.TextXAlignment.Left
	targetLabel.TextWrapped = true
	targetLabel.Parent = scrollFrame
	targetLabel.ZIndex = 5

	Instance.new("UICorner", targetLabel).CornerRadius = UDim.new(0, 10)
	local targetStroke = Instance.new("UIStroke", targetLabel)
	targetStroke.Color = COLORS.Primary
	targetStroke.Transparency = 0.3

	uiElements.TargetLabel = targetLabel

	createButton("🎯 Select Targets", function()
		scanNPCNames()
		uiElements.ShowTargetMenu()
		return "Select Targets"
	end, COLORS.Accent)

	createButton("🚀 Movement: " .. CONFIG.MoveMode, function()
		CONFIG.MoveMode = (CONFIG.MoveMode == "Walk") and "Teleport" or "Walk"
		return "🚀 Movement: " .. CONFIG.MoveMode
	end)

	createStatBar("⚡ Chakra", function() return (getChakraData()) end, function() return (select(2, getChakraData())) end, COLORS.Primary)
	createStatBar("❤ Health", function() return (player.Character and player.Character:FindFirstChildOfClass("Humanoid") and player.Character:FindFirstChildOfClass("Humanoid").Health or 0) end, function() return (player.Character and player.Character:FindFirstChildOfClass("Humanoid") and player.Character:FindFirstChildOfClass("Humanoid").MaxHealth or 100) end, COLORS.Danger)

	createButton("⏱ Return Delay: " .. tostring(CONFIG.ReturnDelay) .. "s", function()
		CONFIG.ReturnDelay += 1
		if CONFIG.ReturnDelay > 10 then
			CONFIG.ReturnDelay = 0
		end
		return "⏱ Return Delay: " .. tostring(CONFIG.ReturnDelay) .. "s"
	end)

	createToggle("Health Refill", "HealthEnabled")
	createToggle("Heal During Combat", "HealDuringCombat")

	createButton("🏥 HP Threshold: " .. tostring(math.floor(CONFIG.AutoHealthThreshold * 100)) .. "%", function()
		CONFIG.AutoHealthThreshold += 0.1
		if CONFIG.AutoHealthThreshold > 0.9 then
			CONFIG.AutoHealthThreshold = 0.1
		end
		return "🏥 HP Threshold: " .. tostring(math.floor(CONFIG.AutoHealthThreshold * 100)) .. "%"
	end)

	createButton("⚡ Chakra Threshold: " .. tostring(math.floor(CONFIG.AutoChakraThreshold * 100)) .. "%", function()
		CONFIG.AutoChakraThreshold += 0.1
		if CONFIG.AutoChakraThreshold > 0.9 then
			CONFIG.AutoChakraThreshold = 0.1
		end
		return "⚡ Chakra Threshold: " .. tostring(math.floor(CONFIG.AutoChakraThreshold * 100)) .. "%"
	end)

	createButton("💊 Use Health Now", function()
		local healthRefillFn = _G.GlassFarmProUseHealthRefill
		if type(healthRefillFn) ~= "function" then
			updateStatus("Health function unavailable")
			return "💊 Use Health Now"
		end

		local ok, message = healthRefillFn()
		if not ok then
			updateStatus(message)
			return "💊 Use Health Now"
		end
		return message
	end, COLORS.Success)

	createToggle("Use Abilities", "AutoAbility")
	createToggle("Anti AFK", "AntiAFK")

	-- ======= BOTTOM PANEL =======
	local bottomPanel = Instance.new("Frame")
	bottomPanel.Size = UDim2.new(1, 0, 0, 140)
	bottomPanel.Position = UDim2.new(0, 0, 1, -140)
	bottomPanel.BackgroundColor3 = COLORS.Dark
	bottomPanel.BackgroundTransparency = 0.2
	bottomPanel.BorderSizePixel = 0
	bottomPanel.Parent = mainFrame

	local bottomGradient = Instance.new("UIGradient", bottomPanel)
	bottomGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLORS.Dark),
		ColorSequenceKeypoint.new(1, COLORS.DarkAlt)
	})

	Instance.new("UICorner", bottomPanel).CornerRadius = UDim.new(0, 20)

	uiElements.StatusLabel = Instance.new("TextLabel")
	uiElements.StatusLabel.Size = UDim2.new(1, -20, 0, 35)
	uiElements.StatusLabel.Position = UDim2.new(0, 10, 0, 5)
	uiElements.StatusLabel.BackgroundTransparency = 1
	uiElements.StatusLabel.TextColor3 = COLORS.TextDim
	uiElements.StatusLabel.Text = "⚡ Status: Idle"
	uiElements.StatusLabel.Font = Enum.Font.GothamMedium
	uiElements.StatusLabel.TextSize = 12
	uiElements.StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	uiElements.StatusLabel.Parent = bottomPanel

	uiElements.ToggleBtn = Instance.new("TextButton")
	uiElements.ToggleBtn.Size = UDim2.new(0.9, 0, 0, 45)
	uiElements.ToggleBtn.Position = UDim2.new(0.05, 0, 0, 48)
	uiElements.ToggleBtn.BackgroundColor3 = COLORS.Success
	uiElements.ToggleBtn.BackgroundTransparency = 0.3
	uiElements.ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	uiElements.ToggleBtn.Text = "▶ START AUTOFARM"
	uiElements.ToggleBtn.Font = Enum.Font.GothamBlack
	uiElements.ToggleBtn.TextSize = 14
	uiElements.ToggleBtn.Parent = bottomPanel
	uiElements.ToggleBtn.ZIndex = 10

	Instance.new("UICorner", uiElements.ToggleBtn).CornerRadius = UDim.new(0, 12)

	local toggleStroke = Instance.new("UIStroke", uiElements.ToggleBtn)
	toggleStroke.Color = COLORS.Success
	toggleStroke.Transparency = 0.3
	toggleStroke.Thickness = 2

	-- ======= TARGET SELECTION MENU =======
	local function createTargetMenu()
		local existing = targetParent:FindFirstChild("TargetMenu")
		if existing then existing:Destroy() end

		local menuGui = Instance.new("ScreenGui")
		menuGui.Name = "TargetMenu"
		menuGui.ResetOnSpawn = false
		menuGui.DisplayOrder = 1000
		menuGui.Parent = targetParent

		local backdrop = Instance.new("Frame")
		backdrop.Size = UDim2.new(1, 0, 1, 0)
		backdrop.BackgroundColor3 = COLORS.Dark
		backdrop.BackgroundTransparency = 0.4
		backdrop.BorderSizePixel = 0
		backdrop.Parent = menuGui
		backdrop.ZIndex = 999

		local menuFrame = Instance.new("Frame")
		menuFrame.Size = UDim2.new(0, 350, 0, 450)
		menuFrame.Position = UDim2.new(0.5, -175, 0.5, -225)
		menuFrame.BackgroundColor3 = COLORS.DarkAlt
		menuFrame.BackgroundTransparency = 0.05
		menuFrame.BorderSizePixel = 0
		menuFrame.Parent = menuGui
		menuFrame.ZIndex = 1000
		menuFrame.ClipsDescendants = true

		Instance.new("UICorner", menuFrame).CornerRadius = UDim.new(0, 16)

		local menuStroke = Instance.new("UIStroke", menuFrame)
		menuStroke.Color = COLORS.Primary
		menuStroke.Transparency = 0.2
		menuStroke.Thickness = 2.5

		local menuTitle = Instance.new("TextLabel")
		menuTitle.Size = UDim2.new(1, 0, 0, 50)
		menuTitle.BackgroundColor3 = COLORS.Dark
		menuTitle.BackgroundTransparency = 0
		menuTitle.TextColor3 = COLORS.Primary
		menuTitle.Font = Enum.Font.GothamBlack
		menuTitle.TextSize = 16
		menuTitle.Text = "🎯 SELECT TARGETS"
		menuTitle.BorderSizePixel = 0
		menuTitle.Parent = menuFrame

		Instance.new("UICorner", menuTitle).CornerRadius = UDim.new(0, 16)

		local titleGrad = Instance.new("UIGradient", menuTitle)
		titleGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, COLORS.Primary),
			ColorSequenceKeypoint.new(1, COLORS.Secondary)
		})
		titleGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(1, 0.95)
		})

		local menuScroll = Instance.new("ScrollingFrame")
		menuScroll.Size = UDim2.new(1, -20, 1, -130)
		menuScroll.Position = UDim2.new(0, 10, 0, 55)
		menuScroll.BackgroundTransparency = 1
		menuScroll.BorderSizePixel = 0
		menuScroll.ScrollBarThickness = 4
		menuScroll.ScrollBarImageColor3 = COLORS.Primary
		menuScroll.Parent = menuFrame

		local menuLayout = Instance.new("UIListLayout")
		menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
		menuLayout.Padding = UDim.new(0, 8)
		menuLayout.Parent = menuScroll

		local menuPadding = Instance.new("UIPadding", menuScroll)
		menuPadding.PaddingLeft = UDim.new(0, 8)
		menuPadding.PaddingRight = UDim.new(0, 8)
		menuPadding.PaddingTop = UDim.new(0, 8)

		menuLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			menuScroll.CanvasSize = UDim2.new(0, 0, 0, menuLayout.AbsoluteContentSize.Y + 16)
		end)

		for _, npcName in ipairs(availableNPCs) do
			local isSelected = table.find(CONFIG.TargetNPCs, npcName)
			
			local checkboxContainer = Instance.new("Frame")
			checkboxContainer.Size = UDim2.new(1, 0, 0, 38)
			checkboxContainer.BackgroundTransparency = 1
			checkboxContainer.Parent = menuScroll

			local checkboxBtn = Instance.new("TextButton")
			checkboxBtn.Size = UDim2.new(1, -10, 1, 0)
			checkboxBtn.BackgroundColor3 = isSelected and COLORS.Success or COLORS.Secondary
			checkboxBtn.BackgroundTransparency = 0.5
			checkboxBtn.TextColor3 = COLORS.Text
			checkboxBtn.Font = Enum.Font.GothamSemibold
			checkboxBtn.TextSize = 12
			checkboxBtn.Text = (isSelected and "✓ " or "  ") .. npcName
			checkboxBtn.Parent = checkboxContainer
			checkboxBtn.ZIndex = 10

			Instance.new("UICorner", checkboxBtn).CornerRadius = UDim.new(0, 10)

			local cbStroke = Instance.new("UIStroke", checkboxBtn)
			cbStroke.Color = isSelected and COLORS.Success or COLORS.Secondary
			cbStroke.Transparency = 0.4
			cbStroke.Thickness = 1.5

			checkboxBtn.MouseEnter:Connect(function()
				smoothTween(checkboxBtn, 0.2, {BackgroundTransparency = 0.3})
			end)

			checkboxBtn.MouseLeave:Connect(function()
				smoothTween(checkboxBtn, 0.2, {BackgroundTransparency = 0.5})
			end)

			checkboxBtn.MouseButton1Click:Connect(function()
				local idx = table.find(CONFIG.TargetNPCs, npcName)
				if idx then
					table.remove(CONFIG.TargetNPCs, idx)
				else
					table.insert(CONFIG.TargetNPCs, npcName)
				end

				local newIsSelected = table.find(CONFIG.TargetNPCs, npcName)
				smoothTween(checkboxBtn, 0.15, {
					BackgroundColor3 = newIsSelected and COLORS.Success or COLORS.Secondary,
				})
				smoothTween(cbStroke, 0.15, {
					Color = newIsSelected and COLORS.Success or COLORS.Secondary,
				})
				checkboxBtn.Text = (newIsSelected and "✓ " or "  ") .. npcName
				uiElements.UpdateTargetLabel()
			end)
		end

		local buttonContainer = Instance.new("Frame")
		buttonContainer.Size = UDim2.new(1, 0, 0, 65)
		buttonContainer.Position = UDim2.new(0, 0, 1, -65)
		buttonContainer.BackgroundColor3 = COLORS.Dark
		buttonContainer.BackgroundTransparency = 0.5
		buttonContainer.BorderSizePixel = 0
		buttonContainer.Parent = menuFrame

		Instance.new("UICorner", buttonContainer).CornerRadius = UDim.new(0, 16)

		local confirmBtn = Instance.new("TextButton")
		confirmBtn.Size = UDim2.new(0.5, -4, 0, 45)
		confirmBtn.Position = UDim2.new(0, 8, 0.5, -22.5)
		confirmBtn.BackgroundColor3 = COLORS.Success
		confirmBtn.BackgroundTransparency = 0.3
		confirmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		confirmBtn.Font = Enum.Font.GothamBlack
		confirmBtn.TextSize = 13
		confirmBtn.Text = "✓ CONFIRM"
		confirmBtn.BorderSizePixel = 0
		confirmBtn.Parent = buttonContainer
		confirmBtn.ZIndex = 11

		Instance.new("UICorner", confirmBtn).CornerRadius = UDim.new(0, 10)

		local confStroke = Instance.new("UIStroke", confirmBtn)
		confStroke.Color = COLORS.Success
		confStroke.Thickness = 1.5

		local cancelBtn = Instance.new("TextButton")
		cancelBtn.Size = UDim2.new(0.5, -4, 0, 45)
		cancelBtn.Position = UDim2.new(0.5, 4, 0.5, -22.5)
		cancelBtn.BackgroundColor3 = COLORS.Danger
		cancelBtn.BackgroundTransparency = 0.3
		cancelBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		cancelBtn.Font = Enum.Font.GothamBlack
		cancelBtn.TextSize = 13
		cancelBtn.Text = "✕ CANCEL"
		cancelBtn.BorderSizePixel = 0
		cancelBtn.Parent = buttonContainer
		cancelBtn.ZIndex = 11

		Instance.new("UICorner", cancelBtn).CornerRadius = UDim.new(0, 10)

		local cancelStroke = Instance.new("UIStroke", cancelBtn)
		cancelStroke.Color = COLORS.Danger
		cancelStroke.Thickness = 1.5

		confirmBtn.MouseButton1Click:Connect(function()
			smoothTween(menuFrame, 0.3, {Position = UDim2.new(0.5, -175, 0.5, -500)})
			task.wait(0.3)
			menuGui:Destroy()
		end)

		cancelBtn.MouseButton1Click:Connect(function()
			CONFIG.TargetNPCs = {}
			scanNPCNames()
			smoothTween(menuFrame, 0.3, {Position = UDim2.new(0.5, -175, 0.5, -500)})
			task.wait(0.3)
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
			startPos = mainFrame.Position
			dragInput = input
		end
	end)

	titleBar.InputChanged:Connect(function(input)
		if input == dragInput and isDragging then
			local delta = input.Position - dragStart
			mainFrame.Position = startPos + UDim2.new(0, delta.X, 0, delta.Y)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input == dragInput then
			isDragging = false
		end
	end)

	-- ======= BUTTON EVENTS =======
	minimizeBtn.MouseButton1Click:Connect(function()
		uiVisible = not uiVisible
		smoothTween(mainFrame, 0.3, {Size = uiVisible and UDim2.new(0, 350, 0, 550) or UDim2.new(0, 350, 0, 65)})
		smoothTween(minimizeBtn, 0.2, {BackgroundTransparency = uiVisible and 0.5 or 0.7})
	end)

	closeBtn.MouseButton1Click:Connect(function()
		smoothTween(mainFrame, 0.3, {Position = UDim2.new(0, 30, 0.5, -600)})
		task.wait(0.3)
		uiElements.Cleanup()
	end)

	-- ======= LOADING ANIMATION =======
	task.wait(1)
	smoothTween(loadingScreen, 0.6, {BackgroundTransparency = 1})
	task.wait(0.6)
	loadingScreen:Destroy()

	smoothTween(mainFrame, 0.8, {Position = UDim2.new(0, 30, 0.5, -275)})

	return screenGui, mainFrame
end

local screenGui, mainFrame = createGUI()

-- ======= CLEANUP FUNCTION =======
function uiElements.Cleanup()
	scriptRunning = false
	CONFIG.AutofarmActive = false

	for _, connection in ipairs(allConnections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	allConnections = {}

	local char = player.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:MoveTo(char:GetPivot().Position)
		end
	end

	if screenGui and screenGui.Parent then
		screenGui:Destroy()
	end

	local targetMenu = player.Parent:FindFirstChild("TargetMenu")
	if targetMenu then
		targetMenu:Destroy()
	end

	print("✓ Autofarm script cleaned up!")
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

	updateStatus("💊 Healing at spawn...")

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
			updateStatus("✓ Returned to combat")
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
	updateStatus("⚔ Fight started!")
end

local function onFightEnded()
	returnTaskId += 1
	local currentTaskId = returnTaskId

	if CONFIG.HealthEnabled and not healthActionBusy then
		local lowHealth = getHealthRatio() <= CONFIG.AutoHealthThreshold
		local lowChakra = getChakraRatio() <= CONFIG.AutoChakraThreshold
		if lowHealth or lowChakra then
			updateStatus("📍 Heading to spawn...")
			useHealthRefillInternal(false)
			return
		end
	end

	if CONFIG.ReturnDelay > 0 then
		updateStatus("⏳ Returning in " .. tostring(CONFIG.ReturnDelay) .. "s")
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
			updateStatus("🚶 Walking to " .. npc.Name)
		else
			hrp.CFrame = npcHrp.CFrame
			updateStatus("🎯 Hunting: " .. npc.Name)
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
			updateStatus("🏥 Using health spot...")
			continue
		end

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
			updateStatus("💀 Recovering...")
			task.wait(2)
			continue
		end

		if nowInCombat then
			if myTurn and not hasActed() then
				processTurnActions()
				task.wait(CONFIG.ActionCooldown)
			else
				updateStatus("⏳ Waiting on Enemy...")
			end
		else
			if #CONFIG.TargetNPCs == 0 then
				updateStatus("📍 Select targets first!")
			else
				local targetNPC = findOptimalNPC()
				if targetNPC then
					travelToNPC(targetNPC)
				else
					updateStatus("🔍 Searching for targets...")
				end
			end
		end
	end
end

-- ======= INITIALIZATION =======
uiElements.ToggleBtn.MouseButton1Click:Connect(function()
	if #CONFIG.TargetNPCs == 0 and not CONFIG.AutofarmActive then
		updateStatus("⚠ Please select targets first!")
		return
	end

	CONFIG.AutofarmActive = not CONFIG.AutofarmActive
	if CONFIG.AutofarmActive then
		uiElements.ToggleBtn.Text = "⏹ STOP AUTOFARM"
		smoothTween(uiElements.ToggleBtn, 0.25, {BackgroundColor3 = COLORS.Danger})
		smoothTween(uiElements.ToggleBtn:FindFirstChildOfClass("UIStroke"), 0.25, {Color = COLORS.Danger})
		scanNPCNames()
		lastCombatState = isInCombat()
		if not lastCombatState then
			saveCurrentPosition()
			resetAbilityCooldownTracking()
		end
		updateStatus("✓ Autofarm running!")
		task.spawn(mainControlLoop)
	else
		uiElements.ToggleBtn.Text = "▶ START AUTOFARM"
		smoothTween(uiElements.ToggleBtn, 0.25, {BackgroundColor3 = COLORS.Success})
		smoothTween(uiElements.ToggleBtn:FindFirstChildOfClass("UIStroke"), 0.25, {Color = COLORS.Success})
		updateStatus("⏹ Autofarm stopped")

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
