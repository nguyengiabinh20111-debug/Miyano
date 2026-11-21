local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local StarterGui = game:GetService("StarterGui")
local Terrain = workspace:FindFirstChildOfClass("Terrain")
local LocalPlayer = Players.LocalPlayer

for _, name in ipairs({"HiroseHubLoader", "ActiveHubNotification", "HiroseCrossChatGui"}) do
	local old = CoreGui:FindFirstChild(name)
	if old then pcall(function() old:Destroy() end) end
	if LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") then
		local oldP = LocalPlayer.PlayerGui:FindFirstChild(name)
		if oldP then pcall(function() oldP:Destroy() end) end
	end
end

local DISCORD_LINK = "https://discord.gg/uqhEpzXy9q"
local CHAT_SERVERS = {
	"https://hirose.nguyengiabinhp212.workers.dev", -- [1] Server 1 (p212)
	"https://miyano.nguyengiabinhtest2011.workers.dev", -- [2] Server 2 (test2011 / miyano)
}
local HUB_BG_ASSET = "rbxassetid://128731683523721"
local CHAT_BG_ASSET = "rbxassetid://115802852640793"
local CHAT_SERVER_TAG = tostring(game.JobId ~= "" and string.sub(game.JobId, 1, 8) or "Global")
local ADMIN_ROBLOX_USERNAME = "djia9243"
local CUSTOM_ICON_ASSET = "rbxassetid://106041745164419"

local SCRIPTS = {
	Chilli = 'loadstring(game:HttpGet("https://raw.githubusercontent.com/tienkhanh1/spicy/main/Chilli.lua"))()',
	Venyx = 'loadstring(game:HttpGet("https://raw.githubusercontent.com/tienkhanh1/Venyx/main/VenyxHub"))()',
	Divine = 'loadstring(game:HttpGet("https://raw.githubusercontent.com/tienkhanh1/Aquavine/main/DivineHub"))()'
}

local SelectedHub, SoundEnabled, FpsBoostEnabled = "Chilli", true, true
local reqFunc = (syn and syn.request) or (http and http.request) or request or http_request

local function safeDecode(raw)
	if type(raw) ~= "string" or raw == "" then return nil end
	local ok, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
	return ok and decoded or nil
end

local function safeEncode(tbl)
	local ok, encoded = pcall(function() return HttpService:JSONEncode(tbl) end)
	return ok and encoded or nil
end

local ServerFailover = {
	activeIndex = 1,
	cooldownUntil = { [1] = 0, [2] = 0 },
	cooldownSeconds = 120,
	lastUtcDay = os.date("!%Y-%m-%d"),
}

local function syncDailyReset()
	local todayUtc = os.date("!%Y-%m-%d")
	if todayUtc ~= ServerFailover.lastUtcDay then
		ServerFailover.lastUtcDay = todayUtc
		ServerFailover.cooldownUntil[1] = 0
		ServerFailover.cooldownUntil[2] = 0
		ServerFailover.activeIndex = 1
	end
end

local function getCandidateOrder()
	syncDailyReset()
	local nowClock = os.clock()
	local primary = ServerFailover.activeIndex
	local secondary = (primary == 1) and 2 or 1

	if (nowClock < (ServerFailover.cooldownUntil[primary] or 0))
		and (nowClock >= (ServerFailover.cooldownUntil[secondary] or 0)) then
		primary, secondary = secondary, primary
		ServerFailover.activeIndex = primary
	end

	local order = {}
	for _, idx in ipairs({ primary, secondary }) do
		local baseUrl = CHAT_SERVERS[idx]
		if type(baseUrl) == "string" and baseUrl ~= "" then
			table.insert(order, {
				index = idx,
				url = string.gsub(baseUrl, "/+$", ""),
			})
		end
	end
	return order
end

local function markServerExhaustedOrError(srvIndex)
	ServerFailover.cooldownUntil[srvIndex] = os.clock() + ServerFailover.cooldownSeconds
	ServerFailover.activeIndex = (srvIndex == 1) and 2 or 1
end

local function chatHttpRequest(method, path, bodyStr)
	if not reqFunc then
		return false, nil, 0
	end

	local candidates = getCandidateOrder()
	local lastRes, lastCode = nil, 0

	for _, srv in ipairs(candidates) do
		local opts = {
			Url = srv.url .. path,
			Method = method,
		}
		if bodyStr then
			opts.Headers = { ["Content-Type"] = "application/json" }
			opts.Body = bodyStr
		end

		local ok, res = pcall(function()
			return reqFunc(opts)
		end)

		local code = (res and tonumber(res.StatusCode or res.Status or 0)) or 0
		local isHttpOk = ok and type(res) == "table" and (res.Success or (code >= 200 and code < 300))
		local decoded = (isHttpOk and res.Body) and safeDecode(res.Body) or nil

		local exhaustedOrBroken = (not isHttpOk)
			or (code == 429)
			or (code >= 500)
			or (type(decoded) ~= "table")
			or (decoded.ok == false)

		if not exhaustedOrBroken then
			ServerFailover.activeIndex = srv.index
			ServerFailover.cooldownUntil[srv.index] = 0
			return true, res, code
		end

		lastRes = res
		lastCode = code
		markServerExhaustedOrError(srv.index)
	end

	return false, lastRes, lastCode
end
local function ApplyFixLag()
	pcall(function()
		Lighting.GlobalShadows = false
		Lighting.FogEnd = 9e9
		settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
		if Terrain then
			Terrain.WaterWaveSize = 0
			Terrain.WaterWaveTransparency = 1
			Terrain.WaterReflectance = 0
		end
		for _, v in ipairs(workspace:GetDescendants()) do
			if v:IsA("BasePart") then
				v.Material = Enum.Material.SmoothPlastic
				v.Reflectance = 0
			elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Fire") or v:IsA("Smoke") or v:IsA("Sparkles") then
				v.Enabled = false
			end
		end
	end)
end

local function MakeDraggable(guiObj)
	local dragging, dragInput, dragStart, startPos
	guiObj.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, input.Position, guiObj.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	guiObj.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			local delta = input.Position - dragStart
			guiObj.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
end

local function attachGui(gui)
	local ok = pcall(function() gui.Parent = CoreGui end)
	if not ok or not gui.Parent then
		local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if pg then gui.Parent = pg end
	end
end
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "HiroseHubLoader"
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.ResetOnSpawn = false
attachGui(ScreenGui)

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Parent = ScreenGui
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
MainFrame.Size = UDim2.new(0, 300, 0, 398)
MainFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 14)

local BgImage = Instance.new("ImageLabel")
BgImage.Parent = MainFrame
BgImage.Size = UDim2.new(1, 0, 1, 0)
BgImage.BackgroundTransparency = 1
BgImage.Image = HUB_BG_ASSET
BgImage.ScaleType = Enum.ScaleType.Stretch
BgImage.ZIndex = 0
Instance.new("UICorner", BgImage).CornerRadius = UDim.new(0, 14)
MakeDraggable(MainFrame)

local TopBar = Instance.new("Frame")
TopBar.Parent = MainFrame
TopBar.Size = UDim2.new(1, 0, 0, 32)
TopBar.BackgroundTransparency = 1
TopBar.ZIndex = 2

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Parent = TopBar
TitleLabel.Position = UDim2.new(0, 8, 0, 0)
TitleLabel.Size = UDim2.new(0, 210, 1, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.Text = "🌶️ CHILLI & VENYX & DIVINE"
TitleLabel.TextColor3 = Color3.fromRGB(255, 210, 130)
TitleLabel.TextStrokeTransparency = 0.25
TitleLabel.TextSize = 12
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.ZIndex = 2

local VersionBadge = Instance.new("TextLabel")
VersionBadge.Parent = TopBar
VersionBadge.Position = UDim2.new(1, -78, 0.5, -8)
VersionBadge.Size = UDim2.new(0, 42, 0, 16)
VersionBadge.BackgroundColor3 = Color3.fromRGB(255, 105, 35)
VersionBadge.BackgroundTransparency = 0.2
VersionBadge.Font = Enum.Font.GothamBold
VersionBadge.Text = "v13.0"
VersionBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
VersionBadge.TextSize = 9
VersionBadge.ZIndex = 2
Instance.new("UICorner", VersionBadge).CornerRadius = UDim.new(1, 0)

local CloseBtn = Instance.new("TextButton")
CloseBtn.Parent = TopBar
CloseBtn.Position = UDim2.new(1, -28, 0.5, -9)
CloseBtn.Size = UDim2.new(0, 18, 0, 18)
CloseBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
CloseBtn.BackgroundTransparency = 0.55
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.TextSize = 9
CloseBtn.ZIndex = 2
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 5)
CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

local ProfileCard = Instance.new("Frame")
ProfileCard.Parent = MainFrame
ProfileCard.Position = UDim2.new(0, 8, 0, 34)
ProfileCard.Size = UDim2.new(1, -16, 0, 52)
ProfileCard.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
ProfileCard.BackgroundTransparency = 0.68
ProfileCard.ZIndex = 2
Instance.new("UICorner", ProfileCard).CornerRadius = UDim.new(0, 10)

