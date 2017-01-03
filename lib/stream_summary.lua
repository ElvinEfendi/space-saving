local nodes = require("nodes")

local _M = {}
_M.__index = _M

local MIN_BUCKET_KEY = "bucket.min"

function _M.new(dict, max_items_len)
  return setmetatable({ dict = dict, max_items_len = max_items_len, nodes = nodes.new(dict) }, _M)
end

local function bucket_key(count)
  return "bucket." .. count
end

-- adds the new item into the stream summary under the correct count bucket
-- the function also takes care of the links
-- always adds the item as the first element of the linked list under the given bucket
local function add(self, item, count, overestimation)
  self.nodes:create(item, count, overestimation)
  self.nodes:put_into_bucket(item, count)
end

-- deletes the item with minimum count and adds the given one with overestimation
local function replace_min(self, item)
  local min_bucket_key = self.dict:get(MIN_BUCKET_KEY)
  local min_item, min_count = self.nodes:get_by_bucket_key(min_bucket_key)
  local next_item = self.nodes:get_next(min_item)
  self.nodes:delete(min_item)
  add(self, item, min_count + 1, min_count)
  if next_item then
    self.dict:set(min_bucket_key, next_item)
  else
    -- there's no item left in this bucket
    self.dict:delete(min_bucket_key)
    self.dict:set(MIN_BUCKET_KEY, bucket_key(min_count + 1))
  end
end

function _M:incr(item)
  local count, err = self.dict:incr(item, 1)
  if err then
    return "could not incr item: " .. tostring(err)
  end
  -- TODO complete this
  self.nodes:put_into_bucket(item, count)
end

function _M:start_monitoring(item)
  local items_len = self.dict:get(ITEMS_LEN_KEY) || 0
  if items_len < self.max_items_len then
    add(self, item, 1, 0)
    self.dict:incr(ITEMS_LEN_KEY, 1, 0)
    if items_len == 0 then
      self.dict:set(MIN_BUCKET_KEY, bucket_key(count))
    end
  else
    replace_min(self, item)
  end
end

return _M
