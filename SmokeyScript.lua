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

-- ======= PREMIUM COLOR PALETTE 🌈 =======
local COLORS = {
	-- Backgrounds
	BgDark = Color3.fromRGB(15, 15, 25),
	BgMedium = Color3.fromRGB(25, 28, 45),
	BgLight = Color3.fromRGB(35, 38, 55),
	
	-- Primary & Secondary
	Primary = Color3.fromRGB(220, 100, 200),
	Secondary = Color3.fromRGB(100, 200, 255),
	Tertiary = Color3.fromRGB(255, 170, 100),
	
	-- Accents
	Accent = Color3.fromRGB(255, 150, 200),
	AccentAlt = Color3.fromRGB(150, 100, 255),
	
	-- Text
	Text = Color3.fromRGB(240, 240, 255),
	TextDim = Color3.fromRGB(180, 190, 220),
	TextMuted = Color3.fromRGB(130, 140, 170),
	
	-- Status
	Success = Color3.fromRGB(100, 220, 150),
	Danger = Color3.fromRGB(255, 100, 100),
	Warning = Color3.fromRGB(255, 200, 100),
	Info = Color3.fromRGB(100, 180, 255),
	
	-- Special
	Glow = Color3.fromRGB(255, 150, 200),
	Purple = Color3.fromRGB(200, 120, 255),
	Cyan = Color3.fromRGB(100, 220, 255),
}

-- ======= ADVANCED TWEEN SYSTEM =======
local function createAdvancedTween(object, duration, targetProps, easingStyle, easingDirection)
	if not object or not object.Parent then return nil end
	
	easingStyle = easingStyle or Enum.EasingStyle.Quad
	easingDirection = easingDirection or Enum.EasingDirection.InOut
	
	if TweenService then
		local tweenInfo = TweenInfo.new(duration, easingStyle, easingDirection)
		local tween = TweenService:Create(object, tweenInfo, targetProps)
		tween:Play()
		return tween
	end
	return nil
end

-- ======= PREMIUM VFX EFFECTS =======
local function createNeonGlow(parent, color, intensity)
	intensity = intensity or 1
	local glow = Instance.new("Frame")
	glow.Size = UDim2.new(1.2, 0, 1.2, 0)
	glow.Position = UDim2.new(-0.1, 0, -0.1, 0)
	glow.BackgroundColor3 = color
	glow.BorderSizePixel = 0
	glow.BackgroundTransparency = 0.7
	glow.Parent = parent
	glow.ZIndex = parent.ZIndex - 1
	
	Instance.new("UICorner", glow).CornerRadius = UDim.new(0, 50)
	
	local blur = Instance.new("UIBlur", glow)
	blur.Size = 15 * intensity
	
	return glow
end

