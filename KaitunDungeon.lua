-- The core waits for LocalPlayer and caches its source after identity is ready.
local source = [====[
do
local Bootstrap=(function()
-- Runs in both the standalone wrapper and the cached core after teleport.
-- IsLoaded alone does not guarantee that Players.LocalPlayer is populated.
local Module = {}
function Module.Check(players, loaded)
    if not loaded then return nil,"waiting-game" end
    local player=players.LocalPlayer
    if not player then return nil,"waiting-local-player" end
    if type(player.UserId)~="number" or player.UserId<=0 or type(player.Name)~="string" or player.Name=="" then
        return nil,"waiting-player-identity"
    end
    if not player:FindFirstChild("PlayerGui") then return nil,"waiting-player-gui" end
    return player
end
function Module.Wait(deps, timeout)
    local started=deps.Now()
    while true do
        -- Re-read LocalPlayer on every attempt; do not capture its initial nil.
        local player,reason=Module.Check(deps.Players,deps.IsLoaded())
        if player then return player end
        if deps.Now()-started>=(timeout or 120) then
            error("[TrashHub] Startup timed out: "..reason..". Run the script again after the game loads.",0)
        end
        deps.Wait(0.1)
    end
end
function Module.WaitNative()
    return Module.Wait({Players=game:GetService("Players"),IsLoaded=function()return game:IsLoaded()end,
        Now=os.clock,Wait=task.wait},120)
end
return Module

end)()
local player=Bootstrap.WaitNative()
local startupSource=...
if type(startupSource)=="string" and type(writefile)=="function" then
    pcall(writefile,"TrashHub_Kaitun_Main_v1_"..player.UserId..".luau",startupSource)
end
end
do
local AutoTeam=(function()
-- Runs before HUD readiness: the game cannot finish spawning without a team.
-- Native TeamSelection and Main.TeamSelect both use SetTeam2, not SetTeam.
local Module = {}
local Controller = {}; Controller.__index = Controller
function Module.new(deps)
    return setmetatable({Deps=deps, Alive=true, NextAttempt=0, Serial=0, Status="waiting-player"}, Controller)
end
function Controller:_cancel()
    self.Serial += 1
    if self.Job then pcall(self.Deps.Cancel, self.Job.Thread); self.Job=nil end
end
function Controller:Step()
    if not self.Alive then return end
    local state, now = self.Deps.Read(), self.Deps.Now()
    if state.Team then
        self:_cancel(); self.Status="team-selected"
        return
    end
    if not state.Loaded or not state.Ready then self.Status="waiting-team-selection"; return end
    if self.Job then
        if now-self.Job.At >= 8 then self:_cancel(); self.Status="request-timeout" end
        return
    end
    if now < self.NextAttempt then return end
    self.NextAttempt=now+3
    self.Status="selecting-marines"
    local job={At=now, Serial=self.Serial}; self.Job=job
    job.Thread=self.Deps.Spawn(function()
        if not self.Alive or self.Job~=job or self.Deps.Read().Team then return end
        local ok, err=pcall(self.Deps.ChooseMarines)
        if not self.Alive or self.Job~=job or job.Serial~=self.Serial then return end
        self.Job=nil
        self.LastError=not ok and tostring(err) or nil
        self.Status=ok and "waiting-team-confirmation" or "request-failed"
    end)
end
function Controller:AttachUI(ui)
    if self.Connection then self.Connection:Disconnect() end
    self.UI=ui; ui.LiveAutoTeam=self
    self.Connection=ui.ScreenGui.Destroying:Connect(function() self:Destroy() end)
end
function Controller:Destroy()
    if not self.Alive then return end
    self.Alive=false; self:_cancel()
    if self.Connection then self.Connection:Disconnect() end
    if self.Thread and self.Thread~=coroutine.running() then pcall(self.Deps.Cancel,self.Thread) end
    if self.UI and self.UI.LiveAutoTeam==self then self.UI.LiveAutoTeam=nil end
    if self.Deps.OnDestroyed then self.Deps.OnDestroyed(self) end
end
function Controller:Start()
    self.Thread=self.Deps.Spawn(function()
        while self.Alive do
            local ok, err=pcall(function() self:Step() end)
            if not ok then self.LastError=tostring(err) end
            -- Team selection is only needed before the initial character spawn.
            if self.Status=="team-selected" then return end
            self.Deps.Wait(0.5)
        end
    end)
    return self
end
function Module.StartNative()
    local env=getgenv()
    if env.TrashHubDungeonTeamBootstrap then env.TrashHubDungeonTeamBootstrap:Destroy() end
    local players, rs=game:GetService("Players"), game:GetService("ReplicatedStorage")
    local deps={Now=os.clock, Spawn=task.defer, Wait=task.wait, Cancel=task.cancel}
    deps.Read=function()
        local p=players.LocalPlayer
        local remotes=rs:FindFirstChild("Remotes")
        local remote=remotes and remotes:FindFirstChild("CommF_")
        return {Team=p and p.Team, Loaded=game:IsLoaded(), Ready=p~=nil and remote~=nil}
    end
    deps.ChooseMarines=function()
        local p=players.LocalPlayer
        if not p or p.Team then return end
        local remotes=rs:FindFirstChild("Remotes")
        local remote=remotes and remotes:FindFirstChild("CommF_")
        assert(remote and remote:IsA("RemoteFunction"),"team remote not ready")
        local getter,setter=getthreadidentity or getidentity,setthreadidentity or setidentity
        local prior=getter and getter()
        if setter and prior then setter(2) end
        local ok,err=pcall(function() remote:InvokeServer("SetTeam2","Marines") end)
        if setter and prior then setter(prior) end
        if not ok then error(err,0) end
    end
    deps.OnDestroyed=function(self)
        if env.TrashHubDungeonTeamBootstrap==self then env.TrashHubDungeonTeamBootstrap=nil end
    end
    local controller=Module.new(deps)
    env.TrashHubDungeonTeamBootstrap=controller
    return controller:Start()
end
return Module

end)()
AutoTeam.StartNative()
end
do
    local env = getgenv()
    if workspace:GetAttribute("IsDungeonInstance") == true then
        local session = env.TrashHubDungeonStatusSession
        if not session or session.JobId ~= game.JobId then
            env.TrashHubDungeonStatusSession = {JobId = game.JobId, StartedAt = os.clock()}
        end
    else env.TrashHubDungeonStatusSession = nil end
end
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local parentGui = (type(gethui) == "function" and gethui())
    or (pcall(function() return CoreGui end) and CoreGui)
    or (LocalPlayer and LocalPlayer:WaitForChild("PlayerGui"))

local GUI_NAME = "CustomProjectUI"
local BLUR_NAME = "CustomProjectUI_Blur"

local oldGui = parentGui:FindFirstChild(GUI_NAME)
if oldGui then
    oldGui:Destroy()
end

pcall(function()
    local oldBlur = Lighting:FindFirstChild(BLUR_NAME)
    if oldBlur then
        oldBlur:Destroy()
    end
end)

local function applyModernFont(textObject, weight)
    local success = pcall(function()
        textObject.FontFace = Font.fromName("Montserrat", weight or Enum.FontWeight.SemiBold)
    end)
    if not success or not textObject.FontFace or textObject.FontFace.Family == "" then
        textObject.Font = Enum.Font.Ubuntu
    end
end

local StatusUI = {}

-- ========================================================
-- CATALOG & RARITY DỮ LIỆU TOÀN BỘ 15 BUFFS CỐT LÕI
-- ========================================================
local RARITY_COLORS = {
    Uncommon  = Color3.fromRGB(65, 215, 50),   -- Xanh lá tươi
    Rare      = Color3.fromRGB(45, 155, 255),  -- Xanh dương sáng
    Epic      = Color3.fromRGB(165, 65, 235),  -- Tím sáng
    Legendary = Color3.fromRGB(255, 175, 40),  -- Vàng cam sáng
}

local BUFF_LIST = {
    -- Hàng 1: 5 Thẻ LEGENDARY (Huyền Thoại)
    { Id = "AttackSpeedMultiplier", DisplayName = "HYPER!", Rarity = "Legendary" },
    { Id = "Fortress", DisplayName = "Fortress", Rarity = "Legendary" },
    { Id = "Overflow", DisplayName = "Overflow", Rarity = "Legendary" },
    { Id = "Shadow", DisplayName = "Shadow", Rarity = "Legendary" },
    { Id = "AllCooldown", DisplayName = "All CD", Rarity = "Legendary" },

    -- Hàng 2: 4 Thẻ EPIC (Sử Thi) + 1 Thẻ RARE (Hiếm)
    { Id = "Lifesteal", DisplayName = "Lifesteal", Rarity = "Epic" },
    { Id = "Sniper", DisplayName = "Sniper", Rarity = "Epic" },
    { Id = "Unbreakable", DisplayName = "Unbreakable", Rarity = "Epic" },
    { Id = "FruitTAPCooldown", DisplayName = "Fruit M1", Rarity = "Epic" },
    { Id = "Armor", DisplayName = "Armor", Rarity = "Rare" },

    -- Hàng 3: 5 Thẻ UNCOMMON (Stats cơ bản)
    { Id = "Melee", DisplayName = "Melee", Rarity = "Uncommon" },
    { Id = "Sword", DisplayName = "Sword", Rarity = "Uncommon" },
    { Id = "Gun", DisplayName = "Gun", Rarity = "Uncommon" },
    { Id = "Fruit", DisplayName = "Fruit", Rarity = "Uncommon" },
    { Id = "Defense", DisplayName = "Defense", Rarity = "Uncommon" },
}

-- ========================================================
-- SPRITES CHÍNH THỨC TOÀN BỘ 15 BUFFS TRÍCH XUẤT TỪ DUNGEON GAME
-- ========================================================
local BUFF_SPRITES = {
    -- Hàng 1: 5 Thẻ LEGENDARY (Huyền Thoại)
    ["AttackSpeedMultiplier"] = {
        Image = "rbxassetid://95545392227413",
        Offset = Vector2.new(1, 1),
        Size = Vector2.new(256, 256),
        Color = Color3.fromRGB(255, 185, 45),
    },
    ["Fortress"] = {
        Image = "rbxassetid://79589836967971",
        Offset = Vector2.new(1, 265),
        Size = Vector2.new(64, 64),
        Color = Color3.fromRGB(255, 215, 65),
    },
    ["Overflow"] = {
        Image = "rbxassetid://125953019736797",
        Offset = Vector2.new(1, 517),
        Size = Vector2.new(256, 256),
        Color = Color3.fromRGB(65, 215, 255),
    },
    ["Shadow"] = {
        Image = "rbxassetid://79589836967971",
        Offset = Vector2.new(1, 397),
        Size = Vector2.new(64, 64),
        Color = Color3.fromRGB(190, 85, 255),
    },
    ["AllCooldown"] = {
        Image = "rbxassetid://125953019736797",
        Offset = Vector2.new(1, 1),
        Size = Vector2.new(256, 256),
        Color = Color3.fromRGB(255, 175, 45),
    },

    -- Hàng 2: 4 Thẻ EPIC (Sử Thi) + 1 Thẻ RARE (Hiếm)
    ["Lifesteal"] = {
        Image = "rbxassetid://84918743365562",
        Offset = Vector2.new(259, 1),
        Size = Vector2.new(256, 256),
        Color = Color3.fromRGB(255, 60, 75),
    },
    ["Sniper"] = {
        Image = "rbxassetid://125953019736797",
        Offset = Vector2.new(517, 517),
        Size = Vector2.new(256, 256),
        Color = Color3.fromRGB(205, 90, 255),
    },
    ["Unbreakable"] = {
        Image = "rbxassetid://79589836967971",
        Offset = Vector2.new(133, 397),
        Size = Vector2.new(64, 64),
        Color = Color3.fromRGB(215, 110, 255),
    },
    ["FruitTAPCooldown"] = {
        Image = "rbxassetid://95955079688448",
        Offset = Vector2.new(761, 153),
        Size = Vector2.new(150, 150),
        Color = Color3.fromRGB(180, 95, 255),
    },
    ["Armor"] = {
        Image = "rbxassetid://125953019736797",
        Offset = Vector2.new(1, 517),
        Size = Vector2.new(256, 256),
        Color = Color3.fromRGB(50, 165, 255),
    },

    -- Hàng 3: 5 Thẻ UNCOMMON (Stats cơ bản)
    ["Melee"] = {
        Image = "rbxassetid://118058864367599",
        Offset = Vector2.new(305, 1),
        Size = Vector2.new(150, 150),
        Color = Color3.fromRGB(75, 225, 65),
    },
    ["Sword"] = {
        Image = "rbxassetid://71600490378919",
        Offset = Vector2.new(153, 1),
        Size = Vector2.new(150, 150),
        Color = Color3.fromRGB(75, 225, 65),
    },
    ["Gun"] = {
        Image = "rbxassetid://115308324665471",
        Offset = Vector2.new(609, 305),
        Size = Vector2.new(150, 150),
        Color = Color3.fromRGB(75, 225, 65),
    },
    ["Fruit"] = {
        Image = "rbxassetid://95955079688448",
        Offset = Vector2.new(761, 153),
        Size = Vector2.new(150, 150),
        Color = Color3.fromRGB(75, 225, 65),
    },
    ["Defense"] = {
        Image = "rbxassetid://84918743365562",
        Offset = Vector2.new(1, 259),
        Size = Vector2.new(256, 256),
        Color = Color3.fromRGB(75, 225, 65),
    },
}

-- ========================================================
-- CATALOG 6 LOẠI NHẪN CHÍNH THỨC & SPRITE CHUẨN TỪ ITEMCONFIG
-- ========================================================
local RING_TIERS = {
    {
        Grade = 4,
        Suffix = "IV",
        Title = "TIER IV - MYTHICAL",
        Req = "Req Lv. 2800",
        Color = Color3.fromRGB(255, 75, 90),
    },
    {
        Grade = 3,
        Suffix = "III",
        Title = "TIER III - LEGENDARY",
        Req = "Req Lv. 2250",
        Color = Color3.fromRGB(255, 175, 40),
    },
    {
        Grade = 2,
        Suffix = "II",
        Title = "TIER II - RARE",
        Req = "Req Lv. 1500",
        Color = Color3.fromRGB(45, 160, 255),
    },
    {
        Grade = 1,
        Suffix = "I",
        Title = "TIER I - UNCOMMON",
        Req = "Req Lv. 1",
        Color = Color3.fromRGB(65, 215, 50),
    },
}

local RING_CATALOG = {
    { Name = "Ring of Might", ShortName = "Might" },
    { Name = "Ring of Spirit", ShortName = "Spirit" },
    { Name = "Ring of Twin Blades", ShortName = "Twin Blades" },
    { Name = "Ring of the Outlaw", ShortName = "Outlaw" },
    { Name = "Ring of Steelheart", ShortName = "Steelheart" },
    { Name = "Ring of the Arcanist", ShortName = "Arcanist" },
}

-- Bảng Sprite chính thức được trích xuất trực tiếp từ ItemConfig của game
local RING_SPRITES = {
    ["Ring of Might"] = {
        [1] = { Image = "rbxassetid://108724946074747", Offset = Vector2.new(1, 1), Size = Vector2.new(250, 250) },
        [2] = { Image = "rbxassetid://108724946074747", Offset = Vector2.new(1, 505), Size = Vector2.new(250, 250) },
        [3] = { Image = "rbxassetid://108724946074747", Offset = Vector2.new(253, 1), Size = Vector2.new(250, 250) },
        [4] = { Image = "rbxassetid://108724946074747", Offset = Vector2.new(253, 1), Size = Vector2.new(250, 250) },
    },
    ["Ring of Spirit"] = {
        [1] = { Image = "rbxassetid://108724946074747", Offset = Vector2.new(253, 253), Size = Vector2.new(250, 250) },
        [2] = { Image = "rbxassetid://108724946074747", Offset = Vector2.new(253, 757), Size = Vector2.new(250, 250) },
        [3] = { Image = "rbxassetid://108724946074747", Offset = Vector2.new(757, 253), Size = Vector2.new(250, 250) },
        [4] = { Image = "rbxassetid://108724946074747", Offset = Vector2.new(757, 253), Size = Vector2.new(250, 250) },
    },
    ["Ring of Twin Blades"] = {
        [1] = { Image = "rbxassetid://135703942827678", Offset = Vector2.new(1, 757), Size = Vector2.new(250, 250) },
        [2] = { Image = "rbxassetid://135703942827678", Offset = Vector2.new(253, 253), Size = Vector2.new(250, 250) },
        [3] = { Image = "rbxassetid://135703942827678", Offset = Vector2.new(253, 757), Size = Vector2.new(250, 250) },
        [4] = { Image = "rbxassetid://135703942827678", Offset = Vector2.new(253, 757), Size = Vector2.new(250, 250) },
    },
    ["Ring of the Outlaw"] = {
        [1] = { Image = "rbxassetid://86013243054512", Offset = Vector2.new(505, 505), Size = Vector2.new(250, 250) },
        [2] = { Image = "rbxassetid://86013243054512", Offset = Vector2.new(757, 505), Size = Vector2.new(250, 250) },
        [3] = { Image = "rbxassetid://135703942827678", Offset = Vector2.new(1, 1), Size = Vector2.new(250, 250) },
        [4] = { Image = "rbxassetid://135703942827678", Offset = Vector2.new(1, 1), Size = Vector2.new(250, 250) },
    },
    ["Ring of Steelheart"] = {
        [1] = { Image = "rbxassetid://108724946074747", Offset = Vector2.new(757, 505), Size = Vector2.new(250, 250) },
        [2] = { Image = "rbxassetid://86013243054512", Offset = Vector2.new(1, 1), Size = Vector2.new(250, 250) },
        [3] = { Image = "rbxassetid://86013243054512", Offset = Vector2.new(1, 505), Size = Vector2.new(250, 250) },
        [4] = { Image = "rbxassetid://86013243054512", Offset = Vector2.new(1, 505), Size = Vector2.new(250, 250) },
    },
    ["Ring of the Arcanist"] = {
        [1] = { Image = "rbxassetid://86013243054512", Offset = Vector2.new(505, 1), Size = Vector2.new(250, 250) },
        [2] = { Image = "rbxassetid://86013243054512", Offset = Vector2.new(253, 253), Size = Vector2.new(250, 250) },
        [3] = { Image = "rbxassetid://86013243054512", Offset = Vector2.new(253, 757), Size = Vector2.new(250, 250) },
        [4] = { Image = "rbxassetid://86013243054512", Offset = Vector2.new(253, 757), Size = Vector2.new(250, 250) },
    },
}

-- Bảng Outline Sprite chính thức từ trinkets-3.png (rbxassetid://111313901245472)
-- Dùng để tạo hiệu ứng ngọn lửa Aura Thần Thoại bọc ngoài nhẫn Cấp IV chuẩn 100% như Blox Fruits
local RING_OUTLINE_SPRITES = {
    ["Ring of Might"] = {
        Image = "rbxassetid://111313901245472",
        Offset = Vector2.new(1, 1),
        Size = Vector2.new(250, 250),
    },
    ["Ring of Spirit"] = {
        Image = "rbxassetid://111313901245472",
        Offset = Vector2.new(1, 253),
        Size = Vector2.new(250, 250),
    },
    ["Ring of Steelheart"] = {
        Image = "rbxassetid://111313901245472",
        Offset = Vector2.new(253, 1),
        Size = Vector2.new(250, 250),
    },
    ["Ring of Twin Blades"] = {
        Image = "rbxassetid://111313901245472",
        Offset = Vector2.new(505, 253),
        Size = Vector2.new(250, 250),
    },
    ["Ring of the Arcanist"] = {
        Image = "rbxassetid://111313901245472",
        Offset = Vector2.new(253, 253),
        Size = Vector2.new(250, 250),
    },
    ["Ring of the Outlaw"] = {
        Image = "rbxassetid://111313901245472",
        Offset = Vector2.new(505, 1),
        Size = Vector2.new(250, 250),
    },
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = GUI_NAME
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = true
screenGui.Parent = parentGui

-- 1. Khung chính dạng kính cao cấp (Frosted Glassmorphism thuần nội bộ UI)
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.Position = UDim2.fromScale(0.5, 0.5)
mainFrame.Size = UDim2.new(0.55, 0, 0.6, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 24, 36)
mainFrame.BackgroundTransparency = 0.2
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui

local aspectRatio = Instance.new("UIAspectRatioConstraint")
aspectRatio.AspectRatio = 1.35
aspectRatio.AspectType = Enum.AspectType.FitWithinMaxSize
aspectRatio.DominantAxis = Enum.DominantAxis.Height
aspectRatio.Parent = mainFrame

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(580, 420)
sizeConstraint.MaxSize = Vector2.new(900, 650)
sizeConstraint.Parent = mainFrame

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 14)
corner.Parent = mainFrame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(150, 185, 235)
stroke.Transparency = 0.62
stroke.Thickness = 1.2
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Parent = mainFrame

local glassSheen = Instance.new("UIGradient")
glassSheen.Rotation = 55
glassSheen.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0.0, Color3.fromRGB(44, 56, 82)),
    ColorSequenceKeypoint.new(1.0, Color3.fromRGB(14, 18, 28)),
})
glassSheen.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0.0, 0.05),
    NumberSequenceKeypoint.new(1.0, 0.25),
})
glassSheen.Parent = mainFrame

-- 2. Vạch phân tách Sidebar
local divider = Instance.new("Frame")
divider.Name = "SidebarDivider"
divider.Position = UDim2.new(0, 138, 0, 16)
divider.Size = UDim2.new(0, 1, 1, -32)
divider.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
divider.BackgroundTransparency = 0.82
divider.BorderSizePixel = 0
divider.Parent = mainFrame

-- 3. Khung Avatar
local avatarImage = Instance.new("ImageLabel")
avatarImage.Name = "UserAvatar"
avatarImage.Position = UDim2.new(0, 23, 0, 20)
avatarImage.Size = UDim2.new(0, 92, 0, 92)
avatarImage.BackgroundColor3 = Color3.fromRGB(36, 42, 60)
avatarImage.BackgroundTransparency = 0.2
avatarImage.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=420&h=420", LocalPlayer and LocalPlayer.UserId or 1)
avatarImage.Parent = mainFrame

local avatarCorner = Instance.new("UICorner")
avatarCorner.CornerRadius = UDim.new(1, 0)
avatarCorner.Parent = avatarImage

local avatarStroke = Instance.new("UIStroke")
avatarStroke.Color = Color3.fromRGB(255, 255, 255)
avatarStroke.Transparency = 0.55
avatarStroke.Thickness = 2
avatarStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
avatarStroke.Parent = avatarImage

task.spawn(function()
    pcall(function()
        if LocalPlayer and LocalPlayer.UserId > 0 then
            local thumb = Players:GetUserThumbnailAsync(
                LocalPlayer.UserId,
                Enum.ThumbnailType.HeadShot,
                Enum.ThumbnailSize.Size420x420
            )
            if thumb and avatarImage and avatarImage.Parent then
                avatarImage.Image = thumb
            end
        end
    end)
end)

-- 4. Tên Người Dùng
local usernameLabel = Instance.new("TextLabel")
usernameLabel.Name = "UsernameLabel"
usernameLabel.Position = UDim2.new(0, 8, 0, 118)
usernameLabel.Size = UDim2.new(0, 122, 0, 20)
usernameLabel.BackgroundTransparency = 1
usernameLabel.Text = LocalPlayer and (LocalPlayer.DisplayName ~= "" and LocalPlayer.DisplayName or LocalPlayer.Name) or "Player"
applyModernFont(usernameLabel, Enum.FontWeight.Bold)
usernameLabel.TextSize = 13
usernameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
usernameLabel.TextTruncate = Enum.TextTruncate.AtEnd
usernameLabel.TextXAlignment = Enum.TextXAlignment.Center
usernameLabel.TextYAlignment = Enum.TextYAlignment.Center
usernameLabel.Parent = mainFrame

-- 5. Tiêu đề góc trên phải
local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "HeaderTitle"
titleLabel.Position = UDim2.new(1, -260, 0, 18)
titleLabel.Size = UDim2.new(0, 240, 0, 22)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "KAITUN DUNGEON"
applyModernFont(titleLabel, Enum.FontWeight.Bold)
titleLabel.TextSize = 14
titleLabel.TextColor3 = Color3.fromRGB(240, 248, 255)
titleLabel.TextTransparency = 0.15
titleLabel.TextXAlignment = Enum.TextXAlignment.Right
titleLabel.TextYAlignment = Enum.TextYAlignment.Top
titleLabel.Parent = mainFrame

-- 6. Content Area
local contentArea = Instance.new("Frame")
contentArea.Name = "ContentArea"
contentArea.Position = UDim2.new(0, 152, 0, 52)
contentArea.Size = UDim2.new(1, -168, 1, -68)
contentArea.BackgroundTransparency = 1
contentArea.Parent = mainFrame

-- 7. Danh sách Tabs
local tabContainer = Instance.new("Frame")
tabContainer.Name = "TabContainer"
tabContainer.Position = UDim2.new(0, 10, 0, 150)
tabContainer.Size = UDim2.new(0, 118, 1, -165)
tabContainer.BackgroundTransparency = 1
tabContainer.Parent = mainFrame

local tabLayout = Instance.new("UIListLayout")
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Padding = UDim.new(0, 6)
tabLayout.Parent = tabContainer

local pages = {}
local tabs = {}
local onTabSwitchedCallbacks = {}

local function switchTab(targetName)
    for name, tabData in pairs(tabs) do
        local isActive = (name == targetName)
        tabData.Button.BackgroundTransparency = isActive and 0.8 or 1
        tabData.Stroke.Transparency = isActive and 0.7 or 1
        tabData.Indicator.Visible = isActive
        tabData.Text.TextColor3 = isActive and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 192, 215)
        
        if pages[name] then
            pages[name].Visible = isActive
        end
    end

    if onTabSwitchedCallbacks[targetName] then
        pcall(onTabSwitchedCallbacks[targetName])
    end

    if StatusUI and StatusUI.OnTabChanged then
        pcall(StatusUI.OnTabChanged, targetName)
    end
end

local tabRegisterOrder = 0
local closeDropdown = nil

local function registerTab(name, isDefault)
    tabRegisterOrder = tabRegisterOrder + 1
    local tabBtn = Instance.new("TextButton")
    tabBtn.Name = "Tab_" .. name:gsub("%s+", "")
    tabBtn.LayoutOrder = tabRegisterOrder
    tabBtn.Size = UDim2.new(1, 0, 0, 34)
    tabBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    tabBtn.BackgroundTransparency = isDefault and 0.8 or 1
    tabBtn.BorderSizePixel = 0
    tabBtn.AutoButtonColor = false
    tabBtn.Text = ""
    tabBtn.Parent = tabContainer

    local tabCorner = Instance.new("UICorner")
    tabCorner.CornerRadius = UDim.new(0, 8)
    tabCorner.Parent = tabBtn

    local tabStroke = Instance.new("UIStroke")
    tabStroke.Color = Color3.fromRGB(255, 255, 255)
    tabStroke.Transparency = isDefault and 0.7 or 1
    tabStroke.Thickness = 1
    tabStroke.Parent = tabBtn

    local activeIndicator = Instance.new("Frame")
    activeIndicator.Name = "ActiveIndicator"
    activeIndicator.Position = UDim2.new(0, 0, 0.5, -9)
    activeIndicator.Size = UDim2.new(0, 3, 0, 18)
    activeIndicator.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
    activeIndicator.BorderSizePixel = 0
    activeIndicator.Visible = isDefault
    activeIndicator.Parent = tabBtn

    local indicatorCorner = Instance.new("UICorner")
    indicatorCorner.CornerRadius = UDim.new(1, 0)
    indicatorCorner.Parent = activeIndicator

    local tabText = Instance.new("TextLabel")
    tabText.Name = "TabText"
    tabText.Position = UDim2.new(0, 12, 0, 0)
    tabText.Size = UDim2.new(1, -14, 1, 0)
    tabText.BackgroundTransparency = 1
    tabText.Text = name
    applyModernFont(tabText, Enum.FontWeight.SemiBold)
    tabText.TextSize = #name > 10 and 11.5 or 13.5
    tabText.TextColor3 = isDefault and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 192, 215)
    tabText.TextXAlignment = Enum.TextXAlignment.Left
    tabText.Parent = tabBtn

    local page = Instance.new("Frame")
    page.Name = name:gsub("%s+", "") .. "Page"
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.Visible = isDefault
    page.Parent = contentArea

    pages[name] = page
    tabs[name] = {
        Button    = tabBtn,
        Stroke    = tabStroke,
        Indicator = activeIndicator,
        Text      = tabText,
    }

    tabBtn.MouseButton1Click:Connect(function()
        if closeDropdown then
            pcall(closeDropdown)
        end
        switchTab(name)
    end)

    return page
end

local statusPage   = registerTab("Status", true)
local ringsPage    = registerTab("Rings", false)
local craftingPage = registerTab("Crafting Rings", false)
local mainPage     = registerTab("Main", false)
local webhookPage  = registerTab("Webhook", false)

-- ==========================================
-- [NOI DUNG TAB MAIN]
;(function()
-- ==========================================
local mainSettings = {
    DungeonMode  = "Easy",
    StopFloor    = "20",
    AutoPickCard = true,
    CardFocus    = "Melee",
    WeaponType   = "Melee",
    OwnerName    = LocalPlayer and LocalPlayer.Name or "",
    IsStarted    = false,
    Alt1         = "",
    Alt2         = "",
    Alt3         = "",
}

local DUNGEON_MODES = {"Easy", "Hard", "Challenge"}
local WEAPON_TYPES = {"Melee", "Sword", "Gun", "Fruit"}

-- Container chính cho Tab Main
local mainContainer = Instance.new("Frame")
mainContainer.Name = "MainContainer"
mainContainer.Size = UDim2.new(1, 0, 1, 0)
mainContainer.BackgroundTransparency = 1
mainContainer.Parent = mainPage

-- Dropdown Overlay và Menu nổi (ZIndex cao, trực thuộc mainPage để không bị clip)
local dropdownOverlay = Instance.new("TextButton")
dropdownOverlay.Name = "DropdownOverlay"
dropdownOverlay.Size = UDim2.new(1, 0, 1, 0)
dropdownOverlay.BackgroundTransparency = 1
dropdownOverlay.Text = ""
dropdownOverlay.Visible = false
dropdownOverlay.ZIndex = 60
dropdownOverlay.Parent = mainPage

local dropdownMenu = Instance.new("Frame")
dropdownMenu.Name = "DropdownMenu"
dropdownMenu.BackgroundColor3 = Color3.fromRGB(24, 30, 44)
dropdownMenu.BackgroundTransparency = 0.08
dropdownMenu.BorderSizePixel = 0
dropdownMenu.Visible = false
dropdownMenu.ZIndex = 61
dropdownMenu.ClipsDescendants = true
dropdownMenu.Parent = mainPage

local dmCorner = Instance.new("UICorner")
dmCorner.CornerRadius = UDim.new(0, 6)
dmCorner.Parent = dropdownMenu

local dmStroke = Instance.new("UIStroke")
dmStroke.Color = Color3.fromRGB(115, 145, 195)
dmStroke.Transparency = 0.35
dmStroke.Thickness = 1.2
dmStroke.Parent = dropdownMenu

local dmScroll = Instance.new("ScrollingFrame")
dmScroll.Name = "Scroll"
dmScroll.Size = UDim2.new(1, 0, 1, 0)
dmScroll.BackgroundTransparency = 1
dmScroll.BorderSizePixel = 0
dmScroll.ScrollBarThickness = 3
dmScroll.ScrollBarImageColor3 = Color3.fromRGB(115, 145, 195)
dmScroll.ScrollBarImageTransparency = 0.35
dmScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
dmScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
dmScroll.ClipsDescendants = true
dmScroll.ZIndex = 62
dmScroll.Parent = dropdownMenu

local dmLayout = Instance.new("UIListLayout")
dmLayout.SortOrder = Enum.SortOrder.LayoutOrder
dmLayout.Padding = UDim.new(0, 2)
dmLayout.Parent = dmScroll

local dmPadding = Instance.new("UIPadding")
dmPadding.PaddingTop = UDim.new(0, 4)
dmPadding.PaddingBottom = UDim.new(0, 4)
dmPadding.PaddingLeft = UDim.new(0, 4)
dmPadding.PaddingRight = UDim.new(0, 4)
dmPadding.Parent = dmScroll

local currentDropdownTarget = nil
local updateAccountLobby = nil

local function closeDropdown()
    dropdownOverlay.Visible = false
    dropdownMenu.Visible = false
    currentDropdownTarget = nil
end

dropdownOverlay.MouseButton1Click:Connect(closeDropdown)

local function positionDropdown(button, targetWidth, targetHeight)
    local btnAbsPos = button.AbsolutePosition
    local pageAbsPos = mainPage.AbsolutePosition
    local relX = btnAbsPos.X - pageAbsPos.X
    local relY = btnAbsPos.Y - pageAbsPos.Y + button.AbsoluteSize.Y + 4
    local menuWidth = math.max(targetWidth or button.AbsoluteSize.X, 130)

    if relX + menuWidth > mainPage.AbsoluteSize.X - 8 then
        relX = mainPage.AbsoluteSize.X - menuWidth - 8
    end
    if relX < 4 then
        relX = 4
    end

    if relY + targetHeight > mainPage.AbsoluteSize.Y - 8 then
        local topRelY = btnAbsPos.Y - pageAbsPos.Y - targetHeight - 4
        if topRelY >= 4 then
            relY = topRelY
        end
    end

    dropdownMenu.Position = UDim2.new(0, relX, 0, relY)
    dropdownMenu.Size = UDim2.new(0, menuWidth, 0, targetHeight)
end

local function openDropdown(button, options, currentSelected, onSelected)
    if currentDropdownTarget == button and dropdownMenu.Visible then
        closeDropdown()
        return
    end

    currentDropdownTarget = button

    for _, child in ipairs(dmScroll:GetChildren()) do
        if child:IsA("TextButton") or child:IsA("Frame") or child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    local itemHeight = 26
    local targetHeight = math.clamp((#options * (itemHeight + 2)) + 8, 34, 150)
    positionDropdown(button, button.AbsoluteSize.X, targetHeight)

    for idx, opt in ipairs(options) do
        local isSelected = (opt == currentSelected)
        local optBtn = Instance.new("TextButton")
        optBtn.Name = "Option_" .. opt
        optBtn.Size = UDim2.new(1, 0, 0, itemHeight)
        optBtn.BackgroundColor3 = isSelected and Color3.fromRGB(48, 64, 92) or Color3.fromRGB(32, 42, 60)
        optBtn.BackgroundTransparency = isSelected and 0.2 or 0.6
        optBtn.BorderSizePixel = 0
        optBtn.AutoButtonColor = false
        optBtn.Text = opt
        applyModernFont(optBtn, isSelected and Enum.FontWeight.Bold or Enum.FontWeight.Medium)
        optBtn.TextSize = 11
        optBtn.TextColor3 = isSelected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(195, 210, 235)
        optBtn.TextXAlignment = Enum.TextXAlignment.Center
        optBtn.LayoutOrder = idx
        optBtn.ZIndex = 63
        optBtn.Parent = dmScroll

        local oCorner = Instance.new("UICorner")
        oCorner.CornerRadius = UDim.new(0, 4)
        oCorner.Parent = optBtn

        optBtn.MouseEnter:Connect(function()
            if not isSelected then optBtn.BackgroundTransparency = 0.35 end
        end)
        optBtn.MouseLeave:Connect(function()
            if not isSelected then optBtn.BackgroundTransparency = 0.6 end
        end)

        optBtn.MouseButton1Click:Connect(function()
            closeDropdown()
            if onSelected then onSelected(opt) end
        end)
    end

    dropdownOverlay.Visible = true
    dropdownMenu.Visible = true
end

-- ========================================================
-- PHẦN TRÊN: 5 THẺ THIẾT LẬP (Hàng 1: 3 thẻ, Hàng 2: 2 thẻ)
-- Đã xóa thẻ ALT theo yêu cầu người dùng
-- ========================================================
local settingsSection = Instance.new("Frame")
settingsSection.Name = "SettingsSection"
settingsSection.Size = UDim2.new(1, 0, 0, 126)
settingsSection.BackgroundTransparency = 1
settingsSection.Parent = mainContainer

local function createSettingCard(name, titleText)
    local card = Instance.new("Frame")
    card.Name = "Card_" .. name
    card.BackgroundColor3 = Color3.fromRGB(44, 55, 80)
    card.BackgroundTransparency = 0.35
    card.BorderSizePixel = 0

    local cCorner = Instance.new("UICorner")
    cCorner.CornerRadius = UDim.new(0, 8)
    cCorner.Parent = card

    local cStroke = Instance.new("UIStroke")
    cStroke.Color = Color3.fromRGB(105, 135, 185)
    cStroke.Transparency = 0.5
    cStroke.Thickness = 1
    cStroke.Parent = card

    local cGrad = Instance.new("UIGradient")
    cGrad.Rotation = 45
    cGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.0, Color3.fromRGB(72, 92, 132)),
        ColorSequenceKeypoint.new(1.0, Color3.fromRGB(36, 46, 68)),
    })
    cGrad.Parent = card

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Name = "Title"
    titleLbl.Position = UDim2.new(0, 8, 0, 4)
    titleLbl.Size = UDim2.new(1, -16, 0, 14)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = string.upper(titleText)
    applyModernFont(titleLbl, Enum.FontWeight.Bold)
    titleLbl.TextSize = 10
    titleLbl.TextColor3 = Color3.fromRGB(175, 190, 220)
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Parent = card

    return card
end

-- Hàng 1 (3 thẻ: CHON CHE DO, FLOOR NGUNG, PICK CARD)
local row1 = Instance.new("Frame")
row1.Name = "Row1"
row1.Position = UDim2.new(0, 0, 0, 0)
row1.Size = UDim2.new(1, 0, 0, 58)
row1.BackgroundTransparency = 1
row1.Parent = settingsSection

local row1Layout = Instance.new("UIListLayout")
row1Layout.FillDirection = Enum.FillDirection.Horizontal
row1Layout.SortOrder = Enum.SortOrder.LayoutOrder
row1Layout.Padding = UDim.new(0, 8)
row1Layout.Parent = row1

-- 1. CHON CHE DO (Dropdown)
local modeCard = createSettingCard("DungeonMode", "Mode DIFFICULTY")
modeCard.Size = UDim2.new(0.333, -5, 1, 0)
modeCard.LayoutOrder = 1
modeCard.Parent = row1

local modeBtn = Instance.new("TextButton")
modeBtn.Name = "ModeButton"
modeBtn.Position = UDim2.new(0, 6, 0, 22)
modeBtn.Size = UDim2.new(1, -12, 0, 28)
modeBtn.BackgroundColor3 = Color3.fromRGB(30, 40, 60)
modeBtn.BackgroundTransparency = 0.35
modeBtn.BorderSizePixel = 0
modeBtn.AutoButtonColor = false
modeBtn.Text = ""
modeBtn.Parent = modeCard

local mbCorner = Instance.new("UICorner")
mbCorner.CornerRadius = UDim.new(0, 5)
mbCorner.Parent = modeBtn

local mbStroke = Instance.new("UIStroke")
mbStroke.Color = Color3.fromRGB(85, 110, 155)
mbStroke.Transparency = 0.55
mbStroke.Thickness = 1
mbStroke.Parent = modeBtn

local modeBtnText = Instance.new("TextLabel")
modeBtnText.Name = "Label"
modeBtnText.Position = UDim2.new(0, 8, 0, 0)
modeBtnText.Size = UDim2.new(1, -26, 1, 0)
modeBtnText.BackgroundTransparency = 1
modeBtnText.Text = mainSettings.DungeonMode
applyModernFont(modeBtnText, Enum.FontWeight.Bold)
modeBtnText.TextSize = 11.5
modeBtnText.TextColor3 = Color3.fromRGB(240, 248, 255)
modeBtnText.TextTruncate = Enum.TextTruncate.AtEnd
modeBtnText.TextXAlignment = Enum.TextXAlignment.Left
modeBtnText.Parent = modeBtn

local mbArrow = Instance.new("TextLabel")
mbArrow.Name = "Arrow"
mbArrow.AnchorPoint = Vector2.new(1, 0.5)
mbArrow.Position = UDim2.new(1, -6, 0.5, 0)
mbArrow.Size = UDim2.new(0, 14, 0, 14)
mbArrow.BackgroundTransparency = 1
mbArrow.Text = "v"
applyModernFont(mbArrow, Enum.FontWeight.Bold)
mbArrow.TextSize = 9.5
mbArrow.TextColor3 = Color3.fromRGB(165, 185, 215)
mbArrow.Parent = modeBtn

modeBtn.MouseButton1Click:Connect(function()
    openDropdown(modeBtn, DUNGEON_MODES, mainSettings.DungeonMode, function(newMode)
        mainSettings.DungeonMode = newMode
        modeBtnText.Text = newMode
        if StatusUI and StatusUI.OnMainSettingChanged then
            pcall(StatusUI.OnMainSettingChanged, "DungeonMode", newMode)
        end
    end)
end)

-- 2. FLOOR NGUNG (TextBox)
local stopFloorCard = createSettingCard("StopFloor", "floor stop")
stopFloorCard.Size = UDim2.new(0.333, -5, 1, 0)
stopFloorCard.LayoutOrder = 2
stopFloorCard.Parent = row1

local stopFloorBox = Instance.new("TextBox")
stopFloorBox.Name = "StopFloorInput"
stopFloorBox.Position = UDim2.new(0, 6, 0, 22)
stopFloorBox.Size = UDim2.new(1, -12, 0, 28)
stopFloorBox.BackgroundColor3 = Color3.fromRGB(30, 40, 60)
stopFloorBox.BackgroundTransparency = 0.35
stopFloorBox.BorderSizePixel = 0
stopFloorBox.ClearTextOnFocus = false
stopFloorBox.Text = mainSettings.StopFloor
stopFloorBox.PlaceholderText = "20 / inf"
stopFloorBox.PlaceholderColor3 = Color3.fromRGB(140, 155, 180)
applyModernFont(stopFloorBox, Enum.FontWeight.Bold)
stopFloorBox.TextSize = 12
stopFloorBox.TextColor3 = Color3.fromRGB(255, 255, 255)
stopFloorBox.TextXAlignment = Enum.TextXAlignment.Center
stopFloorBox.Parent = stopFloorCard

local sfCorner = Instance.new("UICorner")
sfCorner.CornerRadius = UDim.new(0, 5)
sfCorner.Parent = stopFloorBox

local sfStroke = Instance.new("UIStroke")
sfStroke.Color = Color3.fromRGB(85, 110, 155)
sfStroke.Transparency = 0.55
sfStroke.Thickness = 1
sfStroke.Parent = stopFloorBox

stopFloorBox.FocusLost:Connect(function()
    local text = stopFloorBox.Text:match("^%s*(.-)%s*$")
    if text == "" then text = "20" end
    mainSettings.StopFloor = text
    stopFloorBox.Text = text
    if StatusUI and StatusUI.OnMainSettingChanged then
        pcall(StatusUI.OnMainSettingChanged, "StopFloor", text)
    end
end)

-- Pick Card follows the selected damage profile while START is active.
local pickCardCard = createSettingCard("PickCard", "PICK CARD")
pickCardCard.Size = UDim2.new(0.333, -6, 1, 0)
pickCardCard.LayoutOrder = 3
pickCardCard.Parent = row1
local cardFocusBtn = Instance.new("TextButton")
cardFocusBtn.Name = "PickCardFocusButton"
cardFocusBtn.Position = UDim2.fromOffset(6, 22)
cardFocusBtn.Size = UDim2.new(1, -12, 0, 28)
cardFocusBtn.BackgroundColor3 = Color3.fromRGB(30, 40, 60)
cardFocusBtn.BackgroundTransparency = 0.2
cardFocusBtn.BorderSizePixel = 0
cardFocusBtn.AutoButtonColor = false
cardFocusBtn.Text = mainSettings.CardFocus
cardFocusBtn.TextColor3 = Color3.fromRGB(240, 248, 255)
applyModernFont(cardFocusBtn, Enum.FontWeight.Bold)
cardFocusBtn.TextSize = 11.5
cardFocusBtn.Parent = pickCardCard
local pcCorner = Instance.new("UICorner")
pcCorner.CornerRadius = UDim.new(0, 5)
pcCorner.Parent = cardFocusBtn
local pcStroke = Instance.new("UIStroke")
pcStroke.Color = Color3.fromRGB(85, 110, 155)
pcStroke.Transparency = 0.55
pcStroke.Thickness = 1
pcStroke.Parent = cardFocusBtn
local function setCardFocus(value)
    mainSettings.CardFocus = value == "Sword" and "Sword" or "Melee"
    cardFocusBtn.Text = mainSettings.CardFocus
    if StatusUI.OnMainSettingChanged then
        pcall(StatusUI.OnMainSettingChanged, "CardFocus", mainSettings.CardFocus)
    end
end
cardFocusBtn.MouseButton1Click:Connect(function()
    openDropdown(cardFocusBtn, {"Melee", "Sword"}, mainSettings.CardFocus, setCardFocus)
end)

-- Hàng 2 (2 thẻ: WEAPON, OWNER) - Thẻ rộng 50% cân đối, đẹp mắt
local row2 = Instance.new("Frame")
row2.Name = "Row2"
row2.Position = UDim2.new(0, 0, 0, 66)
row2.Size = UDim2.new(1, 0, 0, 58)
row2.BackgroundTransparency = 1
row2.Parent = settingsSection

local row2Layout = Instance.new("UIListLayout")
row2Layout.FillDirection = Enum.FillDirection.Horizontal
row2Layout.SortOrder = Enum.SortOrder.LayoutOrder
row2Layout.Padding = UDim.new(0, 8)
row2Layout.Parent = row2

-- 4. WEAPON (Dropdown)
local weaponCard = createSettingCard("Weapon", "WEAPON")
weaponCard.Size = UDim2.new(0.333, -5, 1, 0)
weaponCard.LayoutOrder = 1
weaponCard.Parent = row2

local weaponBtn = Instance.new("TextButton")
weaponBtn.Name = "WeaponButton"
weaponBtn.Position = UDim2.new(0, 6, 0, 22)
weaponBtn.Size = UDim2.new(1, -12, 0, 28)
weaponBtn.BackgroundColor3 = Color3.fromRGB(30, 40, 60)
weaponBtn.BackgroundTransparency = 0.35
weaponBtn.BorderSizePixel = 0
weaponBtn.AutoButtonColor = false
weaponBtn.Text = ""
weaponBtn.Parent = weaponCard

local wbCorner = Instance.new("UICorner")
wbCorner.CornerRadius = UDim.new(0, 5)
wbCorner.Parent = weaponBtn

local wbStroke = Instance.new("UIStroke")
wbStroke.Color = Color3.fromRGB(85, 110, 155)
wbStroke.Transparency = 0.55
wbStroke.Thickness = 1
wbStroke.Parent = weaponBtn

local weaponBtnText = Instance.new("TextLabel")
weaponBtnText.Name = "Label"
weaponBtnText.Position = UDim2.new(0, 8, 0, 0)
weaponBtnText.Size = UDim2.new(1, -26, 1, 0)
weaponBtnText.BackgroundTransparency = 1
weaponBtnText.Text = mainSettings.WeaponType
applyModernFont(weaponBtnText, Enum.FontWeight.Bold)
weaponBtnText.TextSize = 11.5
weaponBtnText.TextColor3 = Color3.fromRGB(240, 248, 255)
weaponBtnText.TextTruncate = Enum.TextTruncate.AtEnd
weaponBtnText.TextXAlignment = Enum.TextXAlignment.Left
weaponBtnText.Parent = weaponBtn

local wbArrow = Instance.new("TextLabel")
wbArrow.Name = "Arrow"
wbArrow.AnchorPoint = Vector2.new(1, 0.5)
wbArrow.Position = UDim2.new(1, -6, 0.5, 0)
wbArrow.Size = UDim2.new(0, 14, 0, 14)
wbArrow.BackgroundTransparency = 1
wbArrow.Text = "v"
applyModernFont(wbArrow, Enum.FontWeight.Bold)
wbArrow.TextSize = 9.5
wbArrow.TextColor3 = Color3.fromRGB(165, 185, 215)
wbArrow.Parent = weaponBtn

weaponBtn.MouseButton1Click:Connect(function()
    openDropdown(weaponBtn, WEAPON_TYPES, mainSettings.WeaponType, function(newWeapon)
        mainSettings.WeaponType = newWeapon
        weaponBtnText.Text = newWeapon
        if StatusUI and StatusUI.OnMainSettingChanged then
            pcall(StatusUI.OnMainSettingChanged, "WeaponType", newWeapon)
        end
    end)
end)

-- 6. START (Action Button - Bắt đầu / Dừng Kaitun Dungeon)
local startCard = createSettingCard("Start", "START")
startCard.Size = UDim2.new(0.333, -5, 1, 0)
startCard.LayoutOrder = 3
startCard.Parent = row2

local startBtn = Instance.new("TextButton")
startBtn.Name = "StartButton"
startBtn.Position = UDim2.new(0, 6, 0, 22)
startBtn.Size = UDim2.new(1, -12, 0, 28)
startBtn.BackgroundColor3 = Color3.fromRGB(30, 40, 60)
startBtn.BackgroundTransparency = 0.35
startBtn.BorderSizePixel = 0
startBtn.AutoButtonColor = false
startBtn.Text = "START"
applyModernFont(startBtn, Enum.FontWeight.Bold)
startBtn.TextSize = 11.5
startBtn.TextColor3 = Color3.fromRGB(240, 248, 255)
startBtn.Parent = startCard

local sbCorner = Instance.new("UICorner")
sbCorner.CornerRadius = UDim.new(0, 5)
sbCorner.Parent = startBtn

local sbStroke = Instance.new("UIStroke")
sbStroke.Color = Color3.fromRGB(85, 110, 155)
sbStroke.Transparency = 0.55
sbStroke.Thickness = 1
sbStroke.Parent = startBtn

local function updateStartVisual()
    if mainSettings.IsStarted then
        startBtn.Text = "STOP"
        startBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        startBtn.BackgroundColor3 = Color3.fromRGB(48, 65, 96)
        startBtn.BackgroundTransparency = 0.15
        sbStroke.Color = Color3.fromRGB(125, 160, 220)
        sbStroke.Transparency = 0.35
    else
        startBtn.Text = "START"
        startBtn.TextColor3 = Color3.fromRGB(220, 235, 255)
        startBtn.BackgroundColor3 = Color3.fromRGB(30, 40, 60)
        startBtn.BackgroundTransparency = 0.35
        sbStroke.Color = Color3.fromRGB(85, 110, 155)
        sbStroke.Transparency = 0.55
    end
end

startBtn.MouseEnter:Connect(function()
    startBtn.BackgroundTransparency = mainSettings.IsStarted and 0.08 or 0.2
    startBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
end)

startBtn.MouseLeave:Connect(function()
    updateStartVisual()
end)

startBtn.MouseButton1Click:Connect(function()
    mainSettings.IsStarted = not mainSettings.IsStarted
    updateStartVisual()
    if StatusUI and StatusUI.OnStartClick then
        pcall(StatusUI.OnStartClick, mainSettings.IsStarted)
    elseif StatusUI and StatusUI.OnMainSettingChanged then
        pcall(StatusUI.OnMainSettingChanged, "IsStarted", mainSettings.IsStarted)
    end
end)

-- ========================================================
-- PHẦN DƯỚI: ACCOUNT LOBBY (Danh sách tài khoản Owner & Alt)
-- Xác định vai trò: Ai trùng với Owner -> OWNER, Khác -> ALT
-- ========================================================
local row3 = Instance.new("Frame")
row3.Name = "PartyNamesRow"
row3.Position = UDim2.fromOffset(0, 132)
row3.Size = UDim2.new(1, 0, 0, 58)
row3.BackgroundTransparency = 1
row3.Parent = mainContainer
local function nameInput(key, title, x, width, value, placeholder)
    local card = createSettingCard(key, title)
    card.Position, card.Size = UDim2.new(x, 0, 0, 0), UDim2.new(width, -5, 1, 0)
    card.Parent = row3
    local input = Instance.new("TextBox")
    input.Name = key .. "Input"
    input.Position, input.Size = UDim2.fromOffset(6, 22), UDim2.new(1, -12, 0, 28)
    input.BackgroundColor3 = Color3.fromRGB(30, 40, 60)
    input.BackgroundTransparency = 0.2
    input.BorderSizePixel = 0
    input.ClearTextOnFocus = false
    input.Text, input.PlaceholderText = value, placeholder
    input.TextColor3, input.PlaceholderColor3 = Color3.fromRGB(240, 248, 255), Color3.fromRGB(140, 160, 190)
    input.TextXAlignment = Enum.TextXAlignment.Left
    applyModernFont(input, Enum.FontWeight.SemiBold)
    input.TextSize = 11.5
    input.Parent = card
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 5); corner.Parent = input
    local padding = Instance.new("UIPadding"); padding.PaddingLeft = UDim.new(0, 8); padding.PaddingRight = UDim.new(0, 6); padding.Parent = input
    return input
end
local ownerNameInput = nameInput("OwnerUsername", "OWNER USERNAME", 0, 0.333, mainSettings.OwnerName, "@username")
local ownerInputCard = ownerNameInput.Parent
ownerInputCard.LayoutOrder = 2
ownerInputCard.Parent = row2
local altNameInputs = {}
for i = 1, 3 do
    local slot = i
    local input = nameInput("Alt" .. slot, "ALT " .. slot, (slot - 1) / 3, 1 / 3, "", "@username")
    altNameInputs[slot] = input
    input.FocusLost:Connect(function() StatusUI.SetAltSlot(slot, input.Text) end)
end
ownerNameInput.FocusLost:Connect(function() StatusUI.SetOwnerName(ownerNameInput.Text) end)

local lobbySection = Instance.new("Frame")
lobbySection.Name = "LobbySection"
lobbySection.Position = UDim2.new(0, 0, 0, 196)
lobbySection.Size = UDim2.new(1, 0, 1, -200)
lobbySection.BackgroundTransparency = 1
lobbySection.Parent = mainContainer

local lobbyHeader = Instance.new("Frame")
lobbyHeader.Name = "LobbyHeader"
lobbyHeader.Size = UDim2.new(1, 0, 0, 18)
lobbyHeader.BackgroundTransparency = 1
lobbyHeader.Parent = lobbySection

local lobbyTitle = Instance.new("TextLabel")
lobbyTitle.Name = "Title"
lobbyTitle.Position = UDim2.new(0, 2, 0, 0)
lobbyTitle.Size = UDim2.new(0.5, 0, 1, 0)
lobbyTitle.BackgroundTransparency = 1
lobbyTitle.Text = "ACCOUNT LOBBY"
applyModernFont(lobbyTitle, Enum.FontWeight.Bold)
lobbyTitle.TextSize = 11
lobbyTitle.TextColor3 = Color3.fromRGB(175, 190, 220)
lobbyTitle.TextXAlignment = Enum.TextXAlignment.Left
lobbyTitle.Parent = lobbyHeader

local lobbyCountLabel = Instance.new("TextLabel")
lobbyCountLabel.Name = "CountLabel"
lobbyCountLabel.AnchorPoint = Vector2.new(1, 0)
lobbyCountLabel.Position = UDim2.new(1, -4, 0, 0)
lobbyCountLabel.Size = UDim2.new(0.5, 0, 1, 0)
lobbyCountLabel.BackgroundTransparency = 1
lobbyCountLabel.Text = "1 ACCOUNTS (1 ONLINE)"
applyModernFont(lobbyCountLabel, Enum.FontWeight.Bold)
lobbyCountLabel.TextSize = 10
lobbyCountLabel.TextColor3 = Color3.fromRGB(140, 160, 195)
lobbyCountLabel.TextXAlignment = Enum.TextXAlignment.Right
lobbyCountLabel.Parent = lobbyHeader

local lobbyScroll = Instance.new("ScrollingFrame")
lobbyScroll.Name = "LobbyScroll"
lobbyScroll.Position = UDim2.new(0, 0, 0, 22)
lobbyScroll.Size = UDim2.new(1, 0, 1, -24)
lobbyScroll.BackgroundTransparency = 1
lobbyScroll.BorderSizePixel = 0
lobbyScroll.ScrollBarThickness = 3
lobbyScroll.ScrollBarImageColor3 = Color3.fromRGB(115, 145, 195)
lobbyScroll.ScrollBarImageTransparency = 0.35
lobbyScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
lobbyScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
lobbyScroll.ClipsDescendants = true
lobbyScroll.Parent = lobbySection

local lobbyLayout = Instance.new("UIListLayout")
lobbyLayout.SortOrder = Enum.SortOrder.LayoutOrder
lobbyLayout.Padding = UDim.new(0, 6)
lobbyLayout.Parent = lobbyScroll

local function renderAccountRow(accData, order)
    local isOwner = accData.IsOwner == true
    local isOnline = accData.IsOnline ~= false
    local username = accData.Name or "Unknown"
    local displayName = accData.DisplayName or username

    local row = Instance.new("Frame")
    row.Name = "Acc_" .. username
    row.Size = UDim2.new(1, -6, 0, 44)
    row.BackgroundColor3 = Color3.fromRGB(24, 30, 44)
    row.BackgroundTransparency = 0.35
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.Parent = lobbyScroll

    local rCorner = Instance.new("UICorner")
    rCorner.CornerRadius = UDim.new(0, 6)
    rCorner.Parent = row

    local rStroke = Instance.new("UIStroke")
    rStroke.Color = isOwner and Color3.fromRGB(255, 205, 75) or Color3.fromRGB(85, 110, 155)
    rStroke.Transparency = isOwner and 0.35 or 0.65
    rStroke.Thickness = isOwner and 1.2 or 1
    rStroke.Parent = row

    -- 1. Avatar tròn
    local avatarFrame = Instance.new("Frame")
    avatarFrame.Name = "AvatarFrame"
    avatarFrame.Position = UDim2.new(0, 7, 0.5, -16)
    avatarFrame.Size = UDim2.new(0, 32, 0, 32)
    avatarFrame.BackgroundColor3 = Color3.fromRGB(20, 26, 38)
    avatarFrame.BackgroundTransparency = 0.3
    avatarFrame.BorderSizePixel = 0
    avatarFrame.Parent = row

    local avCorner = Instance.new("UICorner")
    avCorner.CornerRadius = UDim.new(1, 0)
    avCorner.Parent = avatarFrame

    local avStroke = Instance.new("UIStroke")
    avStroke.Color = isOwner and Color3.fromRGB(255, 205, 75) or Color3.fromRGB(130, 155, 200)
    avStroke.Transparency = isOwner and 0.4 or 0.7
    avStroke.Thickness = 1
    avStroke.Parent = avatarFrame

    local avImg = Instance.new("ImageLabel")
    avImg.Name = "AvatarImage"
    avImg.Size = UDim2.new(1, 0, 1, 0)
    avImg.BackgroundTransparency = 1
    avImg.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", accData.UserId or 1)
    avImg.Parent = avatarFrame

    local imgCorner = Instance.new("UICorner")
    imgCorner.CornerRadius = UDim.new(1, 0)
    imgCorner.Parent = avImg

    task.spawn(function()
        pcall(function()
            local uid = accData.UserId
            if not uid or uid <= 0 then
                local foundPlr = Players:FindFirstChild(username)
                if foundPlr then
                    uid = foundPlr.UserId
                else
                    local s, resId = pcall(function() return Players:GetUserIdFromNameAsync(username) end)
                    if s and resId then uid = resId end
                end
            end
            if uid and uid > 0 then
                local sThumb, thumb = pcall(function()
                    return Players:GetUserThumbnailAsync(uid, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
                end)
                if sThumb and thumb and avImg and avImg.Parent then
                    avImg.Image = thumb
                end
            end
        end)
    end)

    -- 2. Status Dot
    local statusDot = Instance.new("Frame")
    statusDot.Name = "StatusDot"
    statusDot.Position = UDim2.new(0, 30, 0.5, 6)
    statusDot.Size = UDim2.new(0, 9, 0, 9)
    statusDot.BackgroundColor3 = isOnline and Color3.fromRGB(0, 230, 120) or Color3.fromRGB(150, 160, 175)
    statusDot.BorderSizePixel = 0
    statusDot.ZIndex = 3
    statusDot.Parent = row

    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(1, 0)
    dotCorner.Parent = statusDot

    local dotStroke = Instance.new("UIStroke")
    dotStroke.Color = Color3.fromRGB(24, 30, 44)
    dotStroke.Thickness = 1.5
    dotStroke.Parent = statusDot

    -- 3. Names (DisplayName & @Username)
    local nameContainer = Instance.new("Frame")
    nameContainer.Name = "NameContainer"
    nameContainer.Position = UDim2.new(0, 48, 0, 6)
    nameContainer.Size = UDim2.new(1, -180, 1, -12)
    nameContainer.BackgroundTransparency = 1
    nameContainer.Parent = row

    local dnLabel = Instance.new("TextLabel")
    dnLabel.Name = "DisplayName"
    dnLabel.Size = UDim2.new(1, 0, 0, 17)
    dnLabel.BackgroundTransparency = 1
    dnLabel.Text = displayName
    applyModernFont(dnLabel, Enum.FontWeight.Bold)
    dnLabel.TextSize = 12
    dnLabel.TextColor3 = Color3.fromRGB(245, 250, 255)
    dnLabel.TextTruncate = Enum.TextTruncate.AtEnd
    dnLabel.TextXAlignment = Enum.TextXAlignment.Left
    dnLabel.Parent = nameContainer

    local unLabel = Instance.new("TextLabel")
    unLabel.Name = "Username"
    unLabel.Position = UDim2.new(0, 0, 0, 16)
    unLabel.Size = UDim2.new(1, 0, 0, 14)
    unLabel.BackgroundTransparency = 1
    unLabel.Text = "@" .. username
    applyModernFont(unLabel, Enum.FontWeight.Medium)
    unLabel.TextSize = 9.5
    unLabel.TextColor3 = Color3.fromRGB(155, 175, 205)
    unLabel.TextTruncate = Enum.TextTruncate.AtEnd
    unLabel.TextXAlignment = Enum.TextXAlignment.Left
    unLabel.Parent = nameContainer

    -- 4. Right side: Role Badge & Online Indicator
    local rightGroup = Instance.new("Frame")
    rightGroup.Name = "RightGroup"
    rightGroup.AnchorPoint = Vector2.new(1, 0.5)
    rightGroup.Position = UDim2.new(1, -10, 0.5, 0)
    rightGroup.Size = UDim2.new(0, 130, 0, 26)
    rightGroup.BackgroundTransparency = 1
    rightGroup.Parent = row

    local roleBadge = Instance.new("Frame")
    roleBadge.Name = "RoleBadge"
    roleBadge.AnchorPoint = Vector2.new(1, 0.5)
    roleBadge.Position = UDim2.new(1, -56, 0.5, 0)
    roleBadge.Size = UDim2.new(0, 56, 0, 20)
    roleBadge.BackgroundColor3 = isOwner and Color3.fromRGB(48, 40, 22) or Color3.fromRGB(28, 38, 56)
    roleBadge.BackgroundTransparency = 0.25
    roleBadge.BorderSizePixel = 0
    roleBadge.Parent = rightGroup

    local rbCorner = Instance.new("UICorner")
    rbCorner.CornerRadius = UDim.new(0, 4)
    rbCorner.Parent = roleBadge

    local rbStroke = Instance.new("UIStroke")
    rbStroke.Color = isOwner and Color3.fromRGB(255, 205, 75) or Color3.fromRGB(90, 125, 175)
    rbStroke.Transparency = isOwner and 0.35 or 0.55
    rbStroke.Thickness = 1
    rbStroke.Parent = roleBadge

    local rbLabel = Instance.new("TextLabel")
    rbLabel.Name = "RoleText"
    rbLabel.Size = UDim2.new(1, 0, 1, 0)
    rbLabel.BackgroundTransparency = 1
    rbLabel.Text = isOwner and "OWNER" or "ALT"
    applyModernFont(rbLabel, Enum.FontWeight.Bold)
    rbLabel.TextSize = 10
    rbLabel.TextColor3 = isOwner and Color3.fromRGB(255, 215, 95) or Color3.fromRGB(170, 195, 240)
    rbLabel.TextXAlignment = Enum.TextXAlignment.Center
    rbLabel.TextYAlignment = Enum.TextYAlignment.Center
    rbLabel.Parent = roleBadge

    local statusText = Instance.new("TextLabel")
    statusText.Name = "StatusText"
    statusText.AnchorPoint = Vector2.new(1, 0.5)
    statusText.Position = UDim2.new(1, 0, 0.5, 0)
    statusText.Size = UDim2.new(0, 50, 1, 0)
    statusText.BackgroundTransparency = 1
    statusText.Text = isOnline and "ONLINE" or "OFFLINE"
    applyModernFont(statusText, Enum.FontWeight.Bold)
    statusText.TextSize = 9.5
    statusText.TextColor3 = isOnline and Color3.fromRGB(0, 230, 120) or Color3.fromRGB(150, 160, 175)
    statusText.TextXAlignment = Enum.TextXAlignment.Right
    statusText.TextYAlignment = Enum.TextYAlignment.Center
    statusText.Parent = rightGroup
end

local cachedAccounts
updateAccountLobby = function(customData)
    if type(customData) == "table" then cachedAccounts = customData end
    for _, child in ipairs(lobbyScroll:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") then child:Destroy() end
    end
    local accounts = cachedAccounts
    if not accounts or #accounts == 0 then
        local owner = Players:FindFirstChild(mainSettings.OwnerName)
        accounts = {{Name = mainSettings.OwnerName, DisplayName = owner and owner.DisplayName or mainSettings.OwnerName,
            UserId = owner and owner.UserId or 0, IsOwner = true, IsOnline = owner ~= nil}}
        if LocalPlayer and LocalPlayer.Name:lower() ~= mainSettings.OwnerName:lower() then
            accounts[#accounts + 1] = {Name = LocalPlayer.Name, DisplayName = LocalPlayer.DisplayName,
                UserId = LocalPlayer.UserId, IsOwner = false, IsOnline = true}
        end
    end
    local online = 0
    for i, account in ipairs(accounts) do
        if account.IsOnline then online += 1 end
        renderAccountRow(account, i)
    end
    lobbyCountLabel.Text = string.format("%d ACCOUNTS (%d ONLINE)", #accounts, online)
end

local playerAddedConn = nil
local playerRemovingConn = nil
pcall(function()
    playerAddedConn = Players.PlayerAdded:Connect(function()
        task.wait(0.2)
        if mainPage and mainPage.Parent then
            updateAccountLobby()
        end
    end)
    playerRemovingConn = Players.PlayerRemoving:Connect(function()
        task.wait(0.2)
        if mainPage and mainPage.Parent then
            updateAccountLobby()
        end
    end)
end)

-- Programmatic Setters cho Tab Main
local function setDungeonMode(mode)
    mainSettings.DungeonMode = tostring(mode or "Easy")
    modeBtnText.Text = mainSettings.DungeonMode
    if StatusUI and StatusUI.OnMainSettingChanged then
        pcall(StatusUI.OnMainSettingChanged, "DungeonMode", mainSettings.DungeonMode)
    end
end

local function setStopFloor(floor)
    mainSettings.StopFloor = tostring(floor or "20")
    stopFloorBox.Text = mainSettings.StopFloor
    if StatusUI and StatusUI.OnMainSettingChanged then
        pcall(StatusUI.OnMainSettingChanged, "StopFloor", mainSettings.StopFloor)
    end
end

local function setWeaponType(weapon)
    mainSettings.WeaponType = tostring(weapon or "Melee")
    weaponBtnText.Text = mainSettings.WeaponType
    if StatusUI and StatusUI.OnMainSettingChanged then
        pcall(StatusUI.OnMainSettingChanged, "WeaponType", mainSettings.WeaponType)
    end
end

local function setOwnerName(name)
    mainSettings.OwnerName = tostring(name or ""):match("^%s*@?(.-)%s*$")
    ownerNameInput.Text = mainSettings.OwnerName
    updateAccountLobby()
    if StatusUI and StatusUI.OnMainSettingChanged then
        pcall(StatusUI.OnMainSettingChanged, "OwnerName", mainSettings.OwnerName)
    end
end

local function setStart(state)
    mainSettings.IsStarted = state and true or false
    updateStartVisual()
    if StatusUI and StatusUI.OnMainSettingChanged then
        pcall(StatusUI.OnMainSettingChanged, "IsStarted", mainSettings.IsStarted)
    end
end

updateStartVisual()
updateAccountLobby()

    StatusUI.OwnerNameInput = ownerNameInput
    StatusUI.CardFocusButton = cardFocusBtn
    StatusUI.SetCardFocus = setCardFocus
    StatusUI.PickCardAlways = true
    StatusUI.AltNameInputs = altNameInputs
    StatusUI.SetAltSlot = function(slot, value)
        if slot ~= 1 and slot ~= 2 and slot ~= 3 then return end
        local key = "Alt" .. slot
        mainSettings[key] = tostring(value or ""):match("^%s*@?(.-)%s*$")
        altNameInputs[slot].Text = mainSettings[key]
        if StatusUI.OnMainSettingChanged then pcall(StatusUI.OnMainSettingChanged, key, mainSettings[key]) end
    end
    StatusUI.SetMainStatus = function(message, role)
        StatusUI.MainStatus = {Message = tostring(message), Role = role}
    end
    screenGui.Destroying:Connect(function()
        if playerAddedConn then playerAddedConn:Disconnect() end
        if playerRemovingConn then playerRemovingConn:Disconnect() end
    end)
    StatusUI.MainSettings       = mainSettings
    StatusUI.StartButton        = startBtn
    StatusUI.SetDungeonMode     = setDungeonMode
    StatusUI.SetStopFloor       = setStopFloor
    StatusUI.SetWeaponType      = setWeaponType
    StatusUI.SetOwnerName       = setOwnerName
    StatusUI.SetStart           = setStart
    StatusUI.UpdateAccountLobby = updateAccountLobby
end)()

-- ==========================================
-- [NỘI DUNG TAB STATUS]
;(function()
-- ==========================================

local statusBar = Instance.new("Frame")
statusBar.Name = "UnifiedStatusBar"
statusBar.Size = UDim2.new(1, 0, 0, 62)
statusBar.BackgroundColor3 = Color3.fromRGB(42, 54, 78)
statusBar.BackgroundTransparency = 0.35
statusBar.BorderSizePixel = 0
statusBar.Parent = statusPage

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 10)
barCorner.Parent = statusBar

local barStroke = Instance.new("UIStroke")
barStroke.Color = Color3.fromRGB(110, 140, 195)
barStroke.Transparency = 0.55
barStroke.Thickness = 1
barStroke.Parent = statusBar

local barSheen = Instance.new("UIGradient")
barSheen.Rotation = 45
barSheen.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0.0, Color3.fromRGB(70, 90, 130)),
    ColorSequenceKeypoint.new(1.0, Color3.fromRGB(35, 45, 68)),
})
barSheen.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0.0, 0.2),
    NumberSequenceKeypoint.new(1.0, 0.45),
})
barSheen.Parent = statusBar

local barLayout = Instance.new("UIListLayout")
barLayout.FillDirection = Enum.FillDirection.Horizontal
barLayout.SortOrder = Enum.SortOrder.LayoutOrder
barLayout.Parent = statusBar

local function createStatusItem(parent, title, initialValue, order)
    local item = Instance.new("Frame")
    item.Name = "Item_" .. title
    item.Size = UDim2.new(0.25, 0, 1, 0)
    item.BackgroundTransparency = 1
    item.LayoutOrder = order
    item.Parent = parent

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Name = "Title"
    titleLbl.Position = UDim2.new(0, 0, 0, 10)
    titleLbl.Size = UDim2.new(1, 0, 0, 14)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = string.upper(title)
    applyModernFont(titleLbl, Enum.FontWeight.Medium)
    titleLbl.TextSize = 10
    titleLbl.TextColor3 = Color3.fromRGB(175, 190, 220)
    titleLbl.TextXAlignment = Enum.TextXAlignment.Center
    titleLbl.Parent = item

    local valLbl = Instance.new("TextLabel")
    valLbl.Name = "Value"
    valLbl.Position = UDim2.new(0, 0, 0, 26)
    valLbl.Size = UDim2.new(1, 0, 0, 26)
    valLbl.BackgroundTransparency = 1
    valLbl.Text = initialValue
    applyModernFont(valLbl, Enum.FontWeight.Bold)
    valLbl.TextSize = 19
    valLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    valLbl.TextXAlignment = Enum.TextXAlignment.Center
    valLbl.Parent = item

    if order < 4 then
        local sep = Instance.new("Frame")
        sep.Name = "Sep"
        sep.AnchorPoint = Vector2.new(1, 0.5)
        sep.Position = UDim2.new(1, 0, 0.5, 0)
        sep.Size = UDim2.new(0, 1, 0, 28)
        sep.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        sep.BackgroundTransparency = 0.82
        sep.BorderSizePixel = 0
        sep.Parent = item
    end

    return valLbl
end

local floorLabel  = createStatusItem(statusBar, "Floor", "--", 1)
local timeLabel   = createStatusItem(statusBar, "Time", "0min 00s", 2)
local mobLabel    = createStatusItem(statusBar, "Mobs", "--", 3)
local energyLabel = createStatusItem(statusBar, "Energy", "--/50", 4)

local buffSection = Instance.new("Frame")
buffSection.Name = "BuffSection"
buffSection.Position = UDim2.new(0, 0, 0, 72)
buffSection.Size = UDim2.new(1, 0, 1, -120)
buffSection.BackgroundTransparency = 1
buffSection.Parent = statusPage

local buffGrid = Instance.new("UIGridLayout")
buffGrid.SortOrder = Enum.SortOrder.LayoutOrder
buffGrid.CellPadding = UDim2.new(0.015, 0, 0.04, 0)
buffGrid.CellSize = UDim2.new(0.188, 0, 0.306, 0)
buffGrid.Parent = buffSection

local buffCardsState = {}

-- Bảng lưu trữ tên trang bị hiện tại để tự động đổi ảnh theo đúng vũ khí/trái đang cầm
local equippedToolsMap = {
    Melee = nil,
    Sword = nil,
    Gun = nil,
    Fruit = nil,
}

local function resolveToolSprite(toolName)
    if not toolName or toolName == "" then return nil end
    local success, rf = pcall(function() return game:GetService("ReplicatedFirst") end)
    if not success or not rf then return nil end
    local ok, spritesheets = pcall(require, rf:WaitForChild("Spritesheets", 2))
    if not ok or not spritesheets or not spritesheets.MAP then return nil end
    local map = spritesheets.MAP

    local candidates = {
        toolName .. "1",
        toolName .. "2",
        toolName,
        "Permanent " .. toolName .. "1",
        toolName .. " Fruit1",
    }
    for _, c in ipairs(candidates) do
        if map[c] then
            return {
                Image = map[c].Image,
                Offset = map[c].ImageRectOffset,
                Size = map[c].ImageRectSize,
            }
        end
    end
    for k, v in pairs(map) do
        if k:lower():find(toolName:lower(), 1, true) and not k:find("_Outline") then
            return {
                Image = v.Image,
                Offset = v.ImageRectOffset,
                Size = v.ImageRectSize,
            }
        end
    end
    return nil
end

local function getPlayerEquippedTools()
    local equipped = {
        Melee = nil,
        Sword = nil,
        Gun = nil,
        Fruit = nil,
    }
    local player = Players.LocalPlayer
    if not player then return equipped end

    local function scan(container)
        if not container then return end
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") then
                local tip = tool.ToolTip
                if tip == "Melee" then
                    equipped.Melee = tool.Name
                elseif tip == "Sword" then
                    equipped.Sword = tool.Name
                elseif tip == "Gun" then
                    equipped.Gun = tool.Name
                elseif tip == "Blox Fruit" then
                    equipped.Fruit = tool.Name
                end
            end
        end
    end

    if player.Character then
        scan(player.Character)
    end
    if player:FindFirstChild("Backpack") then
        scan(player.Backpack)
    end
    return equipped
end

local function updateEquipmentCardSprites()
    local tools = getPlayerEquippedTools()
    if tools.Melee then equippedToolsMap.Melee = tools.Melee end
    if tools.Sword then equippedToolsMap.Sword = tools.Sword end
    if tools.Gun then equippedToolsMap.Gun = tools.Gun end
    if tools.Fruit then equippedToolsMap.Fruit = tools.Fruit end

    local mapping = {
        Melee = equippedToolsMap.Melee,
        Sword = equippedToolsMap.Sword,
        Gun = equippedToolsMap.Gun,
        Fruit = equippedToolsMap.Fruit,
        FruitTAPCooldown = equippedToolsMap.Fruit,
    }

    for id, toolName in pairs(mapping) do
        local cardData = buffCardsState[id]
        if cardData and cardData.IconImg and toolName then
            local spr = resolveToolSprite(toolName)
            if spr then
                cardData.IconImg.Image = spr.Image
                cardData.IconImg.ImageRectOffset = spr.Offset
                cardData.IconImg.ImageRectSize = spr.Size
                cardData.IconImg.ImageColor3 = Color3.fromRGB(255, 255, 255)
            end
        end
    end
end

local function updateBuffCardVisual(cardData)
    if not cardData then return end
    cardData.LevelLabel.Text = "Lv. " .. tostring(cardData.Level)
    
    local cardRoot = cardData.Card or cardData.Button
    if cardData.Level > 0 then
        if cardRoot then
            cardRoot.BackgroundColor3 = Color3.fromRGB(52, 66, 96)
            cardRoot.BackgroundTransparency = 0.18
        end
        cardData.Stroke.Transparency = 0.2
        cardData.Stroke.Color = cardData.RarityColor
        cardData.AccentBar.BackgroundTransparency = 0
        cardData.TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)

        if cardData.IconImg then
            cardData.IconImg.ImageTransparency = 0
        end
        if cardData.IconGlow then
            cardData.IconGlow.BackgroundTransparency = 0.82
            cardData.IconGlow.BackgroundColor3 = cardData.RarityColor
        end
        if cardData.Pill then
            cardData.Pill.BackgroundColor3 = Color3.fromRGB(36, 46, 70)
            cardData.Pill.BackgroundTransparency = 0.2
        end
        if cardData.PillStroke then
            cardData.PillStroke.Color = cardData.RarityColor
            cardData.PillStroke.Transparency = 0.3
        end
        cardData.LevelLabel.TextColor3 = cardData.RarityColor
    else
        if cardRoot then
            cardRoot.BackgroundColor3 = Color3.fromRGB(44, 55, 80)
            cardRoot.BackgroundTransparency = 0.35
        end
        cardData.Stroke.Transparency = 0.5
        cardData.Stroke.Color = Color3.fromRGB(105, 135, 185)
        cardData.AccentBar.BackgroundTransparency = 0.3
        cardData.TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)

        if cardData.IconImg then
            cardData.IconImg.ImageTransparency = 0
        end
        if cardData.IconGlow then
            cardData.IconGlow.BackgroundTransparency = 0.88
            cardData.IconGlow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        end
        if cardData.Pill then
            cardData.Pill.BackgroundColor3 = Color3.fromRGB(32, 42, 62)
            cardData.Pill.BackgroundTransparency = 0.3
        end
        if cardData.PillStroke then
            cardData.PillStroke.Color = Color3.fromRGB(80, 105, 150)
            cardData.PillStroke.Transparency = 0.55
        end
        cardData.LevelLabel.TextColor3 = Color3.fromRGB(215, 230, 255)
    end
end

local function resolveBuffData(idOrName)
    if not idOrName then return nil end
    if buffCardsState[idOrName] then
        return buffCardsState[idOrName]
    end
    for _, buff in ipairs(BUFF_LIST) do
        if buff.Id == idOrName or buff.DisplayName == idOrName then
            return buffCardsState[buff.Id]
        end
    end
    return nil
end

local function setBuffLevel(buffId, level)
    local cardData = resolveBuffData(buffId)
    if not cardData then return end
    cardData.Level = math.max(0, tonumber(level) or 0)
    updateBuffCardVisual(cardData)
end

local function addBuffLevel(buffId, amount)
    local cardData = resolveBuffData(buffId)
    if not cardData then return end
    cardData.Level = math.max(0, cardData.Level + (tonumber(amount) or 1))
    updateBuffCardVisual(cardData)
end

for idx, buff in ipairs(BUFF_LIST) do
    local rarityColor = RARITY_COLORS[buff.Rarity] or Color3.fromRGB(255, 255, 255)
    local sprite = BUFF_SPRITES[buff.Id]

    local cardFrame = Instance.new("Frame")
    cardFrame.Name = "Card_" .. buff.Id
    cardFrame.BackgroundColor3 = Color3.fromRGB(44, 55, 80)
    cardFrame.BackgroundTransparency = 0.35
    cardFrame.BorderSizePixel = 0
    cardFrame.LayoutOrder = idx
    cardFrame.ClipsDescendants = true
    cardFrame.Parent = buffSection

    local cCorner = Instance.new("UICorner")
    cCorner.CornerRadius = UDim.new(0, 8)
    cCorner.Parent = cardFrame

    local cStroke = Instance.new("UIStroke")
    cStroke.Color = Color3.fromRGB(105, 135, 185)
    cStroke.Transparency = 0.5
    cStroke.Thickness = 1
    cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    cStroke.Parent = cardFrame

    local cGradient = Instance.new("UIGradient")
    cGradient.Rotation = 45
    cGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.0, Color3.fromRGB(75, 96, 138)),
        ColorSequenceKeypoint.new(1.0, Color3.fromRGB(36, 48, 70)),
    })
    cGradient.Parent = cardFrame

    local accentBar = Instance.new("Frame")
    accentBar.Name = "AccentBar"
    accentBar.Size = UDim2.new(1, 0, 0, 2)
    accentBar.BackgroundColor3 = rarityColor
    accentBar.BackgroundTransparency = 0.3
    accentBar.BorderSizePixel = 0
    accentBar.Parent = cardFrame

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Name = "Title"
    titleLbl.Position = UDim2.new(0, 4, 0, 5)
    titleLbl.Size = UDim2.new(1, -8, 0, 15)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = buff.DisplayName
    applyModernFont(titleLbl, Enum.FontWeight.Bold)
    titleLbl.TextSize = 11
    titleLbl.TextColor3 = Color3.fromRGB(245, 250, 255)
    titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
    titleLbl.TextXAlignment = Enum.TextXAlignment.Center
    titleLbl.TextYAlignment = Enum.TextYAlignment.Center
    titleLbl.Parent = cardFrame

    -- Khung Icon căn giữa thẻ (thoáng đãng, không đóng khung hộp đen)
    local iconContainer = Instance.new("Frame")
    iconContainer.Name = "IconContainer"
    iconContainer.AnchorPoint = Vector2.new(0.5, 0.5)
    iconContainer.Position = UDim2.fromScale(0.5, 0.49)
    iconContainer.Size = UDim2.new(0, 38, 0, 38)
    iconContainer.BackgroundTransparency = 1
    iconContainer.BorderSizePixel = 0
    iconContainer.Parent = cardFrame

    local iconGlow = Instance.new("Frame")
    iconGlow.Name = "Glow"
    iconGlow.AnchorPoint = Vector2.new(0.5, 0.5)
    iconGlow.Position = UDim2.fromScale(0.5, 0.5)
    iconGlow.Size = UDim2.new(0, 40, 0, 40)
    iconGlow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    iconGlow.BackgroundTransparency = 0.94
    iconGlow.BorderSizePixel = 0
    iconGlow.Parent = iconContainer

    local glowCorner = Instance.new("UICorner")
    glowCorner.CornerRadius = UDim.new(1, 0)
    glowCorner.Parent = iconGlow

    local iconImg = Instance.new("ImageLabel")
    iconImg.Name = "Icon"
    iconImg.AnchorPoint = Vector2.new(0.5, 0.5)
    iconImg.Position = UDim2.fromScale(0.5, 0.5)
    iconImg.Size = UDim2.new(0, 34, 0, 34)
    iconImg.BackgroundTransparency = 1
    iconImg.ScaleType = Enum.ScaleType.Fit
    iconImg.ImageTransparency = 0
    iconImg.ImageColor3 = Color3.fromRGB(255, 255, 255) -- Giữ nguyên màu sắc rực rỡ gốc chuẩn game, không bị đè màu xỉn
    iconImg.ZIndex = 2
    if sprite then
        iconImg.Image = sprite.Image
        iconImg.ImageRectOffset = sprite.Offset
        iconImg.ImageRectSize = sprite.Size
    end
    iconImg.Parent = iconContainer

    -- Capsule / Pill hiển thị Level ở đáy thẻ
    local levelPill = Instance.new("Frame")
    levelPill.Name = "LevelPill"
    levelPill.AnchorPoint = Vector2.new(0.5, 1)
    levelPill.Position = UDim2.new(0.5, 0, 1, -5)
    levelPill.Size = UDim2.new(0, 56, 0, 18)
    levelPill.BackgroundColor3 = Color3.fromRGB(32, 42, 62)
    levelPill.BackgroundTransparency = 0.3
    levelPill.BorderSizePixel = 0
    levelPill.Parent = cardFrame

    local pillCorner = Instance.new("UICorner")
    pillCorner.CornerRadius = UDim.new(0, 5)
    pillCorner.Parent = levelPill

    local pillStroke = Instance.new("UIStroke")
    pillStroke.Color = Color3.fromRGB(80, 105, 150)
    pillStroke.Transparency = 0.55
    pillStroke.Thickness = 1
    pillStroke.Parent = levelPill

    local levelLbl = Instance.new("TextLabel")
    levelLbl.Name = "Level"
    levelLbl.Size = UDim2.new(1, 0, 1, 0)
    levelLbl.BackgroundTransparency = 1
    levelLbl.Text = "Lv. 0"
    applyModernFont(levelLbl, Enum.FontWeight.Bold)
    levelLbl.TextSize = 10
    levelLbl.TextColor3 = Color3.fromRGB(215, 230, 255)
    levelLbl.TextXAlignment = Enum.TextXAlignment.Center
    levelLbl.TextYAlignment = Enum.TextYAlignment.Center
    levelLbl.Parent = levelPill

    buffCardsState[buff.Id] = {
        Card        = cardFrame,
        Button      = cardFrame,
        Stroke      = cStroke,
        AccentBar   = accentBar,
        TitleLabel  = titleLbl,
        LevelLabel  = levelLbl,
        Pill        = levelPill,
        PillStroke  = pillStroke,
        IconImg     = iconImg,
        IconGlow    = iconGlow,
        Level       = 0,
        RarityColor = rarityColor,
        Sprite      = sprite,
    }
end

-- Cập nhật ảnh động theo đúng vũ khí/trái đang trang bị trên người
pcall(function()
    updateEquipmentCardSprites()
    if LocalPlayer then
        local function hookToolContainer(cont)
            if not cont then return end
            cont.ChildAdded:Connect(function(c)
                if c:IsA("Tool") then
                    task.wait(0.15)
                    updateEquipmentCardSprites()
                end
            end)
            cont.ChildRemoved:Connect(function(c)
                if c:IsA("Tool") then
                    task.wait(0.15)
                    updateEquipmentCardSprites()
                end
            end)
        end

        hookToolContainer(LocalPlayer:FindFirstChild("Backpack"))
        if LocalPlayer.Character then
            hookToolContainer(LocalPlayer.Character)
        end
        LocalPlayer.CharacterAdded:Connect(function(newChar)
            hookToolContainer(newChar)
            task.wait(0.5)
            updateEquipmentCardSprites()
        end)
    end
end)

local progressSection = Instance.new("Frame")
progressSection.Name = "ProgressSection"
progressSection.AnchorPoint = Vector2.new(0, 1)
progressSection.Position = UDim2.new(0, 0, 1, -2)
progressSection.Size = UDim2.new(1, 0, 0, 38)
progressSection.BackgroundTransparency = 1
progressSection.Parent = statusPage

local progressHeader = Instance.new("Frame")
progressHeader.Name = "ProgressHeader"
progressHeader.Size = UDim2.new(1, 0, 0, 14)
progressHeader.BackgroundTransparency = 1
progressHeader.Parent = progressSection

local progressTitle = Instance.new("TextLabel")
progressTitle.Name = "Title"
progressTitle.Size = UDim2.new(0.5, 0, 1, 0)
progressTitle.BackgroundTransparency = 1
progressTitle.Text = "FLOOR PROGRESS"
applyModernFont(progressTitle, Enum.FontWeight.Bold)
progressTitle.TextSize = 11
progressTitle.TextColor3 = Color3.fromRGB(175, 190, 215)
progressTitle.TextXAlignment = Enum.TextXAlignment.Left
progressTitle.Parent = progressHeader

local progressPercent = Instance.new("TextLabel")
progressPercent.Name = "Percent"
progressPercent.Position = UDim2.new(0.5, 0, 0, 0)
progressPercent.Size = UDim2.new(0.5, 0, 1, 0)
progressPercent.BackgroundTransparency = 1
progressPercent.Text = "0% (0 / 0 Mobs)"
applyModernFont(progressPercent, Enum.FontWeight.SemiBold)
progressPercent.TextSize = 11
progressPercent.TextColor3 = Color3.fromRGB(245, 250, 255)
progressPercent.TextXAlignment = Enum.TextXAlignment.Right
progressPercent.Parent = progressHeader

local progressTrack = Instance.new("Frame")
progressTrack.Name = "ProgressTrack"
progressTrack.Position = UDim2.new(0, 0, 0, 20)
progressTrack.Size = UDim2.new(1, 0, 0, 8)
progressTrack.BackgroundColor3 = Color3.fromRGB(28, 34, 48)
progressTrack.BackgroundTransparency = 0.25
progressTrack.BorderSizePixel = 0
progressTrack.ClipsDescendants = true
progressTrack.Parent = progressSection

local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(1, 0)
trackCorner.Parent = progressTrack

local trackStroke = Instance.new("UIStroke")
trackStroke.Color = Color3.fromRGB(255, 255, 255)
trackStroke.Transparency = 0.8
trackStroke.Thickness = 1
trackStroke.Parent = progressTrack

local progressFill = Instance.new("Frame")
progressFill.Name = "ProgressFill"
progressFill.Size = UDim2.new(0, 0, 1, 0)
progressFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
progressFill.BackgroundTransparency = 0.15
progressFill.BorderSizePixel = 0
progressFill.Parent = progressTrack

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = progressFill

    StatusUI.FloorLabel            = floorLabel
    StatusUI.TimeLabel             = timeLabel
    StatusUI.MobLabel              = mobLabel
    StatusUI.EnergyLabel           = energyLabel
    StatusUI.ProgressFill          = progressFill
    StatusUI.ProgressPercent       = progressPercent
    StatusUI.BuffCardsState        = buffCardsState
    StatusUI.SetBuffLevel          = setBuffLevel
    StatusUI.AddBuffLevel          = addBuffLevel
    StatusUI.UpdateEquippedSprites = updateEquipmentCardSprites
    StatusUI.SetFloor              = function(val) floorLabel.Text = tostring(val or '') end
    StatusUI.SetTime               = function(val) timeLabel.Text = tostring(val or '00:00') end
    StatusUI.SetMobs               = function(val) mobLabel.Text = tostring(val or '0') end
    StatusUI.SetEnergy             = function(val) energyLabel.Text = tostring(val or '100%') end
    StatusUI.SetProgress           = function(ratio, text)
        progressFill.Size = UDim2.new(math.clamp(ratio or 0, 0, 1), 0, 1, 0)
        if text then progressPercent.Text = tostring(text) end
    end
    StatusUI.SetEquippedWeapon     = function(category, toolName)
        if equippedToolsMap[category] ~= nil or category == 'FruitTAPCooldown' then
            equippedToolsMap[category] = toolName
            local cardData = buffCardsState[category]
            if cardData and cardData.IconImg then
                local spr = resolveToolSprite(toolName)
                if spr then
                    cardData.IconImg.Image = spr.Image
                    cardData.IconImg.ImageRectOffset = spr.Offset
                    cardData.IconImg.ImageRectSize = spr.Size
                    cardData.IconImg.ImageColor3 = Color3.fromRGB(255, 255, 255)
                end
            end
        end
    end
end)()

-- ==========================================
-- [NỘI DUNG TAB RINGS]
;(function()
-- Full-frame, KHÔNG CUỘN, 4 hàng (Grade IV -> Grade I)
-- 6 loại nhẫn chính thức: Might, Spirit, Twin Blades, Outlaw, Steelheart, Arcanist
-- Màu sắc sáng sủa, icon rõ nét, đếm số lượng rương thời gian thực
-- ==========================================

local ringsContainer = Instance.new("Frame")
ringsContainer.Name = "RingsContainer"
ringsContainer.Size = UDim2.new(1, 0, 1, 0)
ringsContainer.BackgroundTransparency = 1
ringsContainer.Parent = ringsPage

local ringsLayout = Instance.new("UIListLayout")
ringsLayout.SortOrder = Enum.SortOrder.LayoutOrder
ringsLayout.Padding = UDim.new(0.016, 0)
ringsLayout.Parent = ringsContainer

local ringCardsState = {}
local tierHeaderState = {}

-- Bảng lưu trữ trạng thái hiển thị nhẫn thuần UI (để bạn tự nối logic sau)
local inventoryRingCounts = { [4] = {}, [3] = {}, [2] = {}, [1] = {} }
local equippedRingMap = {}

for grade = 1, 4 do
    for _, ring in ipairs(RING_CATALOG) do
        inventoryRingCounts[grade][ring.Name] = 0
    end
end

local function getInventoryRingCounts()
    return inventoryRingCounts, equippedRingMap
end

-- Tạo 4 hàng đại diện cho 4 Tier
for orderIdx, tier in ipairs(RING_TIERS) do
    local rowFrame = Instance.new("Frame")
    rowFrame.Name = "TierRow_" .. tier.Suffix
    rowFrame.Size = UDim2.new(1, 0, 0.238, 0)
    rowFrame.BackgroundTransparency = 1
    rowFrame.LayoutOrder = orderIdx
    rowFrame.Parent = ringsContainer

    local headerFrame = Instance.new("Frame")
    headerFrame.Name = "Header"
    headerFrame.Size = UDim2.new(1, 0, 0, 24)
    headerFrame.BackgroundColor3 = Color3.fromRGB(36, 46, 68)
    headerFrame.BackgroundTransparency = 0.35
    headerFrame.BorderSizePixel = 0
    headerFrame.Parent = rowFrame

    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 5)
    headerCorner.Parent = headerFrame

    local headerStroke = Instance.new("UIStroke")
    headerStroke.Color = tier.Color
    headerStroke.Transparency = 0.55
    headerStroke.Thickness = 1
    headerStroke.Parent = headerFrame

    local leftAccent = Instance.new("Frame")
    leftAccent.Name = "Accent"
    leftAccent.Size = UDim2.new(0, 3, 1, 0)
    leftAccent.BackgroundColor3 = tier.Color
    leftAccent.BorderSizePixel = 0
    leftAccent.Parent = headerFrame

    local accentCorner = Instance.new("UICorner")
    accentCorner.CornerRadius = UDim.new(0, 2)
    accentCorner.Parent = leftAccent

    local badgeTitle = Instance.new("TextLabel")
    badgeTitle.Name = "Title"
    badgeTitle.Position = UDim2.new(0, 10, 0, 0)
    badgeTitle.Size = UDim2.new(0, 180, 1, 0)
    badgeTitle.BackgroundTransparency = 1
    badgeTitle.Text = tier.Title
    applyModernFont(badgeTitle, Enum.FontWeight.Bold)
    badgeTitle.TextSize = 12
    badgeTitle.TextColor3 = tier.Color
    badgeTitle.TextXAlignment = Enum.TextXAlignment.Left
    badgeTitle.TextYAlignment = Enum.TextYAlignment.Center
    badgeTitle.Parent = headerFrame

    local totalPill = Instance.new("Frame")
    totalPill.Name = "TotalPill"
    totalPill.AnchorPoint = Vector2.new(1, 0.5)
    totalPill.Position = UDim2.new(1, -5, 0.5, 0)
    totalPill.Size = UDim2.new(0, 96, 0, 18)
    totalPill.BackgroundColor3 = Color3.fromRGB(28, 36, 54)
    totalPill.BackgroundTransparency = 0
    totalPill.BorderSizePixel = 0
    totalPill.Parent = headerFrame

    local totalPillCorner = Instance.new("UICorner")
    totalPillCorner.CornerRadius = UDim.new(0, 5)
    totalPillCorner.Parent = totalPill

    local totalPillStroke = Instance.new("UIStroke")
    totalPillStroke.Color = Color3.fromRGB(80, 105, 150)
    totalPillStroke.Transparency = 0.55
    totalPillStroke.Thickness = 1
    totalPillStroke.Parent = totalPill

    local totalLabel = Instance.new("TextLabel")
    totalLabel.Name = "TotalLabel"
    totalLabel.Size = UDim2.new(1, 0, 1, 0)
    totalLabel.BackgroundTransparency = 1
    totalLabel.Text = "0 in Chest"
    applyModernFont(totalLabel, Enum.FontWeight.Bold)
    totalLabel.TextSize = 12
    totalLabel.TextColor3 = Color3.fromRGB(225, 238, 255)
    totalLabel.TextXAlignment = Enum.TextXAlignment.Center
    totalLabel.TextYAlignment = Enum.TextYAlignment.Center
    totalLabel.Parent = totalPill

    tierHeaderState[tier.Suffix] = {
        TotalLabel       = totalLabel,
        TotalPill        = totalPill,
        TotalPillStroke  = totalPillStroke,
        Tier             = tier,
    }

    local slotsFrame = Instance.new("Frame")
    slotsFrame.Name = "SlotsGrid"
    slotsFrame.Position = UDim2.new(0, 0, 0, 28)
    slotsFrame.Size = UDim2.new(1, 0, 1, -28)
    slotsFrame.BackgroundTransparency = 1
    slotsFrame.Parent = rowFrame

    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
    gridLayout.CellSize = UDim2.new(0.155, 0, 1, 0)
    gridLayout.CellPadding = UDim2.new(0.014, 0, 0, 0)
    gridLayout.Parent = slotsFrame

    for ringIdx, ring in ipairs(RING_CATALOG) do
        local card = Instance.new("Frame")
        card.Name = "Card_" .. ring.Name:gsub("%s+", "")
        card.BackgroundColor3 = Color3.fromRGB(44, 55, 80)
        card.BackgroundTransparency = 0.35
        card.BorderSizePixel = 0
        card.LayoutOrder = ringIdx
        card.ClipsDescendants = true
        card.Parent = slotsFrame

        local cCorner = Instance.new("UICorner")
        cCorner.CornerRadius = UDim.new(0, 7)
        cCorner.Parent = card

        local cStroke = Instance.new("UIStroke")
        cStroke.Color = Color3.fromRGB(105, 135, 185)
        cStroke.Transparency = 0.5
        cStroke.Thickness = 1
        cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        cStroke.Parent = card

        local cardGrad = Instance.new("UIGradient")
        cardGrad.Rotation = 45
        cardGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.0, Color3.fromRGB(72, 92, 132)),
            ColorSequenceKeypoint.new(1.0, Color3.fromRGB(36, 46, 68)),
        })
        cardGrad.Parent = card

        local topBar = Instance.new("Frame")
        topBar.Name = "TopBar"
        topBar.Size = UDim2.new(1, 0, 0, 2)
        topBar.BackgroundColor3 = tier.Color
        topBar.BackgroundTransparency = 0.6
        topBar.BorderSizePixel = 0
        topBar.Parent = card

        local rankTag = Instance.new("TextLabel")
        rankTag.Name = "RankTag"
        rankTag.Position = UDim2.new(0, 7, 0, 8)
        rankTag.Size = UDim2.new(0, 20, 0, 13)
        rankTag.BackgroundTransparency = 1
        rankTag.Text = tier.Suffix
        applyModernFont(rankTag, Enum.FontWeight.Bold)
        rankTag.TextSize = 11
        rankTag.TextColor3 = tier.Color
        rankTag.TextTransparency = 0.15
        rankTag.TextXAlignment = Enum.TextXAlignment.Left
        rankTag.TextYAlignment = Enum.TextYAlignment.Center
        rankTag.Parent = card

        -- Pill số lượng ở góc trên bên phải
        local countPill = Instance.new("Frame")
        countPill.Name = "CountPill"
        countPill.AnchorPoint = Vector2.new(1, 0)
        countPill.Position = UDim2.new(1, -6, 0, 6)
        countPill.Size = UDim2.fromOffset(30, 19)
        countPill.BackgroundColor3 = Color3.fromRGB(30, 40, 60)
        countPill.BackgroundTransparency = 0
        countPill.BorderSizePixel = 0
        countPill.ZIndex = 5
        countPill.Parent = card

        local badgeSize = Instance.new("UISizeConstraint")
        badgeSize.MinSize = Vector2.new(30, 19)
        badgeSize.MaxSize = Vector2.new(30, 19)
        badgeSize.Parent = countPill

        local countCorner = Instance.new("UICorner")
        countCorner.CornerRadius = UDim.new(0, 5)
        countCorner.Parent = countPill

        local countStroke = Instance.new("UIStroke")
        countStroke.Color = Color3.fromRGB(85, 110, 155)
        countStroke.Transparency = 0.55
        countStroke.Thickness = 1
        countStroke.Parent = countPill

        local countLbl = Instance.new("TextLabel")
        countLbl.Name = "CountLabel"
        countLbl.Size = UDim2.new(1, 0, 1, 0)
        countLbl.BackgroundTransparency = 1
        countLbl.Text = "0"
        applyModernFont(countLbl, Enum.FontWeight.SemiBold)
        countLbl.TextSize = 14
        countLbl.TextScaled = true
        countLbl.ZIndex = 6
        local countTextSize = Instance.new("UITextSizeConstraint")
        countTextSize.MinTextSize = 10
        countTextSize.MaxTextSize = 14
        countTextSize.Parent = countLbl
        local countPadding = Instance.new("UIPadding")
        countPadding.PaddingLeft = UDim.new(0, 4)
        countPadding.PaddingRight = UDim.new(0, 4)
        countPadding.PaddingTop = UDim.new(0, 1)
        countPadding.PaddingBottom = UDim.new(0, 1)
        countPadding.Parent = countLbl
        countLbl.TextColor3 = Color3.fromRGB(225, 238, 255)
        countLbl.TextXAlignment = Enum.TextXAlignment.Center
        countLbl.TextYAlignment = Enum.TextYAlignment.Center
        countLbl.Parent = countPill

        local eqBadge = Instance.new("Frame")
        eqBadge.Name = "EquippedBadge"
        eqBadge.Position = UDim2.new(0, 4, 0.5, -4)
        eqBadge.Size = UDim2.new(0, 6, 0, 6)
        eqBadge.BackgroundColor3 = Color3.fromRGB(0, 240, 130)
        eqBadge.BorderSizePixel = 0
        eqBadge.Visible = false
        eqBadge.Parent = card

        local eqCorner = Instance.new("UICorner")
        eqCorner.CornerRadius = UDim.new(1, 0)
        eqCorner.Parent = eqBadge

        -- Hào quang Aura dưới mỗi chiếc nhẫn theo màu sắc Tier
        local ringAura = Instance.new("Frame")
        ringAura.Name = "TierAura"
        ringAura.AnchorPoint = Vector2.new(0.5, 0.5)
        ringAura.Position = UDim2.fromScale(0.5, 0.44)
        ringAura.Size = UDim2.new(0, 34, 0, 34)
        ringAura.BackgroundColor3 = tier.Color
        ringAura.BackgroundTransparency = 0.88
        ringAura.BorderSizePixel = 0
        ringAura.ZIndex = 0
        ringAura.Parent = card

        local auraCorner = Instance.new("UICorner")
        auraCorner.CornerRadius = UDim.new(1, 0)
        auraCorner.Parent = ringAura

        -- Lớp viền ngọn lửa Mythic Flame Outline cho Tier 4
        if tier.Grade == 4 then
            local outlineData = RING_OUTLINE_SPRITES[ring.Name]
            if outlineData then
                local outlineImg = Instance.new("ImageLabel")
                outlineImg.Name = "MythicFlameOutline"
                outlineImg.AnchorPoint = Vector2.new(0.5, 0.5)
                outlineImg.Position = UDim2.fromScale(0.5, 0.44)
                outlineImg.Size = UDim2.new(0, 34, 0, 34)
                outlineImg.BackgroundTransparency = 1
                outlineImg.Image = outlineData.Image
                outlineImg.ImageRectOffset = outlineData.Offset
                outlineImg.ImageRectSize = outlineData.Size
                outlineImg.ImageColor3 = Color3.fromRGB(255, 185, 40)
                outlineImg.ImageTransparency = 0.05
                outlineImg.ScaleType = Enum.ScaleType.Fit
                outlineImg.ZIndex = 1
                outlineImg.Parent = card
            end
        end

        local ringImg = Instance.new("ImageLabel")
        ringImg.Name = "RingImage"
        ringImg.AnchorPoint = Vector2.new(0.5, 0.5)
        ringImg.Position = UDim2.fromScale(0.5, 0.44)
        ringImg.Size = UDim2.new(0, 34, 0, 34)
        ringImg.BackgroundTransparency = 1
        ringImg.ImageTransparency = 0
        ringImg.ImageColor3 = Color3.fromRGB(255, 255, 255)
        ringImg.ScaleType = Enum.ScaleType.Fit
        ringImg.ZIndex = 2

        local spriteData = RING_SPRITES[ring.Name] and RING_SPRITES[ring.Name][tier.Grade]
        if spriteData then
            ringImg.Image = spriteData.Image
            ringImg.ImageRectOffset = spriteData.Offset
            ringImg.ImageRectSize = spriteData.Size
        end
        ringImg.Parent = card

        local nameLbl = Instance.new("TextLabel")
        nameLbl.Name = "NameLabel"
        nameLbl.AnchorPoint = Vector2.new(0, 1)
        nameLbl.Position = UDim2.new(0, 3, 1, -3)
        nameLbl.Size = UDim2.new(1, -6, 0, 18)
        nameLbl.BackgroundTransparency = 1
        nameLbl.Text = ring.ShortName
        applyModernFont(nameLbl, Enum.FontWeight.SemiBold)
        nameLbl.TextSize = 12
        nameLbl.TextColor3 = Color3.fromRGB(235, 244, 255)
        nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
        nameLbl.TextXAlignment = Enum.TextXAlignment.Center
        nameLbl.TextYAlignment = Enum.TextYAlignment.Center
        nameLbl.Parent = card

        ringCardsState[ring.Name .. "_" .. tier.Suffix] = {
            Card          = card,
            Stroke        = cStroke,
            TopBar        = topBar,
            CountPill     = countPill,
            CountStroke   = countStroke,
            CountLabel    = countLbl,
            NameLabel     = nameLbl,
            Image         = ringImg,
            Aura          = ringAura,
            EquippedBadge = eqBadge,
            Tier          = tier,
            Ring          = ring,
            Count         = 0,
        }
    end
end

-- Hàm cập nhật số lượng nhẫn và làm sáng/nổi bật thẻ
local function refreshRingCounts()
    local ready = StatusUI.RingInventoryReady == true
    local counts, equippedMap = getInventoryRingCounts()

    for _, tier in ipairs(RING_TIERS) do
        local tierCounts = counts[tier.Grade] or {}
        local totalOwnedInTier = 0

        for _, ring in ipairs(RING_CATALOG) do
            local cardData = ringCardsState[ring.Name .. "_" .. tier.Suffix]
            if cardData then
                local c = tierCounts[ring.Name] or 0
                totalOwnedInTier = totalOwnedInTier + c
                local isEq = equippedMap[ring.Name .. "_" .. tostring(tier.Grade)] == true

                cardData.Count = c
                cardData.CountLabel.Text = ready and tostring(c) or "--"

                if c > 0 then
                    cardData.Card.BackgroundTransparency = 0.08
                    cardData.Card.BackgroundColor3 = Color3.fromRGB(22, 29, 45)
                    cardData.Stroke.Transparency = 0.25
                    cardData.Stroke.Color = tier.Color
                    cardData.TopBar.BackgroundTransparency = 0.1
                    cardData.CountPill.BackgroundColor3 = Color3.fromRGB(10, 15, 25):Lerp(tier.Color, 0.07)
                    cardData.CountStroke.Color = tier.Color
                    cardData.CountStroke.Transparency = 0.3
                    cardData.CountLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                    cardData.Aura.BackgroundTransparency = 0.65
                    cardData.NameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                    cardData.Image.ImageTransparency = 0
                    if cardData.EquippedBadge then
                        cardData.EquippedBadge.Visible = isEq
                    end
                else
                    cardData.Card.BackgroundTransparency = 0.18
                    cardData.Card.BackgroundColor3 = Color3.fromRGB(17, 22, 34)
                    cardData.Stroke.Transparency = 0.5
                    cardData.Stroke.Color = Color3.fromRGB(105, 135, 185)
                    cardData.TopBar.BackgroundTransparency = 0.6
                    cardData.CountPill.BackgroundColor3 = Color3.fromRGB(14, 18, 28)
                    cardData.CountStroke.Color = Color3.fromRGB(85, 110, 155)
                    cardData.CountStroke.Transparency = 0.55
                    cardData.CountLabel.TextColor3 = Color3.fromRGB(145, 157, 180)
                    cardData.Aura.BackgroundTransparency = 0.88
                    cardData.NameLabel.TextColor3 = Color3.fromRGB(235, 244, 255)
                    cardData.Image.ImageTransparency = 0.25
                    if cardData.EquippedBadge then
                        cardData.EquippedBadge.Visible = false
                    end
                end
            end
        end

        local headerData = tierHeaderState[tier.Suffix]
        if headerData and headerData.TotalLabel then
            headerData.TotalLabel.Text = ready and string.format("TOTAL  %d", totalOwnedInTier) or "TOTAL  --"
            if totalOwnedInTier > 0 then
                headerData.TotalLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                if headerData.TotalPillStroke then
                    headerData.TotalPillStroke.Color = tier.Color
                    headerData.TotalPillStroke.Transparency = 0.35
                end
            else
                headerData.TotalLabel.TextColor3 = Color3.fromRGB(225, 238, 255)
                if headerData.TotalPillStroke then
                    headerData.TotalPillStroke.Color = Color3.fromRGB(80, 105, 150)
                    headerData.TotalPillStroke.Transparency = 0.55
                end
            end
        end
    end
end

local function setRingInventoryCount(ringName, grade, count, isEquipped)
    StatusUI.RingInventoryReady = true
    if inventoryRingCounts[grade] then
        inventoryRingCounts[grade][ringName] = count or 0
    end
    if isEquipped ~= nil then
        equippedRingMap[ringName .. "_" .. tostring(grade)] = isEquipped
    end
    refreshRingCounts()
end

-- Đăng ký callback khi bấm sang tab Rings
onTabSwitchedCallbacks["Rings"] = function()
    refreshRingCounts()
end

    StatusUI.RingInventoryReady = false
    StatusUI.RingTierHeaders   = tierHeaderState
    StatusUI.RingCardsState    = ringCardsState
    StatusUI.InventoryCounts   = inventoryRingCounts
    StatusUI.EquippedMap       = equippedRingMap
    StatusUI.SetRingCount      = setRingInventoryCount
    StatusUI.RefreshRingCounts = refreshRingCounts
end)()

-- ==========================================
-- [NỘI DUNG TAB CRAFTING RINGS]
;(function()
-- Giao diện Quản lý Nâng cấp & Ghép Nhẫn (Fusing 3 -> 1)
-- Pure UI Template: Giao diện thuần túy, phát sự kiện callback để bạn tự nối logic
-- ==========================================

local refreshRingCounts = StatusUI.RefreshRingCounts
local craftingContainer = Instance.new("Frame")
craftingContainer.Name = "CraftingContainer"
craftingContainer.Size = UDim2.new(1, 0, 1, 0)
craftingContainer.BackgroundTransparency = 1
craftingContainer.Parent = craftingPage

-- 1. Grid 6 Thẻ Nhẫn (2 cột x 3 hàng)
local craftGrid = Instance.new("Frame")
craftGrid.Name = "CraftingGrid"
craftGrid.Position = UDim2.new(0, 0, 0, 28)
craftGrid.Size = UDim2.new(1, 0, 1, -28)
craftGrid.BackgroundTransparency = 1
craftGrid.Parent = craftingContainer

local craftGridLayout = Instance.new("UIGridLayout")
craftGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
craftGridLayout.CellSize = UDim2.new(0.491, 0, 0.32, 0)
craftGridLayout.CellPadding = UDim2.new(0.018, 0, 0.02, 0)
craftGridLayout.Parent = craftGrid

local craftMessage = Instance.new("TextLabel")
craftMessage.Name = "CraftingStatus"
craftMessage.Position = UDim2.fromOffset(1, 0)
craftMessage.Size = UDim2.new(1, -2, 0, 23)
craftMessage.BackgroundTransparency = 1
craftMessage.Text = "Waiting for ring inventory..."
applyModernFont(craftMessage, Enum.FontWeight.Medium)
craftMessage.TextSize = 11
craftMessage.TextColor3 = Color3.fromRGB(185, 205, 235)
craftMessage.TextXAlignment = Enum.TextXAlignment.Left
craftMessage.TextTruncate = Enum.TextTruncate.AtEnd
craftMessage.Parent = craftingContainer

local ringCraftCards = {}
local ringAutoCraft = {}
local ringAutoPaused, ringAutoAvailable = {}, {}

for _, ring in ipairs(RING_CATALOG) do
    ringAutoCraft[ring.Name] = false
end

-- Cập nhật giao diện nút Auto-Craft
local function updateAutoButtonsUI()
    for _, ring in ipairs(RING_CATALOG) do
        local isEnabled = ringAutoCraft[ring.Name] == true
        local cardData = ringCraftCards[ring.Name]
        if cardData and cardData.AutoBtn then
            cardData.AutoBtn.BackgroundColor3 = Color3.fromRGB(30, 40, 60)
            cardData.AutoBtn.BackgroundTransparency = 0.35
            if cardData.AutoStroke then
                cardData.AutoStroke.Color = Color3.fromRGB(85, 110, 155)
                cardData.AutoStroke.Transparency = 0.5
            end

            local available = ringAutoAvailable[ring.Name] == true
            cardData.AutoBtn.Active = available
            pcall(function() cardData.AutoBtn.Interactable = available end)
            if isEnabled then
                local paused = ringAutoPaused[ring.Name] == true
                cardData.AutoBtn.Text = paused and "PAUSED" or "AUTO: ON"
                cardData.AutoBtn.TextColor3 = paused and Color3.fromRGB(255, 195, 85) or Color3.fromRGB(100, 245, 165)
                cardData.AutoStroke.Color = cardData.AutoBtn.TextColor3
                cardData.AutoStroke.Transparency = 0.3
            else
                cardData.AutoBtn.Text = "AUTO: OFF"
                cardData.AutoBtn.TextColor3 = Color3.fromRGB(165, 180, 205)
            end
        end
    end
end

-- Hàm cập nhật số lượng & tiến trình của từng bước nâng cấp (để bạn tùy ý gọi)
local function setCraftStep(ringName, fromGrade, currentCount, maxCount)
    local cardData = ringCraftCards[ringName]
    if not cardData then return end
    local stepUi = cardData.StepsState[fromGrade]
    if not stepUi then return end

    local cur = currentCount or 0
    local maxVal = maxCount or 3
    stepUi.Count.Text = string.format("%d/%d", cur, maxVal)
    local fillRatio = math.clamp(cur / maxVal, 0, 1)
    stepUi.Fill.Size = UDim2.new(fillRatio, 0, 1, 0)

    if cur >= maxVal then
        stepUi.Button.AutoButtonColor = true
        stepUi.Button.BackgroundColor3 = (fromGrade == 3) and Color3.fromRGB(255, 65, 80) or Color3.fromRGB(245, 170, 35)
        stepUi.Button.BackgroundTransparency = 0.1
        stepUi.Button.TextColor3 = (fromGrade == 3) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(20, 24, 36)
        stepUi.Button.Text = (fromGrade == 3) and "FUSE IV" or "FUSE"
        stepUi.Stroke.Transparency = 0.2
        stepUi.Stroke.Color = (fromGrade == 3) and Color3.fromRGB(255, 130, 145) or Color3.fromRGB(255, 220, 90)
    else
        stepUi.Button.AutoButtonColor = false
        stepUi.Button.BackgroundColor3 = Color3.fromRGB(42, 54, 76)
        stepUi.Button.BackgroundTransparency = 0.35
        stepUi.Button.TextColor3 = Color3.fromRGB(165, 185, 215)
        stepUi.Button.Text = "FUSE"
        stepUi.Stroke.Transparency = 0.55
        stepUi.Stroke.Color = Color3.fromRGB(85, 110, 155)
    end
end

-- Hàm cập nhật số lượng nhẫn T4 cho thẻ
local function setRingT4Count(ringName, count)
    local cardData = ringCraftCards[ringName]
    if not cardData then return end
    local c = count or 0
    cardData.T4Badge.Text = string.format("T4: %d", c)
    if c > 0 then
        cardData.T4Badge.TextColor3 = Color3.fromRGB(255, 105, 120)
        if cardData.T4Stroke then
            cardData.T4Stroke.Color = Color3.fromRGB(255, 130, 145)
            cardData.T4Stroke.Transparency = 0.3
        end
    else
        cardData.T4Badge.TextColor3 = Color3.fromRGB(185, 205, 235)
        if cardData.T4Stroke then
            cardData.T4Stroke.Color = Color3.fromRGB(85, 110, 155)
            cardData.T4Stroke.Transparency = 0.5
        end
    end
end

-- Hàm cập nhật trạng thái Auto cho nhẫn
local function setRingAutoState(ringName, isAuto)
    ringAutoCraft[ringName] = isAuto and true or false
    updateAutoButtonsUI()
end

-- Tạo 6 thẻ cho 6 loại nhẫn
for ringOrder, ring in ipairs(RING_CATALOG) do
    local card = Instance.new("Frame")
    card.Name = "CraftCard_" .. ring.ShortName
    card.BackgroundColor3 = Color3.fromRGB(44, 55, 80)
    card.BackgroundTransparency = 0.35
    card.BorderSizePixel = 0
    card.LayoutOrder = ringOrder
    card.Parent = craftGrid

    local cCorner = Instance.new("UICorner")
    cCorner.CornerRadius = UDim.new(0, 8)
    cCorner.Parent = card

    local cStroke = Instance.new("UIStroke")
    cStroke.Color = Color3.fromRGB(105, 135, 185)
    cStroke.Transparency = 0.5
    cStroke.Thickness = 1
    cStroke.Parent = card

    local cardGrad = Instance.new("UIGradient")
    cardGrad.Rotation = 45
    cardGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.0, Color3.fromRGB(72, 92, 132)),
        ColorSequenceKeypoint.new(1.0, Color3.fromRGB(36, 46, 68)),
    })
    cardGrad.Parent = card

    -- Header (Icon + Name + T4 Pill)
    local cardHeader = Instance.new("Frame")
    cardHeader.Name = "Header"
    cardHeader.Position = UDim2.new(0, 8, 0, 5)
    cardHeader.Size = UDim2.new(1, -16, 0, 22)
    cardHeader.BackgroundTransparency = 1
    cardHeader.Parent = card

    local iconImg = Instance.new("ImageLabel")
    iconImg.Name = "Icon"
    iconImg.Size = UDim2.new(0, 20, 0, 20)
    iconImg.Position = UDim2.new(0, 0, 0.5, -10)
    iconImg.BackgroundTransparency = 1
    iconImg.ScaleType = Enum.ScaleType.Fit
    local spr = RING_SPRITES[ring.Name] and RING_SPRITES[ring.Name][3]
    if spr then
        iconImg.Image = spr.Image
        iconImg.ImageRectOffset = spr.Offset
        iconImg.ImageRectSize = spr.Size
    end
    iconImg.Parent = cardHeader

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "Name"
    nameLabel.Position = UDim2.new(0, 26, 0, 0)
    nameLabel.Size = UDim2.new(1, -152, 1, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = ring.ShortName
    applyModernFont(nameLabel, Enum.FontWeight.Bold)
    nameLabel.TextSize = 13
    nameLabel.TextColor3 = Color3.fromRGB(245, 250, 255)
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextYAlignment = Enum.TextYAlignment.Center
    nameLabel.Parent = cardHeader

    -- T4 Pill Frame & Badge (Góc phải ngoài cùng)
    local t4BadgeFrame = Instance.new("Frame")
    t4BadgeFrame.Name = "T4Pill"
    t4BadgeFrame.AnchorPoint = Vector2.new(1, 0.5)
    t4BadgeFrame.Position = UDim2.new(1, 0, 0.5, 0)
    t4BadgeFrame.Size = UDim2.new(0, 54, 0, 18)
    t4BadgeFrame.BackgroundColor3 = Color3.fromRGB(30, 40, 60)
    t4BadgeFrame.BackgroundTransparency = 0.35
    t4BadgeFrame.BorderSizePixel = 0
    t4BadgeFrame.Parent = cardHeader

    local t4Corner = Instance.new("UICorner")
    t4Corner.CornerRadius = UDim.new(0, 4)
    t4Corner.Parent = t4BadgeFrame

    local t4Stroke = Instance.new("UIStroke")
    t4Stroke.Color = Color3.fromRGB(85, 110, 155)
    t4Stroke.Transparency = 0.5
    t4Stroke.Thickness = 1
    t4Stroke.Parent = t4BadgeFrame

    local t4Badge = Instance.new("TextLabel")
    t4Badge.Name = "T4Badge"
    t4Badge.Size = UDim2.new(1, 0, 1, 0)
    t4Badge.BackgroundTransparency = 1
    t4Badge.Text = "T4: 0"
    applyModernFont(t4Badge, Enum.FontWeight.Bold)
    t4Badge.TextSize = 10.5
    t4Badge.TextColor3 = Color3.fromRGB(185, 205, 235)
    t4Badge.TextXAlignment = Enum.TextXAlignment.Center
    t4Badge.TextYAlignment = Enum.TextYAlignment.Center
    t4Badge.Parent = t4BadgeFrame

    -- Nút Auto-Craft riêng cho từng nhẫn (nằm cạnh T4 Pill)
    local ringAutoBtn = Instance.new("TextButton")
    ringAutoBtn.Name = "RingAutoBtn"
    ringAutoBtn.AnchorPoint = Vector2.new(1, 0.5)
    ringAutoBtn.Position = UDim2.new(1, -58, 0.5, 0)
    ringAutoBtn.Size = UDim2.new(0, 64, 0, 18)
    ringAutoBtn.BackgroundColor3 = Color3.fromRGB(30, 40, 60)
    ringAutoBtn.BackgroundTransparency = 0.35
    ringAutoBtn.BorderSizePixel = 0
    ringAutoBtn.AutoButtonColor = false
    ringAutoBtn.Text = "AUTO: OFF"
    applyModernFont(ringAutoBtn, Enum.FontWeight.Bold)
    ringAutoBtn.TextSize = 9.5
    ringAutoBtn.TextColor3 = Color3.fromRGB(165, 180, 205)
    ringAutoBtn.Parent = cardHeader

    local rAutoCorner = Instance.new("UICorner")
    rAutoCorner.CornerRadius = UDim.new(0, 4)
    rAutoCorner.Parent = ringAutoBtn

    local rAutoStroke = Instance.new("UIStroke")
    rAutoStroke.Color = Color3.fromRGB(85, 110, 155)
    rAutoStroke.Transparency = 0.5
    rAutoStroke.Thickness = 1
    rAutoStroke.Parent = ringAutoBtn

    ringAutoBtn.Activated:Connect(function()
        if not ringAutoAvailable[ring.Name] then return end
        ringAutoCraft[ring.Name] = not ringAutoCraft[ring.Name]
        updateAutoButtonsUI()
        if StatusUI and StatusUI.OnAutoToggle then
            pcall(StatusUI.OnAutoToggle, ring.Name, ringAutoCraft[ring.Name])
        end
    end)

    -- Container chứa 3 Hàng nâng cấp tự co giãn lấp đầy thẻ
    local rowsContainer = Instance.new("Frame")
    rowsContainer.Name = "RowsContainer"
    rowsContainer.Position = UDim2.new(0, 8, 0, 30)
    rowsContainer.Size = UDim2.new(1, -16, 1, -36)
    rowsContainer.BackgroundTransparency = 1
    rowsContainer.Parent = card

    local rowsLayout = Instance.new("UIListLayout")
    rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rowsLayout.Padding = UDim.new(0, 4)
    rowsLayout.FillDirection = Enum.FillDirection.Vertical
    rowsLayout.Parent = rowsContainer

    -- 3 Hàng nâng cấp: Tier 1->2, Tier 2->3, Tier 3->4
    local tierSteps = {
        { From = 1, To = 2, Text = "I → II", Color = Color3.fromRGB(65, 215, 50) },
        { From = 2, To = 3, Text = "II → III", Color = Color3.fromRGB(45, 160, 255) },
        { From = 3, To = 4, Text = "III → IV", Color = Color3.fromRGB(255, 175, 40) },
    }

    local cardStepsState = {}

    for stepIdx, step in ipairs(tierSteps) do
        local row = Instance.new("Frame")
        row.Name = "StepRow_" .. step.From
        row.Size = UDim2.new(1, 0, 0.31, 0)
        row.BackgroundColor3 = Color3.fromRGB(34, 44, 66)
        row.BackgroundTransparency = 0.35
        row.BorderSizePixel = 0
        row.LayoutOrder = stepIdx
        row.Parent = rowsContainer

        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 5)
        rowCorner.Parent = row

        local rowStroke = Instance.new("UIStroke")
        rowStroke.Color = Color3.fromRGB(75, 98, 140)
        rowStroke.Transparency = 0.55
        rowStroke.Thickness = 1
        rowStroke.Parent = row

        local stepTag = Instance.new("TextLabel")
        stepTag.Name = "Tag"
        stepTag.AnchorPoint = Vector2.new(0, 0.5)
        stepTag.Position = UDim2.new(0, 8, 0.5, 0)
        stepTag.Size = UDim2.new(0, 52, 0.85, 0)
        stepTag.BackgroundTransparency = 1
        stepTag.Text = step.Text
        applyModernFont(stepTag, Enum.FontWeight.Bold)
        stepTag.TextSize = 12.5
        stepTag.TextColor3 = step.Color
        stepTag.TextXAlignment = Enum.TextXAlignment.Left
        stepTag.TextYAlignment = Enum.TextYAlignment.Center
        stepTag.Parent = row

        -- Track
        local track = Instance.new("Frame")
        track.Name = "Track"
        track.AnchorPoint = Vector2.new(0, 0.5)
        track.Position = UDim2.new(0, 62, 0.5, 0)
        track.Size = UDim2.new(1, -164, 0, 8)
        track.BackgroundColor3 = Color3.fromRGB(22, 28, 42)
        track.BackgroundTransparency = 0.35
        track.BorderSizePixel = 0
        track.ClipsDescendants = true
        track.Parent = row

        local trackCorner = Instance.new("UICorner")
        trackCorner.CornerRadius = UDim.new(1, 0)
        trackCorner.Parent = track

        local fill = Instance.new("Frame")
        fill.Name = "Fill"
        fill.Size = UDim2.new(0, 0, 1, 0)
        fill.BackgroundColor3 = step.Color
        fill.BorderSizePixel = 0
        fill.Parent = track

        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(1, 0)
        fillCorner.Parent = fill

        local countLbl = Instance.new("TextLabel")
        countLbl.Name = "Count"
        countLbl.AnchorPoint = Vector2.new(1, 0.5)
        countLbl.Position = UDim2.new(1, -64, 0.5, 0)
        countLbl.Size = UDim2.new(0, 36, 0.85, 0)
        countLbl.BackgroundTransparency = 1
        countLbl.Text = "0/3"
        applyModernFont(countLbl, Enum.FontWeight.Bold)
        countLbl.TextSize = 11.5
        countLbl.TextColor3 = Color3.fromRGB(235, 242, 255)
        countLbl.TextXAlignment = Enum.TextXAlignment.Center
        countLbl.TextYAlignment = Enum.TextYAlignment.Center
        countLbl.Parent = row

        -- Button Fuse
        local fuseBtn = Instance.new("TextButton")
        fuseBtn.Name = "FuseBtn"
        fuseBtn.AnchorPoint = Vector2.new(1, 0.5)
        fuseBtn.Position = UDim2.new(1, -6, 0.5, 0)
        fuseBtn.Size = UDim2.new(0, 54, 0, 22)
        fuseBtn.BackgroundColor3 = Color3.fromRGB(42, 54, 76)
        fuseBtn.BackgroundTransparency = 0.35
        fuseBtn.BorderSizePixel = 0
        fuseBtn.AutoButtonColor = false
        fuseBtn.Text = "FUSE"
        applyModernFont(fuseBtn, Enum.FontWeight.Bold)
        fuseBtn.TextSize = 11
        fuseBtn.TextColor3 = Color3.fromRGB(165, 185, 215)
        fuseBtn.Parent = row

        local fCorner = Instance.new("UICorner")
        fCorner.CornerRadius = UDim.new(0, 4)
        fCorner.Parent = fuseBtn

        local fStroke = Instance.new("UIStroke")
        fStroke.Color = Color3.fromRGB(85, 110, 155)
        fStroke.Transparency = 0.55
        fStroke.Thickness = 1
        fStroke.Parent = fuseBtn

        cardStepsState[step.From] = {
            Fill    = fill,
            Count   = countLbl,
            Button  = fuseBtn,
            Stroke  = fStroke,
            StepDef = step,
        }

        fuseBtn.Activated:Connect(function()
        if not cardStepsState[step.From].Enabled then return end
            if StatusUI and StatusUI.OnFuseClick then
                pcall(StatusUI.OnFuseClick, ring.Name, step.From)
            end
        end)
    end

    ringCraftCards[ring.Name] = {
        Card       = card,
        T4Badge    = t4Badge,
        T4Stroke   = t4Stroke,
        AutoBtn    = ringAutoBtn,
        AutoStroke = rAutoStroke,
        StepsState = cardStepsState,
    }
end

-- Callback khi chuyển tab sang Crafting Rings
onTabSwitchedCallbacks["Crafting Rings"] = function()
    updateAutoButtonsUI()
end

-- Chạy cập nhật ban đầu
refreshRingCounts()
updateAutoButtonsUI()

    StatusUI.SetCraftButtonState = function(name, grade, enabled, label, pending)
        local step = ringCraftCards[name].StepsState[grade]
        step.Enabled = enabled == true
        step.Button.Active = step.Enabled
        step.Button.Selectable = step.Enabled
        pcall(function() step.Button.Interactable = step.Enabled end)
        step.Button.Text = label or "FUSE"
        if not step.Enabled then
            step.Button.AutoButtonColor = false
            step.Button.BackgroundColor3 = Color3.fromRGB(42, 54, 76)
            step.Button.BackgroundTransparency = 0.35
            step.Button.TextColor3 = pending and Color3.fromRGB(110, 205, 255) or Color3.fromRGB(145, 163, 190)
            step.Stroke.Color = Color3.fromRGB(85, 110, 155)
            step.Stroke.Transparency = 0.55
        end
    end
    StatusUI.SetCraftAutoState = function(name, selected, paused, available)
        ringAutoCraft[name], ringAutoPaused[name], ringAutoAvailable[name] = selected, paused, available
        updateAutoButtonsUI()
    end
    StatusUI.SetCraftingMessage = function(message, severity)
        craftMessage.Text = message
        craftMessage.TextColor3 = severity == "warning" and Color3.fromRGB(255, 195, 85)
            or (severity == "success" and Color3.fromRGB(100, 235, 160) or Color3.fromRGB(185, 205, 235))
    end
    StatusUI.CraftingStatusLabel = craftMessage
    StatusUI.RingCraftCards      = ringCraftCards
    StatusUI.RingAutoCraft       = ringAutoCraft
    StatusUI.SetCraftStep        = setCraftStep
    StatusUI.SetRingT4Count      = setRingT4Count
    StatusUI.SetRingAutoState    = setRingAutoState
    StatusUI.UpdateAutoButtonsUI = updateAutoButtonsUI
end)()

-- ==========================================
-- [NOI DUNG TAB WEBHOOK]
-- ==========================================
;(function()
local mainSettings = StatusUI.MainSettings
local webhookSettings = {
    Url               = "",
    Enabled           = false,
    PingMode          = "None", -- "None", "@everyone", "User"
    PingUserId        = "",
    NotifyClearFloor  = true,
    NotifyRingDrop    = true,
    NotifyDeath       = true,
}

local webhookContainer = Instance.new("Frame")
webhookContainer.Name = "WebhookContainer"
webhookContainer.Size = UDim2.new(1, 0, 1, 0)
webhookContainer.BackgroundTransparency = 1
webhookContainer.Parent = webhookPage

local webhookScroll = Instance.new("ScrollingFrame")
webhookScroll.Name = "WebhookScroll"
webhookScroll.Size = UDim2.new(1, 0, 1, 0)
webhookScroll.BackgroundTransparency = 1
webhookScroll.BorderSizePixel = 0
webhookScroll.ScrollBarThickness = 3
webhookScroll.ScrollBarImageColor3 = Color3.fromRGB(115, 145, 195)
webhookScroll.ScrollBarImageTransparency = 0.35
webhookScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
webhookScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
webhookScroll.ClipsDescendants = true
webhookScroll.Parent = webhookContainer

local whListLayout = Instance.new("UIListLayout")
whListLayout.SortOrder = Enum.SortOrder.LayoutOrder
whListLayout.Padding = UDim.new(0, 8)
whListLayout.Parent = webhookScroll

local whPadding = Instance.new("UIPadding")
whPadding.PaddingTop = UDim.new(0, 2)
whPadding.PaddingBottom = UDim.new(0, 8)
whPadding.PaddingLeft = UDim.new(0, 2)
whPadding.PaddingRight = UDim.new(0, 6)
whPadding.Parent = webhookScroll

local function createWebhookCard(name, titleText, height, order)
    local card = Instance.new("Frame")
    card.Name = "Card_" .. name
    card.Size = UDim2.new(1, -4, 0, height)
    card.BackgroundColor3 = Color3.fromRGB(44, 55, 80)
    card.BackgroundTransparency = 0.35
    card.BorderSizePixel = 0
    card.LayoutOrder = order
    card.Parent = webhookScroll

    local cCorner = Instance.new("UICorner")
    cCorner.CornerRadius = UDim.new(0, 8)
    cCorner.Parent = card

    local cStroke = Instance.new("UIStroke")
    cStroke.Color = Color3.fromRGB(105, 135, 185)
    cStroke.Transparency = 0.5
    cStroke.Thickness = 1
    cStroke.Parent = card

    local cGrad = Instance.new("UIGradient")
    cGrad.Rotation = 45
    cGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.0, Color3.fromRGB(72, 92, 132)),
        ColorSequenceKeypoint.new(1.0, Color3.fromRGB(36, 46, 68)),
    })
    cGrad.Parent = card

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Name = "Title"
    titleLbl.Position = UDim2.new(0, 10, 0, 6)
    titleLbl.Size = UDim2.new(1, -20, 0, 14)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = string.upper(titleText)
    applyModernFont(titleLbl, Enum.FontWeight.Bold)
    titleLbl.TextSize = 10
    titleLbl.TextColor3 = Color3.fromRGB(175, 190, 220)
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Parent = card

    return card
end

-- 1. CARD URL CONFIGURATION
local urlCard = createWebhookCard("UrlConfig", "PERSONAL DISCORD WEBHOOK URL", 102, 1)

local urlInputBox = Instance.new("TextBox")
urlInputBox.Name = "UrlInput"
urlInputBox.Position = UDim2.new(0, 10, 0, 26)
urlInputBox.Size = UDim2.new(1, -20, 0, 30)
urlInputBox.BackgroundColor3 = Color3.fromRGB(26, 34, 50)
urlInputBox.BackgroundTransparency = 0.35
urlInputBox.BorderSizePixel = 0
urlInputBox.ClearTextOnFocus = false
urlInputBox.Text = webhookSettings.Url
urlInputBox.PlaceholderText = "Paste Discord Webhook URL (https://discord.com/api/webhooks/...)"
urlInputBox.PlaceholderColor3 = Color3.fromRGB(135, 150, 175)
applyModernFont(urlInputBox, Enum.FontWeight.Medium)
urlInputBox.TextSize = 11
urlInputBox.TextColor3 = Color3.fromRGB(245, 250, 255)
urlInputBox.TextXAlignment = Enum.TextXAlignment.Left
urlInputBox.Parent = urlCard

local uibCorner = Instance.new("UICorner")
uibCorner.CornerRadius = UDim.new(0, 5)
uibCorner.Parent = urlInputBox

local uibStroke = Instance.new("UIStroke")
uibStroke.Color = Color3.fromRGB(85, 110, 155)
uibStroke.Transparency = 0.55
uibStroke.Thickness = 1
uibStroke.Parent = urlInputBox

local uibPadding = Instance.new("UIPadding")
uibPadding.PaddingLeft = UDim.new(0, 8)
uibPadding.PaddingRight = UDim.new(0, 8)
uibPadding.Parent = urlInputBox

local urlActionsRow = Instance.new("Frame")
urlActionsRow.Name = "UrlActions"
urlActionsRow.Position = UDim2.new(0, 10, 0, 64)
urlActionsRow.Size = UDim2.new(1, -20, 0, 28)
urlActionsRow.BackgroundTransparency = 1
urlActionsRow.Parent = urlCard

local function createSubButton(name, text, width, pos)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Position = pos
    btn.Size = UDim2.new(0, width, 1, 0)
    btn.BackgroundColor3 = Color3.fromRGB(32, 42, 62)
    btn.BackgroundTransparency = 0.35
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Text = text
    applyModernFont(btn, Enum.FontWeight.Bold)
    btn.TextSize = 10.5
    btn.TextColor3 = Color3.fromRGB(220, 235, 255)
    btn.Parent = urlActionsRow

    local bCorner = Instance.new("UICorner")
    bCorner.CornerRadius = UDim.new(0, 5)
    bCorner.Parent = btn

    local bStroke = Instance.new("UIStroke")
    bStroke.Color = Color3.fromRGB(85, 110, 155)
    bStroke.Transparency = 0.55
    bStroke.Thickness = 1
    bStroke.Parent = btn

    btn.MouseEnter:Connect(function()
        btn.BackgroundTransparency = 0.2
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    end)
    btn.MouseLeave:Connect(function()
        btn.BackgroundTransparency = 0.35
        btn.TextColor3 = Color3.fromRGB(220, 235, 255)
    end)

    return btn, bStroke
end

local testBtn, testStroke = createSubButton("TestBtn", "SEND TEST", 100, UDim2.new(0, 0, 0, 0))
local pasteBtn = createSubButton("PasteBtn", "PASTE", 70, UDim2.new(0, 108, 0, 0))
local clearBtn = createSubButton("ClearBtn", "CLEAR", 65, UDim2.new(0, 186, 0, 0))

local statusLbl = Instance.new("TextLabel")
statusLbl.Name = "StatusLabel"
statusLbl.AnchorPoint = Vector2.new(1, 0.5)
statusLbl.Position = UDim2.new(1, -4, 0.5, 0)
statusLbl.Size = UDim2.new(1, -260, 1, 0)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "Status: Ready"
applyModernFont(statusLbl, Enum.FontWeight.Medium)
statusLbl.TextSize = 10
statusLbl.TextColor3 = Color3.fromRGB(155, 175, 205)
statusLbl.TextTruncate = Enum.TextTruncate.AtEnd
statusLbl.TextXAlignment = Enum.TextXAlignment.Right
statusLbl.Parent = urlActionsRow

urlInputBox.FocusLost:Connect(function()
    webhookSettings.Url = urlInputBox.Text
    if StatusUI and StatusUI.OnWebhookSettingChanged then
        pcall(StatusUI.OnWebhookSettingChanged, "Url", webhookSettings.Url)
    end
end)

pasteBtn.MouseButton1Click:Connect(function()
    local clip = nil
    if typeof(getclipboard) == "function" then
        pcall(function() clip = getclipboard() end)
    end
    if clip and type(clip) == "string" and #clip > 0 then
        urlInputBox.Text = clip
        webhookSettings.Url = clip
        statusLbl.Text = "Status: Pasted from clipboard"
        statusLbl.TextColor3 = Color3.fromRGB(130, 210, 255)
        if StatusUI and StatusUI.OnWebhookSettingChanged then
            pcall(StatusUI.OnWebhookSettingChanged, "Url", clip)
        end
    else
        statusLbl.Text = "Status: Clipboard empty or unsupported"
    end
end)

clearBtn.MouseButton1Click:Connect(function()
    urlInputBox.Text = ""
    webhookSettings.Url = ""
    statusLbl.Text = "Status: Cleared"
    statusLbl.TextColor3 = Color3.fromRGB(155, 175, 205)
    if StatusUI and StatusUI.OnWebhookSettingChanged then
        pcall(StatusUI.OnWebhookSettingChanged, "Url", "")
    end
end)

-- 2. CARD NOTIFICATION TRIGGERS
local triggersCard = createWebhookCard("Triggers", "NOTIFICATION TRIGGERS", 152, 2)

local triggersLayout = Instance.new("UIListLayout")
triggersLayout.SortOrder = Enum.SortOrder.LayoutOrder
triggersLayout.Padding = UDim.new(0, 5)
triggersLayout.Parent = triggersCard

local trPadding = Instance.new("UIPadding")
trPadding.PaddingTop = UDim.new(0, 24)
trPadding.PaddingLeft = UDim.new(0, 10)
trPadding.PaddingRight = UDim.new(0, 10)
trPadding.Parent = triggersCard

local function createTriggerRow(key, title, subtitle, order)
    local row = Instance.new("Frame")
    row.Name = "Row_" .. key
    row.Size = UDim2.new(1, 0, 0, 26)
    row.BackgroundColor3 = Color3.fromRGB(28, 36, 52)
    row.BackgroundTransparency = 0.5
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.Parent = triggersCard

    local rCorner = Instance.new("UICorner")
    rCorner.CornerRadius = UDim.new(0, 4)
    rCorner.Parent = row

    local tLabel = Instance.new("TextLabel")
    tLabel.Name = "Label"
    tLabel.Position = UDim2.new(0, 8, 0, 0)
    tLabel.Size = UDim2.new(1, -85, 1, 0)
    tLabel.BackgroundTransparency = 1
    tLabel.Text = title .. (subtitle and ("  (" .. subtitle .. ")") or "")
    applyModernFont(tLabel, Enum.FontWeight.SemiBold)
    tLabel.TextSize = 10.5
    tLabel.TextColor3 = Color3.fromRGB(215, 230, 250)
    tLabel.TextXAlignment = Enum.TextXAlignment.Left
    tLabel.Parent = row

    local tBtn = Instance.new("TextButton")
    tBtn.Name = "ToggleBtn"
    tBtn.AnchorPoint = Vector2.new(1, 0.5)
    tBtn.Position = UDim2.new(1, -4, 0.5, 0)
    tBtn.Size = UDim2.new(0, 65, 0, 20)
    tBtn.BackgroundColor3 = Color3.fromRGB(34, 46, 68)
    tBtn.BackgroundTransparency = 0.35
    tBtn.BorderSizePixel = 0
    tBtn.AutoButtonColor = false
    tBtn.Text = webhookSettings[key] and "ON" or "OFF"
    applyModernFont(tBtn, Enum.FontWeight.Bold)
    tBtn.TextSize = 10
    tBtn.TextColor3 = webhookSettings[key] and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(160, 175, 200)
    tBtn.Parent = row

    local tbCorner = Instance.new("UICorner")
    tbCorner.CornerRadius = UDim.new(0, 4)
    tbCorner.Parent = tBtn

    local tbStroke = Instance.new("UIStroke")
    tbStroke.Color = webhookSettings[key] and Color3.fromRGB(115, 145, 195) or Color3.fromRGB(75, 95, 135)
    tbStroke.Transparency = webhookSettings[key] and 0.4 or 0.65
    tbStroke.Thickness = 1
    tbStroke.Parent = tBtn

    local function updateRowVisual()
        local val = webhookSettings[key] == true
        tBtn.Text = val and "ON" or "OFF"
        tBtn.TextColor3 = val and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(160, 175, 200)
        tBtn.BackgroundColor3 = val and Color3.fromRGB(48, 64, 94) or Color3.fromRGB(30, 40, 60)
        tbStroke.Color = val and Color3.fromRGB(120, 155, 215) or Color3.fromRGB(75, 95, 135)
        tbStroke.Transparency = val and 0.35 or 0.65
    end

    tBtn.MouseButton1Click:Connect(function()
        webhookSettings[key] = not webhookSettings[key]
        updateRowVisual()
        if StatusUI and StatusUI.OnWebhookSettingChanged then
            pcall(StatusUI.OnWebhookSettingChanged, key, webhookSettings[key])
        end
    end)

    return updateRowVisual
end

local updateEnableToggle = createTriggerRow("Enabled", "ENABLE PERSONAL WEBHOOK", "Personal only", 1)
local updateFloorToggle  = createTriggerRow("NotifyClearFloor", "NOTIFY DUNGEON CLEAR", "Per floor", 2)
local updateRingToggle   = createTriggerRow("NotifyRingDrop", "NOTIFY RING DROP / CRAFT", "T1-T4", 3)
local updateDeathToggle  = createTriggerRow("NotifyDeath", "NOTIFY PLAYER DEATH", "Low HP / Respawn", 4)

-- 3. CARD MENTION & PING SETTINGS
local pingCard = createWebhookCard("PingSettings", "DISCORD MENTION & PING", 68, 3)

local pingUserIdBox = Instance.new("TextBox")
pingUserIdBox.Name = "PingUserId"
pingUserIdBox.Position = UDim2.new(0, 10, 0, 26)
pingUserIdBox.Size = UDim2.new(0.65, -12, 0, 30)
pingUserIdBox.BackgroundColor3 = Color3.fromRGB(26, 34, 50)
pingUserIdBox.BackgroundTransparency = 0.35
pingUserIdBox.BorderSizePixel = 0
pingUserIdBox.ClearTextOnFocus = false
pingUserIdBox.Text = webhookSettings.PingUserId
pingUserIdBox.PlaceholderText = "Discord User ID (Optional)"
pingUserIdBox.PlaceholderColor3 = Color3.fromRGB(135, 150, 175)
applyModernFont(pingUserIdBox, Enum.FontWeight.Medium)
pingUserIdBox.TextSize = 11
pingUserIdBox.TextColor3 = Color3.fromRGB(245, 250, 255)
pingUserIdBox.TextXAlignment = Enum.TextXAlignment.Left
pingUserIdBox.Parent = pingCard

local pubCorner = Instance.new("UICorner")
pubCorner.CornerRadius = UDim.new(0, 5)
pubCorner.Parent = pingUserIdBox

local pubStroke = Instance.new("UIStroke")
pubStroke.Color = Color3.fromRGB(85, 110, 155)
pubStroke.Transparency = 0.55
pubStroke.Thickness = 1
pubStroke.Parent = pingUserIdBox

local pubPad = Instance.new("UIPadding")
pubPad.PaddingLeft = UDim.new(0, 8)
pubPad.Parent = pingUserIdBox

pingUserIdBox.FocusLost:Connect(function()
    webhookSettings.PingUserId = pingUserIdBox.Text
    if StatusUI and StatusUI.OnWebhookSettingChanged then
        pcall(StatusUI.OnWebhookSettingChanged, "PingUserId", webhookSettings.PingUserId)
    end
end)

local pingModeBtn = Instance.new("TextButton")
pingModeBtn.Name = "PingModeBtn"
pingModeBtn.Position = UDim2.new(0.65, 2, 0, 26)
pingModeBtn.Size = UDim2.new(0.35, -12, 0, 30)
pingModeBtn.BackgroundColor3 = Color3.fromRGB(32, 42, 62)
pingModeBtn.BackgroundTransparency = 0.35
pingModeBtn.BorderSizePixel = 0
pingModeBtn.AutoButtonColor = false
applyModernFont(pingModeBtn, Enum.FontWeight.Bold)
pingModeBtn.TextSize = 10.5
pingModeBtn.TextColor3 = Color3.fromRGB(220, 235, 255)
pingModeBtn.Parent = pingCard

local pmbCorner = Instance.new("UICorner")
pmbCorner.CornerRadius = UDim.new(0, 5)
pmbCorner.Parent = pingModeBtn

local pmbStroke = Instance.new("UIStroke")
pmbStroke.Color = Color3.fromRGB(85, 110, 155)
pmbStroke.Transparency = 0.55
pmbStroke.Thickness = 1
pmbStroke.Parent = pingModeBtn

local function updatePingModeText()
    if webhookSettings.PingMode == "@everyone" then
        pingModeBtn.Text = "PING: @EVERYONE"
    elseif webhookSettings.PingMode == "User" then
        pingModeBtn.Text = "PING: USER ID"
    else
        pingModeBtn.Text = "PING: NONE"
    end
end
updatePingModeText()

pingModeBtn.MouseButton1Click:Connect(function()
    if webhookSettings.PingMode == "None" then
        webhookSettings.PingMode = "User"
    elseif webhookSettings.PingMode == "User" then
        webhookSettings.PingMode = "@everyone"
    else
        webhookSettings.PingMode = "None"
    end
    updatePingModeText()
    if StatusUI and StatusUI.OnWebhookSettingChanged then
        pcall(StatusUI.OnWebhookSettingChanged, "PingMode", webhookSettings.PingMode)
    end
end)

-- Ring notifications and SEND TEST share one delivery controller.
testBtn.MouseButton1Click:Connect(function()
    StatusUI.SetWebhookUrl(urlInputBox.Text)
    if StatusUI.OnWebhookTestClick then
        pcall(StatusUI.OnWebhookTestClick)
    else StatusUI.SetWebhookStatus("Webhook is loading...") end
end)

local function setWebhookUrl(url)
    webhookSettings.Url = tostring(url or "")
    urlInputBox.Text = webhookSettings.Url
    if StatusUI and StatusUI.OnWebhookSettingChanged then
        pcall(StatusUI.OnWebhookSettingChanged, "Url", webhookSettings.Url)
    end
end

local function setWebhookEnabled(val)
    webhookSettings.Enabled = (val == true)
    updateEnableToggle()
    if StatusUI and StatusUI.OnWebhookSettingChanged then
        pcall(StatusUI.OnWebhookSettingChanged, "Enabled", webhookSettings.Enabled)
    end
end

local publicCard = createWebhookCard("PublicWebhookNotice", "PUBLIC RING FEED (FIXED)", 100, 4)
local publicNotice=Instance.new("TextLabel")
publicNotice.Name="PublicFeedReadOnly"
publicNotice.Position=UDim2.fromOffset(10,24)
publicNotice.Size=UDim2.new(1,-20,0,40)
publicNotice.BackgroundTransparency=1
publicNotice.Text="Always on - player names show only the first 1/3.\nPersonal settings do not change the public feed."
publicNotice.TextWrapped=true
publicNotice.TextXAlignment=Enum.TextXAlignment.Left
publicNotice.TextColor3=Color3.fromRGB(170,185,210)
publicNotice.TextSize=10
publicNotice.Parent=publicCard
local publicStatus=Instance.new("TextLabel")
publicStatus.Name="PublicWebhookStatus"
publicStatus.Position=UDim2.fromOffset(10,68)
publicStatus.Size=UDim2.new(1,-20,0,20)
publicStatus.BackgroundTransparency=1
publicStatus.Text="Public: Ready (read only)"
publicStatus.TextXAlignment=Enum.TextXAlignment.Left
publicStatus.TextColor3=Color3.fromRGB(190,175,230)
publicStatus.TextSize=10
publicStatus.Parent=publicCard
StatusUI.SetPublicWebhookStatus=function(text)publicStatus.Text="Public: "..tostring(text)end

    StatusUI.WebhookSettings   = webhookSettings
    StatusUI.SetWebhookUrl     = setWebhookUrl
    StatusUI.SetWebhookEnabled = setWebhookEnabled
    StatusUI.SetWebhookStatus = function(text)
        statusLbl.Text = "Status: " .. tostring(text)
        statusLbl.TextColor3 = tostring(text):find("Sent", 1, true) and Color3.fromRGB(120,240,160)
            or Color3.fromRGB(180,200,230)
    end
    StatusUI.ApplyWebhookSettings = function(values)
        for key,value in pairs(values) do
            if type(webhookSettings[key])==type(value) then webhookSettings[key]=value end
        end
        urlInputBox.Text=webhookSettings.Url
        pingUserIdBox.Text=webhookSettings.PingUserId
        updateEnableToggle();updateFloorToggle();updateRingToggle();updateDeathToggle();updatePingModeText()
    end
end)()

-- ==========================================
-- [BẢNG BIẾN STATUS & API THUẦN UI]
-- Cung cấp đầy đủ UI Elements, Setters & Callback Hooks
-- Không chứa logic game hay network phụ thuộc
-- ==========================================
StatusUI.ScreenGui              = screenGui
StatusUI.MainFrame              = mainFrame
StatusUI.TitleLabel             = titleLabel
StatusUI.AvatarImage            = avatarImage
StatusUI.UsernameLabel          = usernameLabel

-- Quản lý Tab & Page
StatusUI.Pages                  = pages
StatusUI.Tabs                   = tabs
StatusUI.StatusPage             = statusPage
StatusUI.RingsPage              = ringsPage
StatusUI.CraftingPage           = craftingPage
StatusUI.MainPage               = mainPage
StatusUI.WebhookPage            = webhookPage
StatusUI.SwitchTab              = switchTab

-- Tab Main Setters phụ
StatusUI.SetAltAccounts         = function() end
StatusUI.OnStartClick           = nil -- function(isStarted)
StatusUI.OnMainSettingChanged   = nil -- function(settingName, value)

-- Tab Webhook Callbacks
StatusUI.OnWebhookTestClick     = nil -- function(url)
StatusUI.OnWebhookSettingChanged = nil -- function(settingName, value)

-- Dọn dẹp UI
StatusUI.Destroy = function()
    if screenGui then
        screenGui:Destroy()
    end
end

-- Callback Slots (Bạn gán function của bạn vào đây để nhận sự kiện từ UI)
StatusUI.OnStartClick            = nil -- function(isStarted)
StatusUI.OnWebhookTestClick       = nil -- function(url)
StatusUI.OnWebhookSettingChanged  = nil -- function(settingName, value)
StatusUI.OnFuseClick             = nil -- function(ringName, fromGrade)
StatusUI.OnAutoToggle            = nil -- function(ringName, isAuto)
StatusUI.OnBuffClick             = nil -- function(buffId, currentLevel)
StatusUI.OnTabChanged            = nil -- function(tabName)

pcall(function()
    if typeof(getgenv) == "function" and getgenv() then
        getgenv().DungeonUI = StatusUI
        getgenv().StatusUI = StatusUI
    end
    if _G then
        _G.DungeonUI = StatusUI
        _G.StatusUI = StatusUI
    end
end)

-- Live inventory binding for the Rings page only.
;(function()
    local RingModule = (function()
-- Dungeon ring inventory and fusion adapter. Verified client paths: 2026-10-17.
-- Data comes from ItemReplicationService. Construction does not fuse anything.
local Rings = {}
Rings.UIOrder = {
    "Ring of Might", "Ring of Spirit", "Ring of Twin Blades",
    "Ring of the Outlaw", "Ring of Steelheart", "Ring of the Arcanist",
}

local function freeze(value)
    if type(value) == "table" and not table.isfrozen(value) then
        for _, child in pairs(value) do freeze(child) end
        table.freeze(value)
    end
    return value
end

local function disconnect(connection)
    if type(connection) == "function" then connection()
    elseif connection then connection:Disconnect() end
end

local function inGameContext(callback)
    local getIdentity = getthreadidentity or getidentity
    local setIdentity = setthreadidentity or setidentity
    local previous = getIdentity and getIdentity()
    if previous and setIdentity then setIdentity(2) end
    local result = table.pack(pcall(callback))
    if previous and setIdentity then setIdentity(previous) end
    if not result[1] then error(result[2], 2) end
    return table.unpack(result, 2, result.n)
end

-- Reading readiness must never require game modules: an early failed require
-- stays cached and can prevent the game's HUD/backpack from mounting.
function Rings.CheckGameReady(player, rs, loaded)
    if not loaded or not player or player:GetAttribute("LoadComplete") ~= true then
        return false, "waiting-for-game-load"
    end
    local economy = rs:FindFirstChild("Economy")
    if not economy or not economy:FindFirstChild("ItemId") then return false, "waiting-for-item-dependencies" end
    for _, name in ipairs({"AccessoriesShared", "ItemReplicationService", "ItemConfig"}) do
        if not rs:FindFirstChild(name) then return false, "waiting-for-item-dependencies" end
    end
    local gui = player:FindFirstChild("PlayerGui")
    local hud = gui and gui:FindFirstChild("HUDRoot")
    if not hud or not hud:IsA("ScreenGui") then return false, "waiting-for-native-hud" end
    for _, child in ipairs(hud:GetChildren()) do
        if child:IsA("GuiObject") then return true end
    end
    return false, "waiting-for-native-hud"
end

local function gameDependencies()
    return inGameContext(function()
        local rs = game:GetService("ReplicatedStorage")
        local player = game:GetService("Players").LocalPlayer
        local ready, reason = Rings.CheckGameReady(player, rs, game:IsLoaded())
        assert(ready, reason)
        local shared = require(rs.AccessoriesShared)
        local service = require(rs.ItemReplicationService)
        local keys = service.KEYS
        local config = require(rs.ItemConfig)
        local current = shared.GetAllTrinkets()
        local catalog = {}
        for _, name in ipairs(shared.GetAllTrinketNames()) do
            local tiers = {}
            for grade = 1, 4 do
                local id = shared.getItemId(name, grade)
                local itemConfig = id and config.tryGet(id)
                local sprite = itemConfig and itemConfig.Display.Sprite
                tiers[grade] = {
                    ItemId = id, Rarity = shared.GetItemRarity(name, grade),
                    Suffix = shared.GetGradeSuffix(grade),
                    Sprite = sprite and {
                        Image = sprite.Image, ImageRectOffset = sprite.ImageRectOffset,
                        ImageRectSize = sprite.ImageRectSize,
                    } or nil,
                }
            end
            catalog[name] = {Name = name, IsCurrent = current[name] ~= nil, Tiers = tiers}
        end
        local watched = {}
        for _, key in ipairs({keys.ACCESSORY_TYPE, keys.ACCESSORY_GRADE,
            keys.ACCESSORY_MODIFIERS, keys.IS_EQUIPPED, keys.IS_FAVORITED}) do
            watched[key] = true
        end
        local remote = assert(rs.Remotes:FindFirstChild("AccessoryInteract"), "AccessoryInteract missing")
        return {
            Catalog = catalog,
            Read = function()
                return inGameContext(function()
                local rows, incomplete = {}, 0
                for _, entry in pairs(service:GetItems(keys.ACCESSORY_TYPE)) do
                    if entry.Value == "Trinket" then
                        local uid = entry.NetworkedUID
                        local item = uid and shared.getReplicatedAccessoryItem(entry.ItemId, uid)
                        if item then
                            rows[#rows + 1] = {
                                UID = uid, ItemId = entry.ItemId, Name = item.Name,
                                Grade = item.Grade, Equipped = item.Equipped,
                                Modifiers = table.clone(item.Modifiers),
                                Favorited = service:ReadItem(keys.IS_FAVORITED, entry.ItemId, uid) == true,
                            }
                        else incomplete += 1 end
                    end
                end
                return rows, service.IsInitialized and player:GetAttribute("LoadComplete") == true
                    and incomplete == 0
                end)
            end,
            Connect = function(callback)
                return inGameContext(function()
                local a = service:ConnectOnChanged(function(key)
                    if watched[key] then callback() end
                end)
                local b = player:GetAttributeChangedSignal("LoadComplete"):Connect(callback)
                return function() disconnect(a); disconnect(b) end
                end)
            end,
            Merge = function(ids)
                return inGameContext(function()
                    return remote:InvokeServer("a", ids[1], ids[2], ids[3])
                end)
            end,
            Now = os.clock, Wait = task.wait, Spawn = task.spawn,
            Defer = task.defer, Cancel = task.cancel,
        }
    end)
end

-- Pure aggregation, also usable by an independent UI data source.
function Rings.BuildSnapshot(rows, catalog, protected, ready)
    local state = {Ready = ready == true, ByName = {}, ByUID = {}, Total = 0,
        AvailableFusions = 0, CurrentAvailableFusions = 0}
    for name, definition in pairs(catalog) do
        local group = {Name = name, IsCurrent = definition.IsCurrent, Tiers = {}}
        for grade = 1, 4 do
            group.Tiers[grade] = {
                Count = 0, EligibleCount = 0, EquippedCount = 0, FavoritedCount = 0,
                EligibleUIDs = {}, FusionCount = 0, Definition = definition.Tiers[grade],
            }
        end
        state.ByName[name] = group
    end
    for _, row in pairs(rows) do
        local group = state.ByName[row.Name]
        local tier = group and group.Tiers[row.Grade]
        if type(row.UID) == "string" and tier and not state.ByUID[row.UID] then
            local item = table.clone(row)
            item.Modifiers = table.clone(row.Modifiers or {})
            state.ByUID[item.UID] = item
            state.Total += 1
            tier.Count += 1
            if item.Equipped then tier.EquippedCount += 1 end
            if item.Favorited then tier.FavoritedCount += 1 end
            if not item.Equipped and not item.Favorited and not protected[item.UID] then
                tier.EligibleCount += 1
                tier.EligibleUIDs[#tier.EligibleUIDs + 1] = item.UID
            end
        end
    end
    for _, group in pairs(state.ByName) do
        for grade, tier in ipairs(group.Tiers) do
            table.sort(tier.EligibleUIDs, function(a, b)
                local aa, bb = state.ByUID[a], state.ByUID[b]
                if #aa.Modifiers ~= #bb.Modifiers then return #aa.Modifiers < #bb.Modifiers end
                return a < b
            end)
            tier.FusionCount = ready and grade < 4 and math.floor(tier.EligibleCount / 3) or 0
            state.AvailableFusions += tier.FusionCount
            if group.IsCurrent then state.CurrentAvailableFusions += tier.FusionCount end
        end
    end
    return freeze(state)
end

local Controller = {}
Controller.__index = Controller

function Rings.new(options)
    options = options or {}
    local deps = options.Dependencies or gameDependencies()
    local self = setmetatable({
        _deps = deps, _alive = true, _listeners = {}, _protected = {},
        _autoTypes = {}, _autoEnabled = false, _nextRequest = 0,
        _interval = math.max(0.3, options.RequestInterval or 0.8),
        _timeout = math.max(1, options.Timeout or 12),
        Status = "idle", LastResult = nil,
    }, Controller)
    self:Refresh()
    self._disconnect = deps.Connect(function() self:_scheduleRefresh() end)
    return self
end

function Controller:_notify()
    for listener in pairs(self._listeners) do
        local ok, err = pcall(listener, self._snapshot, self.Status, self.LastResult)
        if not ok then warn("[DungeonRings] UI callback: " .. tostring(err)) end
    end
end

function Controller:_scheduleRefresh()
    if not self._alive or self._refreshQueued then return end
    self._refreshQueued = true
    self._deps.Defer(function()
        self._refreshQueued = false
        if self._alive then self:Refresh() end
    end)
end

function Controller:Refresh()
    if not self._alive then return self._snapshot end
    local ok, rows, ready = pcall(self._deps.Read)
    if not ok then
        self.Status = "inventory-error"
        self.LastResult = {OK = false, Code = "inventory-error", Detail = tostring(rows)}
        rows, ready = {}, false
    elseif ready and self.Status == "inventory-error" then
        self.Status, self.LastResult = "idle", nil
    end
    self._snapshot = Rings.BuildSnapshot(rows, self._deps.Catalog, self._protected, ready)
    if self._pending and self._pending.TimedOut then self:_settle(self._pending) end
    self:_notify()
    self:_kickAuto()
    return self._snapshot
end

function Controller:GetSnapshot() return self._snapshot end

function Controller:Subscribe(callback)
    assert(self._alive, "controller destroyed")
    self._listeners[callback] = true
    local ok, err = pcall(callback, self._snapshot, self.Status, self.LastResult)
    if not ok then self._listeners[callback] = nil; error(err, 2) end
    return function() self._listeners[callback] = nil end
end

function Controller:SetProtected(uid, enabled)
    self._protected[uid] = enabled == true or nil
    self:Refresh()
end

function Controller:IsBusy()
    return self._pending ~= nil or self._batch == true or self._starting == true
end

function Controller:_settle(pending)
    if not pending.Done then return nil end
    local state = self._snapshot
    local consumed = true
    for _, uid in ipairs(pending.UIDs) do
        if state.ByUID[uid] then consumed = false end
    end
    local nextTier = state.ByName[pending.Name].Tiers[pending.Grade + 1]
    local inventoryConfirmed = state.Ready and consumed and nextTier.Count > pending.BeforeCount
    if pending.CallOK and pending.Accepted == false then
        self.LastResult = {OK = false, Code = "server-rejected", Detail = pending.Payload}
        self.Status = "server-rejected"
    elseif inventoryConfirmed then
        self.LastResult = {OK = true, Code = "confirmed", Name = pending.Name,
            FromGrade = pending.Grade, ToGrade = pending.Grade + 1,
            ServerAccepted = pending.CallOK and pending.Accepted == true, Response = pending.Payload}
        self.Status = "idle"
    else return nil end
    self._pending = nil
    return self.LastResult
end

-- This yields: bind GUI buttons with task.spawn, not a render-frame callback.
function Controller:CraftOnce(name, grade, fromBatch)
    if not self._alive then return false, "destroyed" end
    if self._pending or self._starting or (self._batch and not fromBatch) then return false, "busy" end
    if grade ~= 1 and grade ~= 2 and grade ~= 3 then return false, "invalid-grade" end
    if self._deps.Now() < self._nextRequest then return false, "rate-limited" end
    self._starting = true
    local state = self:Refresh()
    if not self._alive then self._starting = false; return false, "destroyed" end
    local tier = state.ByName[name] and state.ByName[name].Tiers[grade]
    if not tier then self._starting = false; return false, "unknown-ring" end
    if not state.Ready then self._starting = false; return false, "inventory-not-ready" end
    if tier.EligibleCount < 3 then self._starting = false; return false, "not-enough-rings" end
    local ids = {tier.EligibleUIDs[1], tier.EligibleUIDs[2], tier.EligibleUIDs[3]}
    local pending = {Name = name, Grade = grade, UIDs = ids,
        BeforeCount = state.ByName[name].Tiers[grade + 1].Count}
    self._pending = pending
    self._starting = false
    self.Status = "crafting"
    self._nextRequest = self._deps.Now() + self._interval
    self:_notify()
    if not self._alive then self._pending = nil; return false, "destroyed" end
    local invoke = self._deps.Merge
    local defer = self._deps.Defer
    local weakOwner = setmetatable({self}, {__mode = "v"})
    pending.Thread = self._deps.Spawn(function()
        local result = table.pack(pcall(invoke, ids))
        pending.CallOK, pending.Accepted, pending.Payload = result[1], result[2], result[3]
        pending.Done = true
        defer(function()
            local owner = weakOwner[1]
            if owner and owner._alive and pending.TimedOut then owner:Refresh() end
        end)
    end)
    local deadline = self._deps.Now() + self._timeout
    while self._alive do
        self:Refresh()
        local result = self:_settle(pending)
        if result then self:_notify(); return result.OK, result.Code end
        if self._deps.Now() >= deadline then
            pending.TimedOut = true
            self._autoEnabled = false
            self.Status = "uncertain"
            self.LastResult = {OK = false, Code = "awaiting-confirmation",
                RPCFinished = pending.Done == true, RPCError = not pending.CallOK and pending.Accepted or nil}
            self:_notify()
            -- Keep the UID reservation. A timeout is not proof the server rejected the merge.
            return false, "awaiting-confirmation"
        end
        self._deps.Wait(0.1)
    end
    return false, "destroyed"
end

function Controller:_findNext(selected)
    for _, name in ipairs(Rings.UIOrder) do
        local group = self._snapshot.ByName[name]
        if group and (not selected or selected[name]) then
            for grade = 1, 3 do
                if group.Tiers[grade].FusionCount > 0 then return name, grade end
            end
        end
    end
end

function Controller:_waitRate()
    local delay = self._nextRequest - self._deps.Now()
    if delay > 0 then self._deps.Wait(delay) end
end

-- CraftAll includes upgrades unlocked by earlier merges in this batch.
function Controller:CraftAll(selectedTypes)
    if not self._alive then return false, "destroyed", 0 end
    if self:IsBusy() or self._autoRunning then return false, "busy", 0 end
    self._batch = true
    local count, code = 0, "complete"
    while self._alive do
        self:Refresh()
        local name, grade = self:_findNext(selectedTypes)
        if not name then break end
        self:_waitRate()
        if not self._alive then break end
        local ok, result = self:CraftOnce(name, grade, true)
        if not ok then code = result; break end
        count += 1
    end
    self._batch = false
    if not self._alive then code = "destroyed" end
    self:_notify()
    self:_kickAuto()
    return code == "complete", code, count
end

function Controller:_kickAuto()
    if not self._alive or not self._autoEnabled or self._autoRunning or self:IsBusy() then return end
    self._autoRunning = true
    self._autoThread = self._deps.Spawn(function()
        while self._alive and self._autoEnabled and not self:IsBusy() do
            local name, grade = self:_findNext(self._autoTypes)
            if not name then break end
            self:_waitRate()
            if not self._alive or not self._autoEnabled or not self._autoTypes[name] then break end
            local ok, code = self:CraftOnce(name, grade)
            if not ok then
                self._autoEnabled = false
                self.Status = code
                self:_notify()
                break
            end
        end
        self._autoRunning = false
    end)
end

function Controller:SetAutoEnabled(enabled)
    self._autoEnabled = enabled == true
    self:_notify()
    self:_kickAuto()
end

function Controller:SetAutoType(name, enabled)
    assert(self._deps.Catalog[name] and self._deps.Catalog[name].IsCurrent, "unknown current ring")
    self._autoTypes[name] = enabled == true
    if enabled then self._autoEnabled = true end
    self:_notify()
    self:_kickAuto()
end

function Controller:SetAllAuto(enabled)
    for _, name in ipairs(Rings.UIOrder) do self._autoTypes[name] = enabled == true end
    self:SetAutoEnabled(enabled)
end

function Controller:GetAutoState()
    return {Enabled = self._autoEnabled, Types = table.clone(self._autoTypes)}
end

function Controller:GetCraftState()
    local pending = self._pending
    return {
        Alive = self._alive, Busy = self:IsBusy(), Status = self.Status,
        CanRequest = self._alive and not self:IsBusy() and not self._autoRunning
            and self._deps.Now() >= self._nextRequest,
        RingName = pending and pending.Name, FromGrade = pending and pending.Grade,
        AwaitingConfirmation = pending ~= nil and pending.TimedOut == true,
        LastResult = self.LastResult,
    }
end

function Controller:Destroy()
    if not self._alive then return end
    self._alive, self._autoEnabled = false, false
    disconnect(self._disconnect)
    self._disconnect = nil
    table.clear(self._listeners)
    -- Already-sent server actions cannot be undone by disabling/destroying the UI.
    if self._pending and self._pending.Thread and self._deps.Cancel then
        pcall(self._deps.Cancel, self._pending.Thread)
    end
    if self._autoThread and self._deps.Cancel and self._autoThread ~= coroutine.running() then
        pcall(self._deps.Cancel, self._autoThread)
    end
    self._autoThread = nil
end

return Rings

    end)()
    local RingUI = (function()
-- Read-only UI binding. The supplied DungeonRings controller starts with auto off.
local RingsUI = {}
local Binding = {}
Binding.__index = Binding

local function atUIIdentity(identity, callback)
    local getIdentity = getthreadidentity or getidentity
    local setIdentity = setthreadidentity or setidentity
    local previous = getIdentity and getIdentity()
    if setIdentity and identity then setIdentity(identity) end
    local result = table.pack(pcall(callback))
    if previous and setIdentity then setIdentity(previous) end
    if not result[1] then error(result[2], 2) end
    return table.unpack(result, 2, result.n)
end

function RingsUI.Render(ui, snapshot, order)
    ui.RingInventoryReady = snapshot ~= nil and snapshot.Ready == true
    for grade = 1, 4 do
        local counts = ui.InventoryCounts[grade]
        for _, name in ipairs(order) do
            local group = snapshot and snapshot.ByName[name]
            local tier = group and group.Tiers[grade]
            counts[name] = tier and tier.Count or 0
            ui.EquippedMap[name .. "_" .. tostring(grade)] = tier ~= nil
                and tier.EquippedCount > 0
        end
    end
    ui.RefreshRingCounts()
end

function Binding:Refresh()
    if not self._alive then return nil end
    if self.Controller then return self.Controller:Refresh() end
    return nil
end

function Binding:GetSnapshot()
    return self.Controller and self.Controller:GetSnapshot() or nil
end

function Binding:Destroy()
    if not self._alive then return end
    self._alive = false
    if self._unsubscribe then self._unsubscribe(); self._unsubscribe = nil end
    if self._guiConnection then self._guiConnection:Disconnect(); self._guiConnection = nil end
    if self.Controller then self.Controller:Destroy(); self.Controller = nil end
    if self._thread and self._thread ~= coroutine.running() then
        pcall(self._cancel, self._thread)
    end
    self._thread = nil
    if self._ui and self._ui.LiveRings == self then self._ui.LiveRings = nil end
    self._ui = nil
end

function RingsUI.Bind(ui, ringModule, options)
    options = options or {}
    if ui.LiveRings then ui.LiveRings:Destroy() end
    local self = setmetatable({
        _alive = true, _ui = ui, _cancel = options.Cancel or task.cancel,
        _identity = (getthreadidentity or getidentity or function() return nil end)(),
        State = "loading", LastError = nil,
    }, Binding)
    ui.LiveRings = self
    RingsUI.Render(ui, nil, ringModule.UIOrder)
    self._guiConnection = ui.ScreenGui.Destroying:Connect(function() self:Destroy() end)
    local spawn = options.Spawn or task.defer
    local wait = options.Wait or task.wait
    self._thread = spawn(function()
        while self._alive do
            local ok, controller = pcall(ringModule.new, options.ControllerOptions)
            if not self._alive then
                if ok then controller:Destroy() end
                return
            end
            if ok then
                self.Controller = controller
                self._unsubscribe = controller:Subscribe(function(snapshot)
                    if not self._alive then return end
                    self.State = snapshot.Ready and "ready" or "loading"
                    self.LastError = controller.LastResult and controller.LastResult.Detail or nil
                    atUIIdentity(self._identity, function()
                        RingsUI.Render(ui, snapshot, ringModule.UIOrder)
                    end)
                end)
                -- Close the initial read/subscribe window without issuing an RPC.
                controller:Refresh()
                while self._alive do
                    wait(2)
                    if self._alive then controller:Refresh() end
                end
                return
            end
            self.State, self.LastError = "waiting-for-inventory", tostring(controller)
            wait(2)
        end
    end)
    return self
end

return RingsUI

    end)()
    screenGui:SetAttribute("UIRepairVersion", "rings-inventory-2026-10-17")
    StatusUI.IsGameReady = function()
        return RingModule.CheckGameReady(Players.LocalPlayer, game:GetService("ReplicatedStorage"), game:IsLoaded())
    end
    RingUI.Bind(StatusUI, RingModule)
end)()

-- Black circular Trash Hub launcher with curved badge lettering.
;(function()
    local Toggle = (function()
-- A circular launcher that remains visible while the main window is hidden.
local Toggle = {}

local function decodeBase64(encoded)
    local codec = crypt and crypt.base64
    if codec and type(codec.decode) == "function" then
        local ok, decoded = pcall(codec.decode, encoded)
        if ok and type(decoded) == "string" then return decoded end
    end
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local values, output = {}, {}
    for i = 1, #alphabet do values[string.byte(alphabet, i)] = i - 1 end
    for i = 1, #encoded, 4 do
        local a, b, c, d = string.byte(encoded, i, i + 3)
        local value = assert(values[a]) * 262144 + assert(values[b]) * 4096
            + (values[c] or 0) * 64 + (values[d] or 0)
        local first = math.floor(value / 65536)
        local second = math.floor(value / 256) % 256
        local third = value % 256
        output[#output + 1] = d ~= 61 and string.char(first, second, third)
            or (c ~= 61 and string.char(first, second) or string.char(first))
    end
    return table.concat(output)
end

function Toggle.Attach(ui, options)
    options = options or {}
    if ui.ToggleController then ui.ToggleController:Destroy() end
    local alive, connections, loader = true, {}, nil
    local savedVisible, savedToggle = ui.SetVisible, ui.ToggleVisible
    local gui, window = ui.ScreenGui, ui.MainFrame

    local button = Instance.new("ImageButton")
    button.Name = "TrashHubUIToggle"
    button.Size = UDim2.fromOffset(72, 72)
    button.Position = options.Position or UDim2.fromOffset(40, 148)
    button.BackgroundColor3 = Color3.fromRGB(10, 8, 17)
    button.BackgroundTransparency = 0.05
    button.BorderSizePixel = 0
    button.AutoButtonColor = true
    button.ClipsDescendants = true
    button.Image = ""
    button.ZIndex = 50
    button.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = button
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 0, 0)
    stroke.Thickness = 2
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = button

    local fallback = Instance.new("TextLabel")
    fallback.Name = "FallbackMonogram"
    fallback.Size = UDim2.fromScale(1, 1)
    fallback.BackgroundTransparency = 1
    fallback.Text = "TH"
    fallback.Font = Enum.Font.GothamBold
    fallback.TextSize = 25
    fallback.TextColor3 = Color3.fromRGB(193, 155, 255)
    fallback.ZIndex = 51
    fallback.Parent = button

    local logo = Instance.new("ImageLabel")
    logo.Name = "TrashHubLogo"
    logo.Position = UDim2.fromOffset(0, 0)
    logo.Size = UDim2.fromScale(1, 1)
    logo.BackgroundTransparency = 1
    logo.Image = ""
    -- The circular badge includes the curved lettering; display the entire image.
    logo.ImageRectOffset = Vector2.zero
    logo.ImageRectSize = Vector2.zero
    logo.ScaleType = Enum.ScaleType.Fit
    logo.ZIndex = 52
    logo.Parent = button

    local controller = {Button = button, Logo = logo, State = "loading"}
    local function updateAppearance()
        if not alive then return end
        button:SetAttribute("WindowVisible", window.Visible)
        stroke.Transparency = 0
    end
    local function setVisible(visible)
        if alive then window.Visible = visible == true; updateAppearance() end
    end
    local function toggleVisible()
        if alive then setVisible(not window.Visible) end
    end
    local function updateLogo()
        if not alive then return end
        fallback.Visible = not logo.IsLoaded
    end

    connections[#connections + 1] = button.Activated:Connect(toggleVisible)
    connections[#connections + 1] = window:GetPropertyChangedSignal("Visible"):Connect(updateAppearance)
    connections[#connections + 1] = logo:GetPropertyChangedSignal("IsLoaded"):Connect(updateLogo)

    function controller:Destroy()
        if not alive then return end
        alive = false
        for _, connection in ipairs(connections) do connection:Disconnect() end
        table.clear(connections)
        if loader and loader ~= coroutine.running() then pcall(task.cancel, loader) end
        loader = nil
        if ui.SetVisible == setVisible then ui.SetVisible = savedVisible end
        if ui.ToggleVisible == toggleVisible then ui.ToggleVisible = savedToggle end
        if ui.ToggleController == self then ui.ToggleController = nil; ui.ToggleButton = nil end
        self.State = "destroyed"
        button:Destroy()
    end
    connections[#connections + 1] = gui.Destroying:Connect(function() controller:Destroy() end)
    ui.ToggleButton, ui.ToggleController = button, controller
    ui.SetVisible, ui.ToggleVisible = setVisible, toggleVisible
    updateAppearance()

    -- The original PNG is embedded by the build script; no external image host is needed.
    loader = task.defer(function()
        local ok, result = pcall(function()
            local customAsset = getcustomasset or getsynasset
            assert(type(customAsset) == "function", "custom images unavailable")
            local path = options.LogoFile or "TrashHub_Logo_6aafc7d1.png"
            if not (type(isfile) == "function" and isfile(path)) then
                assert(type(writefile) == "function", "image file API unavailable")
                local bytes = decodeBase64(assert(options.LogoBase64, "logo data unavailable"))
                assert(bytes:sub(1, 8) == "\137PNG\r\n\26\n", "invalid logo data")
                if options.LogoBytes then assert(#bytes == options.LogoBytes, "incomplete logo data") end
                if not alive then return nil end
                writefile(path, bytes)
            end
            return customAsset(path)
        end)
        if not alive then return end
        if ok and type(result) == "string" then
            logo.Image = result
            updateLogo()
            controller.State = "ready"
        else
            controller.State, controller.LastError = "fallback", tostring(result)
        end
        loader = nil
    end)
    return controller
end

return Toggle

    end)()
    Toggle.Attach(StatusUI, {
        LogoFile = "TrashHub_Logo_128_323090e353ae.png",
        LogoBytes = 27449,
        LogoBase64 = [=[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]=],
    })
    screenGui:SetAttribute("UIToggleVersion", "trash-hub-black-circle-v2-2026-10-17")
end)()

screenGui:SetAttribute("RingReadabilityVersion", "compact-count-badges-v2")
-- Live crafting uses the existing Rings inventory controller.
;(function()
    local Crafting = (function()
-- Crafting controls share the inventory controller already owned by the Rings UI.
local Crafting = {}
Crafting.Order = {
    "Ring of Might", "Ring of Spirit", "Ring of Twin Blades",
    "Ring of the Outlaw", "Ring of Steelheart", "Ring of the Arcanist",
}
local messages = {
    ["not-enough-rings"] = "Need 3 matching rings. Equipped and favorites are kept.",
    ["inventory-not-ready"] = "Waiting for ring inventory...",
    ["busy"] = "Please wait for the current fusion or cooldown.",
    ["rate-limited"] = "Please wait before the next fusion.",
    ["server-rejected"] = "Fusion rejected by the game. Auto paused.",
    ["inventory-error"] = "Unable to read inventory. Waiting for an update...",
    ["awaiting-confirmation"] = "Waiting for inventory confirmation. Auto paused.",
    ["internal-error"] = "Fusion stopped. Check the executor console for the error.",
    ["invalid-grade"] = "Only tier I, II and III can be fused.",
    ["unknown-ring"] = "This ring type is unavailable.",
}

function Crafting.BuildView(snapshot, state, auto, manualBusy, manualCode)
    state, auto = state or {}, auto or {Types = {}}
    local ready = snapshot ~= nil and snapshot.Ready == true
    local view = {Ready = ready, Rings = {}, Message = "Uses 3 matching rings; equipped and favorites are kept.", Severity = "info"}
    local anyAuto = false
    for _, name in ipairs(Crafting.Order) do
        local group = snapshot and snapshot.ByName[name]
        local selected = auto.Types and auto.Types[name] == true
        local ring = {T4 = group and group.Tiers[4].Count or 0, Steps = {}, Auto = selected,
            Paused = selected and auto.Enabled ~= true, Available = state.Alive == true}
        anyAuto = anyAuto or (selected and auto.Enabled == true)
        for grade = 1, 3 do
            local tier = group and group.Tiers[grade]
            local count = tier and tier.EligibleCount or 0
            local pending = state.RingName == name and state.FromGrade == grade
            local enabled = ready and count >= 3 and state.CanRequest == true and not manualBusy
            local label = enabled and grade == 3 and "FUSE IV" or "FUSE"
            if pending then label = state.AwaitingConfirmation and "CHECK" or "FUSING" end
            ring.Steps[grade] = {Count = count, Enabled = enabled, Label = label, Pending = pending}
        end
        view.Rings[name] = ring
    end
    local result = state.LastResult
    if not ready then view.Message = "Waiting for ring inventory..."
    elseif state.AwaitingConfirmation then
        view.Message, view.Severity = messages["awaiting-confirmation"], "warning"
    elseif state.Busy or manualBusy then view.Message = "Fusing rings... Waiting for inventory confirmation."
    elseif manualCode and messages[manualCode] then
        view.Message, view.Severity = messages[manualCode], "warning"
    elseif result and not result.OK and messages[result.Code] then
        view.Message, view.Severity = messages[result.Code], "warning"
    elseif anyAuto then view.Message = "Auto enabled for selected ring types. Equipped and favorites are kept."
    elseif result and result.OK then view.Message, view.Severity = "Fusion confirmed. Ring inventory updated.", "success" end
    return view
end

local Binding = {}
Binding.__index = Binding
local function atIdentity(identity, callback)
    local getIdentity, setIdentity = getthreadidentity or getidentity, setthreadidentity or setidentity
    local previous = getIdentity and getIdentity()
    if setIdentity and identity then setIdentity(identity) end
    local result = table.pack(pcall(callback))
    if setIdentity and previous then setIdentity(previous) end
    if not result[1] then error(result[2], 2) end
    return table.unpack(result, 2, result.n)
end

function Binding:_render()
    if not self._alive then return end
    local controller = self._controller
    local state = controller and controller:GetCraftState() or {}
    local snapshot = controller and controller:GetSnapshot()
    local auto = controller and controller:GetAutoState() or {Types = {}}
    if self._errorUntil and self._now() >= self._errorUntil then self._manualCode = nil end
    local view = Crafting.BuildView(snapshot, state, auto, self._manualBusy, self._manualCode)
    local ui = self._ui
    atIdentity(self._identity, function()
        for _, name in ipairs(Crafting.Order) do
            local ring = view.Rings[name]
            ui.SetRingT4Count(name, ring.T4)
            if not view.Ready then ui.RingCraftCards[name].T4Badge.Text = "T4: --" end
            ui.SetCraftAutoState(name, ring.Auto, ring.Paused, ring.Available)
            for grade, step in ipairs(ring.Steps) do
                ui.SetCraftStep(name, grade, step.Count, 3)
                if not view.Ready then ui.RingCraftCards[name].StepsState[grade].Count.Text = "--/3" end
                ui.SetCraftButtonState(name, grade, step.Enabled, step.Label, step.Pending)
            end
        end
        ui.SetCraftingMessage(view.Message, view.Severity)
    end)
    self.State, self.LastView = view.Ready and "ready" or "loading", view
    self._canRequest = state.CanRequest
end

function Binding:_reject(code)
    self._manualCode, self._errorUntil = code, self._now() + 5
    self:_render()
    return false, code
end

function Binding:Fuse(name, grade)
    if not self._alive then return false, "destroyed" end
    if grade ~= 1 and grade ~= 2 and grade ~= 3 then return self:_reject("invalid-grade") end
    local controller = self._controller
    if not controller then return self:_reject("inventory-not-ready") end
    local snapshot = controller:GetSnapshot()
    if not snapshot or not snapshot.Ready then return self:_reject("inventory-not-ready") end
    local group = snapshot.ByName[name]
    if not group then return self:_reject("unknown-ring") end
    if self._manualBusy or not controller:GetCraftState().CanRequest then return self:_reject("busy") end
    if group.Tiers[grade].EligibleCount < 3 then return self:_reject("not-enough-rings") end
    self._manualCode, self._errorUntil, self._manualBusy = nil, nil, true
    self:_render()
    self._job = self._spawn(function()
        if not self._alive then return end
        local callOK, ok, code = pcall(controller.CraftOnce, controller, name, grade)
        self._job, self._manualBusy = nil, false
        if not self._alive then return end
        if not callOK then
            self.LastError = tostring(ok)
            warn("[DungeonCraftingUI] " .. self.LastError)
            self:_reject("internal-error")
        elseif not ok then self:_reject(code)
        else self._manualCode, self._errorUntil = nil, nil; self:_render() end
    end)
    return true, "queued"
end

function Binding:SetAuto(name, enabled)
    if not self._alive then return false, "destroyed" end
    if not self._controller then return self:_reject("inventory-not-ready") end
    local ok, err = pcall(self._controller.SetAutoType, self._controller, name, enabled == true)
    if not ok then self.LastError = tostring(err); return self:_reject("unknown-ring") end
    self._manualCode, self._errorUntil = nil, nil
    self:_render()
    return true
end

function Binding:Destroy()
    if not self._alive then return end
    self._alive = false
    if self._unsubscribe then self._unsubscribe(); self._unsubscribe = nil end
    if self._controller then self._controller:SetAutoEnabled(false) end
    if self._connection then self._connection:Disconnect(); self._connection = nil end
    for _, thread in pairs({self._thread, self._job}) do
        if thread ~= coroutine.running() then pcall(self._cancel, thread) end
    end
    local ui = self._ui
    if ui.OnFuseClick == self._onFuse then ui.OnFuseClick = self._oldFuse end
    if ui.OnAutoToggle == self._onAuto then ui.OnAutoToggle = self._oldAuto end
    if ui.LiveCrafting == self then ui.LiveCrafting = nil end
    self._controller, self._thread, self._job, self._ui = nil, nil, nil, nil
    self.State = "destroyed"
end

function Crafting.Bind(ui, options)
    options = options or {}
    if ui.LiveCrafting then ui.LiveCrafting:Destroy() end
    local self = setmetatable({_alive = true, _ui = ui, _now = options.Now or os.clock,
        _spawn = options.Spawn or task.defer, _cancel = options.Cancel or task.cancel,
        _identity = (getthreadidentity or getidentity or function() return nil end)(),
        _oldFuse = ui.OnFuseClick, _oldAuto = ui.OnAutoToggle}, Binding)
    self._onFuse = function(name, grade) return self:Fuse(name, grade) end
    self._onAuto = function(name, enabled) return self:SetAuto(name, enabled) end
    ui.OnFuseClick, ui.OnAutoToggle, ui.LiveCrafting = self._onFuse, self._onAuto, self
    self._connection = ui.ScreenGui.Destroying:Connect(function() self:Destroy() end)
    self:_render()
    local wait = options.Wait or task.wait
    self._thread = self._spawn(function()
        while self._alive do
            local controller = ui.LiveRings and ui.LiveRings.Controller
            if controller ~= self._controller then
                if self._unsubscribe then self._unsubscribe(); self._unsubscribe = nil end
                self._controller = controller
                if controller then self._unsubscribe = controller:Subscribe(function() self:_render() end)
                else self:_render() end
            elseif controller then
                local changed = self._canRequest ~= controller:GetCraftState().CanRequest
                if changed or (self._manualCode and self._errorUntil and self._now() >= self._errorUntil) then
                    self:_render()
                end
            end
            wait(0.25)
        end
    end)
    return self
end

return Crafting

    end)()
    Crafting.Bind(StatusUI)
    screenGui:SetAttribute("CraftingVersion", "shared-rings-controller-v1-2026-10-17")
end)()

;(function()
    local EnemyPolicy = (function()
-- Verified live: summoned shadows use model "Blank Buddy" and
-- Humanoid.DisplayName "<player>'s Shadow [Lv. ...]" inside Workspace.Enemies.
local Policy = {}

function Policy.IsSummon(name, displayName)
    if name == "Blank Buddy" then return true end
    local display = tostring(displayName or ""):gsub("<[^>]+>", "")
    return display:match("^.+'s Shadow%s*%[") ~= nil
        or display:match("^.+'s Shadow$") ~= nil
        or display:match("^.+’s Shadow%s*%[") ~= nil
end

function Policy.IsHostile(model, players, aliveOnly)
    if not model or not model.Parent or not model:IsA("Model") then return false end
    -- The game also puts temporary object hitboxes here; WorldPropCombat owns them.
    if model.Name == "PropHitboxPlaceholder" then return false end
    if players and players:GetPlayerFromCharacter(model) then return false end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid or Policy.IsSummon(model.Name, humanoid.DisplayName) then return false end
    if aliveOnly ~= false and humanoid.Health <= 0 then return false end
    return true
end

function Policy.List(folder, players, aliveOnly)
    local result = {}
    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            if Policy.IsHostile(model, players, aliveOnly) and model:FindFirstChild("HumanoidRootPart") then
                result[#result + 1] = model
            end
        end
    end
    return result
end

return Policy

    end)()
    local StatusModule = (function()
-- Read-only Status controller. Combat/START and the native HUD are independent.
local Module = {}
local Controller = {}; Controller.__index = Controller
local function finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end

function Module.Level(value, definition)
    if not finite(value) or value <= 0 then return 0 end
    local step = definition and definition.Step
    if not finite(step) or step <= 0 then return nil end
    -- The last upgrade can be capped to less than one full Step.
    return math.max(0, math.ceil(value / step - 0.000001))
end

function Module.FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    return string.format("%dmin %02ds", math.floor(seconds / 60), seconds % 60)
end

function Module.new(ui, deps)
    return setmetatable({UI = ui, Deps = deps, Alive = true, Buffs = {}, BuffKnown = false,
        Session = deps.Session, Levels = {}, Snapshot = {}}, Controller)
end

function Controller:AcceptBuffs(buffs)
    if not self.Alive or type(buffs) ~= "table" then return false end
    local copy = {}
    for id, value in pairs(buffs) do
        if type(id) ~= "string" or not finite(value) then return false end
        copy[id] = value
    end
    self.Buffs, self.BuffKnown = copy, true
    return true
end

function Controller:Step()
    if not self.Alive then return end
    local d, now = self.Deps.Read(), self.Deps.Now()
    if d.InDungeon then
        local session = self.Session
        if not session or session.JobId ~= d.JobId
            or (session.DungeonKey and d.DungeonKey and session.DungeonKey ~= d.DungeonKey) then
            session = {JobId = d.JobId, DungeonKey = d.DungeonKey, StartedAt = now}
            self.Session = session
            self.Buffs, self.BuffKnown = {}, false
        elseif d.DungeonKey then session.DungeonKey = d.DungeonKey end
        self.Deps.SaveSession(session)
    elseif self.Session then
        self.Session, self.Buffs, self.BuffKnown = nil, {}, false
        self.Deps.SaveSession(nil)
    end
    if d.InDungeon and d.Buffs then self:AcceptBuffs(d.Buffs) end
    local levels = {}
    for id in pairs(self.UI.BuffCardsState or {}) do
        levels[id] = not d.InDungeon and 0
            or (self.BuffKnown and Module.Level(self.Buffs[id] or 0, d.Definitions and d.Definitions[id]) or nil)
    end
    local total, dead, mobs, ratio, progress
    if finite(d.TotalEnemies) and finite(d.DeadEnemies) and d.TotalEnemies > 0
        and d.ActiveFloor == d.FloorId and not d.HasBoss then
        total = math.floor(d.TotalEnemies)
        dead = math.clamp(math.floor(d.DeadEnemies), 0, total)
        mobs, ratio = total - dead, dead / total
        progress = string.format("%d%% (%d / %d Mobs)", math.floor(ratio * 100 + 0.5), dead, total)
    elseif d.InDungeon and finite(d.LivingEnemies) then
        mobs = d.LivingEnemies
        if d.ExitReady then
            ratio, progress = 1, "100% (Cleared)"
        elseif finite(d.ObservedTotal) and d.ObservedTotal > 0 then
            total = math.max(d.ObservedTotal, mobs)
            dead = total - mobs
            ratio = dead / total
            progress = string.format("%d%% (%d / %d Mobs)", math.floor(ratio * 100 + 0.5), dead, total)
        else ratio, progress = 0, "Waiting for enemies..." end
    else ratio, progress = 0, d.InDungeon and "Waiting for room data..." or "Outside dungeon" end
    local elapsed = self.Session and (self.Session.Elapsed or math.max(0, now - self.Session.StartedAt)) or 0
    local state = {Floor = d.InDungeon and tostring(d.FloorId or "--") or "--",
        Time = Module.FormatTime(elapsed), Mobs = tostring(mobs or (d.InDungeon and "--" or 0)),
        Energy = finite(d.Energy) and string.format("%d/50", math.clamp(math.floor(d.Energy), 0, 50)) or "--/50",
        Progress = progress, Ratio = ratio, Levels = levels, BuffKnown = self.BuffKnown,
        Elapsed = elapsed, DungeonKey = d.DungeonKey, Error = d.Error}
    self.Levels, self.Snapshot = levels, state
    self.Deps.Paint(self.UI, state)
    return state
end

function Controller:Destroy()
    if not self.Alive then return end
    self.Alive = false
    if self.Connection then self.Connection:Disconnect() end
    if type(self.Unsubscribe) == "function" then self.Unsubscribe() end
    if self.Thread and self.Thread ~= coroutine.running() then pcall(self.Deps.Cancel, self.Thread) end
    if self.Deps.Destroy then self.Deps.Destroy() end
    if self.UI.LiveStatus == self then self.UI.LiveStatus = nil end
end

function Module.Bind(ui, deps)
    if ui.LiveStatus then ui.LiveStatus:Destroy() end
    local self = Module.new(ui, deps)
    ui.LiveStatus = self
    if deps.SubscribeBuffs then self.Unsubscribe = deps.SubscribeBuffs(function(b) self:AcceptBuffs(b) end) end
    self.Connection = ui.ScreenGui.Destroying:Connect(function() self:Destroy() end)
    self.Thread = deps.Spawn(function()
        while self.Alive do
            local ok, err = pcall(function() self:Step() end)
            if not ok then self.LastError = tostring(err) else self.LastError = nil end
            deps.Wait(0.5)
        end
    end)
    return self
end

return Module

    end)()
    local StatusAdapter = (function()
-- Verified sources: local Explorer.FloorId, Dungeon TotalEnemies/DeadEnemies,
-- BuffReplicator's raw bonus values, and ReplicatedPlayerData.CurrentEnergy.
local Module = {}
function Module.new(ui, EnemyPolicy)
    local Players, rs = game:GetService("Players"), game:GetService("ReplicatedStorage")
    local player = Players.LocalPlayer
    assert(player,"LocalPlayer is not ready; wait before binding Status")
    local alive, definitions, playerData, energy, lastInit = true, nil, nil, nil, -math.huge
    local job, energyConnection, buffConnection, buffRemote, onBuffs, lastReadError
    local buffs, buffKnown, lastSnapshotTry = nil, false, -math.huge
    local boundsFloor, boundsFrame, boundsSize, seen = nil, nil, nil, {}
    local identity = (getthreadidentity or getidentity or function() return nil end)()
    local function context(level, fn)
        local getter, setter = getthreadidentity or getidentity, setthreadidentity or setidentity
        local previous = getter and getter()
        if setter and level then setter(level) end
        local result = table.pack(pcall(fn))
        if setter and previous then setter(previous) end
        if not result[1] then error(result[2], 2) end
        return table.unpack(result, 2, result.n)
    end
    local function beginInit()
        if job or (definitions and playerData) or os.clock() - lastInit < 5 then return end
        if ui.IsGameReady and not ui.IsGameReady() then return end
        local client, shared = rs:FindFirstChild("DungeonClient"), rs:FindFirstChild("DungeonShared")
        local dataScript = client and client:FindFirstChild("ReplicatedPlayerData")
        local buffScript = shared and shared:FindFirstChild("ExplorerBuffs")
        if not dataScript or not buffScript then return end
        lastInit = os.clock()
        local current = {Started = lastInit}; job = current
        current.Thread = task.defer(function()
            local ok, err = pcall(function()
                local defs, data, value = context(2, function()
                    local a = require(buffScript).ExplorerBuffs
                    local b = require(dataScript)
                    return a, b, b.get()
                end)
                if not alive or job ~= current then return end
                definitions, playerData = defs, data
                energy = type(value) == "table" and value.CurrentEnergy or nil
                if data.OnUpdated then
                    energyConnection = data.OnUpdated:Connect(function()
                        if not alive then return end
                        local success, updated = pcall(function() return context(2, data.get) end)
                        if alive and success and type(updated) == "table" then energy = updated.CurrentEnergy end
                    end)
                end
            end)
            if job == current then job = nil end
            if not ok then lastReadError = tostring(err) end
        end)
    end
    -- Recover the native BuffList's existing state when attached halfway through a run.
    -- Read only: no hookfunction/setupvalue and no replacement of the game's listener.
    local function nativeBuffSnapshot(remote)
        if type(getconnections) ~= "function" or type(getupvalues) ~= "function" then return nil end
        for _, connection in ipairs(getconnections(remote.OnClientEvent)) do
            local callback = connection.Function
            if type(callback) == "function" and debug.info(callback, "s") == "ReplicatedStorage.DungeonClient.Interface" then
                for _, setter in pairs(getupvalues(callback)) do
                    if type(setter) == "function" and debug.info(setter, "s"):find("ReactFiberHooks", 1, true) then
                        for _, queue in pairs(getupvalues(setter)) do
                            if type(queue) == "table" and type(queue.lastRenderedState) == "table" then
                                local copy, valid = {}, true
                                for id, value in pairs(queue.lastRenderedState) do
                                    if type(id) ~= "string" or type(value) ~= "number" then valid = false; break end
                                    copy[id] = value
                                end
                                if valid then return copy end
                            end
                        end
                    end
                end
            end
        end
    end
    local function watchBuffs()
        local shared = rs:FindFirstChild("DungeonShared")
        local remote = shared and shared:FindFirstChild("BuffReplicator")
        if remote ~= buffRemote then
            if buffConnection then buffConnection:Disconnect(); buffConnection = nil end
            buffRemote = remote
            if remote and remote:IsA("RemoteEvent") then
                buffConnection = remote.OnClientEvent:Connect(function(value)
                    if alive and type(value) == "table" then
                        buffs, buffKnown = table.clone(value), true
                        if onBuffs then onBuffs(buffs) end
                    end
                end)
            end
        end
        if not buffKnown and remote and os.clock() - lastSnapshotTry >= 2 then
            lastSnapshotTry = os.clock()
            local ok, snapshot = pcall(nativeBuffSnapshot, remote)
            if ok and snapshot then buffs, buffKnown = snapshot, true end
        end
    end
    local function read()
        if job and os.clock() - job.Started > 8 then
            local old = job; job = nil; pcall(task.cancel, old.Thread)
            lastReadError = "Status data request timed out"
        end
        beginInit()
        watchBuffs()
        local state = {InDungeon = workspace:GetAttribute("IsDungeonInstance") == true,
            JobId = game.JobId, Definitions = definitions, Energy = energy,
            Buffs = buffKnown and buffs or nil, Error = lastReadError}
        if not state.InDungeon then
            boundsFloor, boundsFrame, boundsSize, seen, buffs, buffKnown = nil, nil, nil, {}, nil, false
            state.Buffs = nil
            return state
        end
        local guid = player:GetAttribute("ExplorerGUID")
        local replicas = rs:FindFirstChild("DungeonReplicationObjects")
        local dungeon, explorer
        if guid and replicas then
            for _, candidate in ipairs(replicas:GetChildren()) do
                local explorers = candidate:FindFirstChild("Explorers")
                local e = explorers and explorers:FindFirstChild(guid)
                local ref = e and e:FindFirstChild("Player")
                if ref and ref:IsA("ObjectValue") and ref.Value == player then dungeon, explorer = candidate, e; break end
            end
        end
        if not explorer then return state end
        local floor = explorer:GetAttribute("FloorId")
        state.DungeonKey, state.FloorId = dungeon.Name, floor
        state.ActiveFloor = dungeon:GetAttribute("CurrentExploredLevel")
        state.TotalEnemies, state.DeadEnemies = dungeon:GetAttribute("TotalEnemies"), dungeon:GetAttribute("DeadEnemies")
        local replicatedFloors = dungeon:FindFirstChild("Floors")
        local replicatedFloor = replicatedFloors and replicatedFloors:FindFirstChild(tostring(floor))
        state.HasBoss = replicatedFloor and replicatedFloor:GetAttribute("HasBoss") == true
        local map = workspace:FindFirstChild("Map")
        local worldFloors = map and map:FindFirstChild("Dungeon")
        local worldFloor = worldFloors and worldFloors:FindFirstChild(tostring(floor))
        if worldFloor ~= boundsFloor then
            boundsFloor, boundsFrame, boundsSize, seen = worldFloor, nil, nil, {}
        end
        if worldFloor and not boundsFrame then
            local ok, frame, size = pcall(function() return worldFloor:GetBoundingBox() end)
            if ok and size.Magnitude > 0 then boundsFrame, boundsSize = frame, size end
        end
        local gate = worldFloor and worldFloor:FindFirstChild("ExitTeleporter")
        local exit = gate and gate:FindFirstChild("Root")
        state.ExitReady = exit and exit.CanTouch and exit:FindFirstChildOfClass("TouchTransmitter") ~= nil
        if boundsFrame then
            local living = 0
            for _, mob in ipairs(EnemyPolicy.List(workspace:FindFirstChild("Enemies"), Players, false)) do
                local root = mob:FindFirstChild("HumanoidRootPart")
                local pos, half = boundsFrame:PointToObjectSpace(root.Position), boundsSize * 0.5
                if math.abs(pos.X) <= half.X and math.abs(pos.Y) <= half.Y and math.abs(pos.Z) <= half.Z then
                    seen[mob:GetAttribute("ID") or mob] = true
                    if mob:FindFirstChildOfClass("Humanoid").Health > 0 then living += 1 end
                end
            end
            local total = 0; for _ in pairs(seen) do total += 1 end
            state.LivingEnemies, state.ObservedTotal = living, total
        end
        return state
    end
    local function paint(target, state)
        context(identity, function()
            target.SetFloor(state.Floor); target.SetTime(state.Time)
            target.SetMobs(state.Mobs); target.SetEnergy(state.Energy)
            target.SetProgress(state.Ratio, state.Progress)
            for id, card in pairs(target.BuffCardsState) do
                local level = state.Levels[id]
                if level ~= nil then
                    if card.Level ~= level or card.LevelLabel.Text == "Lv. --" then target.SetBuffLevel(id, level) end
                elseif card.LevelLabel.Text ~= "Lv. --" then card.LevelLabel.Text = "Lv. --" end
            end
        end)
    end
    return {Read = read, Now = os.clock, Paint = paint, Spawn = task.defer, Wait = task.wait, Cancel = task.cancel,
        Session = getgenv().TrashHubDungeonStatusSession,
        SaveSession = function(value) getgenv().TrashHubDungeonStatusSession = value end,
        SubscribeBuffs = function(callback) onBuffs = callback end,
        Destroy = function()
            alive = false; onBuffs = nil
            if job then pcall(task.cancel, job.Thread); job = nil end
            if buffConnection then buffConnection:Disconnect() end
            if energyConnection then energyConnection:Disconnect() end
            table.clear(seen)
        end}
end
return Module

    end)()
    local RaceAutomation = (function()
-- Uses native V3 remote and the V4 BindableEvent. Does not equip tools or send keys.
local Module = {}
Module.V3Tools={"Last Resort","Agility","Water Body","Heavenly Blood","Heightened Senses","Energy Core","Primordial Reign"}
local Controller = {}; Controller.__index=Controller
function Module.new(ui,deps)
    return setmetatable({UI=ui, Deps=deps, Alive=true, NextV3=0, NextV4=0,
        Status={Phase="stopped",V3Requests=0,V4Requests=0}},Controller)
end
function Controller:Step()
    if not self.Alive then return end
    local s,now=self.Deps.Read(),self.Deps.Now()
    if s.Character~=self.Character then
        self.Character=s.Character; self.NextV3,self.NextV4=0,0
    end
    if not s.Active or not s.InDungeon or not s.GameReady then self.Status.Phase="stopped"; return end
    if not s.Alive then self.Status.Phase="waiting-character"; return end
    self.Status.Phase="watching-race"
    if s.HasV3 and s.V3Ready and now>=self.NextV3 then
        self.NextV3=now+1.5
        local ok,err=pcall(self.Deps.UseV3,s)
        if ok and err~=false then self.Status.V3Requests+=1; self.Status.LastV3At=now; self.Status.LastError=nil
        elseif not ok then self.Status.LastError=tostring(err) end
    end
    if s.HasV4 and type(s.RaceEnergy)=="number" and s.RaceEnergy>=1
        and not s.Transformed and not s.Busy and not s.Stunned and now>=self.NextV4 then
        self.NextV4=now+2
        local ok,allowed=pcall(self.Deps.CanUseV4,s)
        if ok and allowed then
            local used,err=pcall(self.Deps.UseV4,s)
            if used and err~=false then self.Status.V4Requests+=1; self.Status.LastV4At=now; self.Status.LastError=nil
            elseif not used then self.Status.LastError=tostring(err) end
        elseif not ok then self.Status.LastError=tostring(allowed) end
    end
end
function Controller:Destroy()
    if not self.Alive then return end
    self.Alive=false; self.Character=nil
    if self.Connection then self.Connection:Disconnect() end
    if self.Thread and self.Thread~=coroutine.running() then pcall(self.Deps.Cancel,self.Thread) end
    if self.UI.LiveRace==self then self.UI.LiveRace=nil end
end
function Module.Native(ui)
    local player,rs=game:GetService("Players").LocalPlayer,game:GetService("ReplicatedStorage")
    assert(player,"LocalPlayer is not ready; wait before binding race automation")
    local function native(fn)
        local getter,setter=getthreadidentity or getidentity,setthreadidentity or setidentity
        local prior=getter and getter()
        if setter and prior then setter(2) end
        local result=table.pack(pcall(fn))
        if setter and prior then setter(prior) end
        if not result[1] then error(result[2],0) end
        return table.unpack(result,2,result.n)
    end
    local function tool(character,name)
        local backpack=player:FindFirstChild("Backpack")
        local found=character and character:FindFirstChild(name) or (backpack and backpack:FindFirstChild(name))
        return found and found:IsA("Tool") and found or nil
    end
    local function read()
        local char=player.Character
        local humanoid=char and char:FindFirstChildOfClass("Humanoid")
        local main=ui.LiveMain
        local combat=main and main.Combat
        local v3
        for _,name in ipairs(Module.V3Tools) do v3=tool(char,name); if v3 then break end end
        local energy=char and char:FindFirstChild("RaceEnergy")
        local transformed=char and char:FindFirstChild("RaceTransformed")
        local busy=char and char:FindFirstChild("Busy")
        local stun=char and char:FindFirstChild("Stun")
        return {Character=char, Alive=humanoid~=nil and humanoid.Health>0,
            Active=main~=nil and main.Settings.IsStarted and combat~=nil and combat._enabled==true,
            InDungeon=workspace:GetAttribute("IsDungeonInstance")==true,
            GameReady=ui.IsGameReady~=nil and ui.IsGameReady(),
            HasV3=v3~=nil, V3Ready=v3~=nil and v3.Enabled,
            HasV4=tool(char,"Awakening")~=nil, RaceEnergy=energy and energy.Value,
            Transformed=transformed and transformed.Value==true,
            Busy=busy and busy.Value==true, Stunned=stun and stun.Value>0}
    end
    local function stillActive(s)
        local now=read()
        return now.Active and now.InDungeon and now.GameReady and now.Alive and now.Character==s.Character,now
    end
    return {Read=read,Now=os.clock,Spawn=task.defer,Wait=task.wait,Cancel=task.cancel,
        UseV3=function(s)
            local valid,now=stillActive(s)
            if not valid or not now.HasV3 or not now.V3Ready then return false end
            local remotes=rs:FindFirstChild("Remotes")
            local remote=remotes and remotes:FindFirstChild("CommE")
            assert(remote and remote:IsA("RemoteEvent"),"V3 remote not ready")
            native(function() remote:FireServer("ActivateAbility") end)
            return true
        end,
        CanUseV4=function(s)
            local valid,now=stillActive(s)
            if not valid or now.Transformed or now.Busy or now.Stunned or not now.HasV4
                or type(now.RaceEnergy)~="number" or now.RaceEnergy<1 then return false end
            local util=rs:FindFirstChild("Util")
            local check=util and util:FindFirstChild("IsTransformed")
            if not check then return false end
            return native(function() return not require(check)(s.Character,false,false) end)
        end,
        UseV4=function(s)
            local valid,now=stillActive(s)
            if not valid or now.Transformed or now.Busy or now.Stunned or not now.HasV4
                or type(now.RaceEnergy)~="number" or now.RaceEnergy<1 then return false end
            local events=rs:FindFirstChild("Events")
            local event=events and events:FindFirstChild("ActivateRaceV4")
            assert(event and event:IsA("BindableEvent"),"V4 event not ready")
            native(function() event:Fire() end)
            return true
        end}
end
function Module.Bind(ui,deps)
    if ui.LiveRace then ui.LiveRace:Destroy() end
    local self=Module.new(ui,deps or Module.Native(ui)); ui.LiveRace=self
    self.Connection=ui.ScreenGui.Destroying:Connect(function() self:Destroy() end)
    self.Thread=self.Deps.Spawn(function()
        while self.Alive do
            local ok,err=pcall(function() self:Step() end)
            if not ok then self.Status.LastError=tostring(err) end
            self.Deps.Wait(0.5)
        end
    end)
    return self
end
return Module

    end)()
    local PartyPads = (function()
-- Dungeon lobby party pads. Client protocol inspected 2026-10-17.
-- Create on every account with the same owner/clone IDs. Start explicitly from UI.
local Module = {}
-- Current game settings UI gates entry/start at 10 energy. Readiness uses the same value.
Module.MinimumEnergy = 10
Module.MaximumEnergy = 50
-- Cost/recovery were supplied by the user; server deductions/recovery have not been measured.
Module.EnergyCostPerRun = 10
Module.ReportedFullRecoverySeconds = 8 * 60 * 60

function Module.IsPublicQueue(config)
    return not config.StrictRoster and #(config.CloneUserIds or {}) == 0
end

function Module.GetRemainingRuns(energy)
    if type(energy) ~= "number" or energy ~= energy then return nil end
    return math.floor(math.max(0, energy) / Module.EnergyCostPerRun)
end

function Module.CheckEligibility(e)
    if not e or e.Ready ~= true then return false, "loading-dungeon-data" end
    if not e.Unlocked then return false, "difficulty-locked" end
    if type(e.Energy) ~= "number" or e.Energy ~= e.Energy then return false, "energy-unavailable" end
    if math.floor(e.Energy) < Module.MinimumEnergy then return false, "insufficient-energy" end
    return true
end

local Planner = {}
Planner.__index = Planner

function Planner.new(config, localUserId)
    assert(type(config.OwnerUserId) == "number" and config.OwnerUserId > 0, "OwnerUserId required")
    assert(config.Difficulty == "Normal" or config.Difficulty == "Hard" or
        config.Difficulty == "Challenge", "Difficulty must be Normal, Hard, or Challenge")
    local required, cloneIds = {[config.OwnerUserId] = true}, {}
    for _, id in ipairs(config.CloneUserIds or {}) do
        assert(type(id) == "number" and id > 0 and not required[id], "duplicate/invalid party UserId")
        required[id] = true
        cloneIds[#cloneIds + 1] = id
    end
    assert(#cloneIds <= 3, "at most three clones for observed four-player pads")
    assert(required[localUserId], "local account is not in the configured roster")
    local cfg = table.clone(config)
    cfg.CloneUserIds = cloneIds
    cfg.Destination = cfg.Destination or "Simulation"
    cfg.JoinTimeout = cfg.JoinTimeout or 10
    cfg.SettingsTimeout = cfg.SettingsTimeout or 5
    cfg.TeamTimeout = cfg.TeamTimeout or 25
    cfg.EnergyRefreshInterval = math.max(5, cfg.EnergyRefreshInterval or 10)
    cfg.RetryUnfilledPadOnTimeout = cfg.RetryUnfilledPadOnTimeout == true
    cfg.ReleaseTimeout = cfg.ReleaseTimeout or 12
    cfg.PadCooldown = cfg.PadCooldown or 12
    cfg.StableTime = cfg.StableTime or 1
    cfg.CapacityGrace = cfg.CapacityGrace or 1
    cfg.StartTimeout = cfg.StartTimeout or 15
    cfg.AutoStart = cfg.AutoStart ~= false
    local slot = 1
    for i, id in ipairs(cloneIds) do if id == localUserId then slot = i + 1 end end
    return setmetatable({Config = cfg, Required = required, Size = #cloneIds + 1,
        PublicQueue = Module.IsPublicQueue(cfg),
        UserId = localUserId, Role = localUserId == cfg.OwnerUserId and "Owner" or "Clone",
        Slot = slot, Phase = "select", Status = "stopped", Cooldowns = {}}, Planner)
end

local function action(kind, padId, value)
    return {Kind = kind, PadId = padId, Value = value}
end

function Planner:_hold(status)
    self.Status = status
    return action("Hold")
end

function Planner:_eligible(snapshot)
    return Module.CheckEligibility(snapshot.Eligibility)
end

function Planner:_retry(now, reason)
    self.Cooldowns[self.Target] = now + self.Config.PadCooldown
    self.OldPad, self.Target = self.Target, nil
    self.Phase, self.Since = "releasing", now
    self.LastRetryReason, self.Status = reason, "leaving-" .. reason
    self.StableSince, self.StableKey, self.FullSince = nil, nil, nil
    self.SettingsSent = false
    return action("Leave", self.OldPad)
end

function Planner:_coherent(pad)
    return type(pad.Count) == "number" and (self.PublicQueue or #pad.Members == pad.Count) and
        type(pad.MaxPlayers) == "number" and type(pad.MinPlayers) == "number" and
        pad.Count >= 0 and pad.MaxPlayers >= pad.MinPlayers and pad.MinPlayers > 0
end

function Planner:_owner(snapshot, now)
    local me = snapshot.Players[self.UserId]
    local localPad = me and me.PadId
    if self.Phase == "releasing" then
        local remaining = false
        for id in pairs(self.Required) do
            local p = snapshot.Players[id]
            if p and p.PadId == self.OldPad then remaining = true end
        end
        if remaining then
            if now - self.Since > self.Config.ReleaseTimeout then
                self.Status = "waiting-clones-to-leave-old-pad"
            end
            if localPad then return action("Leave", localPad) end
            return self:_hold(self.Status)
        end
        self.Phase, self.OldPad = "select", nil
    end
    if self.Phase == "starting" then
        local pad = snapshot.Pads[self.Target]
        if snapshot.LocalTeleporting or (pad and pad.Preparing) then
            return self:_hold("transfer-in-progress")
        end
        if now - self.Since >= self.Config.StartTimeout then
            return self:_hold("start-unconfirmed")
        end
        return self:_hold("waiting-start-ack")
    end
    local eligible, issue = self:_eligible(snapshot)
    if not eligible then
        if self.Target then return self:_retry(now, issue) end
        return self:_hold(issue)
    end
    if self.Phase == "select" then
        if localPad then self.Status = "leaving-existing-pad"; return action("Leave", localPad) end
        for id in pairs(self.Required) do
            if not snapshot.Players[id] then return self:_hold("waiting-party-in-server") end
        end
        local candidates = {}
        for id, pad in pairs(snapshot.Pads) do
            if pad.Destination == self.Config.Destination and self:_coherent(pad) and
                pad.Count == 0 and not pad.Initiator and not pad.Preparing and
                pad.MaxPlayers >= self.Size and (self.Cooldowns[id] or 0) <= now then
                candidates[#candidates + 1] = pad
            end
        end
        table.sort(candidates, function(a, b)
            if a.Distance ~= b.Distance then return (a.Distance or math.huge) < (b.Distance or math.huge) end
            return a.Id < b.Id
        end)
        if #candidates == 0 then return self:_hold("waiting-empty-pad") end
        self.Target, self.Since, self.Phase = candidates[1].Id, now, "joining"
        self.Status = "owner-entering-pad"
        return action("Enter", self.Target, self.Slot)
    end
    local pad = snapshot.Pads[self.Target]
    if not pad or pad.Destination ~= self.Config.Destination then return self:_retry(now, "pad-missing") end
    if pad.Initiator and pad.Initiator ~= self.UserId then return self:_retry(now, "not-initiator") end
    if pad.Preparing then return self:_hold("transfer-in-progress") end
    if localPad ~= self.Target then
        if self.Phase ~= "joining" then return self:_retry(now, "owner-left-pad") end
        if now - self.Since >= self.Config.JoinTimeout then return self:_retry(now, "owner-join-timeout") end
        if pad.Initiator and pad.Initiator ~= self.UserId then return self:_retry(now, "not-initiator") end
        self.Status = "owner-entering-pad"
        return action("Enter", self.Target, self.Slot)
    end
    if pad.Initiator and pad.Initiator ~= self.UserId then return self:_retry(now, "not-initiator") end
    if not pad.Initiator then
        if now - self.Since >= self.Config.JoinTimeout then return self:_retry(now, "initiator-not-confirmed") end
        return self:_hold("waiting-initiator")
    end
    if self.Phase == "joining" then
        self.Phase, self.Since, self.SettingsSent = "configuring", now, false
    end
    if pad.Difficulty ~= self.Config.Difficulty then
        if self.Phase ~= "configuring" then
            self.Phase, self.Since, self.SettingsSent = "configuring", now, false
        end
        if now - self.Since >= self.Config.SettingsTimeout then return self:_retry(now, "settings-not-accepted") end
        if not self.SettingsSent then
            self.SettingsSent, self.Status = true, "selecting-difficulty"
            return action("Difficulty", self.Target, self.Config.Difficulty)
        end
        return self:_hold("waiting-difficulty-ack")
    end
    if self.Phase == "configuring" then self.Phase, self.Since = "team", now end
    local allPresent, outsider = true, false
    local memberSet, ids = {}, {}
    for _, id in ipairs(pad.Members) do memberSet[id] = true; ids[#ids + 1] = id end
    for id in pairs(self.Required) do
        local p = snapshot.Players[id]
        if not p or p.PadId ~= self.Target or p.Alive ~= true or not memberSet[id] then allPresent = false end
    end
    for id in pairs(memberSet) do if not self.Required[id] then outsider = true end end
    if self.Config.StrictRoster and outsider then return self:_retry(now, "outsider-on-pad") end
    if not allPresent and type(pad.Count) == "number" and type(pad.MaxPlayers) == "number" and pad.Count >= pad.MaxPlayers then
        self.FullSince = self.FullSince or now
        if now - self.FullSince >= self.Config.CapacityGrace then return self:_retry(now, "full-with-missing-clone") end
    else self.FullSince = nil end
    if allPresent and self:_coherent(pad) and pad.Count >= pad.MinPlayers and pad.Count <= pad.MaxPlayers then
        table.sort(ids)
        local key = (self.PublicQueue and tostring(self.Config.OwnerUserId) or table.concat(ids, ","))
            .. ":" .. tostring(pad.Count) .. ":" .. pad.Difficulty
        if key ~= self.StableKey then self.StableKey, self.StableSince = key, now end
        if now - self.StableSince >= self.Config.StableTime then
            if not self.Config.AutoStart then return self:_hold("party-ready") end
            self.Phase, self.Since, self.Status = "starting", now, "starting"
            return action("Start", self.Target)
        end
        return self:_hold("confirming-full-party")
    end
    self.StableSince, self.StableKey = nil, nil
    if now - self.Since >= self.Config.TeamTimeout then
        if self.Config.RetryUnfilledPadOnTimeout then return self:_retry(now, "team-join-timeout") end
        -- A missing clone may lack energy/unlocks. Changing an otherwise usable pad cannot fix that.
        return self:_hold(self:_coherent(pad) and
            (self.Size == 1 and "waiting-public-players" or "waiting-clones-not-ready") or "waiting-membership-sync")
    end
    return self:_hold(self:_coherent(pad) and
        (self.Size == 1 and "waiting-public-players" or "waiting-clones") or "waiting-membership-sync")
end

function Planner:_clone(snapshot)
    local owner, me = snapshot.Players[self.Config.OwnerUserId], snapshot.Players[self.UserId]
    local ownerPad = owner and owner.PadId
    local localPad = me and me.PadId
    local pad = ownerPad and snapshot.Pads[ownerPad]
    local valid = pad and pad.Destination == self.Config.Destination and
        pad.Initiator == self.Config.OwnerUserId and pad.Difficulty == self.Config.Difficulty
    if localPad and (localPad ~= ownerPad or not valid) then
        self.Status = "clone-leaving-old-pad"
        return action("Leave", localPad)
    end
    local eligible, issue = self:_eligible(snapshot)
    if not eligible then
        if localPad and pad and not pad.Preparing then self.Status = issue; return action("Leave", localPad) end
        return self:_hold(issue)
    end
    if not valid then return self:_hold("waiting-owner-configured-pad") end
    self.Target = ownerPad
    if pad.Preparing then return self:_hold(localPad == ownerPad and "transfer-in-progress" or "owner-already-starting") end
    if localPad == ownerPad then return self:_hold("clone-joined-owner") end
    if not self:_coherent(pad) then return self:_hold("waiting-membership-sync") end
    if pad.Count >= pad.MaxPlayers then return self:_hold("owner-pad-full") end
    self.Status = "clone-following-owner"
    return action("Enter", ownerPad, self.Slot)
end

function Planner:Step(snapshot, now)
    if snapshot.InDungeon then self.WasInDungeon = true; return self:_hold("in-dungeon") end
    if snapshot.LocalTeleporting then return self:_hold("transfer-in-progress") end
    if not snapshot.InLobby then return self:_hold("outside-dungeon-lobby") end
    if self.WasInDungeon then
        self.WasInDungeon, self.Phase, self.Target, self.OldPad = false, "select", nil, nil
        self.StableSince, self.StableKey, self.SettingsSent = nil, nil, false
        table.clear(self.Cooldowns)
    end
    if not snapshot.LocalAlive then return self:_hold("waiting-character") end
    for id, expiry in pairs(self.Cooldowns) do if expiry <= now then self.Cooldowns[id] = nil end end
    if self.Role == "Owner" then return self:_owner(snapshot, now) end
    return self:_clone(snapshot)
end

Module.Planner = Planner

-- Own one CFrame tween and restore every character property changed for travel.
function Module.CreatePadMover(deps)
    local mover = {Alive = true, Job = nil}
    local speed = tonumber(deps.Speed) or 200
    if speed ~= speed or math.abs(speed) == math.huge then speed = 200 end
    speed = math.clamp(speed, 40, 500)
    local function protect(job)
        for _, part in ipairs(job.Character:GetDescendants()) do
            if part:IsA("BasePart") then
                if job.Collisions[part] == nil then job.Collisions[part] = part.CanCollide end
                part.CanCollide = false
            end
        end
        job.Root.AssemblyLinearVelocity = deps.Zero
        job.Root.AssemblyAngularVelocity = deps.Zero
    end
    function mover:Cancel()
        local job = self.Job
        self.Job = nil
        if not job then return end
        if job.Connection then job.Connection:Disconnect() end
        if job.Tween then pcall(function() job.Tween:Cancel() end) end
        pcall(function() job.Humanoid.AutoRotate = job.AutoRotate end)
        pcall(function()
            job.Root.AssemblyLinearVelocity = deps.Zero
            job.Root.AssemblyAngularVelocity = deps.Zero
        end)
        for part, collision in pairs(job.Collisions) do pcall(function() part.CanCollide = collision end) end
        table.clear(job.Collisions)
    end
    function mover:MoveTo(key, character, root, humanoid, goal, valid)
        if not self.Alive then return false, "mover-destroyed" end
        local checked, allowed = pcall(valid)
        if not checked or not allowed then
            self:Cancel()
            return false, checked and "movement-precondition-changed" or tostring(allowed)
        end
        local job = self.Job
        if job and job.Key == key and job.Character == character and job.Root == root
            and (job.Goal.Position - goal.Position).Magnitude < 0.1 then return true end
        self:Cancel()
        local distance = (root.Position - goal.Position).Magnitude
        if distance < 0.1 then root.CFrame = goal; return true end
        job = {Key = key, Character = character, Root = root, Humanoid = humanoid,
            Goal = goal, AutoRotate = humanoid.AutoRotate, Collisions = {}}
        self.Job = job
        local ok, err = pcall(function()
            humanoid.AutoRotate = false
            protect(job)
            job.Tween = deps.CreateTween(root, math.max(0.05, distance / speed), goal)
            job.Connection = deps.Heartbeat:Connect(function()
                if self.Job ~= job then return end
                local healthy, detail = pcall(function()
                    if not valid() or deps.IsFinished(job.Tween) then self:Cancel(); return end
                    protect(job)
                end)
                if not healthy then self.LastError = tostring(detail); self:Cancel() end
            end)
            job.Tween:Play()
        end)
        if not ok then self.LastError = tostring(err); self:Cancel(); return false, self.LastError end
        return true
    end
    function mover:Destroy()
        if not self.Alive then return end
        self.Alive = false
        self:Cancel()
    end
    return mover
end

local function context(callback)
    local get = getthreadidentity or getidentity
    local set = setthreadidentity or setidentity
    local old = get and get()
    if old and set then set(2) end
    local result = table.pack(pcall(callback))
    if old and set then set(old) end
    if not result[1] then error(result[2], 2) end
    return table.unpack(result, 2, result.n)
end

function Module.CreateRobloxAdapter(config)
    local players = game:GetService("Players")
    local collection = game:GetService("CollectionService")
    local runService = game:GetService("RunService")
    local tweenService = game:GetService("TweenService")
    local localPlayer = players.LocalPlayer
    local module = game.ReplicatedStorage.DungeonClient.ReplicatedPlayerData
    local energyRefreshInterval = math.max(5, config.EnergyRefreshInterval or 10)
    local playerData, dataError, alive = nil, nil, true
    local refreshThread, refreshBusy, lastRefresh = nil, false, -math.huge
    local dataThread = task.spawn(function()
        local ok, result = pcall(function() return context(function()
            local loaded = require(module)
            loaded.get() -- Prime once off the movement/control loop; subsequent reads use the game's cache.
            return loaded
        end) end)
        if ok then playerData, lastRefresh = result, os.clock() else dataError = tostring(result) end
    end)
    local padInstances = {}
    local mover = Module.CreatePadMover({
        Speed = config.PadMoveSpeed, Zero = Vector3.zero, Heartbeat = runService.Heartbeat,
        CreateTween = function(root, duration, goal)
            return tweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = goal})
        end,
        IsFinished = function(tween)
            return tween.PlaybackState == Enum.PlaybackState.Completed or tween.PlaybackState == Enum.PlaybackState.Cancelled
        end,
    })
    local function character()
        local c = localPlayer.Character
        local root = c and c:FindFirstChild("HumanoidRootPart")
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        return root, hum
    end
    local function cancelMove()
        mover:Cancel()
    end
    local function currentPad(player)
        local ref = player:FindFirstChild("TeleporterPadObjectReference")
        return ref and ref:IsA("ObjectValue") and ref.Value or nil
    end
    local function key(model) return model and model:GetFullName() or nil end
    local function readEligibility()
        local e = {Ready = false, Error = dataError, RequiredEnergy = Module.MinimumEnergy}
        if not playerData then return e end
        local ok, d = pcall(playerData.get)
        if not ok or not d then return e end
        local progress = d.DataForDungeonTypes and d.DataForDungeonTypes[config.Destination or "Simulation"]
        local unlocked = progress and progress.UnlockedDifficulties or {Normal = {}}
        e.Ready, e.Energy, e.Unlocked = true, d.CurrentEnergy, not not unlocked[config.Difficulty]
        e.CanJoin, e.Issue = Module.CheckEligibility(e)
        -- GetData is read-only. Refresh low/unknown energy off the control loop, never per frame.
        local needRefresh = type(e.Energy) ~= "number" or e.Energy ~= e.Energy or e.Energy < Module.MinimumEnergy
        if needRefresh and not refreshBusy and os.clock() - lastRefresh >= energyRefreshInterval then
            refreshBusy, lastRefresh = true, os.clock()
            refreshThread = task.spawn(function()
                local refreshed, err = pcall(function() context(function() playerData.get(true) end) end)
                refreshBusy = false
                if alive then dataError = not refreshed and tostring(err) or nil end
            end)
        end
        e.Refreshing = refreshBusy
        return e
    end
    local function read()
        local root, hum = character()
        local snapshot = {Players = {}, Pads = {}, LocalUserId = localPlayer.UserId,
            LocalAlive = root ~= nil and hum ~= nil and hum.Health > 0,
            InLobby = workspace:GetAttribute("MAP") == "Dungeons",
            InDungeon = workspace:GetAttribute("IsDungeonInstance") == true,
            LocalTeleporting = localPlayer:GetAttribute("IsTeleporting") == true,
            Eligibility = readEligibility()}
        padInstances = {}
        for _, model in ipairs(collection:GetTagged("DUNGEON_TELEPORTER")) do
            local part = model:FindFirstChild("Pad")
            if model:IsDescendantOf(workspace) and part and part:IsA("BasePart") then
                local id = key(model)
                padInstances[id] = model
                snapshot.Pads[id] = {Id = id, Name = model.Name, Members = {},
                    Initiator = model:GetAttribute("Initiator"), Difficulty = model:GetAttribute("Difficulty"),
                    Count = model:GetAttribute("NumPlayersOnPad"), MinPlayers = model:GetAttribute("MinPlayers"),
                    MaxPlayers = model:GetAttribute("MaxPlayers"), Destination = model:GetAttribute("Destination"),
                    Preparing = model:GetAttribute("PreparingToTeleport") == true,
                    Countdown = model:GetAttribute("TeleportCountdown"),
                    Distance = root and (root.Position - part.Position).Magnitude or math.huge}
            end
        end
        for _, p in ipairs(players:GetPlayers()) do
            local padId = key(currentPad(p))
            local c = p.Character
            local h = c and c:FindFirstChildOfClass("Humanoid")
            snapshot.Players[p.UserId] = {UserId = p.UserId, Name = p.Name, PadId = padId,
                Alive = h ~= nil and h.Health > 0 and c:FindFirstChild("HumanoidRootPart") ~= nil}
            if padId and snapshot.Pads[padId] then
                table.insert(snapshot.Pads[padId].Members, p.UserId)
            end
        end
        return snapshot
    end
    local function execute(command)
        if not alive then return false, "adapter-destroyed" end
        if command.Kind == "Hold" then cancelMove(); return true end
        local model = padInstances[command.PadId]
        if not model or not model:IsDescendantOf(workspace) then return false, "pad-disappeared" end
        local part = model:FindFirstChild("Pad")
        if not part then return false, "pad-part-missing" end
        if command.Kind == "Enter" or command.Kind == "Leave" then
            if command.Kind == "Enter" then
                local enough, reason = Module.CheckEligibility(readEligibility())
                if not enough then return false, reason end
            end
            local root, hum = character()
            if not root or not hum or hum.Health <= 0 then return false, "character-not-ready" end
            if root.Anchored then cancelMove(); return false, "character-anchored" end
            if command.Kind == "Enter" and model:GetAttribute("PreparingToTeleport") then return false, "pad-starting" end
            if localPlayer:GetAttribute("IsTeleporting") then return false, "player-teleporting" end
            if (command.Kind == "Enter") == (currentPad(localPlayer) == model) then cancelMove(); return true end
            local c = localPlayer.Character
            local leg = c:FindFirstChild("Left Leg")
            local height = math.max(0, hum.HipHeight) + root.Size.Y / 2
                + (leg and leg:IsA("BasePart") and leg.Size.Y or 0)
            local standingY = part.Size.Y / 2 + height + 0.05
            local goal
            if command.Kind == "Leave" then
                -- Retreat beyond both local extents so physical pad overlap ends.
                goal = part.CFrame:PointToWorldSpace(Vector3.new(part.Size.X / 2 + 7, standingY, part.Size.Z / 2 + 7))
            else
                local offsets = {Vector3.new(-3, standingY, -3), Vector3.new(3, standingY, -3),
                    Vector3.new(-3, standingY, 3), Vector3.new(3, standingY, 3)}
                goal = part.CFrame:PointToWorldSpace(offsets[command.Value or 1])
            end
            local moveKey = command.Kind .. command.PadId .. tostring(command.Value)
            return mover:MoveTo(moveKey, c, root, hum, CFrame.new(goal) * (root.CFrame - root.Position), function()
                if not alive or localPlayer.Character ~= c or root.Parent ~= c or hum.Parent ~= c
                    or hum.Health <= 0 or root.Anchored or not model:IsDescendantOf(workspace)
                    or model:FindFirstChild("Pad") ~= part or localPlayer:GetAttribute("IsTeleporting")
                    or workspace:GetAttribute("IsDungeonInstance") == true or workspace:GetAttribute("MAP") ~= "Dungeons" then return false end
                if command.Kind == "Enter" then
                    return not model:GetAttribute("PreparingToTeleport") and currentPad(localPlayer) ~= model
                end
                return currentPad(localPlayer) == model
            end)
        end
        cancelMove()
        if localPlayer.UserId ~= config.OwnerUserId or currentPad(localPlayer) ~= model or
            model:GetAttribute("Initiator") ~= localPlayer.UserId then return false, "leadership-changed" end
        if model:GetAttribute("PreparingToTeleport") then return false, "pad-starting" end
        local remote = model:FindFirstChild("DungeonSettingsChanged")
        if not remote or not remote:IsA("RemoteEvent") then return false, "settings-remote-missing" end
        if command.Kind == "Difficulty" then remote:FireServer("Difficulty", command.Value); return true end
        if command.Kind == "Start" then
            -- Recheck immediately before issuing Start. Never trust a previous UI snapshot.
            local fresh = read()
            local pad = fresh.Pads[command.PadId]
            if not pad or padInstances[command.PadId] ~= model or currentPad(localPlayer) ~= model or
                pad.Initiator ~= config.OwnerUserId or pad.Preparing or fresh.LocalTeleporting or
                type(pad.Count) ~= "number" or type(pad.MinPlayers) ~= "number" or
                type(pad.MaxPlayers) ~= "number" or pad.Difficulty ~= config.Difficulty or
                (not Module.IsPublicQueue(config) and #pad.Members ~= pad.Count) or
                pad.Count < pad.MinPlayers or pad.Count > pad.MaxPlayers or
                not Module.CheckEligibility(fresh.Eligibility) then
                return false, "start-precondition-changed"
            end
            local roster = {[config.OwnerUserId] = true}
            for _, id in ipairs(config.CloneUserIds or {}) do roster[id] = true end
            for id in pairs(roster) do
                local p = fresh.Players[id]
                if not p or p.PadId ~= command.PadId or not p.Alive then return false, "party-changed-before-start" end
            end
            if config.StrictRoster then
                for _, id in ipairs(pad.Members) do if not roster[id] then return false, "outsider-before-start" end end
            end
            remote:FireServer("Start")
            return true
        end
        return false, "unknown-command"
    end
    local characterRemoving = localPlayer.CharacterRemoving:Connect(cancelMove)
    local teleportConnection = localPlayer.OnTeleport:Connect(cancelMove)
    return {
        UserId = localPlayer.UserId, Read = read, Execute = execute, Now = os.clock,
        Wait = task.wait, Spawn = task.spawn, Cancel = task.cancel, CancelMove = cancelMove,
        Destroy = function()
            if not alive then return end
            alive = false
            mover:Destroy()
            characterRemoving:Disconnect()
            teleportConnection:Disconnect()
            if coroutine.status(dataThread) ~= "dead" then pcall(task.cancel, dataThread) end
            if refreshThread and coroutine.status(refreshThread) ~= "dead" then pcall(task.cancel, refreshThread) end
        end,
    }
end

local Controller = {}
Controller.__index = Controller

function Module.new(config, options)
    options = options or {}
    local adapter = options.Adapter
    local planner = Planner.new(config, adapter and adapter.UserId or game.Players.LocalPlayer.UserId)
    adapter = adapter or Module.CreateRobloxAdapter(planner.Config)
    return setmetatable({_alive = true, _enabled = false, _listeners = {},
        Adapter = adapter, Planner = planner, ManualStep = options.ManualStep == true,
        Interval = math.max(0.1, options.Interval or 0.2)}, Controller)
end

function Controller:GetState()
    local p = self.Planner
    local eligible = self.Snapshot and self.Snapshot.Eligibility
    local canJoin, issue = Module.CheckEligibility(eligible)
    return {Enabled = self._enabled, Role = p.Role, Phase = p.Phase, Status = p.Status,
        PadId = p.Target or p.OldPad, LastRetryReason = p.LastRetryReason, LastError = self.LastError,
        Energy = eligible and eligible.Energy, RequiredEnergy = Module.MinimumEnergy,
        MaximumEnergy = Module.MaximumEnergy, EnergyCostPerRun = Module.EnergyCostPerRun,
        RemainingRuns = Module.GetRemainingRuns(eligible and eligible.Energy),
        ReportedFullRecoverySeconds = Module.ReportedFullRecoverySeconds,
        CanJoinPad = canJoin and self.Snapshot.LocalAlive and self.Snapshot.InLobby and
            not self.Snapshot.InDungeon and not self.Snapshot.LocalTeleporting,
        EligibilityIssue = issue,
        Snapshot = self.Snapshot, LastCommand = self.LastCommand}
end

function Controller:_notify()
    for callback in pairs(self._listeners) do pcall(callback, self:GetState()) end
end

function Controller:Subscribe(callback)
    assert(self._alive, "controller destroyed")
    self._listeners[callback] = true
    local ok, err = pcall(callback, self:GetState())
    if not ok then self._listeners[callback] = nil; error(err, 2) end
    return function() self._listeners[callback] = nil end
end

function Controller:Step()
    if not self._alive or not self._enabled or self._stepping then return end
    self._stepping = true
    local ok, err = pcall(function()
        self.Snapshot = self.Adapter.Read()
        local command = self.Planner:Step(self.Snapshot, self.Adapter.Now())
        self.LastCommand = command
        if not self._alive or not self._enabled then return end
        local accepted, reason = self.Adapter.Execute(command)
        if not accepted then
            self.LastError = reason
            -- A guard rejection here means Start was not sent; it is safe to re-evaluate the roster.
            if command.Kind == "Start" then
                self.Planner.Phase, self.Planner.Since = "team", self.Adapter.Now()
                self.Planner.StableSince, self.Planner.StableKey = nil, nil
                self.Planner.Status = "start-guard-rejected"
            end
        end
    end)
    self._stepping = false
    if not ok then
        self.LastError = tostring(err)
        self._enabled, self.Planner.Status = false, "adapter-error"
        self.Adapter.CancelMove()
    end
    self:_notify()
end

function Controller:Start()
    assert(self._alive, "controller destroyed")
    if self._enabled then return end
    self._enabled = true
    self.Planner.Status = "starting-controller"
    if not self.ManualStep then
        self._thread = self.Adapter.Spawn(function()
            while self._alive and self._enabled do self:Step(); self.Adapter.Wait(self.Interval) end
        end)
    end
    self:_notify()
end

function Controller:OwnsMovement()
    return self._enabled and self.Snapshot ~= nil and self.Snapshot.InLobby and
        not self.Snapshot.InDungeon and not self.Snapshot.LocalTeleporting
end

function Controller:Stop()
    self._enabled = false
    self.Planner.Status = "stopped"
    self.Adapter.CancelMove()
    if self._thread then
        if coroutine.running() ~= self._thread then pcall(self.Adapter.Cancel, self._thread) end
        self._thread = nil
    end
    self:_notify()
end

function Controller:Destroy()
    if not self._alive then return end
    self:Stop()
    self._alive = false
    table.clear(self._listeners)
    self.Adapter.Destroy()
end

return Module

    end)()
    local Combat = (function()
local Module = {}
function Module.new(options)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
assert(LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui"), "player-not-ready")

-- ==================== CẤU HÌNH TOÀN CỤC ====================
local Config = {
    AutoFarmDungeon     = false, -- Bật/tắt tự động đánh quái dungeon
    BringMobs           = true,  -- Bật/tắt gom quái
    FastAttack          = true,  -- Bật/tắt đánh siêu nhanh
    AutoMove            = true,  -- Bật/tắt di chuyển CFrame tới quái
    Noclip              = true,  -- Bật/tắt xuyên tường khi bay
    AutoEquip           = true,  -- Tự động cầm vũ khí
    AutoBuso            = true,  -- Tự động bật Buso Haki
    WeaponType          = "Melee", -- "Melee", "Sword", "Any"
    HoverHeight         = 20,    -- Độ cao bay trên đầu quái (studs)
    GlideSpeed          = 280,   -- Tốc độ lướt tới quái (studs/s)
    AttackDistance      = 120,   -- Tầm quét đòn đánh (studs)
    AttackCooldown      = 0.03,  -- Delay giữa các đòn đánh
    BringMobInterval    = 0.15,  -- Tần suất gom quái (giây)
    BringDistance       = 400,   -- Khoảng cách tối đa để gom quái (studs)
    AutoPickCard        = true,  -- Tự động chọn thẻ buff sau mỗi cửa
    CardFocus           = "Melee", -- "Melee" or "Sword"
    CardPriority        = nil, -- Optional custom order; otherwise follows CardFocus.
    CardNoUsefulFallback = "first-offered",
    AutoProceed         = true,
    RoomGlideSpeed      = 220,
    AutoBreakFloor10    = true,
    AutoBreakFloor15    = true,
    PropProbeUnverified = true
}

-- Lưu config vào getgenv để các module khác có thể đọc
for key, value in pairs(options or {}) do Config[key] = value end
Config.AutoFarmDungeon = false
Config.AutoPickCard = false

-- ==================== REMOTES BLOX FRUITS ====================
local CommF_ = nil
local RegisterAttack = nil
local RegisterHit = nil
local hitFunction = nil

pcall(function()
    CommF_ = ReplicatedStorage:WaitForChild("Remotes", 5):WaitForChild("CommF_", 5)
end)

pcall(function()
    local Net = ReplicatedStorage:WaitForChild("Modules", 5):WaitForChild("Net", 5)
    if Net then
        RegisterAttack = Net:WaitForChild("RE/RegisterAttack", 5)
        RegisterHit = Net:WaitForChild("RE/RegisterHit", 5)
    end
end)

-- Tìm SendHitsToServer từ client script nếu executor hỗ trợ getsenv
pcall(function()
    local ps = LocalPlayer:FindFirstChild("PlayerScripts")
    local ls = ps and ps:FindFirstChildOfClass("LocalScript")
    if ls and type(getsenv) == "function" then
        local env = getsenv(ls)
        hitFunction = env and env._G and env._G.SendHitsToServer
    end
end)

-- ==================== HỆ THỐNG TRẠNG THÁI RUNTIME ====================
local DungeonHunter = {
    _isRunning = true,
    _connections = {},
    _targetMob = nil,
    _mobsCount = 0,
    _currentRoomText = "Đang tìm phòng / Cửa 1",
    _lastAttackTick = 0,
    _lastGrabTick = 0,
    _lastEquipTick = 0,
    _lastBusoTick = 0,
    _lastTick = tick(),
    _hoverVelocity = nil,
    _uiStatusParagraph = nil,
    _uiCharParagraph = nil,
    _uiCardParagraph = nil,
    _uiRoomParagraph = nil,
    _uiPropParagraph = nil,
    ModuleVersion = "world-props-skills-4.1",
    _roomMove = nil,
    _lastDungeonStep = -math.huge,
    _noclipSaved = setmetatable({}, {__mode = "k"}),
    _busoJob = nil,
    _stepBusy = false,
    _fluent = nil
}

DungeonHunter.Config = Config
DungeonHunter._enabled = false
DungeonHunter._bringSaved = setmetatable({}, {__mode = "k"})

-- ==================== HELPER FUNCTIONS ====================
local function getCharacter()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return character, humanoid, root
end

local function isAlive(model)
    if not (model and model.Parent) then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function getHitPart(target)
    if not target then return nil end
    local p = target:FindFirstChild("HumanoidRootPart")
    if p and p:IsA("BasePart") then return p end
    p = target:FindFirstChild("Head")
    if p and p:IsA("BasePart") then return p end
    p = target:FindFirstChildWhichIsA("BasePart")
    return p and p:IsA("BasePart") and p or nil
end

local function setHoverState(enable, root, targetPos)
    if not root then
        if not enable and DungeonHunter._hoverVelocity then
            pcall(function() DungeonHunter._hoverVelocity:Destroy() end)
            DungeonHunter._hoverVelocity = nil
        end
        return
    end
    if enable and targetPos then
        if not DungeonHunter._hoverVelocity or DungeonHunter._hoverVelocity.Parent ~= root then
            pcall(function()
                if DungeonHunter._hoverVelocity then DungeonHunter._hoverVelocity:Destroy() end
            end)
            local hv = Instance.new("BodyVelocity")
            hv.Name = "DungeonHoverVelocity"
            hv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            hv.Velocity = Vector3.zero
            hv.Parent = root
            DungeonHunter._hoverVelocity = hv
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    else
        if DungeonHunter._hoverVelocity then
            pcall(function() DungeonHunter._hoverVelocity:Destroy() end)
            DungeonHunter._hoverVelocity = nil
        end
    end
end

-- ==================== TÌM QUÁI DUNGEON ====================
local EnemyPolicy = (function()
-- Verified live: summoned shadows use model "Blank Buddy" and
-- Humanoid.DisplayName "<player>'s Shadow [Lv. ...]" inside Workspace.Enemies.
local Policy = {}

function Policy.IsSummon(name, displayName)
    if name == "Blank Buddy" then return true end
    local display = tostring(displayName or ""):gsub("<[^>]+>", "")
    return display:match("^.+'s Shadow%s*%[") ~= nil
        or display:match("^.+'s Shadow$") ~= nil
        or display:match("^.+’s Shadow%s*%[") ~= nil
end

function Policy.IsHostile(model, players, aliveOnly)
    if not model or not model.Parent or not model:IsA("Model") then return false end
    -- The game also puts temporary object hitboxes here; WorldPropCombat owns them.
    if model.Name == "PropHitboxPlaceholder" then return false end
    if players and players:GetPlayerFromCharacter(model) then return false end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid or Policy.IsSummon(model.Name, humanoid.DisplayName) then return false end
    if aliveOnly ~= false and humanoid.Health <= 0 then return false end
    return true
end

function Policy.List(folder, players, aliveOnly)
    local result = {}
    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            if Policy.IsHostile(model, players, aliveOnly) and model:FindFirstChild("HumanoidRootPart") then
                result[#result + 1] = model
            end
        end
    end
    return result
end

return Policy

end)()
local function getDungeonEnemies()
    return EnemyPolicy.List(Workspace:FindFirstChild("Enemies"), Players, true)
end

local function findNearestEnemy(playerPos)
    local mobs = getDungeonEnemies()
    DungeonHunter._mobsCount = #mobs
    local nearestMob = nil
    local minDist = math.huge

    for _, mob in ipairs(mobs) do
        local mRoot = mob:FindFirstChild("HumanoidRootPart")
        if mRoot then
            local dist = (mRoot.Position - playerPos).Magnitude
            if dist < minDist then
                minDist = dist
                nearestMob = mob
            end
        end
    end

    return nearestMob, minDist
end

-- ==================== BRING MOB ENGINE ====================
local function lockSingleMob(mob)
    if not mob or not mob.Parent then return false end
    local root = mob:FindFirstChild("HumanoidRootPart")
    if not root then return false end

    local saved = DungeonHunter._bringSaved[mob]
    if not saved then
        saved = {Parts = {}}
        DungeonHunter._bringSaved[mob] = saved
        for _, part in ipairs(mob:GetDescendants()) do
            if part:IsA("BasePart") then saved.Parts[part] = part.CanCollide end
        end
    end

    pcall(function()
        root.CanCollide = false
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)

    if not root:FindFirstChild("K4BringVelocity") then
        local bodyVelocity = Instance.new("BodyVelocity")
        bodyVelocity.Name = "K4BringVelocity"
        bodyVelocity.MaxForce = Vector3.new(4000, 4000, 4000)
        bodyVelocity.Velocity = Vector3.zero
        bodyVelocity.Parent = root
        saved.Velocity = bodyVelocity
    end

    for _, instance in ipairs(mob:GetDescendants()) do
        if instance:IsA("BasePart") then
            instance.CanCollide = false
        end
    end

    return true
end

local function restoreBring()
    for mob, saved in pairs(DungeonHunter._bringSaved) do
        if saved.Velocity then pcall(function() saved.Velocity:Destroy() end) end
        for part, collision in pairs(saved.Parts) do pcall(function() part.CanCollide = collision end) end
        DungeonHunter._bringSaved[mob] = nil
    end
end

local function bringMobsToPoint(targetPoint, mobFilterName)
    if not Config.BringMobs then restoreBring(); return end
    for mob, saved in pairs(DungeonHunter._bringSaved) do
        if not EnemyPolicy.IsHostile(mob, Players, true) then
            if saved.Velocity then pcall(function() saved.Velocity:Destroy() end) end
            for part, collision in pairs(saved.Parts) do pcall(function() part.CanCollide = collision end) end
            DungeonHunter._bringSaved[mob] = nil
        end
    end

    -- Chiếm quyền vật lý mô phỏng
    pcall(function()
        if type(sethiddenproperty) == "function" then
            sethiddenproperty(LocalPlayer, "SimulationRadius", math.huge)
        end
    end)

    local mobs = getDungeonEnemies()
    local bringDist = tonumber(Config.BringDistance) or 400
    local count = 0

    for _, mob in ipairs(mobs) do
        local mobRoot = mob:FindFirstChild("HumanoidRootPart")
        if mobRoot then
            -- Nếu có lọc theo tên mob cùng loại hoặc gom toàn bộ quái trong phòng
            local matches = (not mobFilterName) or (tostring(mob.Name) == tostring(mobFilterName))
            local dist = (mobRoot.Position - targetPoint).Magnitude

            if matches and dist <= bringDist then
                local ownsNetwork = true
                if type(isnetworkowner) == "function" then
                    local ok, result = pcall(isnetworkowner, mobRoot)
                    ownsNetwork = ok and (result == true)
                end

                if ownsNetwork then
                    mobRoot.CFrame = CFrame.new(targetPoint)
                    lockSingleMob(mob)
                    count = count + 1
                end
            end
        end
    end

    return count
end

-- ==================== WEAPON & BUSO HAKI ====================
local function autoEquipWeapon()
    if not Config.AutoEquip then return end

    local character, humanoid = getCharacter()
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not (character and humanoid and humanoid.Health > 0 and backpack) then return end

    local equipped = character:FindFirstChildOfClass("Tool")
    local wanted = tostring(Config.WeaponType or "Melee")

    local function isToolAccepted(tool)
        if not tool or not tool:IsA("Tool") then return false end
        local kind = tool.ToolTip
        if Config.WeaponType == "Fruit" then return kind == "Blox Fruit" end
        return kind == Config.WeaponType or (Config.WeaponType == "Any" and (kind == "Melee" or kind == "Sword"))
    end

    if isToolAccepted(equipped) then return end

    for _, tool in ipairs(backpack:GetChildren()) do
        if isToolAccepted(tool) then
            pcall(function()
                humanoid:EquipTool(tool)
            end)
            return
        end
    end
end

local function enableBuso()
    if not Config.AutoBuso then return end
    local character, humanoid = getCharacter()
    if character and humanoid and humanoid.Health > 0 and not character:FindFirstChild("HasBuso") then
        if CommF_ then
            pcall(function()
                CommF_:InvokeServer("Buso")
            end)
        end
    end
end

-- ==================== FAST ATTACK ENGINE ====================
local function collectAttackTargets(character, originPos)
    local hits = {}
    local basePart = nil
    local distLimit = tonumber(Config.AttackDistance) or 120

    local mobs = getDungeonEnemies()
    for _, mob in ipairs(mobs) do
        if isAlive(mob) then
            local hp = getHitPart(mob)
            if hp and (hp.Position - originPos).Magnitude <= distLimit then
                basePart = basePart or hp
                table.insert(hits, {mob, hp})
            end
        end
    end

    return basePart, hits
end

local function executeFastHit(basePart, hits, tool)
    if not (basePart and basePart:IsA("BasePart") and #hits > 0) then return false end

    local cd = 0
    pcall(function()
        local v = tool and tool:FindFirstChild("Cooldown")
        cd = v and tonumber(v.Value) or 0
    end)

    if RegisterAttack then
        RegisterAttack:FireServer(cd)
    end

    local sent = false
    if type(hitFunction) == "function" then
        sent = pcall(function()
            hitFunction(basePart, hits)
        end)
    end

    if not sent and RegisterHit then
        pcall(function()
            RegisterHit:FireServer(basePart, hits)
        end)
    end

    return true
end

-- BEGIN EMBEDDED DUNGEONKIT MODULES
local DungeonModules = {}
DungeonModules.CardPolicy = (function()
-- Pure policy. IDs and offer fields were verified from DungeonShared/ExplorerBuffs.
local Policy = {}
Policy.DefaultPriority = {
    "Melee", "AttackSpeedMultiplier", "Lifesteal", "RaceEnergy",
    "Fortress", "Armor", "Overflow", "Defense", "Shadow", "Size", "Skyjumps",
}

function Policy.PriorityFor(focus)
    local priority = table.clone(Policy.DefaultPriority)
    priority[1] = focus == "Sword" and "Sword" or "Melee"
    return priority
end

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Policy.Choose(offers, definitions, options)
    if type(offers) ~= "table" then return nil, nil, "invalid-offers" end
    options = options or {}
    local focus = options.Focus == "Sword" and "Sword" or "Melee"
    local priority = options.Priority or Policy.PriorityFor(focus)
    local ranks = {}
    for index, id in ipairs(priority) do
        if type(id) == "string" and ranks[id] == nil then ranks[id] = index end
    end
    local best, bestRank, bestGain, bestIndex, fallback
    for index, offer in ipairs(offers) do
        if index > 256 then break end
        if type(offer) == "table" and type(offer.buffName) == "string" then
            local id = offer.buffName
            -- Skill cooldown cards and other weapon categories never enter M1 selection.
            local weaponCard = id == "Melee" or id == "Sword" or id == "Gun" or id == "Fruit"
            local forbidden = id:lower():find("cooldown", 1, true) ~= nil
                or id == "Unbreakable" or (weaponCard and id ~= focus)
                or id == "Sniper" or id == "RageGain" or id == "ConstructHealth"
            local rank = ranks[id]
            local old, new = offer.oldValue == nil and 0 or offer.oldValue, offer.newValue
            local definition = type(definitions) == "table" and definitions[id]
            local cap = type(definition) == "table" and definition.Cap
            local gain
            if finite(old) and finite(new) and new > old then
                if finite(cap) then new = math.min(new, cap) end
                if new > old then gain = new - old end
            end
            if gain and not fallback then fallback = offer end
            if not forbidden and rank and gain and (not best or rank < bestRank
                or (rank == bestRank and gain > bestGain)
                or (rank == bestRank and gain == bestGain and index < bestIndex)) then
                best, bestRank, bestGain, bestIndex = offer, rank, gain, index
            end
        end
    end
    if best then return best.buffName, best, "priority" end
    if fallback and options.NoUsefulCard == "first-offered" then
        return fallback.buffName, fallback, "forced-fallback"
    end
    -- Returning nil preserves the native chooser when every offer is unsuitable.
    return nil, nil, "no-useful-card"
end

return Policy

end)()
DungeonModules.NativeCardUI = (function()
-- Recover native choices already waiting in React card portals.
-- Reads only validated card event-manager metadata; never searches the GC or clicks coordinates.
local NativeUI = {}
NativeUI.__index = NativeUI

function NativeUI.new(policy, options, deps, onSelected)
    return setmetatable({Policy = policy, Options = options, Deps = deps, OnSelected = onSelected,
        Running = false, NextScan = 0, OpenGroups = 0, LastError = nil, History = {},
        _attempts = setmetatable({}, {__mode = "k"})}, NativeUI)
end

function NativeUI:_upvalues(fn)
    if type(fn) ~= "function" or type(self.Deps.GetUpvalues) ~= "function" then return {} end
    local ok, values = pcall(self.Deps.GetUpvalues, fn)
    return ok and type(values) == "table" and values or {}
end

function NativeUI:_context(props)
    for _, value in pairs(self:_upvalues(props.onClose)) do
        if type(value) == "table" and type(value.buffs) == "table" and type(value.onClose) == "function" then
            for _, thread in pairs(self:_upvalues(value.onClose)) do
                if type(thread) == "thread" and coroutine.status(thread) == "suspended" then return value end
            end
        end
    end
end

function NativeUI:_card(button)
    local ok, connections = pcall(self.Deps.GetConnections, button.Activated)
    if not ok or type(connections) ~= "table" then return end
    for index, connection in ipairs(connections) do
        if index > 8 then break end
        local accessible, callback = pcall(function() return connection.Function end)
        if accessible and type(callback) == "function" then
            for _, manager in pairs(self:_upvalues(callback)) do
                if type(manager) == "table" and manager._instance == button and type(manager._listeners) == "table"
                    and (manager._status == nil or manager._status == "Enabled") then
                    local handler = manager._listeners.Activated
                    for _, props in pairs(self:_upvalues(handler)) do
                        if type(props) == "table" and type(props.buffName) == "string" and type(props.onClose) == "function"
                            and not props.nonSelectable and type(props.cardInstanceRef) == "table"
                            and props.cardInstanceRef.current == button then
                            local context = self:_context(props)
                            if context then return props, handler, context end
                        end
                    end
                end
            end
        end
    end
end

function NativeUI:ReadGroups()
    if type(self.Deps.GetConnections) ~= "function" or type(self.Deps.GetUpvalues) ~= "function" then return {} end
    local player = self.Deps.Players and self.Deps.Players.LocalPlayer
    local gui = player and player:FindFirstChild("PlayerGui")
    if not gui then return {} end
    local groups, byContext, screens = {}, {}, 0
    for _, screen in ipairs(gui:GetChildren()) do
        if screen:IsA("ScreenGui") and screen.Enabled and (screen.Name == "ScreenGui" or screen.Name == "BuffSelectorMenu") then
            screens += 1
            if screens > 160 then break end
            for index, button in ipairs(screen:GetDescendants()) do
                if index > 400 then break end
                if button:IsA("TextButton") and button.Visible and button:FindFirstChild("DisplayName")
                    and button:FindFirstChild("BuffDescription") then
                    local props, handler, context = self:_card(button)
                    if context then
                        local group = byContext[context]
                        if not group then
                            group = {Context = context, Offers = context.buffs, Cards = {}}
                            byContext[context] = group
                            table.insert(groups, group)
                        end
                        table.insert(group.Cards, {Props = props, Handler = handler, Button = button})
                    end
                end
            end
        end
    end
    return groups
end

function NativeUI:_callNative(handler)
    local getIdentity, setIdentity = self.Deps.GetThreadIdentity, self.Deps.SetThreadIdentity
    if type(getIdentity) ~= "function" or type(setIdentity) ~= "function" then return handler() end
    local readable, original = pcall(getIdentity)
    if not readable or type(original) ~= "number" then error("native-identity-read-failed", 0) end
    -- The game's chooser requires normal ModuleScripts for its sound/cleanup path.
    -- Invoke it as a game script, then restore this owned selection task's identity.
    local switched, problem = pcall(setIdentity, 2)
    if not switched then error("native-identity-switch-failed: " .. tostring(problem), 0) end
    local result = table.pack(pcall(handler))
    local restored, restoreError = pcall(setIdentity, original)
    if not result[1] then error(result[2], 0) end
    if not restored then error("native-identity-restore-failed: " .. tostring(restoreError), 0) end
    return table.unpack(result, 2, result.n)
end

function NativeUI:Step()
    if not self.Running or self.Deps.Clock() < self.NextScan then return end
    self.NextScan = self.Deps.Clock() + 0.3
    local ok, groups = pcall(self.ReadGroups, self)
    if not ok then self.LastError = tostring(groups); return end
    self.OpenGroups = #groups
    if self.Options.Enabled == false or self._job then return end
    -- Resolve one native prompt at a time, beginning with the last rendered group.
    for index = #groups, 1, -1 do
        local group = groups[index]
        local state = self._attempts[group.Context]
        if not state then state = {Count = 0, NextAt = 0}; self._attempts[group.Context] = state end
        if state.Count < 6 and self.Deps.Clock() >= state.NextAt then
            local id, offer, reason = self.Policy.Choose(group.Offers, self.Options.Definitions, self.Options)
            if id then
                for _, card in ipairs(group.Cards) do
                    if card.Props.buffName == id and card.Props.newValue == offer.newValue
                        and (card.Props.oldValue or 0) == (offer.oldValue or 0) then
                        state.Count += 1
                        state.NextAt = self.Deps.Clock() + 0.8
                        local job = {Valid = true, Started = self.Deps.Clock()}
                        self._job = job
                        job.Thread = self.Deps.Task.spawn(function()
                            if not job.Valid or not self.Running or self.Options.Enabled == false or not card.Button.Parent then
                                if self._job == job then self._job = nil end
                                return
                            end
                            self.LastSelectedId = id
                            table.insert(self.History, {Id = id, At = self.Deps.Clock()})
                            if #self.History > 12 then table.remove(self.History, 1) end
                            if self.OnSelected then pcall(self.OnSelected, id, offer, reason) end
                            -- Let the native handler finish its animation, resume InvokeClient and clean its portals.
                            -- Cancelling it after dispatch could permanently lock the native selection debounce.
                            local success, problem = pcall(self._callNative, self, card.Handler)
                            if self.Running and job.Valid then self.LastError = not success and tostring(problem) or nil end
                            if self._job == job then self._job = nil end
                        end)
                        return
                    end
                end
            end
        end
    end
end

function NativeUI:GetStatus()
    return {Available = type(self.Deps.GetConnections) == "function" and type(self.Deps.GetUpvalues) == "function",
        OpenGroups = self.OpenGroups, Pending = self._job ~= nil, LastSelectedId = self.LastSelectedId, LastError = self.LastError,
        History = table.clone(self.History)}
end
function NativeUI:IsOpen() return self.Running and (self.OpenGroups > 0 or self._job ~= nil) end
function NativeUI:Start() self.Running = true end
function NativeUI:Stop()
    self.Running = false
    if self._job then self._job.Valid = false; self._job = nil end
    self.OpenGroups = 0
    self._attempts = setmetatable({}, {__mode = "k"})
end
NativeUI.Destroy = NativeUI.Stop
return NativeUI

end)()
DungeonModules.CardSelector = (function()
-- Owns the client response to DungeonShared.BuffSelector. No InvokeServer guessing.
local Selector = {}
Selector.__index = Selector

function Selector.new(policy, options, deps)
    options = table.clone(options or {})
    if options.NoUsefulCard == nil then options.NoUsefulCard = "first-offered" end
    return setmetatable({Policy = policy, Options = options, Deps = deps,
        Running = false, Status = {Phase = "stopped"}, LastSelection = nil,
        _binding = nil, _replicator = nil, _replicationConnection = nil}, Selector)
end

function Selector:_status(phase, detail)
    self.Status = {Phase = phase, Detail = detail}
end

function Selector:_getCallback(remote)
    local ok, callback = pcall(self.Deps.GetCallback, remote, "OnClientInvoke")
    return ok, callback
end

function Selector:AttachNativeUI(module)
    if self.NativeUI then self.NativeUI:Stop() end
    self.NativeUI = module.new(self.Policy, self.Options, self.Deps, function(id, offer, reason)
        if self.Running then self:_recordSelection(id, offer, reason, "native-ui") end
    end)
    if self.Running then self.NativeUI:Start() end
end

function Selector:_recordSelection(id, offer, reason, source)
    local selection = {Id = id, OldValue = offer.oldValue, NewValue = offer.newValue,
        RequestedAt = self.Deps.Clock(), Confirmed = false, Reason = reason, Source = source}
    self.LastSelection, self._pending = selection, selection
    self:_status(source == "native-ui" and "native-ui-selection" or "returned-card", id)
    if self.Options.OnSelected then pcall(self.Options.OnSelected, id, offer, reason) end
end

function Selector:_stepNativeUI()
    if self.NativeUI then
        self.NativeUI:Step()
        self._nativeUiOpen = self._nativeUiOpen or self.NativeUI:IsOpen()
    end
end

function Selector:_unbind()
    local binding = self._binding
    self._binding = nil
    if binding then
        local ok, current = self:_getCallback(binding.Remote)
        if ok and current == binding.Wrapper then
            pcall(function() binding.Remote.OnClientInvoke = binding.Original end)
        end
    end
end

function Selector:_bind(remote)
    local ok, previous = self:_getCallback(remote)
    if not ok then self:_status("callback-reader-unavailable"); return end
    if self._binding and self._binding.Remote == remote and previous == self._binding.Wrapper then return end
    self:_unbind()
    if type(previous) ~= "function" then self:_status("waiting-native-handler"); return end
    local binding = {Remote = remote, Original = previous}
    binding.Wrapper = function(offers, ...)
        if not self.Running or self.Options.Enabled == false or self._binding ~= binding then
            return previous(offers, ...)
        end
        local success, id, offer, reason = pcall(self.Policy.Choose, offers, self.Options.Definitions, self.Options)
        if not success or not id then
            self._nativePending = (self._nativePending or 0) + 1
            self:_status("native-choice-required", success and reason or tostring(id))
            local result = table.pack(pcall(previous, offers, ...))
            self._nativePending = math.max(0, (self._nativePending or 1) - 1)
            if not result[1] then error(result[2]) end
            return table.unpack(result, 2, result.n)
        end
        self:_recordSelection(id, offer, reason, "remote")
        -- Native Interface returns this exact buffName to the server's InvokeClient.
        return id
    end
    local assigned, message = pcall(function() remote.OnClientInvoke = binding.Wrapper end)
    if assigned then
        self._binding = binding
        self:_status("listening")
    else
        self:_status("bind-failed", tostring(message))
    end
end

function Selector:_watchReplication(remote)
    if self._replicator == remote then return end
    if self._replicationConnection then self._replicationConnection:Disconnect() end
    self._replicator, self._replicationConnection = remote, nil
    if remote then
        self._replicationConnection = remote.OnClientEvent:Connect(function(buffs)
            if not self.Running then return end
            local pending = self._pending
            local value = type(buffs) == "table" and pending and buffs[pending.Id]
            if pending and type(value) == "number" and value >= pending.NewValue then
                pending.Confirmed, pending.ConfirmedAt = true, self.Deps.Clock()
                self._pending = nil
                self:_status("confirmed", pending.Id)
            end
        end)
    end
end

function Selector:Step()
    if not self.Running then return end
    self._nativeUiOpen = false
    if self.Deps.HasOpenChooser then
        local ok, open = pcall(self.Deps.HasOpenChooser)
        self._nativeUiOpen = ok and open == true
    end
    if self.Options.Enabled == false then
        self:_unbind()
        self:_watchReplication(nil)
        self._pending = nil
        self:_stepNativeUI()
        self:_status("disabled")
        return
    end
    local shared = self.Deps.ReplicatedStorage:FindFirstChild("DungeonShared")
    local remote = shared and shared:FindFirstChild("BuffSelector")
    local replication = shared and shared:FindFirstChild("BuffReplicator")
    if replication and not replication:IsA("RemoteEvent") then replication = nil end
    self:_watchReplication(replication)
    if remote and remote:IsA("RemoteFunction") then
        self:_bind(remote)
    else
        self:_unbind()
        self:_status("waiting-remote")
    end
    self:_stepNativeUI()
    if self._pending and self.Deps.Clock() - self._pending.RequestedAt > (self.Options.AckTimeout or 6) then
        self:_status("confirmation-timeout", self._pending.Id)
        self._pending = nil
    end
end

function Selector:IsChoosing()
    return self.Running and (self._nativeUiOpen == true or (self._nativePending or 0) > 0
        or (self.Options.Enabled ~= false and self._pending ~= nil))
end

function Selector:Start()
    if self.Running then return self end
    self.Running = true
    if self.NativeUI then self.NativeUI:Start() end
    self:Step()
    return self
end

function Selector:Stop()
    self.Running = false
    if self.NativeUI then self.NativeUI:Stop() end
    self:_unbind()
    self:_watchReplication(nil)
    self._pending = nil
    self._nativeUiOpen = false
    self:_status("stopped")
end

Selector.Destroy = Selector.Stop
return Selector

end)()
DungeonModules.RoomNavigator = (function()
-- Reads the local explorer's FloorId and that floor's live exit trigger.
local Navigator = {}
Navigator.__index = Navigator

function Navigator.new(options, deps)
    return setmetatable({Options = options or {}, Deps = deps, Running = false,
        Status = {Phase = "stopped"}, _route = nil, _serial = 0}, Navigator)
end

function Navigator:_status(phase, snapshot, detail)
    self.Status = {Phase = phase, FloorId = snapshot and snapshot.FloorId, Detail = detail}
end

function Navigator:ReadState()
    if self.Deps.ReadState then return self.Deps.ReadState() end
    local deps = self.Deps
    if deps.Workspace:GetAttribute("MAP") ~= "Dungeons" then return nil, "waiting-dungeon" end
    local player = deps.Players.LocalPlayer
    if not player or player:GetAttribute("LoadComplete") == false then return nil, "waiting-player" end
    local guid = player:GetAttribute("ExplorerGUID")
    if type(guid) ~= "string" or guid == "" then return nil, "waiting-explorer" end
    local replicas = deps.ReplicatedStorage:FindFirstChild("DungeonReplicationObjects")
    local dungeon, explorer
    if replicas then
        for _, candidate in ipairs(replicas:GetChildren()) do
            local explorers = candidate:FindFirstChild("Explorers")
            local found = explorers and explorers:FindFirstChild(guid)
            local playerRef = found and found:FindFirstChild("Player")
            if found and playerRef and playerRef:IsA("ObjectValue") and playerRef.Value == player then
                dungeon, explorer = candidate, found
                break
            end
        end
    end
    if not explorer then return nil, "waiting-explorer-replication" end
    local floor = explorer:GetAttribute("FloorId")
    if type(floor) ~= "number" or floor ~= floor or floor < 1 or floor % 1 ~= 0 then
        return nil, "waiting-floor-id"
    end
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root or not humanoid or humanoid.Health <= 0 then return nil, "waiting-character" end
    local state = {Dungeon = dungeon, Explorer = explorer, FloorId = floor,
        Character = character, Humanoid = humanoid, Root = root}
    local map = deps.Workspace:FindFirstChild("Map")
    local floors = map and map:FindFirstChild("Dungeon")
    local worldFloor = floors and floors:FindFirstChild(tostring(floor))
    local teleporter = worldFloor and worldFloor:FindFirstChild("ExitTeleporter")
    local exit = teleporter and teleporter:FindFirstChild("Root")
    if not exit or not exit:IsA("BasePart") or not deps.CollectionService:HasTag(exit, "DungeonProceedWaypoint") then
        return state, "waiting-exit-streaming"
    end
    state.Exit = exit
    state.Ready = exit.CanTouch and exit:FindFirstChildOfClass("TouchTransmitter") ~= nil
    -- Distance to the trigger volume, not its elevated center (the live gate is ~30 studs tall).
    local localPosition = exit.CFrame:PointToObjectSpace(root.Position)
    local half = exit.Size * 0.5
    local nearest = Vector3.new(math.clamp(localPosition.X, -half.X, half.X),
        math.clamp(localPosition.Y, -half.Y, half.Y), math.clamp(localPosition.Z, -half.Z, half.Z))
    state.Distance = (localPosition - nearest).Magnitude
    local goalLocal = Vector3.new(0, math.clamp(localPosition.Y, -half.Y + 1, half.Y - 1), 0)
    state.Goal = exit.CFrame:PointToWorldSpace(goalLocal)
    state.GoalCFrame = CFrame.new(state.Goal)
    return state, state.Ready and "ready" or "waiting-exit-enabled"
end

function Navigator:_cancelPath()
    local job = self._pathJob
    self._pathJob = nil
    if job then
        job.Valid = false
        if job.Thread and self.Deps.Task.cancel then pcall(self.Deps.Task.cancel, job.Thread) end
        if job.Path then pcall(function() job.Path:Destroy() end) end
    end
end

function Navigator:_releaseMovement()
    if not self._moving then return end
    self._moving = false
    if self.Options.CancelMove then
        pcall(self.Options.CancelMove)
    elseif not self.Options.MoveTo and self._route then
        local previous = self._route.Snapshot
        pcall(function() previous.Humanoid:MoveTo(previous.Root.Position) end)
    end
end

function Navigator:_reset()
    self:_releaseMovement()
    self:_cancelPath()
    self._serial += 1
    self._route = nil
end

function Navigator:_requestPath(snapshot)
    if self._pathJob or not self.Deps.PathfindingService then return end
    local route, serial = self._route, self._serial
    local job = {Valid = true, Started = self.Deps.Clock()}
    self._pathJob = job
    job.Thread = self.Deps.Task.spawn(function()
        local path
        local ok, waypoints = pcall(function()
            path = self.Deps.PathfindingService:CreatePath({AgentRadius = 2, AgentHeight = 5,
                AgentCanJump = true, WaypointSpacing = 6})
            job.Path = path
            path:ComputeAsync(snapshot.Root.Position, snapshot.Goal)
            if path.Status ~= self.Deps.PathSuccess then return nil end
            return path:GetWaypoints()
        end)
        if path then pcall(function() path:Destroy() end); job.Path = nil end
        if not job.Valid or self._pathJob ~= job or self._serial ~= serial or self._route ~= route then return end
        self._pathJob = nil
        if ok and type(waypoints) == "table" and #waypoints > 0 then
            route.Waypoints, route.WaypointIndex = waypoints, 1
        end
        route.LastPathAt = self.Deps.Clock()
    end)
end

function Navigator:Step(blocked)
    if not self.Running then return end
    if self.Options.Enabled == false or blocked then
        self:_reset()
        self:_status(self.Options.Enabled == false and "disabled" or "waiting-card")
        return
    end
    local snapshot, phase = self:ReadState()
    if snapshot then
        local last = self._lastObserved
        if last and last.Explorer == snapshot.Explorer and last.FloorId ~= snapshot.FloorId then
            self.LastTransition = {From = last.FloorId, To = snapshot.FloorId, At = self.Deps.Clock()}
            if self.Options.OnFloorChanged then pcall(self.Options.OnFloorChanged, snapshot.FloorId, last.FloorId) end
        end
        self._lastObserved = {Explorer = snapshot.Explorer, FloorId = snapshot.FloorId}
    end
    if not snapshot or not snapshot.Ready then
        self:_reset()
        self:_status(phase or "waiting-exit-enabled", snapshot)
        return
    end
    local route = self._route
    if not route or route.Explorer ~= snapshot.Explorer or route.FloorId ~= snapshot.FloorId
        or route.Character ~= snapshot.Character or route.Exit ~= snapshot.Exit then
        self:_reset()
        route = {Explorer = snapshot.Explorer, FloorId = snapshot.FloorId, Character = snapshot.Character,
            Exit = snapshot.Exit, Snapshot = snapshot, Started = self.Deps.Clock(),
            LastProgressAt = self.Deps.Clock(), BestDistance = snapshot.Distance, Attempts = 0}
        self._route = route
    end
    route.Snapshot = snapshot
    local now = self.Deps.Clock()
    if self.Options.CanMove then
        local ok, allowed = pcall(self.Options.CanMove, snapshot)
        if not ok or not allowed then
            self:_releaseMovement()
            self:_cancelPath()
            route.Started, route.LastProgressAt = now, now
            self:_status("external-movement-owner", snapshot)
            return
        end
    end
    if snapshot.Root.Anchored then
        self:_releaseMovement()
        self:_cancelPath()
        route.Started, route.LastProgressAt = now, now
        self:_status("character-anchored", snapshot)
        return
    end
    if route.Attempts >= (self.Options.MaxTouchAttempts or 3) and route.LastTouch
        and now - route.LastTouch >= (self.Options.TransitionTimeout or 8) then
        self:_releaseMovement()
        self:_status("transition-not-confirmed", snapshot)
        return
    end
    if now - route.Started > (self.Options.MoveTimeout or 90) then
        self:_releaseMovement()
        self:_cancelPath()
        self:_status("movement-timeout", snapshot)
        return
    end
    if snapshot.Distance <= (self.Options.TouchDistance or 3) then
        self:_cancelPath()
        if route.Attempts < (self.Options.MaxTouchAttempts or 3)
            and (not route.LastTouch or now - route.LastTouch >= (self.Options.TransitionTimeout or 8)) then
            route.Attempts += 1
            route.LastTouch = now
            if self.Deps.FireTouch then
                -- Begin/end are balanced, and only the current, nearby, enabled gate is touched.
                pcall(self.Deps.FireTouch, snapshot.Root, snapshot.Exit, 0)
                pcall(self.Deps.FireTouch, snapshot.Root, snapshot.Exit, 1)
            elseif not self.Options.MoveTo then
                pcall(function() snapshot.Humanoid:MoveTo(snapshot.Goal) end)
            end
        end
        self:_status("awaiting-floor-change", snapshot)
        return
    end
    if snapshot.Distance < route.BestDistance - 1 then
        route.BestDistance, route.LastProgressAt = snapshot.Distance, now
    end
    if self._pathJob and now - self._pathJob.Started > (self.Options.PathTimeout or 5) then
        self:_cancelPath()
        route.LastPathAt = now
    end
    if not self.Options.MoveTo and now - route.LastProgressAt > 2
        and (not route.LastPathAt or now - route.LastPathAt > 3) then self:_requestPath(snapshot) end
    if self.Options.MoveTo then
        if not route.LastMoveAt or now - route.LastMoveAt >= (self.Options.MoveInterval or 0.2) then
            route.LastMoveAt = now
            -- Adapter must be non-yielding: set/update your movement controller's destination.
            local ok, accepted = pcall(self.Options.MoveTo, snapshot.GoalCFrame, snapshot)
            if not self.Running or self._route ~= route then return end
            if not ok or accepted == false then
                self:_releaseMovement()
                self:_status("movement-adapter-rejected", snapshot, not ok and tostring(accepted) or nil)
                return
            end
            self._moving = true
        end
    else
        local destination = snapshot.Goal
        if route.Waypoints then
            local waypoint = route.Waypoints[route.WaypointIndex]
            while waypoint and (snapshot.Root.Position - waypoint.Position).Magnitude < 4 do
                route.WaypointIndex += 1
                waypoint = route.Waypoints[route.WaypointIndex]
            end
            if waypoint then
                destination = waypoint.Position
                if waypoint.Action == self.Deps.PathJump then snapshot.Humanoid.Jump = true end
            else
                route.Waypoints = nil
            end
        end
        if not route.LastMoveAt or now - route.LastMoveAt >= 0.5 then
            route.LastMoveAt = now
            snapshot.Humanoid:MoveTo(destination)
            self._moving = true
        end
    end
    self:_status("moving-to-exit", snapshot)
end

function Navigator:IsMoving() return self.Running and self._moving == true end
function Navigator:Retry() self:_reset() end
function Navigator:Start() self.Running = true; return self end
function Navigator:Stop() self.Running = false; self:_reset(); self._lastObserved = nil; self:_status("stopped") end
Navigator.Destroy = Navigator.Stop
return Navigator

end)()
DungeonModules.WorldPropCombat = (function()
-- Floor 10 Shrines and floor 15 vents use skills against replicated prop health.
-- Keep the same live object until HP is zero (or the active vent Speed stops).
local Props = {}
Props.__index = Props
local function number(value, default, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value then return default end
    return math.clamp(value, minimum, maximum)
end
function Props.new(options, deps)
    return setmetatable({Options = options or {}, Deps = deps, Running = false,
        Status = {Phase = "stopped"}, _records = setmetatable({}, {__mode = "k"})}, Props)
end
function Props:_cancelJob()
    local job = self._job
    self._job = nil
    if job then
        job.Valid = false
        if self.Deps.CancelPropSkill then pcall(self.Deps.CancelPropSkill, job) end
        if job.Thread and self.Deps.Task.cancel then pcall(self.Deps.Task.cancel, job.Thread) end
    end
end
function Props:Release(reason, confirmed)
    local target = self.Target
    if self._job and self._job.Casting then self._quietUntil = self.Deps.Clock()+.65 end
    self.Target = nil
    self:_cancelJob()
    if target then
        local retryDelay = number(self.Options.RetryDelay, 15, 1, 120)
        if target.Kind == "vent" then retryDelay = number(self.Options.VentRetryDelay, 2, 0.5, 30) end
        self._records[target.Instance] = {NextAt = self.Deps.Clock() + retryDelay,
            Part = target.Part, Signature = target.Signature, Confirmed = confirmed == true}
        self.LastResult = {Kind = target.Kind, FloorId = target.FloorId, Outcome = reason,
            NativeCalls = target.NativeCalls, SkillCasts = target.SkillCasts, SkillKey = target.LastSkillKey, HitboxId = target.HitboxId,
            SkillTool = target.LastSkillTool, SkillKind = target.LastSkillKind,
            Confirmed = confirmed == true, At = self.Deps.Clock()}
    end
end
function Props:_floor(state)
    local map = self.Deps.Workspace:FindFirstChild("Map")
    local floors = map and map:FindFirstChild("Dungeon")
    return floors and floors:FindFirstChild(tostring(state.FloorId))
end
function Props:_bossStalled(state, kind)
    local expected = kind == "shrine" and "Kitsune Lord" or "Gas Knight"
    local enemies = self.Deps.Workspace:FindFirstChild("Enemies")
    local boss = enemies and enemies:FindFirstChild(expected)
    local humanoid = boss and boss:FindFirstChildOfClass("Humanoid")
    local root = boss and boss:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root or (root.Position - state.Root.Position).Magnitude > 2500 then
        self._boss = nil
        return false
    end
    local now = self.Deps.Clock()
    if self._boss ~= boss or self._bossHp ~= humanoid.Health then
        self._boss, self._bossHp, self._bossChangedAt = boss, humanoid.Health, now
    end
    return now - self._bossChangedAt >= number(self.Options.StallDelay, 4, 1, 30)
end
local function isPart(part)
    return part and part:IsA("BasePart")
end
local function findVentPart(object)
    -- This is only an association anchor. Some live vents have Cylinder.016
    -- detached into Props and all remaining visual parts have CanQuery=false.
    -- Actual damage/aim still goes through the matched enemy placeholder.
    for _, name in ipairs({"Cylinder.016", "Cylinder.015", "Cylinder.009"}) do
        local part = object:FindFirstChild(name)
        if isPart(part) then return part end
    end
    if object:IsA("BasePart") then return object end
    if object:IsA("Model") and isPart(object.PrimaryPart) then return object.PrimaryPart end
    for _, child in ipairs(object:GetChildren()) do
        if isPart(child) then return child end
    end
    for _, descendant in ipairs(object:GetDescendants()) do
        if isPart(descendant) then return descendant end
    end
end
function Props:_propHitbox(part, object, kind)
    local enemies = self.Deps.Workspace:FindFirstChild("Enemies")
    local selected, root, health, distance
    local anchors = {part.Position}
    local shrineBounds, shrineSize
    if kind == "shrine" and object then
        if object:IsA("Model") then
            if object.PrimaryPart then anchors[#anchors+1]=object.PrimaryPart.Position end
            if object.GetPivot then anchors[#anchors+1]=object:GetPivot().Position end
            if object.GetBoundingBox then
                shrineBounds, shrineSize = object:GetBoundingBox()
                anchors[#anchors+1]=shrineBounds.Position
            end
        end
        for _, child in ipairs(object:GetDescendants()) do
            if #anchors >= 32 then break end
            if child:IsA("BasePart") then anchors[#anchors+1]=child.Position end
        end
    end
    if enemies then
        for _, model in ipairs(enemies:GetChildren()) do
            local hit = model.Name == "PropHitboxPlaceholder" and model:FindFirstChild("HumanoidRootPart")
            local hp = hit and model:FindFirstChildOfClass("Humanoid")
            if hit and hp and hp.Health > 0 then
                local d = math.huge
                for _, anchor in ipairs(anchors) do d=math.min(d,(hit.Position-anchor).Magnitude) end
                -- Live floor 10 health roots sit about 25 studs above the neon
                -- pivot. Match against the stone's volume, not only its center.
                if shrineBounds then
                    local point = shrineBounds:PointToObjectSpace(hit.Position)
                    local x = math.max(math.abs(point.X)-shrineSize.X*.5,0)
                    local y = math.max(math.abs(point.Y)-shrineSize.Y*.5,0)
                    local z = math.max(math.abs(point.Z)-shrineSize.Z*.5,0)
                    d = math.min(d,math.sqrt(x*x+y*y+z*z))
                end
                if d <= 12 and (not distance or d < distance) then selected, root, health, distance = model, hit, hp, d end
            end
        end
    end
    return selected, root, health
end
function Props:Completion(target)
    if target.Health and target.Health.Health <= 0 then return "prop-health-zero" end
    if target.Kind ~= "vent" then return nil end
    local speed = tonumber(target.Instance:GetAttribute("Speed"))
    if target.StartSpeed and target.StartSpeed > .05 and speed and speed <= .05 then return "vent-stopped" end
end
function Props:GetApproach(target)
    if not target.UseSkill then return nil end
    local part = target.Part
    local normal = part.CFrame.RightVector
    local halfThickness = part.Size.X*.5
    -- A short Shrine's vertical thickness is not a valid face to stand below.
    if part.Size.Y*.5 < halfThickness and (target.Kind ~= "shrine" or math.abs(part.CFrame.UpVector.Y)<.7) then
        normal, halfThickness = part.CFrame.UpVector, part.Size.Y*.5
    end
    if part.Size.Z*.5 < halfThickness then normal, halfThickness = part.CFrame.LookVector, part.Size.Z*.5 end
    local bounds = target.Floor:GetAttribute("BoundingCF")
    local center = typeof(bounds) == "CFrame" and bounds.Position or target.Character:FindFirstChild("HumanoidRootPart").Position
    if (center-part.Position):Dot(normal) < 0 then normal = -normal end
    return part.Position + normal * (halfThickness + 8)
end
function Props:ReadCandidates(state, kind)
    if self.Deps.ReadPropCandidates then return self.Deps.ReadPropCandidates(state, kind) end
    local floor = self:_floor(state)
    local container = floor and floor:FindFirstChild("Props")
    if not container then return {} end
    local collection = self.Deps.CollectionService
    local out, used = {}, {}
    for _, object in ipairs(container:GetChildren()) do
        local matches = kind == "shrine" and collection:HasTag(object, "DungeonProp_KitsuneShrine")
            or kind == "vent" and (collection:HasTag(object, "DungeonProp_GasVentProp2") or collection:HasTag(object, "GasVentProp"))
        if matches and kind == "vent" then
            local speed = tonumber(object:GetAttribute("Speed"))
            if not object:IsA("Model") or not speed or speed <= 0.05 then matches = false end
        end
        if matches and #out < 32 then
            local part
            if kind == "vent" then
                part = findVentPart(object)
            else
                part = kind == "shrine" and object:FindFirstChild("NeonShrinePart") or object:FindFirstChild("Cylinder.009")
                if not part and object:IsA("Model") then part = object.PrimaryPart end
                if not part then
                    for _, descendant in ipairs(object:GetDescendants()) do
                        if descendant:IsA("BasePart") then part = descendant; break end
                    end
                end
                if not part and object:IsA("BasePart") then part = object end
            end
            local surface, hitbox, health = part
            if surface then
                hitbox, part, health = self:_propHitbox(surface, object, kind)
            end
            if hitbox and not used[hitbox] and part and part:IsA("BasePart") then
                used[hitbox]=true
                out[#out + 1] = {Instance = object, Part = part, Floor = floor, VerifiedHitbox = false, VerifiedDamageable = true,
                    SurfacePart = surface, Hitbox = hitbox, Health = health, UseSkill = true,
                    StartSpeed = tonumber(object:GetAttribute("Speed")), HitboxId = hitbox and hitbox:GetAttribute("ID"),
                    GameTaggedProp = matches == true,
                    Signature = tostring(object:GetAttribute("KitsuneMarkActive")) .. ":" .. tostring(object:GetAttribute("Speed")),
                    Distance = (part.Position - state.Root.Position).Magnitude}
            end
        end
    end
    return out
end
function Props:IsValid(target, state)
    if not (target and state and state.FloorId == target.FloorId and state.Character == target.Character
        and state.Explorer == target.Explorer and target.Floor.Parent ~= nil
        and target.Instance:IsDescendantOf(target.Floor) and target.Part.Parent ~= nil
        and (target.UseSkill and target.Hitbox and target.Part:IsDescendantOf(target.Hitbox)
            or target.Part == target.Instance or target.Part:IsDescendantOf(target.Instance))
        and (not target.VerifiedHitbox or self.Deps.CollectionService:HasTag(target.Part, "M1HitRegistry"))) then
        return false
    end
    if target.Kind == "vent" and target.GameTaggedProp then
        local speed = tonumber(target.Instance:GetAttribute("Speed"))
        if speed ~= nil and speed <= 0.05 then return false end
        local collection = self.Deps.CollectionService
        if not collection:HasTag(target.Instance, "DungeonProp_GasVentProp2")
            and not collection:HasTag(target.Instance, "GasVentProp") then return false end
    end
    if target.Kind == "shrine" and not self.Deps.CollectionService:HasTag(target.Instance,"DungeonProp_KitsuneShrine") then return false end
    if target.UseSkill and (not target.Hitbox or target.Hitbox.Parent ~= self.Deps.Workspace:FindFirstChild("Enemies")
        or not target.Health or target.Health.Health <= 0) then return false end
    return true
end
function Props:Step(blocked)
    if not self.Running then return end
    local state, phase = self.Deps.ReadPropRoom()
    if self.Options.Enabled == false or blocked or not state or state.Ready then
        self:Release(state and state.Ready and "room-open" or "interrupted")
        self.Status = {Phase = self.Options.Enabled == false and "disabled" or (blocked and "room-transition" or phase or "room-open")}
        return
    end
    local kind = state.FloorId == 10 and self.Options.Floor10 ~= false and "shrine"
        or state.FloorId == 15 and self.Options.Floor15 ~= false and "vent"
    if not kind then self:Release("other-floor"); self.Status = {Phase = "other-floor", FloorId = state.FloorId}; return end
    if self._floorId ~= state.FloorId or self._character ~= state.Character or self._explorer ~= state.Explorer then
        self:Release("room-changed")
        self._records = setmetatable({}, {__mode = "k"})
        self._floorId, self._character, self._explorer = state.FloorId, state.Character, state.Explorer
        self._boss, self._bossHp, self._bossChangedAt = nil, nil, nil
    end
    local now = self.Deps.Clock()
    local target = self.Target
    if target then
        local sameRoom = state.FloorId == target.FloorId and state.Character == target.Character and state.Explorer == target.Explorer
        local completed = sameRoom and self:Completion(target)
        local valid = self:IsValid(target,state)
        if valid then target.WaitingHitbox=false end
        if completed then self:Release(completed, true)
        elseif not valid then
            if target.UseSkill and sameRoom then
                self:_cancelJob()
                target.WaitingHitbox = true
                local model, part, health = self:_propHitbox(target.SurfacePart,target.Instance,target.Kind)
                if model then
                    target.Hitbox, target.Part, target.Health = model, part, health
                    target.HitboxId, target.WaitingHitbox, target.Goal = model:GetAttribute("ID"), false, nil
                end
            else self:Release("object-or-hitbox-ended") end
        elseif self._job and now - self._job.Started > (target.UseSkill and 8 or 2) then
            if target.UseSkill then self:_cancelJob(); self.LastError="skill-call-timeout"; self._nextAttack=now+.5
            else self:Release("native-call-timeout") end
        elseif not target.UseSkill and target.AttackStarted and now - target.AttackStarted >= number(self.Options.AttackSeconds, 1.8, 0.5, 5) then self:Release("attempt-unconfirmed")
        elseif not target.UseSkill and now - target.Started >= number(self.Options.MoveTimeout, 8, 2, 30) + (target.AttackStarted and 5 or 0) then self:Release("movement-timeout") end
        -- Return to normal combat for at least this host step after finishing an object.
        if not self.Target then self.Status = {Phase = "returning-to-boss", FloorId = state.FloorId}; return end
    elseif self:IsCoolingDown() then
        self.Status = {Phase="waiting-skill-end", FloorId=state.FloorId}
        return
    elseif not self._nextScan or now >= self._nextScan then
        self._nextScan = now + 0.3
        local candidates = self:ReadCandidates(state, kind)
        table.sort(candidates, function(a, b)
            if a.VerifiedHitbox ~= b.VerifiedHitbox then return a.VerifiedHitbox end
            return a.Distance < b.Distance
        end)
        for _, candidate in ipairs(candidates) do
            local record = self._records[candidate.Instance]
            local eligible = candidate.VerifiedDamageable == true
            local cooling = record and not record.Confirmed and now < record.NextAt and record.Part == candidate.Part and record.Signature == candidate.Signature
            if eligible and not cooling then
                candidate.Kind, candidate.FloorId, candidate.Character, candidate.Explorer = kind, state.FloorId, state.Character, state.Explorer
                candidate.Started, candidate.NativeCalls = now, 0
                self.Target = candidate
                break
            end
        end
    end
    target = self.Target
    self.Status = {Phase = target and (target.WaitingHitbox and "waiting-same-prop-hitbox" or target.AttackStarted and "attacking-object" or "moving-to-object")
        or "waiting-prop-hitbox", FloorId = state.FloorId, Kind = kind,
        VerifiedHitbox = target and target.VerifiedHitbox, NativeCalls = target and target.NativeCalls,
        SkillPhase = target and target.SkillPhase, SkillCasts = target and target.SkillCasts,
        HitboxId = target and target.HitboxId, PropHP = target and target.Health and target.Health.Health,
        SkillTool = target and target.LastSkillTool, SkillKind = target and target.LastSkillKind}
end
function Props:_native(tool)
    local getIdentity, setIdentity = self.Deps.GetThreadIdentity, self.Deps.SetThreadIdentity
    local original
    if type(getIdentity) == "function" and type(setIdentity) == "function" then
        original = getIdentity()
        assert(type(original) == "number", "native identity unavailable")
        setIdentity(2)
    end
    local result = table.pack(pcall(self.Deps.NativePropAttack, tool))
    if original then setIdentity(original) end
    if not result[1] then error(result[2], 0) end
    return table.unpack(result, 2, result.n)
end
function Props:TryAttack(tool, distance)
    local target, now = self.Target, self.Deps.Clock()
    if not self.Running or not target or not target.UseSkill and not tool or distance > 2.5 or self._job then return end
    if now < (self._nextAttack or 0) then return end
    self._nextAttack = now + 0.25
    target.AttackStarted = target.AttackStarted or now
    local job = {Valid = true, Started = now}
    self._job = job
    job.Thread = self.Deps.Task.spawn(function()
        if not job.Valid or not self.Running or self.Target ~= target or self.Options.Enabled == false
            or not self:IsValid(target, self.Deps.ReadPropRoom()) then
            if self._job == job then self._job = nil end
            return
        end
        local ok, result
        if target.UseSkill then
            ok, result = pcall(function()
                assert(self.Deps.NativePropSkill, "native skill adapter unavailable")
                return self.Deps.NativePropSkill(tool, target, job)
            end)
        else ok, result = pcall(self._native, self, tool) end
        if ok then
            if target.UseSkill then
                result = type(result)=="table" and result or {State="skill-input-unconfirmed"}
                target.SkillPhase = result.State
                if result.Key then target.LastSkillKey = result.Key end
                self._nextAttack = self.Deps.Clock()+number(result.Delay,.3,.1,5)
                if result.QuietFor then self._quietUntil = self.Deps.Clock()+number(result.QuietFor,.2,.1,2) end
            else
                target.NativeCalls += 1
                self._quietUntil = self.Deps.Clock() + number(result, 0.8, 0.1, 1.5)
            end
            self.LastError = nil
        else self.LastError = tostring(result) end
        if self._job == job then self._job = nil end
    end)
end
function Props:IsCasting()
    if self._job and self._job.Casting == true then return true end
    local target=self.Target
    local busy=target and target.UseSkill and target.Character:FindFirstChild("Busy")
    return busy ~= nil and busy ~= false and busy.Value == true
end
function Props:OwnsWeapon() return self.Running and self.Target ~= nil and self.Target.UseSkill == true end
function Props:IsCoolingDown() return self.Running and self._quietUntil ~= nil and self.Deps.Clock() < self._quietUntil end
function Props:GetStatus()
    local status = table.clone(self.Status)
    status.LastResult = self.LastResult and table.clone(self.LastResult)
    status.LastError = self.LastError
    return status
end
function Props:Start() self.Running = true end
function Props:Stop()
    self.Running = false
    self:Release("stopped")
    self._records = setmetatable({}, {__mode = "k"})
    self._boss, self._character, self._explorer, self._floorId = nil, nil, nil, nil
    self._nextScan, self._nextAttack, self._quietUntil = nil, nil, nil
    self.Status = {Phase = "stopped"}
end
Props.Destroy = Props.Stop
return Props
end)()
DungeonModules.PropSkillCaster = (function()
-- Rotates owned Melee/Fruit/Sword/Gun skills through normal input and native aim.
-- Props owns the job; cancellation must release keys before cancelling its coroutine.
local Caster = {}
Caster.__index = Caster
local kinds = {"Melee", "Fruit", "Sword", "Gun"}
local kindRank = {Melee=1, Fruit=2, Sword=3, Gun=4}
local function kindOf(tool)
    local kind = tool.ToolTip
    if not kindRank[kind] then kind = tool:GetAttribute("WeaponType") end
    if tool.ToolTip == "Blox Fruit" or kind == "Blox Fruit" or kind == "Demon Fruit" then kind="Fruit" end
    return kindRank[kind] and kind or nil
end
function Caster.new(options, deps)
    return setmetatable({Options = options or {}, Deps = deps, NextKind=1,
        Recent = setmetatable({}, {__mode="k"}), ProbeAfter=setmetatable({}, {__mode="k"})}, Caster)
end
function Caster:Cancel(job)
    if job and job.SkillCleanup then job.SkillCleanup() end
end
function Caster:_moveData(tool, key, gui)
    local movesets = gui and gui:FindFirstChild("MovesetModules")
    local modules = movesets and movesets:FindFirstChild(tool.Name)
    if not modules then return nil end
    local awake = tool:FindFirstChild("AwakenedMoves")
    awake = awake and awake:FindFirstChild(key) ~= nil
    local bindings = modules:FindFirstChild("Bindings")
    local binding = bindings and bindings:FindFirstChild(key)
    local sets = {}
    if binding then
        local setName = binding:GetAttribute(awake and "AwakenedMoveset" or "Moveset")
        local moveName = binding:GetAttribute(awake and "AwakenedMove" or "Move") or key
        local set = setName and modules:FindFirstChild(setName)
        if set then sets[1]={Set=set,Key=moveName} end
    end
    if #sets == 0 then
        for _, set in ipairs(modules:GetChildren()) do
            local isAwake = set.Name:match("%(Awakened%)$") ~= nil
            if isAwake == (awake == true) then sets[#sets+1]={Set=set,Key=key} end
        end
    end
    for _, entry in ipairs(sets) do
        local move = entry.Set:FindFirstChild(entry.Key)
        local shared = move and move:FindFirstChild("Shared")
        if shared then
            local ok, data = pcall(self.Deps.RequireModule or require,shared)
            if ok and type(data)=="table" then return data end
        end
    end
end
function Caster:_readyKey(tool)
    local player = self.Deps.Players.LocalPlayer
    local gui = player and player:FindFirstChild("PlayerGui")
    local main = gui and gui:FindFirstChild("Main")
    local skills = main and main:FindFirstChild("Skills")
    local panel = skills and skills:FindFirstChild(tool.Name)
    local mastery = tonumber(tool:GetAttribute("Level"))
    local energy = player and player.Character and player.Character:FindFirstChild("Energy")
    energy = energy and tonumber(energy.Value)
    local now = self.Deps.Clock()
    local recent = self.Recent[tool] or {}
    local pendingUI, usable, knownMetadata = false, false, false
    for _, key in ipairs({"X", "Z", "C"}) do
        local frame = panel and panel:FindFirstChild(key)
        local cooldown = frame and frame:FindFirstChild("Cooldown")
        local data = self:_moveData(tool,key,gui)
        if data then knownMetadata=true end
        local required, cost = data and tonumber(data.Lvl), data and tonumber(data.Cost)
        local unlocked = (data ~= nil or frame ~= nil) and (not required or mastery and mastery>=required)
        local enoughEnergy = not cost or not energy or energy>=cost
        if unlocked and enoughEnergy then usable=true end
        if unlocked and enoughEnergy and now>=(recent[key] or 0) and not frame then pendingUI=true end
        if unlocked and enoughEnergy and frame and frame:IsA("GuiObject") and frame.Visible and cooldown and cooldown:IsA("GuiObject")
            and cooldown.Size.X.Scale <= 0.01 and math.abs(cooldown.Size.X.Offset) <= 1
            and now >= (recent[key] or 0) then
            return key
        end
    end
    if pendingUI or not panel and not knownMetadata then return nil,"skill-ui-loading" end
    return nil, "waiting-skill-cooldown"
end
function Caster:_tools(char)
    local player = self.Deps.Players.LocalPlayer
    local tools = {}
    for _, container in ipairs({char, player:FindFirstChild("Backpack")}) do
        if container then for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") and kindOf(tool) then tools[#tools+1]=tool end
        end end
    end
    local nextKind = self.NextKind
    table.sort(tools,function(a,b)
        local ar, br = (kindRank[kindOf(a)]-nextKind)%#kinds, (kindRank[kindOf(b)]-nextKind)%#kinds
        if ar~=br then return ar<br end
        if (a.Parent==char)~=(b.Parent==char) then return a.Parent==char end
        return a.Name<b.Name
    end)
    return tools
end
function Caster:_select(char, job)
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health<=0 then return nil,nil,"waiting-character" end
    local deadline = self.Deps.Clock()+2
    for _, tool in ipairs(self:_tools(char)) do
        if not job.Valid or self.Deps.Players.LocalPlayer.Character~=char then return nil,nil,"interrupted" end
        local key, phase = self:_readyKey(tool)
        if key or phase=="skill-ui-loading" and self.Deps.Clock()>=(self.ProbeAfter[tool] or 0) then
            if tool.Parent~=char then
                job.Equipping, job.Tool = true, tool
                humanoid:EquipTool(tool)
                self.Deps.Task.wait(.12)
            end
            local uiDeadline = math.min(deadline,self.Deps.Clock()+.4)
            repeat
                if not job.Valid or self.Deps.Players.LocalPlayer.Character~=char or tool.Parent~=char then return nil,nil,"interrupted" end
                key, phase = self:_readyKey(tool)
                if key then job.Equipping=false;job.Tool=tool;return tool,key,kindOf(tool) end
                if phase~="skill-ui-loading" then break end
                self.Deps.Task.wait(.05)
            until self.Deps.Clock()>=uiDeadline
            self.ProbeAfter[tool]=self.Deps.Clock()+.5
        end
        if self.Deps.Clock()>=deadline then break end
    end
    job.Equipping=false
    return nil,nil,"waiting-all-skills"
end
function Caster:Cast(tool, target, job)
    local player = self.Deps.Players.LocalPlayer
    local char = player and player.Character
    if not char or char ~= target.Character then return {State="waiting-character", Delay=.3} end
    local busy = char:FindFirstChild("Busy")
    local stun = char:FindFirstChild("Stun")
    if busy and busy.Value or stun and tonumber(stun.Value) and stun.Value > 0 then return {State="waiting-character",Delay=.3} end
    local originalTool=char:FindFirstChildOfClass("Tool")
    local vim, mouse, oldHit, oldTarget, code, key, kind
    local connection, pressed, cleaned, result
    local function aim()
        if job.Valid and target.Part.Parent and player.Character == char then
            mouse.Hit = self.Deps.MakeAimFrame and self.Deps.MakeAimFrame(target.Part.Position) or CFrame.new(target.Part.Position)
            mouse.Target = target.Part
        end
    end
    job.SkillCleanup = function()
        if cleaned then return end
        cleaned = true
        if pressed then pcall(function() vim:SendKeyEvent(false,code,false,self.Deps.InputTarget or game) end); pressed=false end
        if connection then connection:Disconnect(); connection=nil end
        if mouse then mouse.Hit, mouse.Target = oldHit, oldTarget end
        job.Casting, job.Equipping = false, false
        if not job.Valid and originalTool and player.Character==char and char:FindFirstChildOfClass("Tool")==job.Tool
            and (originalTool.Parent==char or originalTool.Parent==player:FindFirstChild("Backpack")) then
            local hum=char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health>0 then pcall(function() hum:EquipTool(originalTool) end) end
        end
    end
    local ok, problem = xpcall(function()
        tool, key, kind = self:_select(char,job)
        if not tool then result={State=kind,Delay=.4};return end
        if not job.Valid then result={State="interrupted",Delay=.3};return end
        vim = self.Deps.VirtualInputManager or game:GetService("VirtualInputManager")
        mouse = (self.Deps.RequireModule or require)(self.Deps.ReplicatedStorage.Mouse)
        oldHit, oldTarget = rawget(mouse,"Hit"), rawget(mouse,"Target")
        code = (self.Deps.KeyCodes or Enum.KeyCode)[key]
        job.Casting, job.SkillKey = true, key
        connection = self.Deps.RunService.RenderStepped:Connect(aim)
        aim()
        pressed=true
        vim:SendKeyEvent(true,code,false,self.Deps.InputTarget or game)
        target.LastSkillKey, target.SkillPhase = key, "casting-"..key
        target.LastSkillTool, target.LastSkillKind = tool.Name, kind
        target.SkillCasts = (target.SkillCasts or 0)+1
        self.NextKind=kindRank[kind]%#kinds+1
        self.Recent[tool] = self.Recent[tool] or {}
        self.Recent[tool][key] = self.Deps.Clock()+1.2
        self.Deps.Task.wait(.15)
        if not job.Valid then return end
        aim()
        vim:SendKeyEvent(false,code,false,self.Deps.InputTarget or game)
        pressed=false
        self.Deps.Task.wait(.15)
        local deadline = self.Deps.Clock()+2.5
        while job.Valid and player.Character==char and busy and busy.Value and self.Deps.Clock()<deadline do
            self.Deps.Task.wait(.05)
        end
    end, function(err) return tostring(err) end)
    job.SkillCleanup()
    if not ok then error(problem,0) end
    return result or {State="skill-sent",Key=key,Tool=tool.Name,Kind=kind,Delay=.25,QuietFor=.2}
end
return Caster
end)()
DungeonModules.CreateKit = (function()
-- Factory. Pass the three module return values; works with readfile/loadstring or ModuleScripts.
local function createKit(modules, options, deps)
    options, deps = options or {}, deps or {}
    if not deps.Clock then deps.Clock = os.clock end
    if not deps.Task then deps.Task = task end
    if not deps.GetConnections and type(getconnections) == "function" then deps.GetConnections = getconnections end
    if not deps.GetUpvalues and type(debug) == "table" and type(debug.getupvalues) == "function" then deps.GetUpvalues = debug.getupvalues end
    if not deps.GetThreadIdentity then
        if type(getthreadidentity) == "function" then deps.GetThreadIdentity = getthreadidentity
        elseif type(getidentity) == "function" then deps.GetThreadIdentity = getidentity end
    end
    if not deps.SetThreadIdentity then
        if type(setthreadidentity) == "function" then deps.SetThreadIdentity = setthreadidentity
        elseif type(setidentity) == "function" then deps.SetThreadIdentity = setidentity end
    end
    for _, service in ipairs({"Players", "ReplicatedStorage", "RunService", "CollectionService", "PathfindingService"}) do
        if not deps[service] then deps[service] = game:GetService(service) end
    end
    if not deps.Workspace then deps.Workspace = workspace end
    if not deps.PathSuccess then deps.PathSuccess = Enum.PathStatus.Success end
    if not deps.PathJump then deps.PathJump = Enum.PathWaypointAction.Jump end
    if not deps.GetCallback then
        deps.GetCallback = function(remote, member)
            if type(getcallbackvalue) == "function" then return getcallbackvalue(remote, member) end
            -- Some environments support normal reads; others require getcallbackvalue.
            return remote[member]
        end
    end
    if not deps.FireTouch and type(firetouchinterest) == "function" then deps.FireTouch = firetouchinterest end
    if not deps.HasOpenChooser then
        deps.HasOpenChooser = function()
            local player = deps.Players.LocalPlayer
            local gui = player and player:FindFirstChild("PlayerGui")
            if gui then
                for _, child in ipairs(gui:GetChildren()) do
                    if child.Name == "BuffSelectorMenu" and child.Enabled
                        and child:FindFirstChildWhichIsA("TextButton", true) then return true end
                end
            end
            return false
        end
    end
    local kit = {Running = false, Destroyed = false, _connection = nil, _elapsed = 0}
    kit.Cards = modules.CardSelector.new(modules.CardPolicy, options.Cards, deps)
    if modules.NativeCardUI then kit.Cards:AttachNativeUI(modules.NativeCardUI) end
    kit.Rooms = modules.RoomNavigator.new(options.Rooms, deps)
    if modules.WorldPropCombat then
        local propDeps = table.clone(deps)
        propDeps.ReadPropRoom = function() return kit.Rooms:ReadState() end
        if modules.PropSkillCaster and not propDeps.NativePropSkill then
            local caster = modules.PropSkillCaster.new(options.Props, deps)
            propDeps.NativePropSkill = function(tool, target, job) return caster:Cast(tool, target, job) end
            propDeps.CancelPropSkill = function(job) caster:Cancel(job) end
        end
        if not propDeps.NativePropAttack then
            propDeps.NativePropAttack = function(tool)
                local controller = require(deps.ReplicatedStorage.Controllers.CombatController)
                controller:Attack(tool)
                local character = tool.Parent
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
                local remaining = 0
                if animator then
                    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                        if track.Name:find("-basic", 1, true) then
                            remaining = math.max(remaining, (track.Length - track.TimePosition) / math.max(math.abs(track.Speed), 0.01))
                        end
                    end
                end
                return remaining > 0 and remaining or 0.8
            end
        end
        kit.Props = modules.WorldPropCombat.new(options.Props or {Enabled = false}, propDeps)
    end
    function kit:Step()
        if not self.Running or self._stepping then return end
        self._stepping = true
        local ok, problem = pcall(function()
            self.Cards:Step()
            self.Rooms:Step(self.Cards:IsChoosing())
            if self.Props then self.Props:Step(self:RoomOwnsMovement()) end
        end)
        self._stepping = false
        if not ok then
            self.LastError = tostring(problem)
            self.Rooms:Retry()
            if options.OnError then pcall(options.OnError, self.LastError) end
        end
    end
    function kit:Start()
        if self.Destroyed then return nil, "kit-destroyed" end
        if self.Running then return self end
        self.Running = true
        self.Cards:Start()
        self.Rooms:Start()
        if self.Props then self.Props:Start() end
        if not options.ManualStep then
            self._connection = deps.RunService.Heartbeat:Connect(function(dt)
                self._elapsed += dt
                if self._elapsed >= 0.2 then self._elapsed = 0; self:Step() end
            end)
        end
        return self
    end
    function kit:Stop()
        self.Running = false
        if self._connection then self._connection:Disconnect(); self._connection = nil end
        self.Cards:Stop()
        self.Rooms:Stop()
        if self.Props then self.Props:Stop() end
    end
    function kit:RoomOwnsMovement()
        if not self.Running or self.Rooms.Options.Enabled == false then return false end
        local phase = self.Rooms.Status.Phase
        return self.Rooms:IsMoving() or phase == "awaiting-floor-change"
            or phase == "transition-not-confirmed" or phase == "movement-timeout"
            or phase == "character-anchored"
    end
    function kit:ShouldPauseCombat()
        return self:RoomOwnsMovement() or (self.Props ~= nil and self.Props.Running
            and (self.Props.Target ~= nil or self.Props:IsCoolingDown()))
    end
    function kit:GetStatus()
        return {Running = self.Running, Cards = table.clone(self.Cards.Status), Rooms = table.clone(self.Rooms.Status),
            LastSelection = self.Cards.LastSelection and table.clone(self.Cards.LastSelection),
            LastTransition = self.Rooms.LastTransition and table.clone(self.Rooms.LastTransition),
            NativeCardUI = self.Cards.NativeUI and self.Cards.NativeUI:GetStatus(),
            Props = self.Props and self.Props:GetStatus(), LastError = self.LastError}
    end
    function kit:Destroy()
        if self.Destroyed then return end
        self.Destroyed = true
        self:Stop()
    end
    return kit
end

return createKit
end)()
-- END EMBEDDED DUNGEONKIT MODULES
-- BEGIN DUNGEONKIT HOST ADAPTER
local function restoreDungeonCollision(character)
    for part, original in pairs(DungeonHunter._noclipSaved) do
        if not character or part:IsDescendantOf(character) then
            pcall(function() part.CanCollide = original end)
            DungeonHunter._noclipSaved[part] = nil
        end
    end
end

local function applyDungeonCollision(character)
    if not (Config.Noclip and Config.AutoFarmDungeon) then restoreDungeonCollision(); return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            if DungeonHunter._noclipSaved[part] == nil then DungeonHunter._noclipSaved[part] = part.CanCollide end
            part.CanCollide = false
        end
    end
end

local function syncDungeonKit(force)
    local kit = DungeonHunter.DungeonKit
    if not kit then return end
    kit.Cards.Options.Enabled = DungeonHunter._enabled and Config.AutoPickCard == true
    kit.Cards.Options.Focus = Config.CardFocus
    kit.Cards.Options.Priority = Config.CardPriority
    kit.Cards.Options.NoUsefulCard = Config.CardNoUsefulFallback or "first-offered"
    if kit.Props then
        kit.Props.Options.Enabled = Config.AutoFarmDungeon and (Config.AutoBreakFloor10 or Config.AutoBreakFloor15)
        kit.Props.Options.Floor10, kit.Props.Options.Floor15 = Config.AutoBreakFloor10, Config.AutoBreakFloor15
        kit.Props.Options.ProbeUnverified = Config.PropProbeUnverified
    end
    local enabled = Config.AutoFarmDungeon == true and Config.AutoProceed == true
    local changed = kit.Rooms.Options.Enabled ~= enabled
    kit.Rooms.Options.Enabled = enabled
    if not enabled then DungeonHunter._roomMove = nil end
    local now = tick()
    if force or changed or now - DungeonHunter._lastDungeonStep >= 0.15 then
        DungeonHunter._lastDungeonStep = now
        kit:Step()
        DungeonHunter.ProgressionStatus = kit:GetStatus()
    end
end

local function stepDungeonProgression(dt, character, humanoid, root)
    local kit = DungeonHunter.DungeonKit
    if not kit then return false end
    local roomPhase = kit.Rooms.Status.Phase
    local roomOwnsFrame = Config.AutoFarmDungeon and Config.AutoProceed and
        (kit.Rooms:IsMoving() or roomPhase == "awaiting-floor-change"
            or roomPhase == "transition-not-confirmed" or roomPhase == "movement-timeout"
            or roomPhase == "character-anchored")
    -- Card selection owns only its UI. Keep combat running while it waits for a response.
    if not roomOwnsFrame then return false end
    DungeonHunter._targetMob = nil
    if root.Anchored then setHoverState(false, root); return true end
    setHoverState(true, root, root.Position)
    if roomPhase == "transition-not-confirmed" or roomPhase == "movement-timeout" then return true end
    local movement = DungeonHunter._roomMove
    if not movement or movement.Character ~= character or movement.Root ~= root
        or not movement.Exit.Parent or not movement.Explorer.Parent
        or movement.Explorer:GetAttribute("FloorId") ~= movement.FloorId then
        DungeonHunter._roomMove = nil
        return true
    end
    -- The host's combat step is the only writer to the local root CFrame.
    local goal = movement.Goal.Position
    local delta = goal - root.Position
    local distance = delta.Magnitude
    local speed = tonumber(Config.RoomGlideSpeed) or 220
    if speed ~= speed or speed == math.huge or speed == -math.huge then speed = 220 end
    local moveStep = math.min(distance, math.clamp(speed, 1, 350) * math.clamp(dt, 0, 0.1))
    if distance > 0.01 and moveStep > 0 then
        local nextPosition = root.Position + delta.Unit * moveStep
        local facing = Vector3.new(goal.X, nextPosition.Y, goal.Z)
        if (facing - nextPosition).Magnitude > 0.1 then
            root.CFrame = CFrame.lookAt(nextPosition, facing)
        else
            root.CFrame = (root.CFrame - root.Position) + nextPosition
        end
    end
    root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
    return true
end

local function stepDungeonObjects(dt, character, root)
    local kit = DungeonHunter.DungeonKit
    local props = kit and kit.Props
    local target = props and props.Target
    if not Config.AutoFarmDungeon then return false end
    if not target then
        if props and props:IsCoolingDown() then setHoverState(true, root, root.Position); return true end
        return false
    end
    if target.WaitingHitbox then setHoverState(true, root, root.Position); return true end
    if not props:IsValid(target, kit.Rooms:ReadState()) then return true end
    -- Let the native skill control its dash/body movers; only the host approaches.
    if props:IsCasting() then setHoverState(false, root); return true end
    restoreBring()
    if root.Anchored then return true end
    local part = target.Part
    if target.UseSkill then
        target.Goal = props:GetApproach(target)
        target.PartPosition = part.Position
    elseif not target.Goal or (part.Position - target.PartPosition).Magnitude > 8 then
        local point = part.CFrame:PointToObjectSpace(root.Position)
        local planar = Vector3.new(point.X, 0, point.Z)
        local direction = planar.Magnitude > 0.01 and planar.Unit or Vector3.new(0, 0, 1)
        local half = part.Size * 0.5
        local radius = math.min(math.max(half.X, 0.05) / math.max(math.abs(direction.X), 0.0001),
            math.max(half.Z, 0.05) / math.max(math.abs(direction.Z), 0.0001))
        target.Goal = part.CFrame:PointToWorldSpace(direction * (radius + 4))
        target.PartPosition = part.Position
    end
    local delta = target.Goal - root.Position
    local distance = delta.Magnitude
    if not Config.AutoMove and distance > 2.5 then props:Release("movement-disabled"); return false end
    DungeonHunter._targetMob = nil
    setHoverState(true, root, root.Position)
    local speed = tonumber(Config.RoomGlideSpeed) or 220
    if speed ~= speed then speed = 220 end
    local step = math.min(distance, math.clamp(speed, 1, 350) * math.clamp(dt, 0, 0.1))
    local position = root.Position
    if distance > 0.01 then position += delta.Unit * step end
    if (part.Position - position).Magnitude > 0.01 then root.CFrame = CFrame.lookAt(position, part.Position) end
    root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
    local tool = character:FindFirstChildOfClass("Tool")
    if target.UseSkill or tool and (tool.ToolTip == "Melee" or tool.ToolTip == "Sword") then
        props:TryAttack(tool, (target.Goal - root.Position).Magnitude)
    end
    return true
end

local function initDungeonModules()
        local kit = DungeonModules.CreateKit(DungeonModules, {
        ManualStep = true,
        Props = {Enabled = Config.AutoFarmDungeon, Floor10 = Config.AutoBreakFloor10, Floor15 = Config.AutoBreakFloor15,
            ProbeUnverified = Config.PropProbeUnverified, StallDelay = 4, AttackSeconds = 1.8, MoveTimeout = 8, RetryDelay = 15, VentRetryDelay = 2},
        Cards = {
            Enabled = Config.AutoPickCard,
            Focus = Config.CardFocus,
            Priority = Config.CardPriority,
            NoUsefulCard = Config.CardNoUsefulFallback,
            OnSelected = function(id, _, reason)
                if DungeonHunter._isRunning then
                    warn("[Kaitun Dungeon] Card:", id, reason)
                end
            end,
        },
        Rooms = {
            CanMove = function(state)
                return DungeonHunter._enabled and (not tonumber(Config.StopFloor) or state.FloorId < tonumber(Config.StopFloor))
            end,
            Enabled = Config.AutoFarmDungeon and Config.AutoProceed,
            MoveTo = function(goal, state)
                if not DungeonHunter._enabled or not Config.AutoFarmDungeon or not Config.AutoProceed then return false end
                if tonumber(Config.StopFloor) and state.FloorId >= tonumber(Config.StopFloor) then return false end
                DungeonHunter._roomMove = {Goal = goal, Character = state.Character, Root = state.Root,
                    Exit = state.Exit, Explorer = state.Explorer, FloorId = state.FloorId}
                return true
            end,
            CancelMove = function() DungeonHunter._roomMove = nil end,
            OnFloorChanged = function(floor)
                DungeonHunter._roomMove = nil
                DungeonHunter._targetMob = nil
                if DungeonHunter.DungeonKit and DungeonHunter.DungeonKit.Props then DungeonHunter.DungeonKit.Props:Release("floor-changed") end
                restoreBring()
                DungeonHunter._currentRoomText = "Phòng " .. tostring(floor)
            end,
        },
        OnError = function(message)
            if DungeonHunter._isRunning then warn("[Kaitun Dungeon][Modules]", message) end
        end,
    })
    DungeonHunter.DungeonKit = kit

end
-- END DUNGEONKIT HOST ADAPTER

-- ==================== VÒNG LẶP CHIẾN ĐẤU CHÍNH ====================
local function onCombatStep()
    if not DungeonHunter._enabled or Workspace:GetAttribute("IsDungeonInstance") ~= true then return end
    local room = DungeonHunter.DungeonKit.Rooms:ReadState()
    if not room then return end
    local stopFloor = tonumber(Config.StopFloor)
    if stopFloor and room.FloorId >= stopFloor and room.Ready then
        DungeonHunter.StopReached = room.FloorId
        DungeonHunter:SetEnabled(false)
        return
    end
    local now = tick()
    local dt = math.clamp(now - DungeonHunter._lastTick, 0, 0.1)
    DungeonHunter._lastTick = now
    syncDungeonKit()

    local character, humanoid, root = getCharacter()
    if not (character and humanoid and root and humanoid.Health > 0) then
        setHoverState(false, root)
        return
    end

    -- Noclip khi bật tính năng
    applyDungeonCollision(character)

    -- Định kỳ bật Buso & Cầm vũ khí
    if now - DungeonHunter._lastEquipTick >= 0.75 then
        DungeonHunter._lastEquipTick = now
        local props = DungeonHunter.DungeonKit and DungeonHunter.DungeonKit.Props
        if not (props and props:OwnsWeapon()) then pcall(autoEquipWeapon) end
    end
    local busoJob = DungeonHunter._busoJob
    if busoJob and now - busoJob.Started > 5 then
        DungeonHunter._busoJob = nil
        if busoJob.Thread then pcall(task.cancel, busoJob.Thread) end
    end
    if now - DungeonHunter._lastBusoTick >= 1.0 and not DungeonHunter._busoJob then
        DungeonHunter._lastBusoTick = now
        local job = {Started = now}
        DungeonHunter._busoJob = job
        job.Thread = task.spawn(function()
            if DungeonHunter._isRunning and LocalPlayer.Character == character then pcall(enableBuso) end
            if DungeonHunter._busoJob == job then DungeonHunter._busoJob = nil end
        end)
    end

    if stepDungeonProgression(dt, character, humanoid, root) then return end
    if stepDungeonObjects(dt, character, root) then return end

    if not Config.AutoFarmDungeon then
        setHoverState(false, root)
        DungeonHunter._targetMob = nil
        return
    end

    -- Tìm quái gần nhất trong dungeon
    local targetMob, distToTarget = findNearestEnemy(root.Position)
    DungeonHunter._targetMob = targetMob

    if not (targetMob and targetMob:FindFirstChild("HumanoidRootPart")) then
        setHoverState(false, root)
        return
    end

    local mobRoot = targetMob.HumanoidRootPart
    local hoverTargetPos = mobRoot.Position + Vector3.new(0, tonumber(Config.HoverHeight) or 20, 0)

    -- Di chuyển CFrame mượt mà
    if Config.AutoMove then
        setHoverState(true, root, hoverTargetPos)

        local currentPos = root.Position
        local distToHover = (currentPos - hoverTargetPos).Magnitude
        local speed = tonumber(Config.GlideSpeed) or 280
        local moveStep = math.clamp(speed * dt, 0, 30)

        local nextPos
        if distToHover > moveStep then
            local direction = (hoverTargetPos - currentPos).Unit
            nextPos = currentPos + direction * moveStep
        else
            nextPos = hoverTargetPos
        end

        -- Khóa hướng nhìn thẳng về phía quái bên dưới
        local lookTarget = Vector3.new(mobRoot.Position.X, nextPos.Y, mobRoot.Position.Z)
        if (lookTarget - nextPos).Magnitude > 0.1 then
            root.CFrame = CFrame.lookAt(nextPos, lookTarget)
        else
            root.CFrame = (root.CFrame - root.Position) + nextPos
        end
    end

    -- Gom quái (Bring Mobs) về ngay bên dưới vị trí hover của player
    if Config.BringMobs and (now - DungeonHunter._lastGrabTick >= (tonumber(Config.BringMobInterval) or 0.15)) then
        DungeonHunter._lastGrabTick = now
        local groundPoint = root.Position - Vector3.new(0, tonumber(Config.HoverHeight) or 20, 0)
        pcall(bringMobsToPoint, groundPoint, targetMob.Name)
    end

    -- Fast Attack
    if Config.FastAttack and (now - DungeonHunter._lastAttackTick >= (tonumber(Config.AttackCooldown) or 0.03)) then
        local tool = character:FindFirstChildOfClass("Tool")
        if tool and (tool.ToolTip == "Melee" or tool.ToolTip == "Sword") then
            local basePart, hits = collectAttackTargets(character, root.Position)
            if executeFastHit(basePart, hits, tool) then
                DungeonHunter._lastAttackTick = now
            end
        elseif tool and now - DungeonHunter._lastAttackTick >= 0.18 and (root.Position - mobRoot.Position).Magnitude < 45 then
            DungeonHunter._lastAttackTick = now
            if not DungeonHunter._nativeJob then
                local job = {}; DungeonHunter._nativeJob = job
                job.Thread = task.defer(function()
                    pcall(function()
                        local getter, setter = getthreadidentity or getidentity, setthreadidentity or setidentity
                        local prior = getter and getter()
                        if prior and setter then setter(2) end
                        local ok, err = pcall(function() require(ReplicatedStorage.Controllers.CombatController):Attack(tool) end)
                        if prior and setter then setter(prior) end
                        if not ok then DungeonHunter.LastStepError = tostring(err) end
                    end)
                    if DungeonHunter._nativeJob == job then DungeonHunter._nativeJob = nil end
                end)
            end
        end
    end
end

-- ==================== KHỞI TẠO FLUENT UI ====================
function DungeonHunter:Configure(values)
    for key, value in pairs(values) do self.Config[key] = value end
    self.Config.CardFocus = self.Config.CardFocus == "Sword" and "Sword" or "Melee"
    if self.DungeonKit then
        self.DungeonKit.Cards.Options.Focus = self.Config.CardFocus
        self.DungeonKit.Cards.Options.Priority = self.Config.CardPriority
    end
end

function DungeonHunter:SetEnabled(enabled)
    enabled = enabled == true and self._isRunning
    self._enabled, Config.AutoFarmDungeon = enabled, enabled
    if enabled then
        self.StopReached = nil
        self._lastTick = tick()
        self.DungeonKit:Start()
    else
        self.DungeonKit:Stop()
        self._targetMob, self._roomMove = nil, nil
        setHoverState(false, nil)
        restoreDungeonCollision()
        restoreBring()
        for _, key in ipairs({"_nativeJob", "_busoJob"}) do
            local job = self[key]
            if job and job.Thread then pcall(task.cancel, job.Thread) end
            self[key] = nil
        end
    end
end

function DungeonHunter:GetState()
    local room = self.DungeonKit.Rooms:ReadState()
    return {Enabled = self._enabled, FloorId = room and room.FloorId, FloorReady = room and room.Ready,
        StopReached = self.StopReached, LastError = self.LastStepError, Modules = self.DungeonKit:GetStatus()}
end

function DungeonHunter:Destroy()
    if not self._isRunning then return end
    self:SetEnabled(false)
    self._isRunning = false
    if self.DungeonKit then
        self.DungeonKit:Destroy()
    end
    self._roomMove = nil
    if self._busoJob then
        if self._busoJob.Thread then pcall(task.cancel, self._busoJob.Thread) end
        self._busoJob = nil
    end
    if self._fluent then pcall(function() self._fluent:Destroy() end); self._fluent = nil end
    Config.AutoFarmDungeon = false
    Config.BringMobs = false
    Config.FastAttack = false
    Config.AutoProceed = false
    Config.AutoPickCard = false

    -- Ngắt toàn bộ connections
    for _, conn in ipairs(self._connections) do
        pcall(function() conn:Disconnect() end)
    end
    self._connections = {}

    -- Hủy hover velocity
    local _, _, root = getCharacter()
    setHoverState(false, root)

    -- Khôi phục va chạm
    restoreDungeonCollision()

    warn("[Kaitun Dungeon] Đã dừng và dọn dẹp sạch sẽ toàn bộ kết nối.")
end

-- ==================== KÍCH HOẠT VÒNG LẶP ====================
initDungeonModules()
local stepConn = RunService.Stepped:Connect(function()
    if DungeonHunter._isRunning and DungeonHunter._enabled and not DungeonHunter._stepBusy then
        DungeonHunter._stepBusy = true
        local ok, problem = pcall(onCombatStep)
        DungeonHunter._stepBusy = false
        if not ok then DungeonHunter.LastStepError = tostring(problem) end
    end
end)
table.insert(DungeonHunter._connections, stepConn)

table.insert(DungeonHunter._connections, LocalPlayer.CharacterRemoving:Connect(function(character)
    if not DungeonHunter._isRunning then return end
    DungeonHunter._roomMove = nil
    DungeonHunter._targetMob = nil
    if DungeonHunter.DungeonKit then DungeonHunter.DungeonKit.Rooms:Retry() end
    if DungeonHunter.DungeonKit and DungeonHunter.DungeonKit.Props then DungeonHunter.DungeonKit.Props:Release("respawn") end
    setHoverState(false, nil)
    restoreDungeonCollision(character)
    restoreBring()
end))

-- Khởi động UI Fluent


warn("[Kaitun Dungeon] Khởi tạo thành công! Sẵn sàng đánh quái, chọn card và tự qua cổng.")
return DungeonHunter

end
return Module

    end)()
    local MainModule = (function()
-- Explicit OWNER/ALT usernames coordinate through the game's pad membership.
local Module = {}
function Module.Difficulty(v)
    if v == "Easy" or v == "Normal" then return "Normal" end
    if v == "Hard" then return "Hard" end
    if v == "Challenge" or v == "Nightmare / Challenge" then return "Challenge" end
end
function Module.ParseNames(owner, alts)
    owner = tostring(owner or ""):match("^%s*@?(.-)%s*$")
    local function valid(n) return #n >= 3 and #n <= 20 and n:match("^[%w_]+$") ~= nil end
    if not valid(owner) then return nil, "Enter the owner's Roblox username, not display name" end
    local names, seen = {owner}, {[owner:lower()] = true}
    for n in tostring(alts or ""):gmatch("[^,;%s]+") do
        n = n:gsub("^@", "")
        if not valid(n) then return nil, "Invalid ALT username: " .. n end
        if not seen[n:lower()] then names[#names + 1] = n; seen[n:lower()] = true end
    end
    if #names > 4 then return nil, "Use one owner and at most three ALTs" end
    return names
end
function Module.ParseSlots(owner, slots)
    local names, err = Module.ParseNames(owner, "")
    if not names then return nil, err end
    local seen = {[names[1]:lower()] = true}
    for slot = 1, 3 do
        local name = tostring(slots[slot] or ""):match("^%s*@?(.-)%s*$")
        if name ~= "" then
            if #name < 3 or #name > 20 or not name:match("^[%w_]+$") then
                return nil, "ALT " .. slot .. ": enter one Roblox username or leave blank"
            end
            if not seen[name:lower()] then
                names[#names + 1], seen[name:lower()] = name, true
            end
        end
    end
    return names
end
function Module.ParseAccountSlots(owner, slots, localName)
    local names,err=Module.ParseSlots(owner,slots)
    if not names then return nil,err end
    -- On an ALT, selecting another account as OWNER already identifies this
    -- local account as a follower. Do not require typing itself into ALT 1..3.
    -- The owner's explicit ALT slots remain its authoritative required roster.
    if type(localName)=="string" and localName~="" then
        local found=false
        for _,name in ipairs(names)do if name:lower()==localName:lower()then found=true;break end end
        if not found then
            if #names>=4 then return nil,"This ALT plus the configured names exceeds the four-player pad limit" end
            names[#names+1]=localName
        end
    end
    return names
end
function Module.ResolveRoster(names, resolved, localId)
    local members, ids, seen, ownerId, localFound = {}, {}, {}, nil, false
    for i, n in ipairs(names) do
        local p = resolved[n:lower()]
        if not p or type(p.UserId) ~= "number" or p.UserId <= 0 then return nil, "Username not found: " .. n end
        if not seen[p.UserId] then
            seen[p.UserId], localFound = true, localFound or p.UserId == localId
            if i == 1 then ownerId = p.UserId else ids[#ids + 1] = p.UserId end
            members[#members + 1] = {UserId = p.UserId, Name = p.Name, DisplayName = p.DisplayName or p.Name,
                IsOwner = i == 1, IsOnline = p.IsOnline == true}
        end
    end
    if not localFound then return nil, "This account is not in OWNER / ALTs" end
    table.sort(ids)
    return {OwnerId = ownerId, CloneIds = ids, Members = members, Role = localId == ownerId and "OWNER" or "ALT"}
end
local Main = {}; Main.__index = Main
local messages = {
    ["waiting-party-in-server"] = "Waiting for the configured ALTs in this server",
    ["waiting-owner"] = "Waiting for the owner in this server",
    ["insufficient-energy"] = "Not enough dungeon energy (requires 10)",
    ["difficulty-locked"] = "This difficulty is locked on this account",
    ["waiting-empty-pad"] = "Waiting for an empty pad",
    ["waiting-clones"] = "Waiting for all configured ALTs in the owner's pad",
    ["waiting-clones-not-ready"] = "Waiting for ALTs; check their START, energy and difficulty",
    ["waiting-public-players"] = "Waiting for other players to meet the pad minimum",
    ["start-unconfirmed"] = "Start sent; waiting for transfer confirmation",
}
function Main:_cancelLobbyJob()
    self.LobbySerial=(self.LobbySerial or 0)+1
    if self.LobbyJob then pcall(self.Deps.Cancel,self.LobbyJob); self.LobbyJob=nil end
end
function Main:_requestLobby(world)
    local now=self.Deps.Now()
    if world.Level and world.Level<1100 then return "Dungeon unlocks at level 1100" end
    if world.InCombat then return "Waiting to leave combat before entering dungeon lobby" end
    if self.LobbyJob then
        if now-self.LobbyRequestedAt>=10 then
            self:_cancelLobbyJob(); self.LobbyError="Dungeon lobby request timed out"
        end
        return self.LobbyError or "Entering dungeon lobby..."
    end
    if now<(self.LobbyNextAttempt or 0) then return self.LobbyError or "Waiting for dungeon lobby transfer..." end
    if not self.Deps.EnterLobby then return "Waiting for dungeon lobby travel support" end
    self.Deps.Save(self.Settings); self.Deps.QueueResume()
    self.LobbyRequestedAt,self.LobbyNextAttempt,self.LobbyError=now,now+15,nil
    local serial=self.LobbySerial
    self.LobbyJob=self.Deps.Spawn(function()
        local ok,err=pcall(self.Deps.EnterLobby)
        if not self.Alive or serial~=self.LobbySerial then return end
        self.LobbyJob=nil
        if not ok then self.LobbyError=tostring(err) end
    end)
    return "Entering dungeon lobby..."
end
function Main:_cancelCombatJob()
    self.CombatSerial = (self.CombatSerial or 0) + 1
    if self.CombatJob then pcall(self.Deps.Cancel, self.CombatJob); self.CombatJob = nil end
end
function Main:_skipReturn(world)
    local event=world.ReturnToHub
    if self.ReturnEvent~=event then
        self.ReturnEvent,self.ReturnSkipped,self.ReturnNextAttempt,self.ReturnError=event,false,nil,nil
    end
    if self.ReturnSkipped then return "Skip sent; waiting for party to return to lobby" end
    if self.Deps.Now()<(self.ReturnNextAttempt or 0) then return self.ReturnError or "Waiting to skip the return timer" end
    self.ReturnNextAttempt=self.Deps.Now()+2
    self.Deps.Save(self.Settings);self.Deps.QueueResume()
    local ok,sent=pcall(function()
        assert(self.Deps.SkipReturn,"return Skip adapter unavailable")
        return self.Deps.SkipReturn(event)
    end)
    if ok and sent==true then
        self.ReturnSkipped=true
        return "Skip sent; waiting for party to return to lobby"
    end
    self.ReturnError=ok and "Waiting for the dungeon return prompt" or tostring(sent)
    return self.ReturnError
end
function Main:_resetRun()
    self:_cancelLobbyJob()
    self:_cancelCombatJob()
    if self.Combat then self.Combat:Destroy(); self.Combat = nil end
    if self.Pads then self.Pads:Destroy(); self.Pads = nil end
    self.PadKey, self.CompletedFloor, self.ActionError = nil, nil, nil
    self.ReturnEvent,self.ReturnSkipped,self.ReturnNextAttempt,self.ReturnError=nil,nil,nil,nil
end
function Main:_stopGameplay()
    self:_cancelCombatJob()
    if self.Pads and self.Pads._enabled then self.Pads:Stop() end
    if self.Combat and self.Combat._enabled then self.Combat:SetEnabled(false) end
end
function Main:_stop()
    self:_cancelLobbyJob()
    self:_stopGameplay()
end
function Main:SetRunning(enabled)
    if not self.Alive then return false end
    enabled = enabled == true
    local previous = self.Settings.IsStarted
    self.Settings.IsStarted = enabled
    if enabled then
        if not previous then
            self.CompletedFloor = nil
            if self.Combat then self.Combat.StopReached = nil end
        end
    else self:_stop() end
    self.Deps.Save(self.Settings)
    if enabled then self.Deps.QueueResume() end
end
function Main:SettingChanged(key, value)
    if not self.Alive or self.Painting then return end
    if key == "IsStarted" then self:SetRunning(value); return end
    if key == "StopFloor" then value = tostring(math.clamp(math.floor(tonumber(value) or 20), 1, 1000)) end
    if key == "CardFocus" then value = value == "Sword" and "Sword" or "Melee" end
    if key == "AutoPickCard" and self.UI.PickCardAlways then value = true end
    if key == "OwnerName" or key == "Alt1" or key == "Alt2" or key == "Alt3" then
        if self.Settings[key] == value then return end
        self.Settings.IsStarted = false
        self.Generation += 1; self.Roster, self.ResolveError = nil, nil; self:_stop()
        if self.Pads then self.Pads:Destroy(); self.Pads = nil end
        self.PadKey = nil
        if self.ResolveJob then pcall(self.Deps.Cancel, self.ResolveJob); self.ResolveJob = nil end
    end
    if key == "StopFloor" and self.Settings[key] ~= value then
        self.CompletedFloor = nil
        if self.Combat then self.Combat.StopReached = nil end
    end
    self.Settings[key] = value
    if self.Combat then self.Combat:Configure({StopFloor = tonumber(self.Settings.StopFloor),
        AutoPickCard = self.Settings.AutoPickCard == true, CardFocus = self.Settings.CardFocus,
        WeaponType = self.Settings.WeaponType}) end
    self.Deps.Save(self.Settings)
end
function Main:_resolve()
    if self.Roster or self.ResolveJob then return end
    local names, err = Module.ParseAccountSlots(self.Settings.OwnerName,
        {self.Settings.Alt1, self.Settings.Alt2, self.Settings.Alt3}, self.Deps.Player.Name)
    if not names then self.ResolveError = err; return end
    if self.ResolveError and self.Deps.Now() - self.LastResolve < 5 then return end
    self.LastResolve, self.ResolveStarted = self.Deps.Now(), self.Deps.Now()
    local generation = self.Generation
    self.ResolveJob = self.Deps.Spawn(function()
        local ok, result = pcall(self.Deps.ResolveNames, names)
        if not self.Alive or generation ~= self.Generation then return end
        self.ResolveJob = nil
        if ok then self.Roster, self.ResolveError = Module.ResolveRoster(names, result, self.Deps.Player.UserId)
        else self.ResolveError = tostring(result) end
    end)
end
function Main:_paint(message)
    self.Painting = true
    local ok, err = pcall(self.Deps.Paint, self.UI, {Members = self.Roster and self.Roster.Members or {},
        Running = self.Settings.IsStarted, Message = message, Role = self.Roster and self.Roster.Role or "--"})
    self.Painting = false
    if not ok then self.LastError = tostring(err) end
end
function Main:Step()
    if not self.Alive then return end
    if self.ResolveJob and self.Deps.Now() - self.ResolveStarted > 10 then
        self.Generation += 1; pcall(self.Deps.Cancel, self.ResolveJob); self.ResolveJob = nil
        self.ResolveError = "Username lookup timed out; check OWNER / ALTs"
    end
    self:_resolve()
    local world, roster = self.Deps.World(), self.Roster
    if world.GameReady == false then
        self:_stop()
        self:_paint("Waiting for the game to finish loading...")
        return
    end
    -- START is the persistent switch; a floor limit only pauses this run.
    -- Release old controllers when changing runs so their completion/queue state
    -- cannot block the next lobby or the next dungeon in the same DataModel.
    if world.InDungeon then
        if not self.WasInDungeon or (self.DungeonKey and world.DungeonKey and self.DungeonKey ~= world.DungeonKey) then
            self:_resetRun()
        end
        self.WasInDungeon = true
        if world.DungeonKey then self.DungeonKey = world.DungeonKey end
    elseif world.InLobby and not world.Teleporting and self.WasInDungeon then
        self:_resetRun()
        self.WasInDungeon, self.DungeonKey = false, nil
    end
    -- ReturnToHub is created by the game for its end-of-run Skip vote. A floor
    -- limit alone is not an end-of-run signal. Each account submits its own vote.
    if self.Settings.IsStarted and world.InDungeon and world.ReturnToHub and not world.Teleporting then
        self:_stopGameplay()
        self:_paint(self:_skipReturn(world))
        return
    end
    local message = self.ResolveError or "Resolving party usernames..."
    if roster then self.Deps.RefreshPresence(roster.Members) end
    if not roster then self:_stop()
    elseif not self.Settings.IsStarted then
        self:_stop(); message = #roster.CloneIds == 0 and "Ready • START to queue with other players"
            or "Ready • Same OWNER/ALTs on all accounts, then START"
    elseif world.InDungeon then
        if self.Pads and self.Pads._enabled then self.Pads:Stop() end
        if not self.Combat and not self.CombatJob then
            local serial = self.CombatSerial
            self.CombatJob = self.Deps.Spawn(function()
                local ok, c = pcall(self.Deps.CreateCombat)
                if not self.Alive or serial ~= self.CombatSerial then
                    if ok then c:Destroy() end
                    return
                end
                self.CombatJob = nil
                if ok then self.Combat = c else self.ActionError = tostring(c) end
            end)
        end
        if self.Combat then
            local state = self.Combat:GetState()
            if state.StopReached then self.CompletedFloor = state.StopReached end
            if self.CompletedFloor then
                if self.Combat._enabled then self.Combat:SetEnabled(false) end
                message = "Completed floor " .. self.CompletedFloor .. " • START stays on; waiting for lobby"
            else
                self.Combat:Configure({AutoPickCard = self.Settings.AutoPickCard == true,
                    CardFocus = self.Settings.CardFocus,
                    WeaponType = self.Settings.WeaponType, StopFloor = tonumber(self.Settings.StopFloor)})
                if not self.Combat._enabled then self.Combat:SetEnabled(true) end
                message = state.LastError or ("Dungeon active • Floor " .. tostring(state.FloorId or "--"))
            end
        else message = self.ActionError or "Loading dungeon modules..." end
    elseif world.InLobby and not world.Teleporting then
        self:_cancelLobbyJob()
        if self.Combat and self.Combat._enabled then self.Combat:SetEnabled(false) end
        local difficulty = Module.Difficulty(self.Settings.DungeonMode)
        if not difficulty then message = "Select Easy, Hard or Challenge"
        else
            local key = tostring(roster.OwnerId) .. ":" .. difficulty .. ":" .. table.concat(roster.CloneIds, ",")
            if self.PadKey ~= key then
                if self.Pads then self.Pads:Destroy() end
                self.Pads = self.Deps.CreatePads({OwnerUserId = roster.OwnerId, CloneUserIds = roster.CloneIds,
                    Difficulty = difficulty, Destination = "Simulation", AutoStart = true})
                self.PadKey = key
            end
            if not self.Pads._enabled then self.Pads:Start() end
            self.Pads:Step()
            local state = self.Pads:GetState()
            message = messages[state.EligibilityIssue] or messages[state.Status] or (roster.Role .. " • " .. state.Status)
            if state.Energy then message ..= " • " .. tostring(state.Energy) .. "/50 energy" end
        end
    elseif world.InSea and not world.Teleporting then
        self:_stopGameplay()
        message=self:_requestLobby(world)
    else self:_stop(); message = "Waiting for teleport..." end
    self:_paint(message)
end
function Main:Destroy()
    if not self.Alive then return end
    self:_stop(); self.Alive = false; self.Deps.Save(self.Settings)
    if self.Pads then self.Pads:Destroy() end
    if self.Combat then self.Combat:Destroy() end
    for _, t in pairs({self.Thread, self.ResolveJob, self.CombatJob}) do if t ~= coroutine.running() then pcall(self.Deps.Cancel, t) end end
    if self.DestroyConnection then self.DestroyConnection:Disconnect() end
    if self.TeleportConnection then self.TeleportConnection:Disconnect() end
    if self.UI.OnStartClick == self.OnStart then self.UI.OnStartClick = self.OldStart end
    if self.UI.OnMainSettingChanged == self.OnSetting then self.UI.OnMainSettingChanged = self.OldSetting end
    if self.UI.LiveMain == self then self.UI.LiveMain = nil end
end
function Module.Bind(ui, deps)
    if ui.LiveMain then ui.LiveMain:Destroy() end
    local settings, saved = table.clone(ui.MainSettings), deps.Load() or {}
    for key, value in pairs(settings) do if type(saved[key]) == type(value) then settings[key] = saved[key] end end
    local hasSavedSlots = type(saved.Alt1) == "string" or type(saved.Alt2) == "string" or type(saved.Alt3) == "string"
    local legacyNames = saved.AltNames or ui.MainSettings.AltNames
    if not hasSavedSlots and type(legacyNames) == "string" then
        settings.Alt1, settings.Alt2, settings.Alt3 = "", "", ""
        local slot = 0
        for name in legacyNames:gmatch("[^,;%s]+") do
            slot += 1
            if slot <= 3 then settings["Alt" .. slot] = name:gsub("^@", "")
            else settings.Alt3 ..= ", " .. name end
        end
    end
    for slot = 1, 3 do
        local key = "Alt" .. slot
        settings[key] = tostring(settings[key] or ""):match("^%s*@?(.-)%s*$")
    end
    settings.AltNames = nil
    settings.CardFocus = settings.CardFocus == "Sword" and "Sword" or "Melee"
    if ui.PickCardAlways then settings.AutoPickCard = true end
    settings.StopFloor = tostring(math.clamp(math.floor(tonumber(settings.StopFloor) or 20), 1, 1000))
    if not Module.Difficulty(settings.DungeonMode) then settings.DungeonMode = "Easy" end
    if settings.WeaponType ~= "Melee" and settings.WeaponType ~= "Sword" and settings.WeaponType ~= "Gun" and settings.WeaponType ~= "Fruit" then settings.WeaponType = "Melee" end
    local self = setmetatable({Alive = true, UI = ui, Deps = deps, Settings = settings, Generation = 0,
        LastResolve = -math.huge, OldStart = ui.OnStartClick, OldSetting = ui.OnMainSettingChanged}, Main)
    self.OnStart = function(enabled) self:SetRunning(enabled) end
    self.OnSetting = function(key, value) self:SettingChanged(key, value) end
    ui.OnStartClick, ui.OnMainSettingChanged, ui.LiveMain = self.OnStart, self.OnSetting, self
    self.Painting = true; deps.InitializeUI(ui, settings); self.Painting = false
    if settings.IsStarted then deps.QueueResume() end
    self.DestroyConnection = ui.ScreenGui.Destroying:Connect(function() self:Destroy() end)
    if deps.OnTeleport then self.TeleportConnection = deps.OnTeleport(function() deps.Save(self.Settings); deps.QueueResume() end) end
    self.Thread = deps.Spawn(function()
        while self.Alive do
            local ok, err = pcall(function() self:Step() end)
            if not ok then self.LastError = tostring(err); self:_stop(); self:_paint(self.LastError) end
            deps.Wait(0.25)
        end
    end)
    return self
end
return Module

    end)()
    local MainAdapter = (function()
local Module = {}
function Module.new(StatusUI, PartyPads, Combat)
local Players = game:GetService("Players")
local identity = (getthreadidentity or getidentity or function() return nil end)()
local function uiContext(callback)
    local getter, setter = getthreadidentity or getidentity, setthreadidentity or setidentity
    local previous = getter and getter()
    if setter and identity then setter(identity) end
    local ok, err = pcall(callback)
    if setter and previous then setter(previous) end
    if not ok then error(err, 2) end
end
local player = game:GetService("Players").LocalPlayer
assert(player and type(player.UserId)=="number" and player.UserId>0,"LocalPlayer is not ready; wait before binding Main")
local http = game:GetService("HttpService")
local statePath = "TrashHub_KaitunSettings_" .. player.UserId .. ".json"
local sourcePath = "TrashHub_Kaitun_Main_v1_" .. player.UserId .. ".luau"
local cache, cacheCount, queued, lastRoster = {}, 0, false, nil
local function queueResume()
    if queued then return true end
    if getgenv().TrashHubKaitunQueuedSource == sourcePath then
        queued, StatusUI.TeleportResumeReady = true, true
        return true
    end
    local queue = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
        or (fluxus and fluxus.queue_on_teleport)
    if type(queue) ~= "function" or type(isfile) ~= "function" or not isfile(sourcePath) then
        StatusUI.TeleportResumeReady = false; return false
    end
    local ok = pcall(queue, string.format("loadstring(readfile(%q))()", sourcePath))
    if ok then getgenv().TrashHubKaitunQueuedSource = sourcePath end
    queued, StatusUI.TeleportResumeReady = ok, ok
    return ok
end
local function presence(members)
    for _, member in ipairs(members) do
        local p = Players:GetPlayerByUserId(member.UserId)
        member.IsOnline = p ~= nil
        if p then member.DisplayName, member.Name = p.DisplayName, p.Name end
    end
end
local deps
deps = {
    Player = player, Now = os.clock, Spawn = task.defer, Wait = task.wait, Cancel = task.cancel,
    ResolveNames = function(names)
        local resolved = {}
        for _, name in ipairs(names) do
            local p
            for _, candidate in ipairs(Players:GetPlayers()) do if candidate.Name:lower() == name:lower() then p = candidate; break end end
            if p then resolved[name:lower()] = {UserId = p.UserId, Name = p.Name, DisplayName = p.DisplayName, IsOnline = true}
            else
                local id = cache[name:lower()]
                if not id then
                    id = Players:GetUserIdFromNameAsync(name)
                    if cacheCount >= 32 then table.clear(cache); cacheCount = 0 end
                    cache[name:lower()] = id
                    cacheCount += 1
                end
                resolved[name:lower()] = {UserId = id, Name = name, DisplayName = name, IsOnline = false}
            end
        end
        return resolved
    end,
    RefreshPresence = presence,
    World = function()
        local guid = player:GetAttribute("ExplorerGUID")
        local map=workspace:GetAttribute("MAP")
        local character=player.Character
        local data=player:FindFirstChild("Data")
        local level=data and data:FindFirstChild("Level")
        local shared=game.ReplicatedStorage:FindFirstChild("DungeonShared")
        local returning=shared and shared:FindFirstChild("ReturnToHub")
        return {GameReady = not StatusUI.IsGameReady or StatusUI.IsGameReady(),
            InLobby = map == "Dungeons",
            InSea=map=="Sea1" or map=="Sea2" or map=="Sea3",
            Level=level and level.Value, InCombat=character and not not character:GetAttribute("InCombat"),
            InDungeon = workspace:GetAttribute("IsDungeonInstance") == true,
            ReturnToHub=returning and returning:IsA("RemoteEvent") and returning or nil,
            DungeonKey = guid and (game.JobId .. ":" .. guid) or nil,
            Teleporting = player:GetAttribute("IsTeleporting") == true}
    end,
    CreatePads = function(config) return PartyPads.new(config, {ManualStep = true}) end,
    SkipReturn=function(event)
        local main=StatusUI.LiveMain
        local shared=game.ReplicatedStorage:FindFirstChild("DungeonShared")
        if not main or not main.Alive or not main.Settings.IsStarted
            or workspace:GetAttribute("IsDungeonInstance")~=true
            or player:GetAttribute("IsTeleporting")==true
            or not shared or shared:FindFirstChild("ReturnToHub")~=event
            or not event:IsA("RemoteEvent") then return false end
        local getter,setter=getthreadidentity or getidentity,setthreadidentity or setidentity
        local previous=getter and getter()
        if setter and previous then setter(2) end
        local ok,err=pcall(function() event:FireServer() end)
        if setter and previous then setter(previous) end
        if not ok then error(err,0) end
        return true
    end,
    EnterLobby=function()
        local world=deps.World()
        if not StatusUI.LiveMain or not StatusUI.LiveMain.Settings.IsStarted or not world.GameReady
            or not world.InSea or world.Teleporting or world.InCombat then return end
        if world.Level and world.Level<1100 then return end
        local modules=game.ReplicatedStorage:FindFirstChild("Modules")
        local net=modules and modules:FindFirstChild("Net")
        local remote=net and net:FindFirstChild("RF/DungeonNPCNetworkFunction")
        assert(remote and remote:IsA("RemoteFunction"),"dungeon lobby remote not ready")
        local getter,setter=getthreadidentity or getidentity,setthreadidentity or setidentity
        local previous=getter and getter()
        if setter and previous then setter(2) end
        local ok,err=pcall(function() remote:InvokeServer("TeleportToDungeonHub",false) end)
        if setter and previous then setter(previous) end
        if not ok then error(err,0) end
    end,
    CreateCombat = function() return Combat.new({AutoPickCard = false, GlideSpeed = 200}) end,
    QueueResume = queueResume,
    OnTeleport = function(callback) return player.OnTeleport:Connect(callback) end,
    Save = function(settings)
        getgenv().TrashHubKaitunSettings = table.clone(settings)
        if type(writefile) == "function" then pcall(function() writefile(statePath, http:JSONEncode(settings)) end) end
    end,
    Load = function()
        if type(getgenv().TrashHubKaitunSettings) == "table" then return getgenv().TrashHubKaitunSettings end
        if type(isfile) == "function" and isfile(statePath) and type(readfile) == "function" then
            local ok, settings = pcall(function() return http:JSONDecode(readfile(statePath)) end)
            if ok and type(settings) == "table" then return settings end
        end
    end,
    InitializeUI = function(ui, settings)
        uiContext(function()
            ui.SetOwnerName(settings.OwnerName)
            for slot = 1, 3 do ui.SetAltSlot(slot, settings["Alt" .. slot] or "") end
            ui.SetDungeonMode(settings.DungeonMode)
            ui.SetStopFloor(settings.StopFloor)
            ui.SetWeaponType(settings.WeaponType)
            ui.SetCardFocus(settings.CardFocus)
            ui.SetStart(settings.IsStarted)
        end)
    end,
    Paint = function(ui, state)
        uiContext(function()
            local parts = {}
            for _, m in ipairs(state.Members) do parts[#parts + 1] = m.UserId .. ":" .. tostring(m.IsOwner) .. ":" .. tostring(m.IsOnline) .. ":" .. m.Name end
            local key = table.concat(parts, "|")
            if key ~= lastRoster then lastRoster = key; ui.UpdateAccountLobby(state.Members) end
            if ui.MainSettings.IsStarted ~= state.Running then ui.SetStart(state.Running) end
            ui.SetMainStatus(state.Message, state.Role)
        end)
    end,
}
return deps

end
return Module

    end)()

local teamBootstrap=getgenv().TrashHubDungeonTeamBootstrap
if teamBootstrap then teamBootstrap:AttachUI(StatusUI) end
StatusModule.Bind(StatusUI, StatusAdapter.new(StatusUI, EnemyPolicy))
RaceAutomation.Bind(StatusUI)
MainModule.Bind(StatusUI, MainAdapter.new(StatusUI, PartyPads, Combat))
screenGui:SetAttribute("MainVersion", "auto-return-skip-v14")
end)()

-- BEGIN RING RECEIPT WEBHOOK
;(function()
    local RingWebhook = (function()
-- Ring receipts use stable inventory UID/grade identities, not UI counters.
local Module={}
local roman={"I","II","III","IV"}
local rarity={"Uncommon","Rare","Legendary","Mythical"}
local function clean(value,max)
    local text=tostring(value or ""):gsub("`","'"):gsub("[%c]"," "):sub(1,max or 120)
    while utf8 and not utf8.len(text) do text=text:sub(1,-2) end
    return text
end
function Module.MaskPlayer(value)
    local text=clean(value,120)
    local size=utf8.len(text) or #text
    local keep=math.floor(size/3)
    local last=keep>0 and ((utf8.offset(text,keep+1) or (#text+1))-1) or 0
    return text:sub(1,last)..string.rep("*",size-keep)
end
function Module.NormalizeUrl(value)
    local url=tostring(value or ""):match("^%s*(.-)%s*$")
    local base,tail=url:match("^(https://discord%.com/api/webhooks/%d+/[%w_%-]+)(.*)$")
    if not base or tail~="" and not tail:match("^%?[%w_=&%%%.%-]+$") then return nil end
    local args={}
    for pair in tail:gsub("^%?",""):gmatch("[^&]+") do
        if not pair:match("^wait=") then args[#args+1]=pair end
    end
    args[#args+1]="wait=true"
    return base.."?"..table.concat(args,"&")
end
function Module.BuildPayload(context,items,settings,stamp,isTest,formatTime)
    local groups={}
    for _,item in ipairs(items) do
        local grade=tonumber(item.Grade)
        if grade and grade>=1 and grade<=4 and grade%1==0 then
            local key=clean(item.Name,64).."|"..grade
            if not groups[key] then groups[key]={Name=clean(item.Name,64),Grade=grade,Count=0} end
            groups[key].Count+=tonumber(item.Count) or 1
        end
    end
    local keys={};for key in pairs(groups) do keys[#keys+1]=key end;table.sort(keys)
    local lines={}
    for _,key in ipairs(keys) do
        local item=groups[key]
        lines[#lines+1]=string.format("%s [Tier %s - %s] x%d",item.Name,roman[item.Grade],rarity[item.Grade],item.Count)
    end
    local player=clean(context.DisplayName or context.Player,60)
    if settings.MaskPlayer then player=Module.MaskPlayer(player) end
    if context.Player and context.Player~=context.DisplayName then
        local username=clean(context.Player,20)
        if settings.MaskPlayer then username=Module.MaskPlayer(username) end
        player..=" (@"..username..")"
    end
    local detail=table.concat(lines,"\n")
    if isTest then detail="[TEST] "..detail end
    local payload={username="Trash Hub Webhook",allowed_mentions={parse={}},embeds={{
        title="Trash Hub Webhook",color=0xFBBF24,
        fields={{name="Player",value="```"..player.."```",inline=true},
            {name="Difficulty",value="```"..clean(context.Difficulty or "Unknown",40).."```",inline=true},
            {name="Detail",value="```"..detail:sub(1,980).."```",inline=false}},
        footer={text=formatTime and formatTime(stamp) or (os.date("!%H:%M | %d/%m/%Y",stamp+7*3600).." (UTC+7)")},
    }}}
    local ping=tostring(settings.PingUserId or "")
    if not settings.MaskPlayer and settings.PingMode=="User" and ping:match("^%d+$") and #ping>=17 and #ping<=20 then
        payload.content="<@"..ping..">";payload.allowed_mentions.users={ping}
    elseif not settings.MaskPlayer and settings.PingMode=="@everyone" then
        payload.content="@everyone";payload.allowed_mentions.parse={"everyone"}
    end
    return payload
end
local Controller={};Controller.__index=Controller
function Module.new(settings,deps,saved)
    local self=setmetatable({Settings=table.clone(settings),Deps=deps,Alive=true,Seen={},Queue={}},Controller)
    if type(saved)=="table" and type(saved.Updated)=="number" and deps.UTC()-saved.Updated>=0 and deps.UTC()-saved.Updated<=900 then
        self.Primed=saved.Primed==true
        self.Seen=type(saved.Seen)=="table" and saved.Seen or {}
        for _,entry in ipairs(type(saved.Queue)=="table" and saved.Queue or {}) do
            if #self.Queue<20 and type(entry)=="table" and type(entry.Items)=="table" and type(entry.Context)=="table"
                and type(entry.Stamp)=="number" and deps.UTC()-entry.Stamp<900 then
                entry.InFlight,entry.NextAt=nil,nil;self.Queue[#self.Queue+1]=entry
            end
        end
    end
    return self
end
function Controller:_status(text) if self.Alive and self.Deps.Status then self.Deps.Status(text) end end
function Controller:Export()
    local queue={}
    for _,entry in ipairs(self.Queue) do if not entry.InFlight then queue[#queue+1]={Items=entry.Items,Context=entry.Context,Stamp=entry.Stamp,Test=entry.Test} end end
    return {Primed=self.Primed,Seen=table.clone(self.Seen),Queue=queue,Updated=self.Deps.UTC()}
end
function Controller:_save()
    self.SavedAt=self.Deps.Now()
    if self.Deps.SaveState then self.Deps.SaveState(self:Export()) end
end
function Controller:Observe(snapshot)
    if not self.Alive or not snapshot or not snapshot.Ready then return end
    local added,changed={},not self.Primed
    local now=self.Deps.UTC()
    for uid,item in pairs(snapshot.ByUID or {}) do
        local grade=tonumber(item.Grade)
        if type(uid)=="string" and type(item.Name)=="string" and grade and grade>=1 and grade<=4 and grade%1==0 then
            local key=uid.."|"..item.Name.."|"..grade
            if not self.Seen[key] then
                changed=true
                if self.Primed then added[#added+1]={Name=item.Name,Grade=grade,Count=1} end
            end
            self.Seen[key]=now
        end
    end
    self.Primed=true
    local stale={}
    for key,at in pairs(self.Seen) do
        if type(at)~="number" or now-at>86400 then self.Seen[key]=nil else stale[#stale+1]={Key=key,At=at} end
    end
    if #stale>4096 then
        table.sort(stale,function(a,b)return a.At<b.At end)
        for i=1,#stale-4096 do self.Seen[stale[i].Key]=nil end
    end
    if #added>0 and self.Settings.Enabled and self.Settings.NotifyRingDrop then
        local context=self.Deps.Context()
        -- Separate large batches so Discord's 1,024-character field limit cannot hide rings.
        for first=1,#added,8 do
            local items={};for i=first,math.min(first+7,#added) do items[#items+1]=added[i] end
            self:_enqueue({Items=items,Context=context,Stamp=now})
        end
    end
    if changed then self:_save() end
end
function Controller:_enqueue(entry)
    if #self.Queue>=20 then self:_status("Queue full; notification skipped");return false end
    self.Queue[#self.Queue+1]=entry;self:_save();return true
end
function Controller:SendTest()
    if not self.Alive then return false end
    if not Module.NormalizeUrl(self.Settings.Url) then self:_status("Invalid Discord webhook URL");return false end
    return self:_enqueue({Items={{Name="Ring of Might",Grade=4,Count=1}},Context=self.Deps.Context(),Stamp=self.Deps.UTC(),Test=true})
end
function Controller:_cancel()
    local job=self.Job;self.Job=nil
    if job then job.Valid=false;if job.Thread then pcall(self.Deps.Cancel,job.Thread) end end
end
function Controller:SettingChanged(key,value)
    local old=self.Settings[key];self.Settings[key]=value
    if key=="Url" and old~=value or key=="Enabled" and not value or key=="NotifyRingDrop" and not value then
        self:_cancel();table.clear(self.Queue);self:_save()
    end
end
function Controller:Tick()
    if not self.Alive then return end
    if not self.SavedAt or self.Deps.Now()-self.SavedAt>=30 then self:_save() end
    if self.Job then
        if self.Deps.Now()-self.Job.Started>15 then
            self:_cancel();table.remove(self.Queue,1);self:_save();self:_status("Request timed out; delivery unknown")
        end
        return
    end
    local entry=self.Queue[1]
    if not entry then return end
    if not entry.Test and (not self.Settings.Enabled or not self.Settings.NotifyRingDrop) then
        table.remove(self.Queue,1);self:_save();return
    end
    if self.Deps.Now()<(entry.NextAt or 0) then return end
    local url=Module.NormalizeUrl(self.Settings.Url)
    if not url then table.remove(self.Queue,1);self:_save();self:_status("Invalid Discord webhook URL");return end
    local payload=Module.BuildPayload(entry.Context,entry.Items,self.Settings,entry.Stamp,entry.Test,self.Deps.FormatTime)
    local job={Valid=true,Started=self.Deps.Now()};self.Job=job
    entry.InFlight=true;self:_save();self:_status("Sending...")
    job.Thread=self.Deps.Spawn(function()
        if not self.Alive or not job.Valid or self.Job~=job then return end
        local ok,response=pcall(self.Deps.Request,url,payload)
        if not self.Alive or not job.Valid or self.Job~=job then return end
        self.Job=nil
        local code=ok and type(response)=="table" and tonumber(response.StatusCode)
        if code==429 and (entry.Attempts or 0)<2 then
            entry.Attempts=(entry.Attempts or 0)+1;entry.InFlight=false
            entry.NextAt=self.Deps.Now()+math.clamp(tonumber(response.RetryAfter) or 5,1,120)
            self:_status("Discord rate limit; retrying...")
        else
            table.remove(self.Queue,1)
            if code and code>=200 and code<300 then
                self.Sent=(self.Sent or 0)+1;self:_status("Sent successfully")
            else self:_status(code and ("Discord HTTP "..code) or "HTTP request failed") end
        end
        self:_save()
    end)
end
function Controller:Destroy()
    if not self.Alive then return end
    self:_save();self.Alive=false;self:_cancel()
end
return Module

    end)()
    local WebhookAdapter = (function()
-- Shares the existing inventory controller and owns all webhook callbacks/jobs.
local Adapter={}
local PUBLIC_WEBHOOK_URL="https://discord.com/api/webhooks/1561052983264026769/dsIVQgikAzjpzdmZl3r9r2T_8-TfYN5Ze_PmMQHNnu-kEQueUuMImRBuTAenXUWYkwg0"
local Binding={};Binding.__index=Binding
local function disconnect(c) if type(c)=="function" then c() elseif c then c:Disconnect() end end
local function identityCall(identity,callback)
    local getter,setter=getthreadidentity or getidentity,setthreadidentity or setidentity
    local previous=getter and getter()
    if setter and identity then setter(identity) end
    local result=table.pack(pcall(callback))
    if setter and previous then setter(previous) end
    if not result[1] then error(result[2],0) end
    return table.unpack(result,2,result.n)
end
function Binding:_context()
    local main=self.UI.LiveMain
    local difficulty=main and main.Settings.DungeonMode or self.UI.MainSettings.DungeonMode
    if workspace:GetAttribute("IsDungeonInstance")==true then
        local replicas=game.ReplicatedStorage:FindFirstChild("DungeonReplicationObjects")
        local guid=self.Player:GetAttribute("ExplorerGUID")
        if replicas and guid then for _,dungeon in ipairs(replicas:GetChildren()) do
            local explorers=dungeon:FindFirstChild("Explorers")
            if explorers and explorers:FindFirstChild(guid) then
                difficulty=dungeon:GetAttribute("Difficulty") or dungeon:GetAttribute("DungeonMode") or difficulty
                break
            end
        end end
        self.LastDifficulty=difficulty
    else difficulty=self.LastDifficulty or difficulty end
    if difficulty=="Normal" then difficulty="Easy" end
    return {Player=self.Player.Name,DisplayName=self.Player.DisplayName,Difficulty=difficulty or "Unknown"}
end
function Binding:_saveConfig()
    self.Env.TrashHubWebhookSettings=table.clone(self.Controller.Settings)
    if type(writefile)=="function" then pcall(writefile,self.ConfigPath,self.Http:JSONEncode(self.Controller.Settings)) end
end
function Binding:Destroy()
    if not self.Alive then return end
    self.Alive=false
    if self.Unsubscribe then disconnect(self.Unsubscribe) end
    if self.Connection then disconnect(self.Connection) end
    if self.Controller then self.Controller:Destroy() end
    if self.PublicController then self.PublicController:Destroy() end
    if self.Thread and self.Thread~=coroutine.running() then pcall(task.cancel,self.Thread) end
    local ui=self.UI
    if ui.OnWebhookSettingChanged==self.OnSetting then ui.OnWebhookSettingChanged=self.OldSetting end
    if ui.OnWebhookTestClick==self.OnTest then ui.OnWebhookTestClick=self.OldTest end
    if ui.SendWebhook==self.Send then ui.SendWebhook=self.OldSend end
    if ui.LiveWebhook==self then ui.LiveWebhook=nil end
    self.Unsubscribe,self.Connection,self.Thread,self.UI=nil,nil,nil,nil
end
function Adapter.Bind(ui,Module,options)
    options=options or {}
    if ui.LiveWebhook then ui.LiveWebhook:Destroy() end
    local player=game.Players.LocalPlayer
    local self=setmetatable({Alive=true,UI=ui,Player=player,Http=game:GetService("HttpService"),Env=getgenv(),
        Identity=(getthreadidentity or getidentity or function()end)(),
        OldSetting=ui.OnWebhookSettingChanged,OldTest=ui.OnWebhookTestClick,OldSend=ui.SendWebhook},Binding)
    local stem="TrashHub_RingWebhook_"..player.UserId
    self.ConfigPath,self.StatePath,self.PublicStatePath=stem.."_config.json",stem.."_state.json",stem.."_public_state.json"
    local function read(path)
        if type(isfile)=="function" and type(readfile)=="function" and isfile(path) then
            local ok,value=pcall(function() return self.Http:JSONDecode(readfile(path)) end)
            if ok and type(value)=="table" then return value end
        end
    end
    local loaded=read(self.ConfigPath) or self.Env.TrashHubWebhookSettings or {}
    local settings=table.clone(ui.WebhookSettings)
    for key,value in pairs(settings) do if type(loaded[key])==type(value) then settings[key]=loaded[key] end end
    if settings.PingMode~="User" and settings.PingMode~="@everyone" then settings.PingMode="None" end
    local function publicDestination(value)
        local normalized=Module.NormalizeUrl(value)
        return normalized and normalized:match("^[^?]+") == PUBLIC_WEBHOOK_URL
    end
    if publicDestination(settings.Url) then settings.Url="" end
    local saved=read(self.StatePath)
    self.LastDifficulty=saved and saved.LastDifficulty
    local deps={Now=os.clock,UTC=os.time,Spawn=task.defer,Cancel=task.cancel,
        Context=function() return self:_context() end,
        Status=function(text)
            if self.Alive then identityCall(self.Identity,function() ui.SetWebhookStatus(text) end) end
        end,
        SaveState=function(state)
            state.LastDifficulty=self.LastDifficulty
            if type(writefile)=="function" then pcall(writefile,self.StatePath,self.Http:JSONEncode(state)) end
        end,
        Request=options.Request or function(url,payload)
            return identityCall(self.Identity,function()
                local requestFn=(syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
                assert(type(requestFn)=="function","Executor HTTP unsupported")
                local response=requestFn({Url=url,Method="POST",Headers={["Content-Type"]="application/json"},Body=self.Http:JSONEncode(payload)})
                if type(response)~="table" then return {} end
                if tonumber(response.StatusCode)==429 then
                    local ok,body=pcall(function()return self.Http:JSONDecode(response.Body or "")end)
                    if ok and type(body)=="table" then response.RetryAfter=tonumber(body.retry_after) end
                end
                return response
            end)
        end,
    }
    self.Controller=Module.new(settings,deps,saved)
    local publicDeps=table.clone(deps)
    publicDeps.Status=function(text)
        if self.Alive and ui.SetPublicWebhookStatus then identityCall(self.Identity,function()ui.SetPublicWebhookStatus(text)end) end
    end
    publicDeps.SaveState=function(state)
        if type(writefile)=="function" then pcall(writefile,self.PublicStatePath,self.Http:JSONEncode(state)) end
    end
    -- Public routing is a source constant and never reads user configuration.
    self.PublicController=Module.new({Url=PUBLIC_WEBHOOK_URL,Enabled=true,NotifyRingDrop=true,
        PingMode="None",PingUserId="",MaskPlayer=true},publicDeps,read(self.PublicStatePath))
    self.OnSetting=function(key,value)
        if type(settings[key])~=type(value) then return end
        if key=="Url" and publicDestination(value) then
            self.Controller:SettingChanged("Url","");self:_saveConfig()
            ui.ApplyWebhookSettings(self.Controller.Settings)
            ui.SetWebhookStatus("Public endpoint is reserved; enter a personal webhook")
            return
        end
        self.Controller:SettingChanged(key,value);self:_saveConfig()
        if self.OldSetting then pcall(self.OldSetting,key,value) end
    end
    self.OnTest=function()return self.Controller:SendTest()end
    self.Send=self.OnTest
    ui.OnWebhookSettingChanged,ui.OnWebhookTestClick,ui.SendWebhook=self.OnSetting,self.OnTest,self.Send
    ui.LiveWebhook=self
    ui.ApplyWebhookSettings(settings)
    self.Connection=ui.ScreenGui.Destroying:Connect(function()self:Destroy()end)
    self:_saveConfig()
    self.Thread=task.defer(function()
        while self.Alive do
            self:_context()
            local controller=ui.LiveRings and ui.LiveRings.Controller
            if controller~=self.Rings then
                if self.Unsubscribe then disconnect(self.Unsubscribe);self.Unsubscribe=nil end
                self.Rings=controller
                if controller then self.Unsubscribe=controller:Subscribe(function(snapshot)
                    self.Controller:Observe(snapshot)
                    self.PublicController:Observe(snapshot)
                end) end
            end
            self.Controller:Tick()
            self.PublicController:Tick()
            task.wait(.25)
        end
    end)
    return self
end
return Adapter

    end)()
    WebhookAdapter.Bind(StatusUI, RingWebhook)
    screenGui:SetAttribute("WebhookVersion", "ring-receipts-public-v16")
end)()
-- END RING RECEIPT WEBHOOK

return StatusUI


]====]
local chunk, problem = loadstring(source)
assert(chunk, problem)
return chunk(source)
