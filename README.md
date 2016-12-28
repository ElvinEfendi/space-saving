# Space Saving
Space Saving is an efficient counter based algorithm to find all frequent and top-k frequent items in a stream. This is the implementation of it as an Nginx Lua module to discover frequent items in a given stream. The implementation uses time based sliding window to focus on an interval of time rather than the whole history. Space Saving is deterministic but it solves a relaxed version of the original frequent items discovery problem. That being said, it can report if its output is guaranteed to be sound. It should also be noted that this module does not implement the Stream-Summary data structure described in the original paper([1]).


## Usage
```
http {
  ...
  lua_shared_dict space_saving_dict 10m;
  ...

  server {
    ...
    location / {
      access_by_lua '
        local space_saving = require("space_saving")
        -- track frequent API clients in 15 minutes windows
        local ss = space_saving.new("space_saving_dict", 15 * 60)
        local api_client_id = ngx.var.arg_api_client_id
        ss:process(api_client_id)

        -- get the frequency of given API client and do something in real time
        local stats = ss:stats(api_client_id)

        -- get list of all frequent API clients
        local api_clients, guaranteed = ss:frequent_keys()
      ';
    }
    ...
  }
}
```

## References
 1. Efficient computation of frequent and top-k elements in data streams by Ahmed Metwally et al.
 2. Finding Frequent Items in Data Streams by Graham Cormode et al.