local function createRippleEffect(parent, color)
	local ripple = Instance.new("Frame")
	ripple.Size = UDim2.new(0, 0, 0, 0)
	ripple.Position = UDim2.new(0.5, 0, 0.5, 0)
	ripple.AnchorPoint = Vector2.new(0.5, 0.5)
	ripple.BackgroundColor3 = color
	ripple.BorderSizePixel = 0
	ripple.BackgroundTransparency = 0.5
	ripple.Parent = parent
	
	Instance.new("UICorner", ripple).CornerRadius = UDim.new(1, 0)
	
	task.spawn(function()
		createAdvancedTween(ripple, 0.6, {
			Size = UDim2.new(1.5, 0, 1.5, 0),
			BackgroundTransparency = 1
		}, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		task.wait(0.7)
		if ripple and ripple.Parent then
			ripple:Destroy()
		end
	end)
end

local function createParticleExplosion(parent, color, count)
	count = count or 12
	for i = 1, count do
		local particle = Instance.new("Frame")
		particle.Size = UDim2.new(0, 6, 0, 6)
		particle.BackgroundColor3 = color
		particle.BorderSizePixel = 0
		particle.BackgroundTransparency = 0.3
		particle.Parent = parent
		
		Instance.new("UICorner", particle).CornerRadius = UDim.new(1, 0)
		
		local angle = (i / count) * math.pi * 2
		local distance = 60
		local startPos = UDim2.new(0.5, math.cos(angle) * 5 - 3, 0.5, math.sin(angle) * 5 - 3)
		
		particle.Position = startPos
		
		task.spawn(function()
			createAdvancedTween(particle, 0.8, {
				Position = UDim2.new(0.5, math.cos(angle) * distance - 3, 0.5, math.sin(angle) * distance - 3),
				BackgroundTransparency = 1
			}, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
		end)
		
		task.delay(0.9, function()
			if particle and particle.Parent then
				particle:Destroy()
			end
		end)
	end
end

-- ======= PREMIUM LOADING ANIMATION =======
local function createPremiumLoadingScreen()
	local container = Instance.new("Frame")
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 1, 0)
	
	-- Animated background
	local bgAnim = Instance.new("Frame")
	bgAnim.Size = UDim2.new(1, 0, 1, 0)
	bgAnim.BackgroundColor3 = COLORS.BgDark
	bgAnim.BorderSizePixel = 0
	bgAnim.Parent = container
	bgAnim.ZIndex = 1
	
	local bgGradient = Instance.new("UIGradient", bgAnim)
	bgGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLORS.BgDark),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(40, 35, 80)),
		ColorSequenceKeypoint.new(1, COLORS.BgDark)
	})
	
	-- Loading box
	local loadingBox = Instance.new("Frame")
	loadingBox.Size = UDim2.new(0, 320, 0, 320)
	loadingBox.Position = UDim2.new(0.5, -160, 0.5, -160)
	loadingBox.BackgroundColor3 = COLORS.BgMedium
	loadingBox.BackgroundTransparency = 0.1
	loadingBox.BorderSizePixel = 0
	loadingBox.Parent = container
	loadingBox.ZIndex = 2
	loadingBox.ClipsDescendants = true
	
	local corner = Instance.new("UICorner", loadingBox)
	corner.CornerRadius = UDim.new(0, 30)
	
	local stroke = Instance.new("UIStroke", loadingBox)
	stroke.Color = COLORS.Primary
	stroke.Thickness = 3
	stroke.Transparency = 0.2
	
	-- Neon glow
	local glowBox = Instance.new("Frame")
	glowBox.Size = UDim2.new(1.15, 0, 1.15, 0)
	glowBox.Position = UDim2.new(-0.075, 0, -0.075, 0)
	glowBox.BackgroundColor3 = COLORS.Primary
	glowBox.BorderSizePixel = 0
	glowBox.BackgroundTransparency = 0.85
	glowBox.Parent = loadingBox
	glowBox.ZIndex = 0
	
	Instance.new("UICorner", glowBox).CornerRadius = UDim.new(0, 30)
	
	-- Rotating border effect
	local borderFrame = Instance.new("Frame")
	borderFrame.Size = UDim2.new(1, 0, 1, 0)
	borderFrame.BackgroundTransparency = 1
	borderFrame.Parent = loadingBox
	borderFrame.ZIndex = 2
	
	for i = 1, 4 do
		local segment = Instance.new("Frame")
		segment.Size = UDim2.new(0.3, 0, 0.02, 0)
		segment.BackgroundColor3 = COLORS.Primary
		segment.BorderSizePixel = 0
		segment.Parent = borderFrame
		segment.Rotation = i * 90
		segment.Position = UDim2.new(0.35, 0, -0.01, 0)
	end
	
	task.spawn(function()
		while borderFrame and borderFrame.Parent do
			createAdvancedTween(borderFrame, 3, {
				Rotation = 360
			}, Enum.EasingStyle.Linear)
			task.wait(3)
			if borderFrame and borderFrame.Parent then
				borderFrame.Rotation = 0
			end
		end
	end)
	
	-- Pulsing emoji
	local emoji = Instance.new("TextLabel")
	emoji.Size = UDim2.new(0, 100, 0, 100)
	emoji.Position = UDim2.new(0.5, -50, 0.5, -80)
	emoji.BackgroundTransparency = 1
	emoji.Text = "⚡"
	emoji.TextSize = 70
	emoji.Parent = loadingBox
	emoji.ZIndex = 3
	
	task.spawn(function()
		local emojis = {"⚡", "✨", "🌟", "💫"}
		local idx = 1
		while emoji and emoji.Parent do
			task.wait(0.5)
			if emoji and emoji.Parent then
				emoji.Text = emojis[idx]
				idx = (idx % #emojis) + 1
			end
		end
	end)
	
	-- Pulsing animation for emoji
	task.spawn(function()
		while emoji and emoji.Parent do
			createAdvancedTween(emoji, 0.8, {
				TextTransparency = 0.2,
				TextSize = 85
			}, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			task.wait(0.8)
			if emoji and emoji.Parent then
				createAdvancedTween(emoji, 0.8, {
					TextTransparency = 0,
					TextSize = 70
				}, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
				task.wait(0.8)
			end
		end
	end)
	
	-- Loading text with animation
	local loadText = Instance.new("TextLabel")
	loadText.Size = UDim2.new(1, 0, 0, 40)
	loadText.Position = UDim2.new(0, 0, 0.65, 0)
	loadText.BackgroundTransparency = 1
	loadText.Text = "CARREGANDO"
	loadText.TextColor3 = COLORS.Primary
	loadText.Font = Enum.Font.GothamBlack
	loadText.TextSize = 16
	loadText.Parent = loadingBox
	loadText.ZIndex = 3
	
	-- Animated dots
	task.spawn(function()
		local dots = 0
		while loadText and loadText.Parent do
			dots = (dots + 1) % 4
			loadText.Text = "CARREGANDO" .. string.rep(".", dots)
			task.wait(0.4)
		end
	end)
	
	-- Percentage
	local percentLabel = Instance.new("TextLabel")
	percentLabel.Size = UDim2.new(1, 0, 0, 30)
	percentLabel.Position = UDim2.new(0, 0, 0.82, 0)
	percentLabel.BackgroundTransparency = 1
	percentLabel.Text = "0%"
	percentLabel.TextColor3 = COLORS.Secondary
	percentLabel.Font = Enum.Font.GothamMedium
	percentLabel.TextSize = 14
	percentLabel.Parent = loadingBox
	percentLabel.ZIndex = 3
	
	-- Progress bar
	local progressBg = Instance.new("Frame")
	progressBg.Size = UDim2.new(0.8, 0, 0, 6)
	progressBg.Position = UDim2.new(0.1, 0, 0.9, 0)
	progressBg.BackgroundColor3 = COLORS.BgDark
	progressBg.BorderSizePixel = 0
	progressBg.Parent = loadingBox
	progressBg.ZIndex = 3
	
	Instance.new("UICorner", progressBg).CornerRadius = UDim.new(1, 0)
	
	local progressFill = Instance.new("Frame")
	progressFill.Size = UDim2.new(0, 0, 1, 0)
	progressFill.BackgroundColor3 = COLORS.Primary
	progressFill.BorderSizePixel = 0
	progressFill.Parent = progressBg
	progressFill.ZIndex = 3
	
	Instance.new("UICorner", progressFill).CornerRadius = UDim.new(1, 0)
	
	-- Simulate loading progress
	task.spawn(function()
		for progress = 0, 100, 2 do
			if percentLabel and percentLabel.Parent then
				percentLabel.Text = progress .. "%"
				createAdvancedTween(progressFill, 0.1, {
					Size = UDim2.new(progress / 100, 0, 1, 0)
				})
				task.wait(0.1)
			end
		end
	end)
	
	return container
end

-- ======= MAIN UI SYSTEM =======
local uiElements = {}
local isDragging = false
local dragInput = nil
local dragStart = nil
local startPos = nil
local uiVisible = true
local mainFrame = nil
local screenGui = nil

updateStatus = function(text)
	if uiElements.StatusLabel then
		uiElements.StatusLabel.Text = text
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

local function createAdvancedButton(text, callback, buttonColor)
	buttonColor = buttonColor or COLORS.Secondary
	
	local btnContainer = Instance.new("Frame")
	btnContainer.Size = UDim2.new(1, 0, 0, 46)
	btnContainer.BackgroundTransparency = 1
	btnContainer.Parent = nil
	
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.BackgroundColor3 = buttonColor
	btn.BackgroundTransparency = 0.5
	btn.TextColor3 = COLORS.Text
	btn.Font = Enum.Font.GothamSemibold
	btn.TextSize = 12
	btn.Text = text
	btn.Parent = btnContainer
	btn.ZIndex = 5
	
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 16)
	
	local btnStroke = Instance.new("UIStroke", btn)
	btnStroke.Color = buttonColor
	btnStroke.Transparency = 0.4
	btnStroke.Thickness = 2
	
	-- Glow effect
	local glow = Instance.new("Frame")
	glow.Size = UDim2.new(1.1, 0, 1.1, 0)
	glow.Position = UDim2.new(-0.05, 0, -0.05, 0)
	glow.BackgroundColor3 = buttonColor
	glow.BorderSizePixel = 0
	glow.BackgroundTransparency = 0.9
	glow.Parent = btnContainer
	glow.ZIndex = 4
	
	Instance.new("UICorner", glow).CornerRadius = UDim.new(0, 16)
	
	btn.MouseEnter:Connect(function()
		createAdvancedTween(btn, 0.2, {
			BackgroundTransparency = 0.2
		}, Enum.EasingStyle.Quad)
		createAdvancedTween(btnStroke, 0.2, {
			Transparency = 0.1
		})
		createAdvancedTween(glow, 0.2, {
			BackgroundTransparency = 0.7
		})
		createParticleExplosion(btn, buttonColor, 8)
	end)
	
	btn.MouseLeave:Connect(function()
		createAdvancedTween(btn, 0.2, {
			BackgroundTransparency = 0.5
		}, Enum.EasingStyle.Quad)
		createAdvancedTween(btnStroke, 0.2, {
			Transparency = 0.4
		})
		createAdvancedTween(glow, 0.2, {
			BackgroundTransparency = 0.9
		})
	end)
	
	btn.MouseButton1Down:Connect(function()
		createRippleEffect(btn, buttonColor)
		createAdvancedTween(btn, 0.08, {
			Size = UDim2.new(0.95, 0, 0.95, 0)
		}, Enum.EasingStyle.Back)
	end)
	
	btn.MouseButton1Up:Connect(function()
		createAdvancedTween(btn, 0.12, {
			Size = UDim2.new(1, 0, 1, 0)
		}, Enum.EasingStyle.Back)
		
		task.wait(0.05)
		local result = callback()
		if typeof(result) == "string" and result ~= "" then
			local originalText = text
			btn.Text = result
			task.spawn(function()
				task.wait(2)
				btn.Text = originalText
			end)
		end
	end)
	
	return btn, btnContainer
end

local function createAdvancedToggle(text, configKey)
	local toggleContainer = Instance.new("Frame")
	toggleContainer.Size = UDim2.new(1, 0, 0, 46)
	toggleContainer.BackgroundTransparency = 1
	toggleContainer.Parent = nil
	
	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = CONFIG[configKey] and COLORS.Success or COLORS.Secondary
	bg.BackgroundTransparency = 0.5
	bg.Parent = toggleContainer
	
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 16)
	
	local bgStroke = Instance.new("UIStroke", bg)
	bgStroke.Color = CONFIG[configKey] and COLORS.Success or COLORS.Secondary
	bgStroke.Transparency = 0.4
	bgStroke.Thickness = 2
	
	-- Glow
	local glow = Instance.new("Frame")
	glow.Size = UDim2.new(1.1, 0, 1.1, 0)
	glow.Position = UDim2.new(-0.05, 0, -0.05, 0)
	glow.BackgroundColor3 = CONFIG[configKey] and COLORS.Success or COLORS.Secondary
	glow.BorderSizePixel = 0
	glow.BackgroundTransparency = 0.9
	glow.Parent = toggleContainer
	glow.ZIndex = -1
	
	Instance.new("UICorner", glow).CornerRadius = UDim.new(0, 16)
	
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.BackgroundTransparency = 1
	btn.TextColor3 = COLORS.Text
	btn.Font = Enum.Font.GothamSemibold
	btn.TextSize = 12
	btn.Text = (CONFIG[configKey] and "✓ " or "○ ") .. text
	btn.Parent = bg
	
	btn.MouseEnter:Connect(function()
		createAdvancedTween(bg, 0.2, {BackgroundTransparency = 0.3})
		createAdvancedTween(glow, 0.2, {BackgroundTransparency = 0.7})
		createParticleExplosion(bg, CONFIG[configKey] and COLORS.Success or COLORS.Secondary, 6)
	end)
	
	btn.MouseLeave:Connect(function()
		createAdvancedTween(bg, 0.2, {BackgroundTransparency = 0.5})
		createAdvancedTween(glow, 0.2, {BackgroundTransparency = 0.9})
	end)
	
	btn.MouseButton1Click:Connect(function()
		createRippleEffect(bg, COLORS.Primary)
		CONFIG[configKey] = not CONFIG[configKey]
		
		local newColor = CONFIG[configKey] and COLORS.Success or COLORS.Secondary
		createAdvancedTween(bg, 0.3, {
			BackgroundColor3 = newColor,
		}, Enum.EasingStyle.Quad)
		createAdvancedTween(bgStroke, 0.3, {
			Color = newColor,
		})
		createAdvancedTween(glow, 0.3, {
			BackgroundColor3 = newColor,
		})
		
		btn.Text = (CONFIG[configKey] and "✓ " or "○ ") .. text
	end)
	
	return btn, toggleContainer
end

local function createAdvancedStatBar(label, getValue, getMax, color)
	local statContainer = Instance.new("Frame")
	statContainer.Size = UDim2.new(1, 0, 0, 56)
	statContainer.BackgroundTransparency = 1
	statContainer.Parent = nil
	
	local statLabel = Instance.new("TextLabel")
	statLabel.Size = UDim2.new(1, 0, 0, 18)
	statLabel.BackgroundTransparency = 1
	statLabel.TextColor3 = COLORS.TextDim
	statLabel.Font = Enum.Font.GothamMedium
	statLabel.TextSize = 10
	statLabel.Text = label .. ": --/--"
	statLabel.TextXAlignment = Enum.TextXAlignment.Left
	statLabel.Parent = statContainer
	
	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, 0, 0, 26)
	barBg.Position = UDim2.new(0, 0, 0, 24)
	barBg.BackgroundColor3 = COLORS.BgDark
	barBg.BackgroundTransparency = 0.4
	barBg.Parent = statContainer
	
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 12)
	
	local barStroke = Instance.new("UIStroke", barBg)
	barStroke.Color = color
	barStroke.Transparency = 0.4
	barStroke.Thickness = 1.5
	
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(0.5, 0, 1, 0)
	barFill.BackgroundColor3 = color
	barFill.BackgroundTransparency = 0
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg
	
	Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 12)
	
	-- Glow effect on bar
	local barGlow = Instance.new("Frame")
	barGlow.Size = UDim2.new(1.1, 0, 1.2, 0)
	barGlow.Position = UDim2.new(-0.05, 0, -0.1, 0)
	barGlow.BackgroundColor3 = color
	barGlow.BorderSizePixel = 0
	barGlow.BackgroundTransparency = 0.85
	barGlow.Parent = barBg
	barGlow.ZIndex = 0
	
	Instance.new("UICorner", barGlow).CornerRadius = UDim.new(0, 12)
	
	task.spawn(function()
		while statContainer and statContainer.Parent do
			local current, max = getValue(), getMax()
			local ratio = max > 0 and (current / max) or 0
			ratio = math.max(0, math.min(1, ratio))
			
			createAdvancedTween(barFill, 0.4, {Size = UDim2.new(ratio, 0, 1, 0)}, Enum.EasingStyle.Quad)
			statLabel.Text = label .. ": " .. math.floor(current) .. "/" .. math.floor(max)
			
			task.wait(0.4)
		end
	end)
	
	return statContainer
