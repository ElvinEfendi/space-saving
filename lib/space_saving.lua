local json = require("cjson")

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
  -- an element i is considered frequent if f(i) >= phi*number_of_hits
  local phi = phi or 0.001
  -- this is the error rate we allow, i.e f^(i) >= (phi-epsilon)*number_of_hits
  local epsilon = epsilon or 0.001
  -- according to the paper 1/epsilon is the safest value to guarantee f_i > epsilon*number_of_hits
  local max_counters_size = max_counters_size or 1/epsilon

  return setmetatable({ dict = dict, phi = phi, window = window, epsilon = epsilon, max_counters_size = max_counters_size }, _M)
end

local function calculate_min_and_size(counters)
  local min_count = math.huge
  local min_count_key
  local counters_size = 0
  for key, stats in pairs(counters) do
    counters_size = counters_size + 1
    if stats.counters < min_count then
      min_count = stats.count
      min_count_index = key
    end
  end
  return min_count, min_count_key, counters_size
end

local function get_or_init_counters(self)
  local counters_json
  local hits, err = self.dict:incr("hits", 1)
  if hits then
    counters_json = self.dict:get("counters")
  elseif err ~= "not found" then
    return nil, err
  else
    counters_json = "{}"
    self.dict:set("counters", counters_json, self.window)
    self.dict:add("hits", 1, self.window)
  end

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

function _M:process(key)
  local counters, err = get_or_init_counters(self)
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
  return update_counters(self, counters)
end

function _M:report(key)
  local counters = self.dict:get("counters") or ""
  local hits = self.dict:get("hits") or 0
  return counters .. " <br/>hits: " .. hits
end

return _M
