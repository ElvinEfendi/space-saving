local json = require("cjson")
local resty_lock = require("resty.lock")

local _M = {}
_M.version = "0.0.1"
_M.__index = _M

-- initialize an instance of algorithm with given parameters using
-- the giving shared dict and window(in seconds) size
function _M.new(dict_name, window, phi, epsilon, max_counters_size)
  local dict = ngx.shared[dict_name]
  if not dict then
    return nil, "shared dict not found"
  end
  local window = window or 5 * 60
  -- this defines what should be considered frequent
  -- an element i is considered frequent if f(i) >= phi*hits
  local phi = phi or 0.001
  -- this is the error rate we allow, i.e f^(i) >= (phi-epsilon)*hits
  local epsilon = epsilon or 0.001
  -- when the stream distribution is ignored O(1/epsilon) is the uper bound for the number of counters needed
  local max_counters_size = max_counters_size or 1/epsilon

  return setmetatable({ dict = dict, phi = phi, window = window, epsilon = epsilon, max_counters_size = max_counters_size }, _M)
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

local function incr_hits_and_init_counters(self)
  local hits, err = self.dict:incr("hits", 1)
  if not hits and err ~= "not found" then
    return nil, err
  elseif not hits then
    self.dict:set("counters", "{}", self.window)
    self.dict:add("hits", 1, self.window)
  end
end

local function get_counters(self)
  local counters_json = self.dict:get("counters")
  local ok, counters = pcall(json.decode, counters_json)
  if not ok then
    return nil, string.format("Could not decode counters, error: %s", counters)
  end
  return counters, nil
end

local function update_counters(self, counters)
  local ok, counters_json = pcall(json.encode, counters)
  if not ok then
    return string.format("Could not encode counters, error: %s", counters_json)
  end
  local ok, err = self.dict:replace("counters", counters_json)
  if not ok then
    return err
  end
  return nil
end

local function support(self)
  local hits, err = self.dict:get("hits")
  if not hits then
    return nil, string.format("Could not get hits: %s", err)
  end
  return self.phi * hits, nil
end

function _M:process(key)
  if not key then
    return "key can not be nil"
  end
  local lock = resty_lock:new("locks_dict")
  local elapsed, err = lock:lock(key)
  if not elapsed then
    return "failed to acquire the lock: " .. tostring(err)
  end
  incr_hits_and_init_counters(self)
  local counters, err = get_counters(self)
  if err then
    return err
  end
  local stats = counters[key]
  if stats then
    stats.count = stats.count + 1
  else
    local min_count, min_count_key, counters_size = calculate_min_and_size(counters)
    if counters_size < self.max_counters_size then
      stats = { count = 1, overestimation = 0 }
    else
      counters[min_count_index] = nil
      stats = { count = min_count + 1, overestimation = min_count }
    end
    counters[key] = stats
  end
  local err = update_counters(self, counters)
  if err then
    return "could not update counters: " .. tostring(err)
  end
  local ok, err = lock:unlock()
  if not ok then
    return "failed to unlock: " .. tostring(err)
  end
  return nil
end

function _M:frequent_keys()
  local counters, err = get_counters(self)
  if err then
    return nil, nil, err
  end
  local support, err = support(self)
  if err then
    return nil, nil, err
  end
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
  local counters, err = get_counters(self)
  if err then
    return nil, err
  end
  local support, err = support(self)
  if err then
    return nil, err
  end
  return counters[key], nil
end

return _M