local IconBox = Instance.new("TextLabel")
IconBox.Parent = ProfileCard
IconBox.Position = UDim2.new(0, 8, 0.5, -14)
IconBox.Size = UDim2.new(0, 28, 0, 28)
IconBox.BackgroundColor3 = Color3.fromRGB(255, 105, 35)
IconBox.BackgroundTransparency = 0.35
IconBox.Text = "🌶️"
IconBox.TextSize = 16
IconBox.ZIndex = 2
Instance.new("UICorner", IconBox).CornerRadius = UDim.new(0, 8)

local AuthorLabel = Instance.new("TextLabel")
AuthorLabel.Parent = ProfileCard
AuthorLabel.Position = UDim2.new(0, 42, 0, 3)
AuthorLabel.Size = UDim2.new(1, -50, 0, 16)
AuthorLabel.BackgroundTransparency = 1
AuthorLabel.Font = Enum.Font.GothamBold
AuthorLabel.Text = "Tác giả: Hirose x Miyano"
AuthorLabel.TextColor3 = Color3.fromRGB(255, 210, 130)
AuthorLabel.TextStrokeTransparency = 0.2
AuthorLabel.TextSize = 12.5
AuthorLabel.TextXAlignment = Enum.TextXAlignment.Left
AuthorLabel.ZIndex = 2

local NameLabel = Instance.new("TextLabel")
NameLabel.Parent = ProfileCard
NameLabel.Position = UDim2.new(0, 42, 0, 19)
NameLabel.Size = UDim2.new(1, -50, 0, 13)
NameLabel.BackgroundTransparency = 1
NameLabel.Font = Enum.Font.GothamBold
NameLabel.Text = "Chilli & Venyx & Divine V13 Max"
NameLabel.TextColor3 = Color3.fromRGB(255, 235, 190)
NameLabel.TextStrokeTransparency = 0.25
NameLabel.TextSize = 10
NameLabel.TextXAlignment = Enum.TextXAlignment.Left
NameLabel.ZIndex = 2

local SubLabel = Instance.new("TextLabel")
SubLabel.Parent = ProfileCard
SubLabel.Position = UDim2.new(0, 42, 0, 32)
SubLabel.Size = UDim2.new(1, -50, 0, 12)
SubLabel.BackgroundTransparency = 1
SubLabel.Font = Enum.Font.Gotham
SubLabel.Text = "● Sẵn sàng (Chilli VIP)"
SubLabel.TextColor3 = Color3.fromRGB(115, 255, 175)
SubLabel.TextStrokeTransparency = 0.25
SubLabel.TextSize = 9
SubLabel.TextXAlignment = Enum.TextXAlignment.Left
SubLabel.ZIndex = 2

local function makeInfoCard(posY, height)
	local f = Instance.new("Frame")
	f.Parent = MainFrame
	f.Position = UDim2.new(0, 8, 0, posY)
	f.Size = UDim2.new(1, -16, 0, height)
	f.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	f.BackgroundTransparency = 0.68
	f.ZIndex = 2
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)
	return f
end

local function makeCardLabel(parent, pos, size, font, text, color, textSize)
	local l = Instance.new("TextLabel")
	l.Parent = parent
	l.Position = pos
	l.Size = size
	l.BackgroundTransparency = 1
	l.Font = font
	l.Text = text
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.25
	l.TextSize = textSize
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.ZIndex = 2
	return l
end

local VirexCard = makeInfoCard(90, 34)
makeCardLabel(VirexCard, UDim2.new(0, 8, 0, 3), UDim2.new(0, 150, 0, 14), Enum.Font.GothamBold, "🔍 VIREX - FINDER", Color3.fromRGB(115, 255, 175), 10)
makeCardLabel(VirexCard, UDim2.new(0, 8, 0, 17), UDim2.new(0, 150, 0, 14), Enum.Font.Gotham, "Tính năng nổi bật V13", Color3.fromRGB(235, 240, 255), 8)

local RateBadge = Instance.new("TextLabel")
RateBadge.Parent = VirexCard
RateBadge.Position = UDim2.new(1, -96, 0.5, -9)
RateBadge.Size = UDim2.new(0, 88, 0, 18)
RateBadge.BackgroundColor3 = Color3.fromRGB(25, 95, 58)
RateBadge.BackgroundTransparency = 0.25
RateBadge.Font = Enum.Font.GothamBold
RateBadge.Text = "✨ CHUẨN CAO"
RateBadge.TextColor3 = Color3.fromRGB(130, 255, 185)
RateBadge.TextSize = 8
RateBadge.ZIndex = 2
Instance.new("UICorner", RateBadge).CornerRadius = UDim.new(1, 0)

local ChatIntroCard = makeInfoCard(128, 34)
makeCardLabel(ChatIntroCard, UDim2.new(0, 8, 0, 3), UDim2.new(0, 165, 0, 14), Enum.Font.GothamBold, "🌐 CHAT TOÀN SERVER", Color3.fromRGB(255, 210, 130), 10)
makeCardLabel(ChatIntroCard, UDim2.new(0, 8, 0, 17), UDim2.new(0, 175, 0, 14), Enum.Font.Gotham, "Chat xuyên server + avatar người chơi", Color3.fromRGB(235, 240, 255), 8)

local ChatIntroBadge = Instance.new("TextLabel")
ChatIntroBadge.Parent = ChatIntroCard
ChatIntroBadge.Position = UDim2.new(1, -88, 0.5, -9)
ChatIntroBadge.Size = UDim2.new(0, 80, 0, 18)
ChatIntroBadge.BackgroundColor3 = Color3.fromRGB(255, 105, 35)
ChatIntroBadge.BackgroundTransparency = 0.2
ChatIntroBadge.Font = Enum.Font.GothamBold
ChatIntroBadge.Text = "💬 TÍNH NĂNG MỚI"
ChatIntroBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
ChatIntroBadge.TextSize = 7.5
ChatIntroBadge.ZIndex = 2
Instance.new("UICorner", ChatIntroBadge).CornerRadius = UDim.new(1, 0)

makeCardLabel(MainFrame, UDim2.new(0, 10, 0, 166), UDim2.new(0, 90, 0, 16), Enum.Font.GothamBold, "🎮 CHỌN HUB", Color3.fromRGB(255, 210, 130), 10)

local SoundBtn = Instance.new("TextButton")
SoundBtn.Parent = MainFrame
SoundBtn.Position = UDim2.new(1, -110, 0, 165)
SoundBtn.Size = UDim2.new(0, 102, 0, 16)
SoundBtn.BackgroundColor3 = Color3.fromRGB(32, 140, 78)
SoundBtn.BackgroundTransparency = 0.2
SoundBtn.Font = Enum.Font.GothamBold
SoundBtn.Text = "🔊 ÂM THANH: BẬT"
SoundBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
SoundBtn.TextSize = 8
SoundBtn.ZIndex = 2
Instance.new("UICorner", SoundBtn).CornerRadius = UDim.new(1, 0)

SoundBtn.MouseButton1Click:Connect(function()
	SoundEnabled = not SoundEnabled
	SoundBtn.Text = SoundEnabled and "🔊 ÂM THANH: BẬT" or "🔇 ÂM THANH: TẮT"
	SoundBtn.BackgroundColor3 = SoundEnabled and Color3.fromRGB(32, 140, 78) or Color3.fromRGB(60, 60, 70)
end)

local HubContainer = Instance.new("Frame")
HubContainer.Parent = MainFrame
HubContainer.Position = UDim2.new(0, 8, 0, 186)
HubContainer.Size = UDim2.new(1, -16, 0, 70)
HubContainer.BackgroundTransparency = 1
HubContainer.ZIndex = 2

local function CreateHubCard(name, pos, size, icon, title)
	local Card = Instance.new("TextButton")
	Card.Name = name
	Card.Parent = HubContainer
	Card.Position = pos
	Card.Size = size
	Card.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	Card.BackgroundTransparency = 0.68
	Card.Text = ""
	Card.AutoButtonColor = false
	Card.ZIndex = 2
	Instance.new("UICorner", Card).CornerRadius = UDim.new(0, 10)

	local Title = Instance.new("TextLabel")
	Title.Parent = Card
	Title.Position = UDim2.new(0, 4, 0, 4)
	Title.Size = UDim2.new(1, -8, 0, 16)
	Title.BackgroundTransparency = 1
	Title.Font = Enum.Font.GothamBold
	Title.Text = icon .. " " .. title
	Title.TextColor3 = Color3.fromRGB(255, 255, 255)
	Title.TextStrokeTransparency = 0.25
	Title.TextSize = 10
	Title.TextXAlignment = Enum.TextXAlignment.Center
	Title.ZIndex = 2

	local StatusPill = Instance.new("TextLabel")
	StatusPill.Name = "StatusPill"
	StatusPill.Parent = Card
	StatusPill.Position = UDim2.new(0, 6, 1, -24)
	StatusPill.Size = UDim2.new(1, -12, 0, 18)
	StatusPill.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
	StatusPill.BackgroundTransparency = 0.25
	StatusPill.Font = Enum.Font.GothamBold
	StatusPill.Text = "Chọn"
	StatusPill.TextColor3 = Color3.fromRGB(235, 240, 255)
	StatusPill.TextSize = 9
	StatusPill.ZIndex = 2
	Instance.new("UICorner", StatusPill).CornerRadius = UDim.new(0, 6)
	return Card
