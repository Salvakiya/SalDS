# SalDS
Data Structures implemented with LuaJIT's FFI


Current data structures are..
**Vector(dynamic array)
**Hashtable

The Hashtable is not ready for use and does contain bugs. The Vector SHOULD be ready for use.

Example usage:
```lua
local salds = require("salds")
local ffi = require("ffi")
ffi.cdef[[
  struct Position{
    float x,y;
  };
]]

vec = salds.new_vec("struct Position")
vec:push(ffi.new("struct Position", 10, 20))
foo = vec:pop()
```

iteration
```lua
local pointer = vec:ptr()
for i = 0, vec:itersize() do
  print(pointer[i])
end
for i in vec:iterindex() do
  print(pointer[i])
end```
