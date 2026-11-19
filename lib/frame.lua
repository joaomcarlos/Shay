local frame = {}

frame.forward = function(orientation)
  local angle = 2 * math.pi * orientation
  return {x = math.sin(angle), y = -math.cos(angle)}
end

frame.right = function(orientation)
  local angle = 2 * math.pi * orientation
  return {x = math.cos(angle), y = math.sin(angle)}
end

-- shared.lua offsets are {side, forward}: every hardpoint lies along the stock's length.
frame.rotate = function(orientation, offset)
  local forward, right = frame.forward(orientation), frame.right(orientation)
  return {x = right.x * offset[1] + forward.x * offset[2], y = right.y * offset[1] + forward.y * offset[2]}
end

frame.place = function(entity, offset)
  local rotated, position = frame.rotate(entity.orientation, offset), entity.position
  return {x = position.x + rotated.x, y = position.y + rotated.y}
end

-- frame.place without the table churn: fills `out` for per-tick callers that
-- consume the position synchronously (teleport targets and the like).
frame.place_into = function(entity, offset, out)
  local angle = 2 * math.pi * entity.orientation
  local sin, cos = math.sin(angle), math.cos(angle)
  local position = entity.position
  out.x = cos * offset[1] + sin * offset[2] + position.x
  out.y = sin * offset[1] - cos * offset[2] + position.y
  return out
end

frame.distance = function(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

return frame
