local json = require("cjson")

local _M = {}
_M.version = "0.0.1"
_M.__index = _M

function _M.new(dict_name, window, phi, epsilon, number_of_counters)
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
  local number_of_counters = number_of_counters or 1/epsilon

  return setmetatable({ dict = dict, phi = phi, window = window, epsilon = epsilon, number_of_counters = number_of_counters }, _M)
end

function _M:process(key, weight)
  local weight = weight or 1
  local counters_json
  local hits, err = self.dict:incr("hits", 1)
  if not hits and err == "not found" then
    counters_json = "{}"
    self.dict:set("counters", counters_json, self.window)
    self.dict:add("hits", 1, self.window)
  else
    counters_json = self.dict:get("counters")
  end

  local ok, counters = pcall(json.decode, counters_json)
  local stats = counters[key]
  if stats then
    stats.weight = stats.weight + 1
  else
    local min_weight = math.huge
    local min_weight_index
    local current_number_of_counters = 0
    for key, stats in pairs(counters) do
      current_number_of_counters = current_number_of_counters + 1
      if stats.weight < min_weight then
        min_weight = stats.weight
        min_weight_index = key
      end
    end
    if current_number_of_counters < self.number_of_counters then
      stats = { weight = 1, overestimation = 0 }
    else
      counters[min_weight_index] = nil
      stats = { weight = min_weight + weight, overestimation = min_weight }
    end
    counters[key] = stats
  end

  local ok, counters_json = pcall(json.encode, counters)
  self.dict:replace("counters", counters_json)
end

function _M:report(key)
  local counters = self.dict:get("counters") or ""
  local hits = self.dict:get("hits") or 0
  return counters .. " <br/>hits: " .. hits
end

return _M
