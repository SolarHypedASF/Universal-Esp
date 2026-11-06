-- Player ESP: box, name, and distance.
-- Project with WorldToViewportPoint. WorldToScreenPoint adds the topbar inset and shifts every box.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local drawings = {}
local connection: RBXScriptConnection? = nil
local running = true

local genv = getgenv()
local previousCleanup = genv.__playerEspCleanup
genv.__playerEspCleanup = nil
if type(previousCleanup) == "function" then
	previousCleanup()
end

-- live-reload injects STATE into the global environment. Read it without a bare global
-- so the editor type checker accepts the script when it is opened on its own.
local live: any = (genv :: any).STATE
if type(live) ~= "table" then
	local compiled = loadstring("return STATE")
	if compiled then
		local ok, value = pcall(compiled)
		if ok and type(value) == "table" then
			live = value
		end
	end
end

local function destroyPack(pack)
	pack.box:Remove()
	pack.name:Remove()
	pack.distance:Remove()
end

local function destroyDrawings()
	for player, pack in pairs(drawings) do
		destroyPack(pack)
		drawings[player] = nil
	end
end

local function cleanup()
	if not running then
		return
	end
	running = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	destroyDrawings()
	if genv.__playerEspCleanup == cleanup then
		genv.__playerEspCleanup = nil
	end
end

genv.__playerEspCleanup = cleanup
if type(live) == "table" and type(live.onCleanup) == "function" then
	live.onCleanup(cleanup)
end

local function ensure(player)
	local pack = drawings[player]
	if pack then
		return pack
	end

	local box = Drawing.new("Square")
	box.Filled = false
	box.Thickness = 1
	box.Transparency = 1
	box.Visible = false

	local name = Drawing.new("Text")
	name.Size = 14
	name.Center = true
	name.Outline = true
	name.OutlineColor = Color3.new(0, 0, 0)
	name.Transparency = 1
	name.Visible = false

	local distance = Drawing.new("Text")
	distance.Size = 13
	distance.Center = true
	distance.Outline = true
	distance.OutlineColor = Color3.new(0, 0, 0)
	distance.Color = Color3.fromRGB(230, 230, 230)
	distance.Transparency = 1
	distance.Visible = false

	pack = {
		box = box,
		name = name,
		distance = distance,
	}
	drawings[player] = pack
	return pack
end

local function hide(pack)
	pack.box.Visible = false
	pack.name.Visible = false
	pack.distance.Visible = false
end

local CORNERS = {
	Vector3.new(-1, -1, -1),
	Vector3.new(-1, -1, 1),
	Vector3.new(-1, 1, -1),
	Vector3.new(-1, 1, 1),
	Vector3.new(1, -1, -1),
	Vector3.new(1, -1, 1),
	Vector3.new(1, 1, -1),
	Vector3.new(1, 1, 1),
}

local function colorFor(player: Player): Color3
	if player.Team then
		return player.TeamColor.Color
	end
	return Color3.fromRGB(255, 80, 80)
end

local function step()
	if not running then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local origin = camera.CFrame.Position
	local viewport = camera.ViewportSize
	local seen = {}

	for _, player in Players:GetPlayers() do
		if player ~= localPlayer then
			seen[player] = true
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local pack = ensure(player)

			if humanoid and root and humanoid.Health > 0 then
				local ok, cf, size = pcall(character.GetBoundingBox, character)
				if ok and cf and size then
					local half = size * 0.5
					local minX, minY = math.huge, math.huge
					local maxX, maxY = -math.huge, -math.huge
					local inFront = false

					for _, sign in CORNERS do
						local world = (cf :: CFrame):PointToWorldSpace(half * sign)
						local screen = camera:WorldToViewportPoint(world)
						if screen.Z > 0 then
							inFront = true
							minX = math.min(minX, screen.X)
							minY = math.min(minY, screen.Y)
							maxX = math.max(maxX, screen.X)
							maxY = math.max(maxY, screen.Y)
						end
					end

					local overlaps = inFront
						and maxX > 0
						and maxY > 0
						and minX < viewport.X
						and minY < viewport.Y

					if overlaps then
						local width = math.max(maxX - minX, 2)
						local height = math.max(maxY - minY, 2)
						local color = colorFor(player)
						local studs = math.floor((root.Position - origin).Magnitude + 0.5)

						pack.box.Position = Vector2.new(minX, minY)
						pack.box.Size = Vector2.new(width, height)
						pack.box.Color = color
						pack.box.Visible = true

						pack.name.Text = player.DisplayName
						pack.name.Color = color
						pack.name.Position = Vector2.new(minX + width * 0.5, minY - 16)
						pack.name.Visible = true

						pack.distance.Text = string.format("%d studs", studs)
						pack.distance.Position = Vector2.new(minX + width * 0.5, maxY + 2)
						pack.distance.Visible = true
					else
						hide(pack)
					end
				else
					hide(pack)
				end
			else
				hide(pack)
			end
		end
	end

	for player, pack in pairs(drawings) do
		if not seen[player] then
			destroyPack(pack)
			drawings[player] = nil
		end
	end
end

if type(live) == "table" and type(live.connect) == "function" then
	connection = live.connect(RunService.RenderStepped, step)
else
	connection = RunService.RenderStepped:Connect(step)
end
