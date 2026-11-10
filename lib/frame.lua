local frame = {}

frame.forward = function(orientation)
  local angle = 2 * math.pi * orientation
  return {x = math.sin(angle), y = -math.cos(angle)}
end

frame.right = function(orientation)
  local angle = 2 * math.pi * orientation
  return {x = math.cos(angle), y = math.sin(angle)}
end

-- shared.lua offsets are {side, forward}: every hardpoint lies along the stock's length and grinder_offset sits at the nose.
frame.rotate = function(orientation, offset)
  local forward, right = frame.forward(orientation), frame.right(orientation)
  return {x = right.x * offset[1] + forward.x * offset[2], y = right.y * offset[1] + forward.y * offset[2]}
end

frame.place = function(entity, offset)
  local rotated, position = frame.rotate(entity.orientation, offset), entity.position
  return {x = position.x + rotated.x, y = position.y + rotated.y}
end

frame.distance = function(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

return frame
