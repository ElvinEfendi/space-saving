use Test::Nginx::Socket::Lua 'no_plan';
use Cwd qw(cwd);

my $pwd = cwd();
my $cpath = "$pwd/vendor/_linux/?.so";
if ($^O eq "darwin") {
  $cpath = "$pwd/vendor/_osx/?.so";
}
our $HttpConfig = <<"_EOC_";
  lua_package_cpath "$cpath";
  lua_package_path "$pwd/lib/?.lua;$pwd/../lua-resty-lock/lib/?.lua;;";
  lua_shared_dict space_saving_dict 10m;
  lua_shared_dict locks_dict 100k;
_EOC_

no_long_string();
run_tests();

__DATA__

=== TEST 1: Test process(key) function
--- http_config eval: $::HttpConfig
--- config
location = /t {
  access_by_lua '
    local space_saving = require("space_saving")
    local ss = space_saving.new("space_saving_dict", nil, nil, nil, 2)
    ss:process(ngx.var.arg_key)
  ';
  content_by_lua '
    local json = require("cjson")
    local space_saving = require("space_saving")
    local ss = space_saving.new("space_saving_dict", nil, nil, nil, 2)
    local frequent_keys, guaranteed, err = ss:frequent_keys()
    ngx.say(json.encode(frequent_keys))
  ';
}
--- pipelined_requests eval
["GET /t?key=1", "GET /t?key=1", "GET /t?key=2", "GET /t?key=3"]
--- response_body eval
["{\"1\":{\"overestimation\":0,\"count\":1}}\n",
 "{\"1\":{\"overestimation\":0,\"count\":2}}\n",
 "{\"1\":{\"overestimation\":0,\"count\":2},\"2\":{\"overestimation\":0,\"count\":1}}\n",
 "{\"1\":{\"overestimation\":0,\"count\":2},\"3\":{\"overestimation\":1,\"count\":2}}\n"]

=== TEST 2: It should find frequent keys with given support
We want the algorithm to report all keys in the processed stream
that makes more than one-third of the whole stream, so phi = 1/3.
--- http_config eval
"$::HttpConfig"
. qq!
  init_by_lua '
    local space_saving = require("space_saving")
    local ss = space_saving.new("space_saving_dict", nil, 1/3)
    processed_stream = {1, 1, 2, 3, 1, 2, 2, 2}
    for _, key in ipairs(processed_stream) do
      ss:process(key)
    end
  ';
!
--- config
location = /t {
  access_by_lua '
    local space_saving = require("space_saving")
    local ss = space_saving.new("space_saving_dict", nil, 1/3)
    ss:process(ngx.var.arg_key)
  ';
  content_by_lua '
    local json = require("cjson")
    local space_saving = require("space_saving")
    local ss = space_saving.new("space_saving_dict", nil, 1/3)
    local frequent_keys, guaranteed, err = ss:frequent_keys()
    ngx.say(json.encode(frequent_keys))
  ';
}
--- request
GET /t?key=3
--- response_body
{"2":{"overestimation":0,"count":4}}