end

local ChilliCard = CreateHubCard("ChilliCard", UDim2.new(0, 0, 0, 0), UDim2.new(0.32, 0, 1, 0), "🔥", "Chilli")
local VenyxCard = CreateHubCard("VenyxCard", UDim2.new(0.34, 0, 0, 0), UDim2.new(0.32, 0, 1, 0), "⚡", "Venyx")
local DivineCard = CreateHubCard("DivineCard", UDim2.new(0.68, 0, 0, 0), UDim2.new(0.32, 0, 1, 0), "💎", "Divine")

local function UpdateHubSelection()
	local map = {
		Chilli = {ChilliCard, Color3.fromRGB(45, 22, 12), Color3.fromRGB(255, 105, 35), "Chilli & Venyx & Divine V13 Max", "● Sẵn sàng (Chilli VIP)"},
		Venyx = {VenyxCard, Color3.fromRGB(22, 24, 52), Color3.fromRGB(110, 100, 255), "Venyx Hub V13 Max", "● Sẵn sàng (Venyx Hub 2)"},
		Divine = {DivineCard, Color3.fromRGB(14, 38, 52), Color3.fromRGB(50, 160, 220), "Divine Hub (Aquavine)", "● Sẵn sàng (Aquavine Divine)"}
	}
	for _, card in ipairs({ChilliCard, VenyxCard, DivineCard}) do
		card.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		card.BackgroundTransparency = 0.68
		card.StatusPill.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
		card.StatusPill.BackgroundTransparency = 0.25
		card.StatusPill.TextColor3 = Color3.fromRGB(235, 240, 255)
		card.StatusPill.Text = "Chọn"
	end
	local cfg = map[SelectedHub] or map.Chilli
	cfg[1].BackgroundColor3 = cfg[2]
	cfg[1].BackgroundTransparency = 0.55
	cfg[1].StatusPill.BackgroundColor3 = cfg[3]
	cfg[1].StatusPill.BackgroundTransparency = 0.15
	cfg[1].StatusPill.TextColor3 = Color3.fromRGB(255, 255, 255)
	cfg[1].StatusPill.Text = "✓ CHỌN"
	NameLabel.Text, SubLabel.Text = cfg[4], cfg[5]
end

ChilliCard.MouseButton1Click:Connect(function() SelectedHub = "Chilli" UpdateHubSelection() end)
VenyxCard.MouseButton1Click:Connect(function() SelectedHub = "Venyx" UpdateHubSelection() end)
DivineCard.MouseButton1Click:Connect(function() SelectedHub = "Divine" UpdateHubSelection() end)
UpdateHubSelection()

local FpsCard = makeInfoCard(262, 32)
makeCardLabel(FpsCard, UDim2.new(0, 8, 0, 3), UDim2.new(0, 160, 0, 13), Enum.Font.GothamBold, "🌙 FPS Boost & Fix Lag", Color3.fromRGB(255, 210, 130), 10)
makeCardLabel(FpsCard, UDim2.new(0, 8, 0, 16), UDim2.new(0, 180, 0, 13), Enum.Font.Gotham, "Tối ưu hóa game cực mượt", Color3.fromRGB(235, 240, 255), 8)

local FpsBtn = Instance.new("TextButton")
FpsBtn.Parent = FpsCard
FpsBtn.Position = UDim2.new(1, -48, 0.5, -9)
FpsBtn.Size = UDim2.new(0, 40, 0, 18)
FpsBtn.BackgroundColor3 = Color3.fromRGB(32, 150, 85)
FpsBtn.BackgroundTransparency = 0.2
FpsBtn.Font = Enum.Font.GothamBold
FpsBtn.Text = "BẬT"
FpsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FpsBtn.TextSize = 9
FpsBtn.ZIndex = 2
Instance.new("UICorner", FpsBtn).CornerRadius = UDim.new(1, 0)

FpsBtn.MouseButton1Click:Connect(function()
	FpsBoostEnabled = not FpsBoostEnabled
	FpsBtn.Text = FpsBoostEnabled and "BẬT" or "TẮT"
	FpsBtn.BackgroundColor3 = FpsBoostEnabled and Color3.fromRGB(32, 150, 85) or Color3.fromRGB(60, 60, 70)
end)

local DiscordCard = makeInfoCard(298, 32)
makeCardLabel(DiscordCard, UDim2.new(0, 8, 0, 3), UDim2.new(0, 150, 0, 13), Enum.Font.GothamBold, "💬 DISCORD", Color3.fromRGB(170, 195, 255), 9)
makeCardLabel(DiscordCard, UDim2.new(0, 8, 0, 16), UDim2.new(0, 170, 0, 13), Enum.Font.Gotham, DISCORD_LINK, Color3.fromRGB(235, 240, 255), 9)

local CopyBtn = Instance.new("TextButton")
CopyBtn.Parent = DiscordCard
CopyBtn.Position = UDim2.new(1, -70, 0.5, -9)
CopyBtn.Size = UDim2.new(0, 62, 0, 18)
CopyBtn.BackgroundColor3 = Color3.fromRGB(88, 101, 242)
CopyBtn.BackgroundTransparency = 0.2
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Text = "📋 SAO CHÉP"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 8
CopyBtn.ZIndex = 2
Instance.new("UICorner", CopyBtn).CornerRadius = UDim.new(0, 6)

CopyBtn.MouseButton1Click:Connect(function()
	if setclipboard then pcall(setclipboard, DISCORD_LINK) end
	CopyBtn.Text = "✓ CHÉP"
	task.wait(1.5)
	CopyBtn.Text = "📋 SAO CHÉP"
end)

local WishContainer = makeInfoCard(334, 20)
WishContainer.UICorner.CornerRadius = UDim.new(0, 8)
local WishLabel = makeCardLabel(WishContainer, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0), Enum.Font.GothamBold, "✨ CHÚC BẠN CHƠI GAME VUI VẺ 👉👈", Color3.fromRGB(255, 210, 130), 9)
WishLabel.TextXAlignment = Enum.TextXAlignment.Center
WishLabel.ZIndex = 3

local ChatGui = Instance.new("ScreenGui")
ChatGui.Name = "HiroseCrossChatGui"
ChatGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ChatGui.ResetOnSpawn = false
attachGui(ChatGui)

local ChatPill = Instance.new("ImageButton")
ChatPill.Name = "ChatPill"
ChatPill.Parent = ChatGui
ChatPill.Position = UDim2.new(0, 14, 0.72, 0)
ChatPill.Size = UDim2.new(0, 52, 0, 52)
ChatPill.BackgroundColor3 = Color3.fromRGB(16, 17, 24)
ChatPill.BackgroundTransparency = 0.1
ChatPill.Image = CUSTOM_ICON_ASSET
ChatPill.ScaleType = Enum.ScaleType.Crop
ChatPill.ZIndex = 10
Instance.new("UICorner", ChatPill).CornerRadius = UDim.new(1, 0)
MakeDraggable(ChatPill)

local ChatBox = Instance.new("Frame")
ChatBox.Name = "ChatBox"
ChatBox.Parent = ChatGui
ChatBox.Position = UDim2.new(0, 10, 0.04, 0)
ChatBox.Size = UDim2.new(0, 250, 0, 372)
ChatBox.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
ChatBox.BackgroundTransparency = 0.45
ChatBox.BorderSizePixel = 0
ChatBox.ClipsDescendants = true
ChatBox.Visible = false
ChatBox.ZIndex = 9
Instance.new("UICorner", ChatBox).CornerRadius = UDim.new(0, 12)
MakeDraggable(ChatBox)

local ChatBg = Instance.new("ImageLabel")
ChatBg.Name = "ChatBg"
ChatBg.Parent = ChatBox
ChatBg.Size = UDim2.new(1, 0, 1, 0)
ChatBg.Image = CHAT_BG_ASSET
ChatBg.ScaleType = Enum.ScaleType.Crop
ChatBg.BackgroundTransparency = 1
ChatBg.ZIndex = 9
Instance.new("UICorner", ChatBg).CornerRadius = UDim.new(0, 12)

local AuthorAfterIcon = Instance.new("ImageLabel")
AuthorAfterIcon.Parent = ChatBox
AuthorAfterIcon.Position = UDim2.new(0, 5, 0, 1)
AuthorAfterIcon.Size = UDim2.new(0, 26, 0, 26)
AuthorAfterIcon.BackgroundTransparency = 1
AuthorAfterIcon.Image = CUSTOM_ICON_ASSET
AuthorAfterIcon.ScaleType = Enum.ScaleType.Crop
AuthorAfterIcon.ZIndex = 11
Instance.new("UICorner", AuthorAfterIcon).CornerRadius = UDim.new(1, 0)

local ChatAuthorLabel = makeCardLabel(ChatBox, UDim2.new(0, 35, 0, 4), UDim2.new(1, -63, 0, 18), Enum.Font.GothamBold, "Tác giả: Hirose x Miyano", Color3.fromRGB(255, 210, 130), 12)
ChatAuthorLabel.ZIndex = 11

local ChatDiscordSub = makeCardLabel(ChatBox, UDim2.new(0, 35, 0, 22), UDim2.new(1, -125, 0, 13), Enum.Font.GothamMedium, DISCORD_LINK, Color3.fromRGB(170, 195, 255), 8.5)
ChatDiscordSub.ZIndex = 11