end

local function createPremiumGUI()
	local targetParent = (type(gethui) == "function" and gethui()) or game:GetService("CoreGui") or player:WaitForChild("PlayerGui")
	
	local existing = targetParent:FindFirstChild("NarutoBot")
	if existing then existing:Destroy() end
	
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "NarutoBot"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 999
	screenGui.Parent = targetParent
	
	-- ======= LOADING SCREEN =======
	local loadingScreenGui = Instance.new("ScreenGui")
	loadingScreenGui.Name = "LoadingScreen"
	loadingScreenGui.ResetOnSpawn = false
	loadingScreenGui.DisplayOrder = 10000
	loadingScreenGui.Parent = targetParent
	
	local loadingContainer = createPremiumLoadingScreen()
	loadingContainer.Parent = loadingScreenGui
	
	-- ======= MAIN FRAME =======
	mainFrame = Instance.new("Frame")
	mainFrame.Size = UDim2.new(0, 480, 0, 800)
	mainFrame.Position = UDim2.new(0.5, -240, 0.5, -400)
	mainFrame.BackgroundColor3 = COLORS.BgMedium
	mainFrame.BackgroundTransparency = 0.05
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui
	mainFrame.ClipsDescendants = true
	mainFrame.ZIndex = 999
	
	Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 35)
	
	local mainStroke = Instance.new("UIStroke", mainFrame)
	mainStroke.Color = COLORS.Primary
	mainStroke.Transparency = 0.15
	mainStroke.Thickness = 2.5
	
	-- Neon border glow
	local neonGlow = createNeonGlow(mainFrame, COLORS.Primary, 0.8)
	
	-- ======= ANIMATED TITLEBAR =======
	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 110)
	titleBar.BackgroundColor3 = COLORS.BgDark
	titleBar.BackgroundTransparency = 0.2
	titleBar.BorderSizePixel = 0
	titleBar.Parent = mainFrame
	titleBar.ZIndex = 100
	
	local titleGradient = Instance.new("UIGradient", titleBar)
	titleGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLORS.Primary),
		ColorSequenceKeypoint.new(0.5, COLORS.AccentAlt),
		ColorSequenceKeypoint.new(1, COLORS.Accent)
	})
	titleGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.87),
		NumberSequenceKeypoint.new(1, 0.93)
	})
	
	Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 35)
	
	-- Avatar with rotation
	local avatar = Instance.new("TextLabel")
	avatar.Size = UDim2.new(0, 80, 0, 80)
	avatar.Position = UDim2.new(0, 15, 0.5, -40)
	avatar.BackgroundTransparency = 1
	avatar.Text = "⚡"
	avatar.TextSize = 60
	avatar.Parent = titleBar
	avatar.ZIndex = 110
	
	task.spawn(function()
		while avatar and avatar.Parent do
			createAdvancedTween(avatar, 3, {Rotation = 360}, Enum.EasingStyle.Linear)
			task.wait(3)
			if avatar and avatar.Parent then
				avatar.Rotation = 0
			end
		end
	end)
	
	-- Title text
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -180, 0, 40)
	title.Position = UDim2.new(0, 100, 0, 10)
	title.BackgroundTransparency = 1
	title.Text = "NARUTO BOT"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 24
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Parent = titleBar
	title.ZIndex = 110
	
	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -180, 0, 35)
	subtitle.Position = UDim2.new(0, 100, 0, 50)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "✨ Premium Autofarm System ✨"
	subtitle.TextColor3 = COLORS.Accent
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextSize = 11
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Parent = titleBar
	subtitle.ZIndex = 110
	
	-- Control buttons
	local minimizeBtn = Instance.new("TextButton")
	minimizeBtn.Size = UDim2.new(0, 42, 0, 42)
	minimizeBtn.Position = UDim2.new(1, -95, 0.5, -21)
	minimizeBtn.BackgroundColor3 = COLORS.Secondary
	minimizeBtn.BackgroundTransparency = 0.35
	minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	minimizeBtn.Font = Enum.Font.GothamBold
	minimizeBtn.TextSize = 22
	minimizeBtn.Text = "−"
	minimizeBtn.Parent = titleBar
	minimizeBtn.ZIndex = 110
	
	Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 14)
	
	local minimizeStroke = Instance.new("UIStroke", minimizeBtn)
	minimizeStroke.Color = COLORS.Secondary
	minimizeStroke.Transparency = 0.3
	minimizeStroke.Thickness = 1.5
	
	minimizeBtn.MouseEnter:Connect(function()
		createAdvancedTween(minimizeBtn, 0.2, {BackgroundTransparency = 0.15}, Enum.EasingStyle.Quad)
		createParticleExplosion(minimizeBtn, COLORS.Secondary, 6)
	end)
	
	minimizeBtn.MouseLeave:Connect(function()
		createAdvancedTween(minimizeBtn, 0.2, {BackgroundTransparency = 0.35})
	end)
	
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 42, 0, 42)
	closeBtn.Position = UDim2.new(1, -42, 0.5, -21)
	closeBtn.BackgroundColor3 = COLORS.Danger
	closeBtn.BackgroundTransparency = 0.35
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 20
	closeBtn.Text = "✕"
	closeBtn.Parent = titleBar
	closeBtn.ZIndex = 110
	
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 14)
	
	local closeStroke = Instance.new("UIStroke", closeBtn)
	closeStroke.Color = COLORS.Danger
	closeStroke.Transparency = 0.3
	closeStroke.Thickness = 1.5
	
	closeBtn.MouseEnter:Connect(function()
		createAdvancedTween(closeBtn, 0.2, {BackgroundTransparency = 0.15}, Enum.EasingStyle.Quad)
		createParticleExplosion(closeBtn, COLORS.Danger, 6)
	end)
	
	closeBtn.MouseLeave:Connect(function()
		createAdvancedTween(closeBtn, 0.2, {BackgroundTransparency = 0.35})
	end)
	
	-- ======= SCROLLING CONTENT =======
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Size = UDim2.new(1, -24, 1, -240)
	scrollFrame.Position = UDim2.new(0, 12, 0, 120)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 5
	scrollFrame.ScrollBarImageColor3 = COLORS.Primary
	scrollFrame.ScrollBarImageTransparency = 0.4
	scrollFrame.Parent = mainFrame
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 12)
	listLayout.Parent = scrollFrame
	
	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 24)
	end)
	
	-- ======= SECTION DIVIDER =======
	local function createSectionDivider(text)
		local divider = Instance.new("Frame")
		divider.Size = UDim2.new(1, 0, 0, 45)
		divider.BackgroundTransparency = 1
		divider.Parent = scrollFrame
		
		local line = Instance.new("Frame")
		line.Size = UDim2.new(1, 0, 0, 1.5)
		line.Position = UDim2.new(0, 0, 0.5, -1)
		line.BackgroundColor3 = COLORS.Primary
		line.BackgroundTransparency = 0.5
		line.BorderSizePixel = 0
		line.Parent = divider
		
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -40, 0, 24)
		label.Position = UDim2.new(0, 20, 0, 8)
		label.BackgroundColor3 = COLORS.BgMedium
		label.BackgroundTransparency = 0.2
		label.BorderSizePixel = 0
		label.TextColor3 = COLORS.Primary
		label.Font = Enum.Font.GothamBlack
		label.TextSize = 11
		label.Text = text
		label.Parent = divider
		
		Instance.new("UICorner", label).CornerRadius = UDim.new(0, 8)
	end
	
	-- ======= TARGET SECTION =======
	createSectionDivider("🎯 TARGET SELECTION")
	
	local targetLabel = Instance.new("TextLabel")
	targetLabel.Size = UDim2.new(1, 0, 0, 50)
	targetLabel.BackgroundColor3 = COLORS.Accent
	targetLabel.BackgroundTransparency = 0.65
	targetLabel.TextColor3 = COLORS.Text
	targetLabel.Font = Enum.Font.GothamMedium
	targetLabel.TextSize = 10
	targetLabel.Text = "🎯 No targets selected"
	targetLabel.TextXAlignment = Enum.TextXAlignment.Left
	targetLabel.TextWrapped = true
	targetLabel.Parent = scrollFrame
	targetLabel.ZIndex = 5
	
	Instance.new("UICorner", targetLabel).CornerRadius = UDim.new(0, 14)
	
	local targetStroke = Instance.new("UIStroke", targetLabel)
	targetStroke.Color = COLORS.Accent
	targetStroke.Transparency = 0.3
	targetStroke.Thickness = 1.5
	
	local targetPadding = Instance.new("UIPadding", targetLabel)
	targetPadding.PaddingLeft = UDim.new(0, 14)
	targetPadding.PaddingRight = UDim.new(0, 14)
	targetPadding.PaddingTop = UDim.new(0, 8)
	targetPadding.PaddingBottom = UDim.new(0, 8)
	
	uiElements.TargetLabel = targetLabel
	
	local _, selectTargetsBtn = createAdvancedButton("🎯 SELECT TARGETS", function()
		scanNPCNames()
		uiElements.ShowTargetMenu()
	end, COLORS.Accent)
	selectTargetsBtn.Parent = scrollFrame
	
	-- ======= MOVEMENT SECTION =======
	createSectionDivider("🚀 MOVEMENT")
	
	local _, moveBtn = createAdvancedButton("🚀 Movement: " .. CONFIG.MoveMode, function()
		CONFIG.MoveMode = (CONFIG.MoveMode == "Walk") and "Teleport" or "Walk"
		return "🚀 Movement: " .. CONFIG.MoveMode
	end, COLORS.Tertiary)
	moveBtn.Parent = scrollFrame
	
	-- ======= STATS SECTION =======
	createSectionDivider("⚡ STATS & RESOURCES")
	
	local chakraBar = createAdvancedStatBar("⚡ Chakra", function() return (getChakraData()) end, function() return (select(2, getChakraData())) end, COLORS.Secondary)
	chakraBar.Parent = scrollFrame
	
	local healthBar = createAdvancedStatBar("❤ Health", function() return (player.Character and player.Character:FindFirstChildOfClass("Humanoid") and player.Character:FindFirstChildOfClass("Humanoid").Health or 0) end, function() return (player.Character and player.Character:FindFirstChildOfClass("Humanoid") and player.Character:FindFirstChildOfClass("Humanoid").MaxHealth or 100) end, COLORS.Danger)
	healthBar.Parent = scrollFrame
	
	-- ======= DELAY & HEALTH SECTION =======
	createSectionDivider("⏱ TIMING & RECOVERY")
	
	local _, returnDelayBtn = createAdvancedButton("⏱ Return Delay: " .. tostring(CONFIG.ReturnDelay) .. "s", function()
		CONFIG.ReturnDelay += 1
		if CONFIG.ReturnDelay > 10 then
			CONFIG.ReturnDelay = 0
		end
		return "⏱ Return Delay: " .. tostring(CONFIG.ReturnDelay) .. "s"
	end, COLORS.Warning)
	returnDelayBtn.Parent = scrollFrame
	
	local _, healthThresholdBtn = createAdvancedButton("🏥 HP Threshold: " .. tostring(math.floor(CONFIG.AutoHealthThreshold * 100)) .. "%", function()
		CONFIG.AutoHealthThreshold += 0.1
		if CONFIG.AutoHealthThreshold > 0.9 then
			CONFIG.AutoHealthThreshold = 0.1
		end
		return "🏥 HP Threshold: " .. tostring(math.floor(CONFIG.AutoHealthThreshold * 100)) .. "%"
	end, COLORS.Danger)
	healthThresholdBtn.Parent = scrollFrame
	
	local _, chakraThresholdBtn = createAdvancedButton("⚡ Chakra Threshold: " .. tostring(math.floor(CONFIG.AutoChakraThreshold * 100)) .. "%", function()
		CONFIG.AutoChakraThreshold += 0.1
		if CONFIG.AutoChakraThreshold > 0.9 then
			CONFIG.AutoChakraThreshold = 0.1
		end
		return "⚡ Chakra Threshold: " .. tostring(math.floor(CONFIG.AutoChakraThreshold * 100)) .. "%"
	end, COLORS.Secondary)
	chakraThresholdBtn.Parent = scrollFrame
	
	local _, healthBtn = createAdvancedButton("💊 Use Health", function()
		local healthRefillFn = _G.GlassFarmProUseHealthRefill
		if type(healthRefillFn) ~= "function" then
			return ""
		end
		return healthRefillFn() and "✓ Used" or "✕ Failed"
	end, COLORS.Success)
	healthBtn.Parent = scrollFrame
	
	-- ======= TOGGLES SECTION =======
	createSectionDivider("⚙ OPTIONS")
	
	local _, healthEnableToggle = createAdvancedToggle("Health Refill", "HealthEnabled")
	healthEnableToggle.Parent = scrollFrame
	
	local _, healDuringCombatToggle = createAdvancedToggle("Heal During Combat", "HealDuringCombat")
	healDuringCombatToggle.Parent = scrollFrame
	
	local _, abilitiesToggle = createAdvancedToggle("Use Abilities", "AutoAbility")
	abilitiesToggle.Parent = scrollFrame
	
	local _, antiAFKToggle = createAdvancedToggle("Anti AFK", "AntiAFK")
	antiAFKToggle.Parent = scrollFrame
	
	-- ======= BOTTOM PANEL =======
	local bottomPanel = Instance.new("Frame")
	bottomPanel.Size = UDim2.new(1, 0, 0, 130)
	bottomPanel.Position = UDim2.new(0, 0, 1, -130)
	bottomPanel.BackgroundColor3 = COLORS.BgDark
	bottomPanel.BackgroundTransparency = 0.2
	bottomPanel.BorderSizePixel = 0
	bottomPanel.Parent = mainFrame
	
	Instance.new("UICorner", bottomPanel).CornerRadius = UDim.new(0, 35)
	
	local bottomStroke = Instance.new("UIStroke", bottomPanel)
	bottomStroke.Color = COLORS.Primary
	bottomStroke.Transparency = 0.4
	bottomStroke.Thickness = 2
	
	-- Status label
	uiElements.StatusLabel = Instance.new("TextLabel")
	uiElements.StatusLabel.Size = UDim2.new(1, -24, 0, 30)
	uiElements.StatusLabel.Position = UDim2.new(0, 12, 0, 8)
	uiElements.StatusLabel.BackgroundTransparency = 1
	uiElements.StatusLabel.TextColor3 = COLORS.Primary
	uiElements.StatusLabel.Text = "💫 Waiting for command..."
	uiElements.StatusLabel.Font = Enum.Font.GothamMedium
	uiElements.StatusLabel.TextSize = 12
	uiElements.StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	uiElements.StatusLabel.Parent = bottomPanel
	
	-- Toggle button
	uiElements.ToggleBtn = Instance.new("TextButton")
	uiElements.ToggleBtn.Size = UDim2.new(0.92, 0, 0, 52)
	uiElements.ToggleBtn.Position = UDim2.new(0.04, 0, 0, 44)
	uiElements.ToggleBtn.BackgroundColor3 = COLORS.Success
	uiElements.ToggleBtn.BackgroundTransparency = 0.3
	uiElements.ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	uiElements.ToggleBtn.Text = "▶ START"
	uiElements.ToggleBtn.Font = Enum.Font.GothamBlack
	uiElements.ToggleBtn.TextSize = 14
	uiElements.ToggleBtn.Parent = bottomPanel
	uiElements.ToggleBtn.ZIndex = 10
	
	Instance.new("UICorner", uiElements.ToggleBtn).CornerRadius = UDim.new(0, 14)
	
	local toggleStroke = Instance.new("UIStroke", uiElements.ToggleBtn)
	toggleStroke.Color = COLORS.Success
	toggleStroke.Transparency = 0.2
	toggleStroke.Thickness = 2
	
	local toggleGlow = Instance.new("Frame")
	toggleGlow.Size = UDim2.new(1.08, 0, 1.08, 0)
	toggleGlow.Position = UDim2.new(-0.04, 0, -0.04, 0)
	toggleGlow.BackgroundColor3 = COLORS.Success
	toggleGlow.BorderSizePixel = 0
	toggleGlow.BackgroundTransparency = 0.9
	toggleGlow.Parent = uiElements.ToggleBtn
	toggleGlow.ZIndex = 9
	
	Instance.new("UICorner", toggleGlow).CornerRadius = UDim.new(0, 14)
	
	uiElements.ToggleBtn.MouseEnter:Connect(function()
		createAdvancedTween(uiElements.ToggleBtn, 0.2, {BackgroundTransparency = 0.1}, Enum.EasingStyle.Quad)
		createAdvancedTween(toggleGlow, 0.2, {BackgroundTransparency = 0.7})
		createParticleExplosion(uiElements.ToggleBtn, COLORS.Success, 10)
	end)
	
	uiElements.ToggleBtn.MouseLeave:Connect(function()
		createAdvancedTween(uiElements.ToggleBtn, 0.2, {BackgroundTransparency = 0.3})
		createAdvancedTween(toggleGlow, 0.2, {BackgroundTransparency = 0.9})
	end)
	
	-- ======= TARGET SELECTION MENU =======
	local function createPremiumTargetMenu()
		local existing = targetParent:FindFirstChild("TargetMenuPremium")
		if existing then existing:Destroy() end
		
		local menuGui = Instance.new("ScreenGui")
		menuGui.Name = "TargetMenuPremium"
		menuGui.ResetOnSpawn = false
		menuGui.DisplayOrder = 2000
		menuGui.Parent = targetParent
		
		-- Animated backdrop
		local backdrop = Instance.new("Frame")
		backdrop.Size = UDim2.new(1, 0, 1, 0)
		backdrop.BackgroundColor3 = COLORS.BgDark
		backdrop.BackgroundTransparency = 0.5
		backdrop.BorderSizePixel = 0
		backdrop.Parent = menuGui
		backdrop.ZIndex = 1999
		
		-- Menu frame
		local menuFrame = Instance.new("Frame")
		menuFrame.Size = UDim2.new(0, 440, 0, 580)
		menuFrame.Position = UDim2.new(0.5, -220, 0.5, -290)
		menuFrame.BackgroundColor3 = COLORS.BgMedium
		menuFrame.BackgroundTransparency = 0.08
		menuFrame.BorderSizePixel = 0
		menuFrame.Parent = menuGui
		menuFrame.ZIndex = 2000
		menuFrame.ClipsDescendants = true
		
		Instance.new("UICorner", menuFrame).CornerRadius = UDim.new(0, 30)
		
		local menuStroke = Instance.new("UIStroke", menuFrame)
		menuStroke.Color = COLORS.Primary
		menuStroke.Transparency = 0.15
		menuStroke.Thickness = 2.5
		
		-- Neon glow
		createNeonGlow(menuFrame, COLORS.Primary, 0.6)
		
		-- Menu title
		local menuTitle = Instance.new("TextLabel")
		menuTitle.Size = UDim2.new(1, 0, 0, 70)
		menuTitle.BackgroundColor3 = COLORS.BgDark
		menuTitle.BackgroundTransparency = 0.15
		menuTitle.TextColor3 = COLORS.Primary
		menuTitle.Font = Enum.Font.GothamBlack
		menuTitle.TextSize = 18
		menuTitle.Text = "🎯 SELECT YOUR TARGETS"
		menuTitle.BorderSizePixel = 0
		menuTitle.Parent = menuFrame
		menuTitle.ZIndex = 2001
		
		Instance.new("UICorner", menuTitle).CornerRadius = UDim.new(0, 30)
		
		local menuScroll = Instance.new("ScrollingFrame")
		menuScroll.Size = UDim2.new(1, -24, 1, -160)
		menuScroll.Position = UDim2.new(0, 12, 0, 80)
		menuScroll.BackgroundTransparency = 1
		menuScroll.BorderSizePixel = 0
		menuScroll.ScrollBarThickness = 5
		menuScroll.ScrollBarImageColor3 = COLORS.Primary
		menuScroll.ScrollBarImageTransparency = 0.4
		menuScroll.Parent = menuFrame
		menuScroll.ZIndex = 2001
		menuScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		
		local menuLayout = Instance.new("UIListLayout")
		menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
		menuLayout.Padding = UDim.new(0, 10)
		menuLayout.Parent = menuScroll
		
		menuLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			menuScroll.CanvasSize = UDim2.new(0, 0, 0, menuLayout.AbsoluteContentSize.Y + 20)
		end)
		
		-- NPC checkboxes
		for idx, npcName in ipairs(availableNPCs) do
			local isSelected = table.find(CONFIG.TargetNPCs, npcName)
			
			local checkboxContainer = Instance.new("Frame")
			checkboxContainer.Size = UDim2.new(1, 0, 0, 44)
			checkboxContainer.BackgroundTransparency = 1
			checkboxContainer.Parent = menuScroll
			
			local checkboxBtn = Instance.new("TextButton")
			checkboxBtn.Size = UDim2.new(1, 0, 1, 0)
			checkboxBtn.BackgroundColor3 = isSelected and COLORS.Success or COLORS.Secondary
			checkboxBtn.BackgroundTransparency = 0.5
			checkboxBtn.TextColor3 = COLORS.Text
			checkboxBtn.Font = Enum.Font.GothamSemibold
			checkboxBtn.TextSize = 12
			checkboxBtn.Text = (isSelected and "✓ " or "  ") .. npcName
			checkboxBtn.Parent = checkboxContainer
			checkboxBtn.ZIndex = 2002
			
			Instance.new("UICorner", checkboxBtn).CornerRadius = UDim.new(0, 14)
			
			local cbStroke = Instance.new("UIStroke", checkboxBtn)
			cbStroke.Color = isSelected and COLORS.Success or COLORS.Secondary
			cbStroke.Transparency = 0.4
			cbStroke.Thickness = 1.5
			
			-- Glow
			local cbGlow = Instance.new("Frame")
			cbGlow.Size = UDim2.new(1.08, 0, 1.08, 0)
			cbGlow.Position = UDim2.new(-0.04, 0, -0.04, 0)
			cbGlow.BackgroundColor3 = isSelected and COLORS.Success or COLORS.Secondary
			cbGlow.BorderSizePixel = 0
			cbGlow.BackgroundTransparency = 0.9
			cbGlow.Parent = checkboxContainer
			cbGlow.ZIndex = 2001
			
			Instance.new("UICorner", cbGlow).CornerRadius = UDim.new(0, 14)
			
			checkboxBtn.MouseEnter:Connect(function()
				createAdvancedTween(checkboxBtn, 0.2, {BackgroundTransparency = 0.3})
				createAdvancedTween(cbGlow, 0.2, {BackgroundTransparency = 0.7})
				createParticleExplosion(checkboxBtn, isSelected and COLORS.Success or COLORS.Secondary, 6)
			end)
			
			checkboxBtn.MouseLeave:Connect(function()
				createAdvancedTween(checkboxBtn, 0.2, {BackgroundTransparency = 0.5})
				createAdvancedTween(cbGlow, 0.2, {BackgroundTransparency = 0.9})
			end)
			
			checkboxBtn.MouseButton1Click:Connect(function()
				createRippleEffect(checkboxBtn, COLORS.Primary)
				local idx = table.find(CONFIG.TargetNPCs, npcName)
				if idx then
					table.remove(CONFIG.TargetNPCs, idx)
				else
					table.insert(CONFIG.TargetNPCs, npcName)
				end
				
				local newIsSelected = table.find(CONFIG.TargetNPCs, npcName)
				local newColor = newIsSelected and COLORS.Success or COLORS.Secondary
				createAdvancedTween(checkboxBtn, 0.2, {
					BackgroundColor3 = newColor,
				}, Enum.EasingStyle.Quad)
				createAdvancedTween(cbStroke, 0.2, {
					Color = newColor,
				})
				createAdvancedTween(cbGlow, 0.2, {
					BackgroundColor3 = newColor,
				})
				checkboxBtn.Text = (newIsSelected and "✓ " or "  ") .. npcName
				uiElements.UpdateTargetLabel()
			end)
		end
		
		-- Bottom buttons
		local buttonContainer = Instance.new("Frame")
		buttonContainer.Size = UDim2.new(1, 0, 0, 70)
		buttonContainer.Position = UDim2.new(0, 0, 1, -70)
		buttonContainer.BackgroundColor3 = COLORS.BgDark
		buttonContainer.BackgroundTransparency = 0.3
		buttonContainer.BorderSizePixel = 0
		buttonContainer.Parent = menuFrame
		buttonContainer.ZIndex = 2001
		
		Instance.new("UICorner", buttonContainer).CornerRadius = UDim.new(0, 30)
		
		local confirmBtn = Instance.new("TextButton")
		confirmBtn.Size = UDim2.new(0.48, 0, 0, 50)
		confirmBtn.Position = UDim2.new(0.02, 0, 0.5, -25)
		confirmBtn.BackgroundColor3 = COLORS.Success
		confirmBtn.BackgroundTransparency = 0.3
		confirmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		confirmBtn.Font = Enum.Font.GothamBlack
		confirmBtn.TextSize = 13
		confirmBtn.Text = "✓ CONFIRM"
		confirmBtn.BorderSizePixel = 0
		confirmBtn.Parent = buttonContainer
		confirmBtn.ZIndex = 2002
		
		Instance.new("UICorner", confirmBtn).CornerRadius = UDim.new(0, 12)
		
		local confirmStroke = Instance.new("UIStroke", confirmBtn)
		confirmStroke.Color = COLORS.Success
		confirmStroke.Transparency = 0.2
		confirmStroke.Thickness = 1.5
		
		local cancelBtn = Instance.new("TextButton")
		cancelBtn.Size = UDim2.new(0.48, 0, 0, 50)
		cancelBtn.Position = UDim2.new(0.5, 0, 0.5, -25)
		cancelBtn.BackgroundColor3 = COLORS.Danger
		cancelBtn.BackgroundTransparency = 0.3
		cancelBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		cancelBtn.Font = Enum.Font.GothamBlack
		cancelBtn.TextSize = 13
		cancelBtn.Text = "✕ CANCEL"
		cancelBtn.BorderSizePixel = 0
		cancelBtn.Parent = buttonContainer
		cancelBtn.ZIndex = 2002
		
		Instance.new("UICorner", cancelBtn).CornerRadius = UDim.new(0, 12)
		
		local cancelStroke = Instance.new("UIStroke", cancelBtn)
		cancelStroke.Color = COLORS.Danger
		cancelStroke.Transparency = 0.2
		cancelStroke.Thickness = 1.5
		
		confirmBtn.MouseEnter:Connect(function()
			createAdvancedTween(confirmBtn, 0.2, {BackgroundTransparency = 0.1})
			createParticleExplosion(confirmBtn, COLORS.Success, 8)
		end)
		
		confirmBtn.MouseLeave:Connect(function()
			createAdvancedTween(confirmBtn, 0.2, {BackgroundTransparency = 0.3})
		end)
		
		cancelBtn.MouseEnter:Connect(function()
			createAdvancedTween(cancelBtn, 0.2, {BackgroundTransparency = 0.1})
			createParticleExplosion(cancelBtn, COLORS.Danger, 8)
		end)
		
		cancelBtn.MouseLeave:Connect(function()
			createAdvancedTween(cancelBtn, 0.2, {BackgroundTransparency = 0.3})
		end)
		
		confirmBtn.MouseButton1Click:Connect(function()
			createRippleEffect(confirmBtn, COLORS.Success)
			createAdvancedTween(menuFrame, 0.4, {Position = UDim2.new(0.5, -220, 0.5, 700)}, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			task.wait(0.4)
			menuGui:Destroy()
		end)
		
		cancelBtn.MouseButton1Click:Connect(function()
			createRippleEffect(cancelBtn, COLORS.Danger)
			CONFIG.TargetNPCs = {}
			createAdvancedTween(menuFrame, 0.4, {Position = UDim2.new(0.5, -220, 0.5, 700)}, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			task.wait(0.4)
			menuGui:Destroy()
			uiElements.UpdateTargetLabel()
		end)
		
		createAdvancedTween(menuFrame, 0.5, {Position = UDim2.new(0.5, -220, 0.5, -290)}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	
	uiElements.ShowTargetMenu = createPremiumTargetMenu
	
	uiElements.UpdateTargetLabel = function()
		if #CONFIG.TargetNPCs == 0 then
			targetLabel.Text = "🎯 No targets selected"
		else
			targetLabel.Text = "🎯 " .. table.concat(CONFIG.TargetNPCs, ", ")
		end
	end
	
	-- ======= DRAGGING FUNCTIONALITY =======
	local function onInputBegan(input, gameProcessed)
		if gameProcessed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			isDragging = true
			dragStart = input.Position
			startPos = mainFrame.Position
			dragInput = input
		end
	end
	
	local function onInputChanged(input)
		if input == dragInput and isDragging then
			local delta = input.Position - dragStart
			mainFrame.Position = startPos + UDim2.new(0, delta.X, 0, delta.Y)
		end
	end
	
	local function onInputEnded(input)
		if input == dragInput then
			isDragging = false
		end
	end
	
	titleBar.InputBegan:Connect(onInputBegan)
	titleBar.InputChanged:Connect(onInputChanged)
	UserInputService.InputEnded:Connect(onInputEnded)
	
	-- ======= BUTTON EVENTS =======
	minimizeBtn.MouseButton1Click:Connect(function()
		createRippleEffect(minimizeBtn, COLORS.Secondary)
		uiVisible = not uiVisible
		createAdvancedTween(mainFrame, 0.5, {
			Size = uiVisible and UDim2.new(0, 480, 0, 800) or UDim2.new(0, 480, 0, 110)
		}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end)
	
	closeBtn.MouseButton1Click:Connect(function()
		createRippleEffect(closeBtn, COLORS.Danger)
		createAdvancedTween(mainFrame, 0.5, {Position = UDim2.new(0.5, -240, 0.5, -1200)}, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.wait(0.5)
		uiElements.Cleanup()
	end)
	
	-- ======= LOADING FINISH =======
	task.wait(3)
	createAdvancedTween(loadingContainer, 0.6, {Size = UDim2.new(1, 0, 0, 0)}, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	task.wait(0.6)
	loadingScreenGui:Destroy()
	
	createAdvancedTween(mainFrame, 0.7, {Position = UDim2.new(0.5, -240, 0.5, -400)}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	
	return screenGui, mainFrame
end

local screenGui, mainFrame = createPremiumGUI()

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
end

-- ======= GAMEPLAY FUNCTIONS =======
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

-- ======= HEALTH REFILL =======
useHealthRefillInternal = function(ignoreEnabledCheck)
	if not ignoreEnabledCheck and not CONFIG.HealthEnabled then
		return false
	end
	
	if healthActionBusy then
		return false
	end
	
	local now = os.clock()
	if now - lastHealthUse < CONFIG.HealthButtonCooldown then
		return false
	end
	
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	
	if not char or not hrp or not humanoid then
		return false
	end
	
	if not CONFIG.HealthTeleportCFrame then
		return false
	end
	
	local safeCFrame = CONFIG.HealthTeleportCFrame * CFrame.new(CONFIG.TeleportOffset)
	
	healthActionBusy = true
	lastHealthUse = now
	returnTaskId += 1
	local currentTaskId = returnTaskId
	
	if CONFIG.AutofarmActive then
		setAutofarmPausedForHealth(true)
	end
	
	local success = pcall(function()
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
		return false
	end
	
	updateStatus("💊 Healing...")
	
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
		end
		
		healthActionBusy = false
		setAutofarmPausedForHealth(false)
	end)
	
	return true
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

-- ======= COMBAT ENGINE =======
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
				updateStatus("⏳ Waiting for turn...")
			end
		else
			if #CONFIG.TargetNPCs == 0 then
				updateStatus("📍 Select targets first!")
			else
				local targetNPC = findOptimalNPC()
				if targetNPC then
					travelToNPC(targetNPC)
				else
					updateStatus("🔍 Searching...")
				end
			end
		end
	end
end

-- ======= INITIALIZATION =======
uiElements.ToggleBtn.MouseButton1Click:Connect(function()
	if #CONFIG.TargetNPCs == 0 and not CONFIG.AutofarmActive then
		updateStatus("⚠ Select targets first!")
		return
	end
	
	CONFIG.AutofarmActive = not CONFIG.AutofarmActive
	if CONFIG.AutofarmActive then
		uiElements.ToggleBtn.Text = "⏹ STOP"
		createAdvancedTween(uiElements.ToggleBtn, 0.3, {BackgroundColor3 = COLORS.Danger}, Enum.EasingStyle.Quad)
		createAdvancedTween(uiElements.ToggleBtn:FindFirstChildOfClass("UIStroke"), 0.3, {Color = COLORS.Danger})
		scanNPCNames()
		lastCombatState = isInCombat()
		if not lastCombatState then
			saveCurrentPosition()
			resetAbilityCooldownTracking()
		end
		updateStatus("✓ Running!")
		task.spawn(mainControlLoop)
	else
		uiElements.ToggleBtn.Text = "▶ START"
		createAdvancedTween(uiElements.ToggleBtn, 0.3, {BackgroundColor3 = COLORS.Success}, Enum.EasingStyle.Quad)
		createAdvancedTween(uiElements.ToggleBtn:FindFirstChildOfClass("UIStroke"), 0.3, {Color = COLORS.Success})
		updateStatus("⏹ Stopped")
		
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
