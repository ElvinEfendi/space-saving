local _M = {}
_M.version = "0.0.1"
_M.__index = _M

-- initialize an instance of algorithm with given parameters using
-- the giving shared dict and window(in seconds) size
function _M.new(phi, epsilon, max_counters_size)
  -- this defines what should be considered frequent
  -- an element i is considered frequent if f(i) >= phi*hits
  local phi = phi or 0.001
  -- this is the error rate we allow, i.e f^(i) >= (phi-epsilon)*hits
  local epsilon = epsilon or 0.001
  -- when the stream distribution is ignored 1/epsilon is the uper bound for the number of counters needed
  local max_counters_size = max_counters_size or 1/epsilon

  local o = {
    hits = 0,
    counters = {},
    phi = phi,
    epsilon = epsilon,
    max_counters_size = max_counters_size
  }

  return setmetatable(o, _M)
end

local function calculate_min_and_size(counters)
  local min_count = math.huge
  local min_count_key
  local counters_size = 0
  for key, stats in pairs(counters) do
    counters_size = counters_size + 1
    if stats.count < min_count then
      min_count = stats.count
      min_count_index = key
    end
  end
  return min_count, min_count_key, counters_size
end

local function get_support(self)
  return self.phi * self.hits
end

function _M:process(key)
  if not key then
    return "key can not be nil"
  end

  self.hits = self.hits + 1

  local stats = self.counters[key]
  if stats then
    stats.count = stats.count + 1
  else
    local min_count, min_count_key, counters_size = calculate_min_and_size(counters)
    if counters_size < self.max_counters_size then
      -- add a new counter for the key since there's still a room
      stats = { count = 1, overestimation = 0 }
    else
      counters[min_count_key] = nil -- deletes the key with minimum hits
      stats = { count = min_count + 1, overestimation = min_count }
    end
    counters[key] = stats
  end
  self.counters = counters

  return nil
end

function _M:frequent_keys()
  local support = get_support(self)
  local frequent_keys = {}
  local guaranteed = true
  for key, stats in pairs(counters) do
    if stats.count > support then
      frequent_keys[key] = stats
      if stats.count - stats.overestimation < support then
        guaranteed = false
      end
    end
  end
  return frequent_keys, guaranteed, nil
end

function _M:stats(key)
  return self.counters[key]
end

return _M