local OnlineToggleBtn = Instance.new("TextButton")
OnlineToggleBtn.Parent = ChatBox
OnlineToggleBtn.Position = UDim2.new(1, -92, 0, 21)
OnlineToggleBtn.Size = UDim2.new(0, 64, 0, 14)
OnlineToggleBtn.BackgroundColor3 = Color3.fromRGB(16, 48, 32)
OnlineToggleBtn.BackgroundTransparency = 0.35
OnlineToggleBtn.Font = Enum.Font.GothamBold
OnlineToggleBtn.Text = "● 1 online ▾"
OnlineToggleBtn.TextColor3 = Color3.fromRGB(115, 255, 175)
OnlineToggleBtn.TextSize = 8.5
OnlineToggleBtn.ZIndex = 11
Instance.new("UICorner", OnlineToggleBtn).CornerRadius = UDim.new(1, 0)

local HideChatBtn = Instance.new("TextButton")
HideChatBtn.Parent = ChatBox
HideChatBtn.Position = UDim2.new(1, -24, 0, 5)
HideChatBtn.Size = UDim2.new(0, 18, 0, 18)
HideChatBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
HideChatBtn.BackgroundTransparency = 0.55
HideChatBtn.Font = Enum.Font.GothamBold
HideChatBtn.Text = "−"
HideChatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
HideChatBtn.TextSize = 12
HideChatBtn.ZIndex = 11
Instance.new("UICorner", HideChatBtn).CornerRadius = UDim.new(0, 5)

local MsgScroll = Instance.new("ScrollingFrame")
MsgScroll.Parent = ChatBox
MsgScroll.Position = UDim2.new(0, 6, 0, 38)
MsgScroll.Size = UDim2.new(1, -12, 1, -72)
MsgScroll.BackgroundTransparency = 1
MsgScroll.BorderSizePixel = 0
MsgScroll.ScrollBarThickness = 3
MsgScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
MsgScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
MsgScroll.Visible = false
MsgScroll.ZIndex = 10

local MsgLayout = Instance.new("UIListLayout")
MsgLayout.Parent = MsgScroll
MsgLayout.SortOrder = Enum.SortOrder.LayoutOrder
MsgLayout.Padding = UDim.new(0, 6)

local MsgPad = Instance.new("UIPadding")
MsgPad.Parent = MsgScroll
MsgPad.PaddingTop, MsgPad.PaddingBottom, MsgPad.PaddingLeft, MsgPad.PaddingRight = UDim.new(0, 4), UDim.new(0, 4), UDim.new(0, 4), UDim.new(0, 4)

local LockedChatNotice = makeCardLabel(ChatBox, UDim2.new(0, 12, 0.42, 0), UDim2.new(1, -24, 0, 36), Enum.Font.GothamBold, "🔒 Chưa có tin nhắn mới.\nKhi có người nhắn, tin nhắn sẽ hiện!", Color3.fromRGB(255, 225, 150), 10)
LockedChatNotice.TextXAlignment = Enum.TextXAlignment.Center
LockedChatNotice.TextWrapped = true
LockedChatNotice.ZIndex = 11
local OnlinePanel = Instance.new("Frame")
OnlinePanel.Parent = ChatBox
OnlinePanel.Position = UDim2.new(0, 6, 0, 38)
OnlinePanel.Size = UDim2.new(1, -12, 1, -44)
OnlinePanel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
OnlinePanel.BackgroundTransparency = 0.14
OnlinePanel.BorderSizePixel = 0
OnlinePanel.Visible = false
OnlinePanel.ZIndex = 14
Instance.new("UICorner", OnlinePanel).CornerRadius = UDim.new(0, 8)

local BackFromOnlineBtn = Instance.new("TextButton")
BackFromOnlineBtn.Parent = OnlinePanel
BackFromOnlineBtn.Position = UDim2.new(0, 6, 0, 4)
BackFromOnlineBtn.Size = UDim2.new(0, 62, 0, 18)
BackFromOnlineBtn.BackgroundColor3 = Color3.fromRGB(255, 105, 35)
BackFromOnlineBtn.BackgroundTransparency = 0.2
BackFromOnlineBtn.Font = Enum.Font.GothamBold
BackFromOnlineBtn.Text = "< Quay lại"
BackFromOnlineBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
BackFromOnlineBtn.TextSize = 8.5
BackFromOnlineBtn.ZIndex = 15
Instance.new("UICorner", BackFromOnlineBtn).CornerRadius = UDim.new(0, 6)

local OnlineListTitle = makeCardLabel(OnlinePanel, UDim2.new(0, 74, 0, 4), UDim2.new(1, -80, 0, 18), Enum.Font.GothamBold, "Đang bật script · 1", Color3.fromRGB(115, 255, 175), 9.5)
OnlineListTitle.TextXAlignment = Enum.TextXAlignment.Right
OnlineListTitle.ZIndex = 15

local OnlineScroll = Instance.new("ScrollingFrame")
OnlineScroll.Parent = OnlinePanel
OnlineScroll.Position = UDim2.new(0, 5, 0, 26)
OnlineScroll.Size = UDim2.new(1, -10, 1, -30)
OnlineScroll.BackgroundTransparency = 1
OnlineScroll.BorderSizePixel = 0
OnlineScroll.ScrollBarThickness = 3
OnlineScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
OnlineScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
OnlineScroll.ZIndex = 15

local OnlineLayout = Instance.new("UIListLayout")
OnlineLayout.Parent = OnlineScroll
OnlineLayout.SortOrder = Enum.SortOrder.LayoutOrder
OnlineLayout.Padding = UDim.new(0, 4)

local avatarCache, userIdCache, activeScriptUsers = {}, {}, {}
local hasSeenFirstMessage = false

local function unlockChatStream()
	if not hasSeenFirstMessage then
		hasSeenFirstMessage = true
		LockedChatNotice.Visible = false
		MsgScroll.Visible = true
	end
end

local function resolveUserId(username, userId)
	local idNum = tonumber(userId)
	if idNum and idNum > 0 then return idNum end
	local uname = tostring(username or "")
	if uname == "" or uname == "Player" or uname == "Hệ thống" or uname == "Hirose x Miyano" then return nil end
	if userIdCache[uname] then return userIdCache[uname] end
	local plr = Players:FindFirstChild(uname)
	if plr and plr.UserId > 0 then userIdCache[uname] = plr.UserId return plr.UserId end
	local ok, fetchedId = pcall(function() return Players:GetUserIdFromNameAsync(uname) end)
	if ok and tonumber(fetchedId) and tonumber(fetchedId) > 0 then
		userIdCache[uname] = tonumber(fetchedId)
		return tonumber(fetchedId)
	end
	return nil
end

