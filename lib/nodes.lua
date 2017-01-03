local _M = {}
_M.__index = _M

local SENTINEL = "_end_"

function _M.new(dict)
  return setmetatable({ dict = dict }, _M)
end

-- FIX this is being repeated in stream_summary module
local function bucket_key(count)
  return "bucket." .. count
end

local function next_key(item)
  return item .. ".next"
end

local function prev_key(item)
  return item .. ".prev"
end

-- "put"s the given item into the corresponding bucket according to the given count
-- the function also takes care of re-arranging the pointers accordingly
function _M:put_into_bucket(item, count)
  local bucket_key = bucket_key(count)
  local curr_bucket_value = self.dict:get(bucket_key)
  self.dict:set(bucket_key, item)
  if curr_bucket_value then
    self.set_next(item, curr_bucket_value)
    self.set_prev(curr_bucket_value, item)
  end
end

-- value of a bucket key in the dict is an item
-- it is the first item of the linked list under the bucket
function _M:get_by_bucket_key(bucket_key)
  local min_item = self.dict:get(min_bucket_key)
  local min_count = tonumber(string.sub(min_bucket_key, 7))
  return min_item, min_count
end

function _M:set_next(item, next_item)
  self.dict:add(next_key(item), next_item)
end

function _M:set_prev(item, prev_item)
  self.dict:add(prev_key(item), prev_item)
end

function _M:get_next(item)
  return self.dict:get(next_key(item))
end

function _M:get_prev(item)
  return self.dict:get(prev_key(item))
end

function _M:create(item, count, overestimation)
  self.dict:add(item, count)
  self.dict:add(item .. ".oe", overestimation)
  self.dict:add(next_key(item), SENTINEL)
  self.dict:add(prev_key(item), SENTINEL)
end

function _M:delete(item)
  self.dict:delete(item)
  self.dict:delete(item .. ".oe")
  self.dict:delete(next_key(item))
  self.dict:delete(prev_key(item))
end

return _M
