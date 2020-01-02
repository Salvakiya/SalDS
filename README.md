# SalDS
Data Structures implemented with LuaJIT's FFI


Current data structures are..

* Vector(dynamic array)
* Hashtable

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

iteration - these functions are provided to help with the fact that these indexes start at 0 and not 1 like lua arrays
```lua
--get the pointer to the c data
local pointer = vec:ptr()

--itersize() will return the size-1
for i = 0, vec:itersize() do
  print(pointer[i])
end

--or iterate over I like so
for i in vec:iterindex() do
  print(pointer[i])
end
```