local function applyAvatarAsync(avatarImg, username, userId)
	task.spawn(function()
		local idNum = resolveUserId(username, userId)
		if not idNum then return end
		if avatarCache[idNum] then
			if avatarImg and avatarImg.Parent then avatarImg.Image = avatarCache[idNum] end
			return
		end
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(idNum, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok and type(url) == "string" and url ~= "" then
			avatarCache[idNum] = url
			if avatarImg and avatarImg.Parent then avatarImg.Image = url end
		end
	end)
end

local function sendRemoteFriendRequest(targetUser, targetId)
	local resolvedId = resolveUserId(targetUser, targetId)
	if not resolvedId or resolvedId <= 0 then return end
	local targetPlr = Players:GetPlayerByUserId(resolvedId) or Players:FindFirstChild(tostring(targetUser or ""))
	if targetPlr and LocalPlayer then
		pcall(function() LocalPlayer:RequestFriendship(targetPlr) end)
		pcall(function() StarterGui:SetCore("PromptSendFriendRequest", targetPlr) end)
	end
	if reqFunc then
		task.spawn(function()
			pcall(function()
				reqFunc({
					Url = "https://friends.roblox.com/v1/users/" .. tostring(resolvedId) .. "/request-friendship",
					Method = "POST",
					Headers = { ["Content-Type"] = "application/json" },
					Body = HttpService:JSONEncode({ friendshipOriginSourceType = "PlayerSearch" })
				})
			end)
		end)
	end
end

local ActionSheet = Instance.new("Frame")
ActionSheet.Parent = ChatBox
ActionSheet.Position = UDim2.new(0, 6, 0.41, 0)
ActionSheet.Size = UDim2.new(1, -12, 0, 92)
ActionSheet.BackgroundColor3 = Color3.fromRGB(20, 16, 30)
ActionSheet.BackgroundTransparency = 0.06
ActionSheet.BorderSizePixel = 0
ActionSheet.Visible = false
ActionSheet.ZIndex = 19
Instance.new("UICorner", ActionSheet).CornerRadius = UDim.new(0, 12)
local sheetStroke = Instance.new("UIStroke", ActionSheet)
sheetStroke.Color = Color3.fromRGB(255, 130, 60)
sheetStroke.Thickness = 1.2

local selectedMsgTarget = nil
local ChatInput
local function setReplyMode(target)
	if not target or not ChatInput then return end
	ChatInput.Text = "@" .. tostring(target.user) .. " (" .. tostring(target.text) .. ") "
	ChatInput:CaptureFocus()
end

local function makeSheetBtn(parent, pos, size, bg, text)
	local b = Instance.new("TextButton")
	b.Parent = parent
	b.Position, b.Size, b.BackgroundColor3 = pos, size, bg
	b.Font = Enum.Font.GothamBold
	b.Text = text
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.TextSize = 8.5
	b.ZIndex = 20
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	return b
end

makeSheetBtn(ActionSheet, UDim2.new(0, 5, 0, 6), UDim2.new(0.32, -4, 0, 26), Color3.fromRGB(42, 45, 58), "📋 Chép").MouseButton1Click:Connect(function()
	if selectedMsgTarget and setclipboard then pcall(setclipboard, tostring(selectedMsgTarget.text or "")) end
	ActionSheet.Visible = false
end)
makeSheetBtn(ActionSheet, UDim2.new(0.34, 0, 0, 6), UDim2.new(0.32, -4, 0, 26), Color3.fromRGB(235, 110, 45), "↩ Trả lời").MouseButton1Click:Connect(function()
	if selectedMsgTarget then setReplyMode(selectedMsgTarget) end
	ActionSheet.Visible = false
end)
makeSheetBtn(ActionSheet, UDim2.new(0.68, 0, 0, 6), UDim2.new(0.32, -5, 0, 26), Color3.fromRGB(36, 150, 92), "🤝 Kết bạn").MouseButton1Click:Connect(function()
	if selectedMsgTarget then
		sendRemoteFriendRequest(selectedMsgTarget.user, selectedMsgTarget.userId)
	end
	ActionSheet.Visible = false
end)

local ReactionDock = Instance.new("Frame")
ReactionDock.Parent = ActionSheet
ReactionDock.Position = UDim2.new(0, 5, 0, 40)
ReactionDock.Size = UDim2.new(1, -31, 0, 42)
ReactionDock.BackgroundColor3 = Color3.fromRGB(34, 24, 48)
ReactionDock.BackgroundTransparency = 0.08
ReactionDock.ZIndex = 20
Instance.new("UICorner", ReactionDock).CornerRadius = UDim.new(1, 0)

local EmojiScroll = Instance.new("ScrollingFrame")
EmojiScroll.Parent = ReactionDock
EmojiScroll.Position = UDim2.new(0, 4, 0, 2)
EmojiScroll.Size = UDim2.new(1, -8, 1, -4)
EmojiScroll.BackgroundTransparency = 1
EmojiScroll.BorderSizePixel = 0
EmojiScroll.ScrollBarThickness = 2
EmojiScroll.ScrollingDirection = Enum.ScrollingDirection.X
EmojiScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
EmojiScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
EmojiScroll.Active = true
EmojiScroll.ZIndex = 21

local EmojiLayout = Instance.new("UIListLayout")
EmojiLayout.Parent = EmojiScroll
EmojiLayout.FillDirection = Enum.FillDirection.Horizontal
EmojiLayout.VerticalAlignment = Enum.VerticalAlignment.Center
EmojiLayout.Padding = UDim.new(0, 5)

local swipeDragging, swipeStartX, swipeStartCanvasX = false, 0, 0
EmojiScroll.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		swipeDragging = true
		swipeStartX = input.Position.X
		swipeStartCanvasX = EmojiScroll.CanvasPosition.X
	end
end)
EmojiScroll.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		swipeDragging = false
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if swipeDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local deltaX = input.Position.X - swipeStartX
		local maxX = math.max(0, EmojiScroll.AbsoluteCanvasSize.X - EmojiScroll.AbsoluteWindowSize.X)
		local nextX = math.clamp(swipeStartCanvasX - deltaX * 1.25, 0, maxX)
		EmojiScroll.CanvasPosition = Vector2.new(nextX, 0)
	end
end)

local emojis = {"❤️", "😂", "😮", "😢", "👍", "🔥", "🥰", "😭", "😡", "🎉", "💯", "✨", "🤡", "🤝", "💔", "🤩"}
for i, em in ipairs(emojis) do
	local eb = Instance.new("TextButton")
	eb.Parent = EmojiScroll
	eb.LayoutOrder = i
	eb.Size = UDim2.new(0, 28, 0, 28)
	eb.BackgroundColor3 = Color3.fromRGB(52, 36, 72)
	eb.BackgroundTransparency = 0.15
	eb.Font = Enum.Font.GothamBold
	eb.Text = em
	eb.TextColor3 = Color3.fromRGB(255, 255, 255)
	eb.TextSize = 13.5
	eb.ZIndex = 22
	Instance.new("UICorner", eb).CornerRadius = UDim.new(1, 0)
	eb.MouseButton1Click:Connect(function()
		if selectedMsgTarget and selectedMsgTarget.reactLabel then
			selectedMsgTarget.reactLabel.Text = em
			selectedMsgTarget.reactLabel.Visible = true
		end
		ActionSheet.Visible = false
	end)
end

local closeDockBtn = Instance.new("TextButton")
closeDockBtn.Parent = ActionSheet
closeDockBtn.Position = UDim2.new(1, -24, 0, 48)
closeDockBtn.Size = UDim2.new(0, 19, 0, 26)
closeDockBtn.BackgroundColor3 = Color3.fromRGB(185, 55, 75)
closeDockBtn.Font = Enum.Font.GothamBold
closeDockBtn.Text = "X"
closeDockBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeDockBtn.TextSize = 9
closeDockBtn.ZIndex = 21
Instance.new("UICorner", closeDockBtn).CornerRadius = UDim.new(0, 6)
closeDockBtn.MouseButton1Click:Connect(function() ActionSheet.Visible = false end)

