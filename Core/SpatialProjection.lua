local _, addon = ...
if type(addon) ~= "table" then return end

local Spatial = {}
addon.VignetteRadarSpatial = Spatial

local TWO_PI = math.pi * 2
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

Spatial.Number = addon.Secret.Number

function Spatial.Angle(value)
    value = Spatial.Number(value)
    if not value then return nil end
    value = value % TWO_PI
    return value > math.pi and value - TWO_PI or value
end

-- Identical bearing convention to the ordinary radar, followed by an
-- orthographic tilt of the horizontal map plane. No altitude is inferred.
function Spatial.Project(dx, dy, facing, range, radius, tilt)
    dx, dy = Spatial.Number(dx), Spatial.Number(dy)
    facing, range = Spatial.Number(facing), Spatial.Number(range)
    radius, tilt = Spatial.Number(radius), Spatial.Number(tilt)
    if not (dx and dy and facing and range and radius and tilt)
        or range <= 0 or radius <= 0 or tilt <= 0 or tilt > 1 then return nil end
    local distance = math.sqrt(dx * dx + dy * dy)
    local bearing = Spatial.Angle(atan2(dy, dx) - facing)
    local fraction = distance / range
    return -math.sin(bearing) * fraction * radius,
        math.cos(bearing) * fraction * radius * tilt, distance
end

return Spatial