local function rebuildOnlineList()
	for _, child in ipairs(OnlineScroll:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	local count = 0
	for _, info in pairs(activeScriptUsers) do
		count += 1
		local item = Instance.new("Frame")
		item.Parent = OnlineScroll
		item.LayoutOrder = count
		item.Size = UDim2.new(1, 0, 0, 34)
		item.BackgroundColor3 = Color3.fromRGB(24, 24, 34)
		item.BackgroundTransparency = 0.25
		item.BorderSizePixel = 0
		item.ZIndex = 16
		Instance.new("UICorner", item).CornerRadius = UDim.new(0, 7)

		local av = Instance.new("ImageButton")
		av.Parent = item
		av.Position = UDim2.new(0, 5, 0.5, -12)
		av.Size = UDim2.new(0, 24, 0, 24)
		av.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		av.BackgroundTransparency = 0.5
		av.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
		av.ScaleType = Enum.ScaleType.Crop
		av.ZIndex = 17
		Instance.new("UICorner", av).CornerRadius = UDim.new(1, 0)
		applyAvatarAsync(av, info.realName, info.userId)
		av.MouseButton1Click:Connect(function() sendRemoteFriendRequest(info.realName, info.userId) end)

		local editedLbl = makeCardLabel(item, UDim2.new(0, 34, 0, 3), UDim2.new(1, -40, 0, 14), Enum.Font.GothamBold, tostring(info.editedName or info.realName), Color3.fromRGB(255, 255, 255), 10.5)
		editedLbl.ZIndex = 17

		local rawLbl = makeCardLabel(item, UDim2.new(0, 34, 0, 17), UDim2.new(1, -40, 0, 13), Enum.Font.Gotham, "@" .. tostring(info.realName), Color3.fromRGB(185, 200, 225), 8.5)
		rawLbl.ZIndex = 17
	end
	local finalCount = math.max(1, count)
	OnlineToggleBtn.Text = "● " .. tostring(finalCount) .. " online ▾"
	OnlineListTitle.Text = "Đang bật script · " .. tostring(finalCount)
end

local function registerScriptUser(realName, editedName, userId)
	local rName = tostring(realName or "")
	if rName == "" or rName == "Player" or rName == "Hệ thống" or rName == "Hirose x Miyano" then return end
	local eName = tostring(editedName or "")
	if eName == "" then
		local plr = Players:FindFirstChild(rName)
		eName = (plr and plr.DisplayName) or rName
	end
	activeScriptUsers[rName] = { realName = rName, editedName = eName, userId = tonumber(userId) or 0 }
	rebuildOnlineList()
end

OnlineToggleBtn.MouseButton1Click:Connect(function() rebuildOnlineList() OnlinePanel.Visible = not OnlinePanel.Visible end)
BackFromOnlineBtn.MouseButton1Click:Connect(function() OnlinePanel.Visible = false end)

local function formatLockedTime(ts)
	local num = tonumber(ts)
	if num and num > 0 then
		if num > 1e11 then num = math.floor(num / 1000) end
		local ok, dt = pcall(function() return os.date("%H:%M", num) end)
		if ok and type(dt) == "string" and #dt == 5 then return dt end
	end
	local okNow, nowStr = pcall(function() return os.date("%H:%M") end)
	return (okNow and nowStr) or "23:58"
end

local msgOrder = 0
local function appendChatLine(username, text, userId, timestamp, customColor, shouldUnlock, autoCopyText)
	if shouldUnlock then
		unlockChatStream()
	end
	msgOrder += 1
	local safeUser = tostring(username or "Player")
	local safeText = tostring(text or "")
	local safeId = tonumber(userId) or 0
	local myName = (LocalPlayer and LocalPlayer.Name) or ""
	local isSelf = (myName ~= "" and safeUser == myName)
	local isAdmin = (safeUser == ADMIN_ROBLOX_USERNAME)
	local lockedTime = formatLockedTime(timestamp)

	local row = Instance.new("Frame")
	row.Name = "MsgRow_" .. tostring(msgOrder)
	row.Parent = MsgScroll
	row.LayoutOrder = msgOrder
	row.Size = UDim2.new(1, 0, 0, 42)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.ZIndex = 10

	local avatarImg = Instance.new("ImageButton")
	avatarImg.Parent = row
	avatarImg.Size = UDim2.new(0, 26, 0, 26)
	avatarImg.Position = isSelf and UDim2.new(1, -28, 0, 2) or UDim2.new(0, 2, 0, 2)
	avatarImg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	avatarImg.BackgroundTransparency = 0.45
	avatarImg.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
	avatarImg.ScaleType = Enum.ScaleType.Crop
	avatarImg.ZIndex = 12
	Instance.new("UICorner", avatarImg).CornerRadius = UDim.new(1, 0)
	applyAvatarAsync(avatarImg, safeUser, safeId)
	avatarImg.MouseButton1Click:Connect(function()
		sendRemoteFriendRequest(safeUser, safeId)
	end)

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Parent = row
	nameLbl.Position = isSelf and UDim2.new(0, 4, 0, 0) or UDim2.new(0, 32, 0, 0)
	nameLbl.Size = UDim2.new(1, -36, 0, 14)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextStrokeTransparency = 0.25
	nameLbl.TextSize = 10
	nameLbl.TextXAlignment = isSelf and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left
	nameLbl.ZIndex = 11

	if isAdmin then
		nameLbl.RichText = true
		nameLbl.Text = '<font color="#FFD746">' .. safeUser .. '</font> <font color="#FF3737">[ADMIN]</font> · ' .. lockedTime
		nameLbl.TextColor3 = Color3.fromRGB(220, 225, 240)
	else
		nameLbl.Text = safeUser .. " · " .. lockedTime
		nameLbl.TextColor3 = customColor or (isSelf and Color3.fromRGB(255, 210, 125) or Color3.fromRGB(165, 225, 255))
	end

	local msgStack = Instance.new("Frame")
	msgStack.Parent = row
	msgStack.AnchorPoint = isSelf and Vector2.new(1, 0) or Vector2.new(0, 0)
	msgStack.Position = isSelf and UDim2.new(1, -32, 0, 15) or UDim2.new(0, 32, 0, 15)
	msgStack.Size = UDim2.new(0, 0, 0, 0)
	msgStack.AutomaticSize = Enum.AutomaticSize.XY
	msgStack.BackgroundTransparency = 1
	msgStack.ZIndex = 11

	local stackLayout = Instance.new("UIListLayout")
	stackLayout.Parent = msgStack
	stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
	stackLayout.HorizontalAlignment = isSelf and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left
	stackLayout.Padding = UDim.new(0, 3)

	local bubble = Instance.new("TextButton")
	bubble.Parent = msgStack
	bubble.LayoutOrder = 1
	bubble.Size = UDim2.new(0, 0, 0, 22)
	bubble.AutomaticSize = Enum.AutomaticSize.XY
	bubble.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bubble.BackgroundTransparency = 0.42
	bubble.BorderSizePixel = 0
	bubble.Text = safeText
	bubble.Font = Enum.Font.GothamMedium
	bubble.TextColor3 = Color3.fromRGB(255, 255, 255)
	bubble.TextStrokeTransparency = 0.25
	bubble.TextSize = 11.5
	bubble.TextWrapped = true
	bubble.TextXAlignment = isSelf and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left
	bubble.ZIndex = 11
	Instance.new("UICorner", bubble).CornerRadius = UDim.new(0, 8)

	local sizeLimit = Instance.new("UISizeConstraint", bubble)
	sizeLimit.MaxSize = Vector2.new(165, 180)
	sizeLimit.MinSize = Vector2.new(26, 22)

	local bPad = Instance.new("UIPadding")
	bPad.Parent = bubble
	bPad.PaddingTop, bPad.PaddingBottom, bPad.PaddingLeft, bPad.PaddingRight = UDim.new(0, 4), UDim.new(0, 4), UDim.new(0, 7), UDim.new(0, 7)

	local reactBadge = Instance.new("TextLabel")
	reactBadge.Parent = msgStack
	reactBadge.LayoutOrder = 2
	reactBadge.Size = UDim2.new(0, 24, 0, 16)
	reactBadge.BackgroundColor3 = Color3.fromRGB(16, 17, 24)
	reactBadge.BackgroundTransparency = 0.2
	reactBadge.Font = Enum.Font.GothamBold
	reactBadge.Text = ""
	reactBadge.TextSize = 11
	reactBadge.Visible = false
	reactBadge.ZIndex = 13
	Instance.new("UICorner", reactBadge).CornerRadius = UDim.new(1, 0)

	local rPad = Instance.new("UIPadding")
	rPad.Parent = row
	rPad.PaddingBottom = UDim.new(0, 4)

	bubble.MouseButton1Click:Connect(function()
		if autoCopyText and setclipboard then
			pcall(setclipboard, autoCopyText)
			bubble.Text = "✓ Đã chép: " .. autoCopyText
			task.wait(1.2)
			if bubble and bubble.Parent then bubble.Text = safeText end
			return
		end
		selectedMsgTarget = { user = safeUser, text = safeText, userId = safeId, reactLabel = reactBadge }
		ActionSheet.Visible = true
	end)

	task.defer(function()
		MsgScroll.CanvasPosition = Vector2.new(0, math.max(0, MsgScroll.AbsoluteCanvasSize.Y - MsgScroll.AbsoluteWindowSize.Y))
	end)
end
ChatInput = Instance.new("TextBox")
ChatInput.Parent = ChatBox
ChatInput.Position = UDim2.new(0, 6, 1, -27)
ChatInput.Size = UDim2.new(1, -78, 0, 22)
ChatInput.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
ChatInput.BackgroundTransparency = 0.22
ChatInput.Font = Enum.Font.Gotham
ChatInput.PlaceholderText = "Nhập tin nhắn..."
ChatInput.PlaceholderColor3 = Color3.fromRGB(220, 225, 240)
ChatInput.Text = ""
ChatInput.TextColor3 = Color3.fromRGB(255, 255, 255)
ChatInput.TextSize = 10.5
ChatInput.ClearTextOnFocus = false
ChatInput.ZIndex = 11
Instance.new("UICorner", ChatInput).CornerRadius = UDim.new(0, 6)

local QuickEmojiBtn = Instance.new("TextButton")
QuickEmojiBtn.Name = "QuickEmojiBtn"
QuickEmojiBtn.Parent = ChatBox
QuickEmojiBtn.Position = UDim2.new(1, -69, 1, -27)
QuickEmojiBtn.Size = UDim2.new(0, 22, 0, 22)
QuickEmojiBtn.BackgroundColor3 = Color3.fromRGB(48, 36, 72)
QuickEmojiBtn.BackgroundTransparency = 0.15
QuickEmojiBtn.Font = Enum.Font.GothamBold
QuickEmojiBtn.Text = "😀"
QuickEmojiBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
QuickEmojiBtn.TextSize = 12
QuickEmojiBtn.ZIndex = 11
Instance.new("UICorner", QuickEmojiBtn).CornerRadius = UDim.new(0, 6)

local SendChatBtn = Instance.new("TextButton")
SendChatBtn.Parent = ChatBox
SendChatBtn.Position = UDim2.new(1, -44, 1, -27)
SendChatBtn.Size = UDim2.new(0, 38, 0, 22)
SendChatBtn.BackgroundColor3 = Color3.fromRGB(255, 105, 35)
SendChatBtn.BackgroundTransparency = 0.12
SendChatBtn.Font = Enum.Font.GothamBold
SendChatBtn.Text = "GỬI"
SendChatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
SendChatBtn.TextSize = 10
SendChatBtn.ZIndex = 11
Instance.new("UICorner", SendChatBtn).CornerRadius = UDim.new(0, 6)

local QuickEmojiPicker = Instance.new("Frame")
QuickEmojiPicker.Name = "QuickEmojiPicker"
QuickEmojiPicker.Parent = ChatBox
QuickEmojiPicker.Position = UDim2.new(0, 6, 1, -138)
QuickEmojiPicker.Size = UDim2.new(1, -12, 0, 106)
QuickEmojiPicker.BackgroundColor3 = Color3.fromRGB(20, 16, 30)
QuickEmojiPicker.BackgroundTransparency = 0.06
QuickEmojiPicker.BorderSizePixel = 0
QuickEmojiPicker.ClipsDescendants = true
QuickEmojiPicker.Visible = false
QuickEmojiPicker.ZIndex = 22
Instance.new("UICorner", QuickEmojiPicker).CornerRadius = UDim.new(0, 10)
local quickPickerStroke = Instance.new("UIStroke", QuickEmojiPicker)
quickPickerStroke.Color = Color3.fromRGB(255, 130, 60)
quickPickerStroke.Thickness = 1.2

local QuickEmojiHeader = Instance.new("Frame")
QuickEmojiHeader.Parent = QuickEmojiPicker
QuickEmojiHeader.Size = UDim2.new(1, 0, 0, 22)
QuickEmojiHeader.BackgroundColor3 = Color3.fromRGB(30, 24, 44)
QuickEmojiHeader.BackgroundTransparency = 0.15
QuickEmojiHeader.BorderSizePixel = 0
QuickEmojiHeader.ZIndex = 23

local QuickEmojiTitle = makeCardLabel(QuickEmojiHeader, UDim2.new(0, 8, 0, 0), UDim2.new(1, -54, 1, 0), Enum.Font.GothamBold, "😀 Icon (Kéo ngang/dọc · Bấm gửi)", Color3.fromRGB(255, 210, 130), 8.5)
QuickEmojiTitle.ZIndex = 24

local CloseQuickPickerBtn = Instance.new("TextButton")
CloseQuickPickerBtn.Parent = QuickEmojiHeader
CloseQuickPickerBtn.Position = UDim2.new(1, -22, 0.5, -8)
CloseQuickPickerBtn.Size = UDim2.new(0, 16, 0, 16)
CloseQuickPickerBtn.BackgroundColor3 = Color3.fromRGB(185, 55, 75)
CloseQuickPickerBtn.Font = Enum.Font.GothamBold
CloseQuickPickerBtn.Text = "X"
CloseQuickPickerBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseQuickPickerBtn.TextSize = 8.5
CloseQuickPickerBtn.ZIndex = 24
Instance.new("UICorner", CloseQuickPickerBtn).CornerRadius = UDim.new(0, 4)
CloseQuickPickerBtn.MouseButton1Click:Connect(function()
	QuickEmojiPicker.Visible = false
end)

local QuickEmojiScroll = Instance.new("ScrollingFrame")
QuickEmojiScroll.Name = "QuickEmojiScroll"
QuickEmojiScroll.Parent = QuickEmojiPicker
QuickEmojiScroll.Position = UDim2.new(0, 5, 0, 25)
QuickEmojiScroll.Size = UDim2.new(1, -10, 1, -29)
QuickEmojiScroll.BackgroundTransparency = 1
QuickEmojiScroll.BorderSizePixel = 0
QuickEmojiScroll.ScrollBarThickness = 2.5
QuickEmojiScroll.ScrollingDirection = Enum.ScrollingDirection.XY
QuickEmojiScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
QuickEmojiScroll.AutomaticCanvasSize = Enum.AutomaticSize.XY
QuickEmojiScroll.Active = true
QuickEmojiScroll.ZIndex = 23

local QuickEmojiGrid = Instance.new("UIGridLayout")
QuickEmojiGrid.Parent = QuickEmojiScroll
QuickEmojiGrid.CellSize = UDim2.new(0, 32, 0, 32)
QuickEmojiGrid.CellPadding = UDim2.new(0, 4, 0, 4)
QuickEmojiGrid.FillDirection = Enum.FillDirection.Horizontal
QuickEmojiGrid.FillDirectionMaxCells = 10
QuickEmojiGrid.SortOrder = Enum.SortOrder.LayoutOrder

local qSwipeDragging, qSwipeStartPos, qSwipeStartCanvas = false, Vector2.new(), Vector2.new()
QuickEmojiScroll.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		qSwipeDragging = true
		qSwipeStartPos = input.Position
		qSwipeStartCanvas = QuickEmojiScroll.CanvasPosition
	end
end)
QuickEmojiScroll.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		qSwipeDragging = false
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if qSwipeDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - qSwipeStartPos
		local maxX = math.max(0, QuickEmojiScroll.AbsoluteCanvasSize.X - QuickEmojiScroll.AbsoluteWindowSize.X)
		local maxY = math.max(0, QuickEmojiScroll.AbsoluteCanvasSize.Y - QuickEmojiScroll.AbsoluteWindowSize.Y)
		local nextX = math.clamp(qSwipeStartCanvas.X - delta.X * 1.25, 0, maxX)
		local nextY = math.clamp(qSwipeStartCanvas.Y - delta.Y * 1.25, 0, maxY)
		QuickEmojiScroll.CanvasPosition = Vector2.new(nextX, nextY)
	end
end)

local lastMsgId = 0
local clearCycleSignal = 0
local seededInitialHistory = false
local forceFetchNow = false
local isSending = false

local function sendChatPayload(rawText)
	if isSending or not reqFunc then return end
	local cleanText = tostring(rawText or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if cleanText == "" then return end
	if #cleanText > 200 then cleanText = string.sub(cleanText, 1, 200) end
	isSending = true
	SendChatBtn.Text = "..."
	unlockChatStream()
	local nowTs = os.time()
	local payload = safeEncode({
		user = (LocalPlayer and LocalPlayer.Name) or "Player",
		displayName = (LocalPlayer and LocalPlayer.DisplayName) or ((LocalPlayer and LocalPlayer.Name) or "Player"),
		userId = (LocalPlayer and LocalPlayer.UserId) or 0,
		text = cleanText,
		time = nowTs,
		server = CHAT_SERVER_TAG
	})
	task.spawn(function()
		local ok, res = chatHttpRequest("POST", "/send", payload)
		isSending = false
		SendChatBtn.Text = "GỬI"
		if not (ok and res and (res.StatusCode == 200 or res.Success)) then
			appendChatLine("Hệ thống", "Gửi lỗi, thử lại sau", 0, nowTs, Color3.fromRGB(255, 110, 110), true)
		end
	end)
end

local quickIcons20 = {
	"😂", "🔥", "❤️", "👍", "😭", "😎", "🤩", "😡", "🤡", "💯",
	"✨", "🎉", "💔", "🥰", "😮", "😢", "🤝", "🚀", "👑", "🥶"
}

for idx, iconChar in ipairs(quickIcons20) do
	local iconBtn = Instance.new("TextButton")
	iconBtn.Name = "QuickIcon_" .. tostring(idx)
	iconBtn.Parent = QuickEmojiScroll
	iconBtn.LayoutOrder = idx
	iconBtn.BackgroundColor3 = Color3.fromRGB(46, 34, 68)
	iconBtn.BackgroundTransparency = 0.12
	iconBtn.Font = Enum.Font.GothamBold
	iconBtn.Text = iconChar
	iconBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	iconBtn.TextSize = 15
	iconBtn.ZIndex = 24
	Instance.new("UICorner", iconBtn).CornerRadius = UDim.new(0, 7)

	iconBtn.MouseButton1Click:Connect(function()
		QuickEmojiPicker.Visible = false
		sendChatPayload(iconChar)
	end)
end

QuickEmojiBtn.MouseButton1Click:Connect(function()
	ActionSheet.Visible = false
	OnlinePanel.Visible = false
	QuickEmojiPicker.Visible = not QuickEmojiPicker.Visible
end)

local function fetchChatMessagesOnce()
	if not reqFunc then return end
	local seenClearAtStart = clearCycleSignal
	local path = "/messages" .. (lastMsgId > 0 and ("?after=" .. tostring(lastMsgId)) or "")
	local ok, res = chatHttpRequest("GET", path, nil)
	if ok and res and (res.StatusCode == 200 or res.Success) then
		local data = safeDecode(res.Body)
		if type(data) == "table" and data.ok then
			if type(data.messages) == "table" then
				for _, m in ipairs(data.messages) do
					local mid = tonumber(m.id) or 0
					if mid > lastMsgId then
						lastMsgId = mid
						if seededInitialHistory and seenClearAtStart == clearCycleSignal then
							appendChatLine(tostring(m.user or "Player"), tostring(m.text or ""), m.userId, m.time or m.timestamp or m.createdAt, nil, true)
						end
					end
				end
				seededInitialHistory = true
			end
		end
	end
end

local function openChatBox()
	ChatBox.Visible = true
	ChatPill.Visible = false
	forceFetchNow = true
end
local function closeChatBox()
	ChatBox.Visible = false
	OnlinePanel.Visible, ActionSheet.Visible, QuickEmojiPicker.Visible = false, false, false
	ChatPill.Visible = true
end

ChatPill.MouseButton1Click:Connect(openChatBox)
HideChatBtn.MouseButton1Click:Connect(closeChatBox)

local function sendCrossChat()
	local rawText = ChatInput.Text:gsub("^%s+", ""):gsub("%s+$", "")
	if rawText == "" then return end
	ChatInput.Text = ""
	sendChatPayload(rawText)
end

SendChatBtn.MouseButton1Click:Connect(sendCrossChat)
ChatInput.FocusLost:Connect(function(enterPressed) if enterPressed then sendCrossChat() end end)

task.spawn(function()
	while ChatGui and ChatGui.Parent do
		task.wait(600)
		appendChatLine("Hệ thống", DISCORD_LINK, 0, os.time(), Color3.fromRGB(170, 195, 255), true, DISCORD_LINK)
	end
end)

task.spawn(function()
	while ChatGui and ChatGui.Parent do
		task.wait(1800)
		clearCycleSignal += 1
		for _, child in ipairs(MsgScroll:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		MsgScroll.CanvasPosition = Vector2.new(0, 0)
		appendChatLine("Hệ thống", "Mỗi 30 phút hệ thống sẽ tự xoá toàn bộ tin nhắn!", 0, os.time(), Color3.fromRGB(255, 210, 130), true)
	end
end)

task.spawn(function()
	if not reqFunc then return end
	local myUser = (LocalPlayer and LocalPlayer.Name) or "Player"
	local myDisplay = (LocalPlayer and LocalPlayer.DisplayName) or myUser
	local myId = (LocalPlayer and LocalPlayer.UserId) or 0
	registerScriptUser(myUser, myDisplay, myId)

	local function syncActiveUsers(listData)
		if type(listData) ~= "table" then return end
		local fresh = { [myUser] = { realName = myUser, editedName = myDisplay, userId = myId } }
		for _, u in ipairs(listData) do
			if type(u) == "table" then
				local rName = tostring(u.user or u.username or u.realName or "")
				if rName ~= "" and rName ~= "Player" then
					fresh[rName] = { realName = rName, editedName = tostring(u.displayName or u.editedName or u.nick or rName), userId = tonumber(u.userId) or 0 }
				end
			elseif type(u) == "string" and u ~= "" then
				fresh[u] = { realName = u, editedName = u, userId = 0 }
			end
		end
		activeScriptUsers = fresh
		rebuildOnlineList()
	end

	task.spawn(function()
		while ChatGui and ChatGui.Parent do
			pcall(function()
				local okPing, r = chatHttpRequest("POST", "/ping", safeEncode({ user = myUser, displayName = myDisplay, userId = myId, server = CHAT_SERVER_TAG }))
				if okPing and r and r.Body then
					local pData = safeDecode(r.Body)
					if type(pData) == "table" then syncActiveUsers(pData.users or pData.activeUsers) end
				end
			end)
			task.wait(45)
		end
	end)

	while ChatGui and ChatGui.Parent do
		if ChatBox.Visible or forceFetchNow then
			forceFetchNow = false
			fetchChatMessagesOnce()
			task.wait(3)
		else
			task.wait(1)
		end
	end
end)
local RunBtn = Instance.new("TextButton")
RunBtn.Parent = MainFrame
RunBtn.Position = UDim2.new(0, 8, 0, 360)
RunBtn.Size = UDim2.new(1, -16, 0, 24)
RunBtn.BackgroundColor3 = Color3.fromRGB(255, 105, 35)
RunBtn.Font = Enum.Font.GothamBold
RunBtn.Text = "🚀 CHẠY SCRIPT"
RunBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
RunBtn.TextSize = 10
RunBtn.ZIndex = 2
Instance.new("UICorner", RunBtn).CornerRadius = UDim.new(1, 0)

RunBtn.MouseButton1Click:Connect(function()
	RunBtn.Text = "⏳ ĐANG TẢI & FIX LAG..."
	if FpsBoostEnabled then ApplyFixLag() end

	local hubTitleText = SelectedHub == "Venyx" and "Venyx Hub V13 Max" or (SelectedHub == "Divine" and "Divine Hub (Aquavine)" or "Chilli & Venyx & Divine V13 Max")
	local ActiveGui = Instance.new("ScreenGui")
	ActiveGui.Name = "ActiveHubNotification"
	ActiveGui.ResetOnSpawn = false
	attachGui(ActiveGui)

	local NotifFrame = Instance.new("Frame")
	NotifFrame.Parent = ActiveGui
	NotifFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	NotifFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	NotifFrame.Size = UDim2.new(0, 240, 0, 56)
	NotifFrame.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
	NotifFrame.BackgroundTransparency = 0.2
	Instance.new("UICorner", NotifFrame).CornerRadius = UDim.new(1, 0)

	local RainbowStroke = Instance.new("UIStroke", NotifFrame)
	RainbowStroke.Thickness = 2.5
	task.spawn(function()
		local hue = 0
		while RainbowStroke and RainbowStroke.Parent do
			hue = (hue + 0.01) % 1
			RainbowStroke.Color = Color3.fromHSV(hue, 1, 1)
			task.wait(0.04)
		end
	end)
	MakeDraggable(NotifFrame)

	local IconContainer = Instance.new("Frame", NotifFrame)
	IconContainer.Position = UDim2.new(0, 8, 0.5, -13)
	IconContainer.Size = UDim2.new(0, 26, 0, 26)
	IconContainer.BackgroundTransparency = 1
	local IconImage = Instance.new("ImageLabel", IconContainer)
	IconImage.Size = UDim2.new(1, 0, 1, 0)
	IconImage.BackgroundTransparency = 1
	IconImage.Image = "rbxassetid://83467411655369"
	IconImage.ScaleType = Enum.ScaleType.Crop
	Instance.new("UICorner", IconImage).CornerRadius = UDim.new(1, 0)

	local NotifTitle = Instance.new("TextLabel", NotifFrame)
	NotifTitle.Position = UDim2.new(0, 38, 0, 5)
	NotifTitle.Size = UDim2.new(1, -75, 0, 15)
	NotifTitle.BackgroundTransparency = 1
	NotifTitle.Font = Enum.Font.GothamBold
	NotifTitle.Text = hubTitleText
	NotifTitle.TextColor3 = Color3.fromRGB(255, 190, 120)
	NotifTitle.TextSize = 9
	NotifTitle.TextXAlignment = Enum.TextXAlignment.Left

	local NotifSub = Instance.new("TextLabel", NotifFrame)
	NotifSub.Position = UDim2.new(0, 38, 0, 21)
	NotifSub.Size = UDim2.new(1, -75, 0, 14)
	NotifSub.BackgroundTransparency = 1
	NotifSub.Font = Enum.Font.GothamBold
	NotifSub.Text = "👤 Tác giả: Hirose x Miyano | 💬 Bấm copy link"
	NotifSub.TextColor3 = Color3.fromRGB(255, 100, 100)
	NotifSub.TextSize = 7.5
	NotifSub.TextXAlignment = Enum.TextXAlignment.Left

	local NotifDetail = Instance.new("TextLabel", NotifFrame)
	NotifDetail.Position = UDim2.new(0, 38, 0, 35)
	NotifDetail.Size = UDim2.new(1, -75, 0, 14)
	NotifDetail.BackgroundTransparency = 1
	NotifDetail.Font = Enum.Font.GothamMedium
	NotifDetail.Text = "discord.gg/uqhEpzXy9q"
	NotifDetail.TextColor3 = Color3.fromRGB(160, 170, 255)
	NotifDetail.TextSize = 8
	NotifDetail.TextXAlignment = Enum.TextXAlignment.Left

	local ClickBtn = Instance.new("TextButton", NotifFrame)
	ClickBtn.Position = UDim2.new(0, 38, 0, 0)
	ClickBtn.Size = UDim2.new(1, -75, 1, 0)
	ClickBtn.BackgroundTransparency = 1
	ClickBtn.Text = ""
	ClickBtn.MouseButton1Click:Connect(function()
		if setclipboard then pcall(setclipboard, DISCORD_LINK) end
		NotifTitle.Text = "✓ ĐÃ SAO CHÉP LINK!"
		task.wait(1.5)
		NotifTitle.Text = hubTitleText
	end)

	local MinimizeText = Instance.new("TextLabel", NotifFrame)
	MinimizeText.Position = UDim2.new(0, 12, 0, 0)
	MinimizeText.Size = UDim2.new(1, -44, 1, 0)
	MinimizeText.BackgroundTransparency = 1
	MinimizeText.Font = Enum.Font.GothamBold
	MinimizeText.Text = "Tác Giả: Hirose x Miyano"
	MinimizeText.TextColor3 = Color3.fromRGB(255, 120, 120)
	MinimizeText.TextSize = 9
	MinimizeText.TextXAlignment = Enum.TextXAlignment.Left
	MinimizeText.Visible = false

	local ToggleBtn = Instance.new("TextButton", NotifFrame)
	ToggleBtn.Position = UDim2.new(1, -32, 0.5, -14)
	ToggleBtn.Size = UDim2.new(0, 26, 0, 26)
	ToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	ToggleBtn.Font = Enum.Font.GothamBold
	ToggleBtn.Text = "▲"
	ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	ToggleBtn.TextSize = 11
	Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(1, 0)

	local isMinimized = false
	ToggleBtn.MouseButton1Click:Connect(function()
		isMinimized = not isMinimized
		if isMinimized then
			ToggleBtn.Text = "▼"
			TweenService:Create(NotifFrame, TweenInfo.new(0.2), {Size = UDim2.new(0, 160, 0, 32)}):Play()
			NotifTitle.Visible, NotifSub.Visible, NotifDetail.Visible, IconContainer.Visible, MinimizeText.Visible = false, false, false, false, true
		else
			ToggleBtn.Text = "▲"
			TweenService:Create(NotifFrame, TweenInfo.new(0.2), {Size = UDim2.new(0, 240, 0, 56)}):Play()
			MinimizeText.Visible = false
			task.wait(0.1)
			NotifTitle.Visible, NotifSub.Visible, NotifDetail.Visible, IconContainer.Visible = true, true, true, true
		end
	end)

	local targetCode = SCRIPTS[SelectedHub]
	task.spawn(function()
		local func, err = loadstring(targetCode)
		if func then func() else warn("Lỗi load script: " .. tostring(err)) end
	end)

	task.wait(0.5)
	ScreenGui:Destroy()
end)
