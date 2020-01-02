local ffi = require("ffi")
local C = ffi.C
local _allocations = {}

ffi.cdef[[
    void* malloc(size_t size);
    void* calloc(size_t num, size_t size);
    void* realloc(void *ptr, size_t new_size);
    void free(void *ptr);
    void *memcpy(void *str1, const void *str2, size_t n);
]]

--if you want to manually free a malloc
local function free(pointer)
    if pointer then
        ffi.gc(pointer, nil)
        ffi.C.free(pointer)
    end
end

--if you want to malloc (size*sizeof(type)) will cast to array of type
local function alloc(size, type)
    if not (size and type) then error("alloc requires 2 arguments(size, type)",2) end
    local ctype_size = ffi.sizeof(type)
    local _allocation = ffi.C.calloc(size,ctype_size)
    
    if not _allocation then return nil end

    return ffi.gc(ffi.cast(type.."*",_allocation),ffi.C.free)
end

--if you want to copy to dest from src (sizeof(type)*size) bytes
local function copy(dest, src, type, size)
    ffi.copy(dest,src,size*ffi.sizeof(type))
end

local function _allocate(self, reserve_n, shrink_to_fit)
    --determine the new size
    local new_capacity = math.max(1,reserve_n or 2*self._capacity, shrink_to_fit and 1 or 2*self._capacity)
    local new_data = alloc(new_capacity, self._ctype) -- allocate new memory
    local min_capacity = math.min(new_capacity, self._capacity) -- determine relevant area to copy
    copy(new_data, self._c_pointer, self._ctype, min_capacity) -- copy data
    free(self._c_pointer)
    self._c_pointer = new_data
    self._capacity = new_capacity
end


local struct_counter = 0
local struct_cahce = {}
--[[
    struct("foo","float x,y;") or struct("float x,y;") are both valid
]]
local function struct(name_or_body, body)
    local name          --what the struct is nammed
    local structbody    --body of the struct

    if body then
        --the user specified a name

        name = name_or_body
        structbody = body
    else
        --auto generate a name
        struct_counter = struct_counter+1
        name = "__salstruct_"..struct_counter
        struct_body = name_or_body
    end

    if struct_cache[body] then
        return struct_cache[body]
    end

    name = "struct "..name
    --define
    ffi.cdef(table.concat{name, "{", structbody, "};"})
    struct_cache[body] = name
    return name
end


local _vec_mt = {
    __index = {
        allocate = function(self, reserve_n, shrink_to_fit)
            --determine the new size
            local new_capacity = math.max(1,reserve_n or 2*self._capacity, shrink_to_fit and 1 or 2*self._capacity)
            local new_data = alloc(new_capacity, self._c_type) -- allocate new memory
            local min_capacity = math.min(new_capacity, self._capacity) -- determine relevant area to copy
            copy(new_data, self._c_pointer, self._c_type, min_capacity) -- copy data
            free(self._c_pointer)
            self._c_pointer = new_data
            self._capacity = new_capacity
        end,

        compact = function(self)
            self:allocate(self._size, true)
            return self
        end,

        reserve_n = function(self, count)
            self:allocate(count)
            return self
        end,

        push = function(self, value)
            local new_size = self._size+1
            if new_size>self._capacity then self:allocate(new_size) end
            self._c_pointer[self._size] = value
            self._size = new_size
        end,

        pop = function(self)
            if self._size>0 then
                self._size=self._size-1
                return self._c_pointer[self._size]
            end
        end,

        insert = function(self, index, value)
            local new_size = self._size+1
            if new_size>self._capacity then self:allocate(new_size) end
            for i = self._size-1, index, -1 do
                self._c_pointer[i+1] = self._c_pointer[i]
            end
            self._c_pointer[index] = value
            self._size = new_size
        end,

        remove = function(self, index)
            if index == nil then return self:pop() end
            if index<0 or index>=self._size then
                error("index <"..index.."> is out of bounds!", 2)
            end
            local v = self._c_pointer[index]
            for i = index, self._size-2 do
                self._c_pointer[i] = self._c_pointer[i+1]
            end
            self._size = self._size-1
            return v
        end,

        set = function(self, index, value)
            if index<0 or index>=self._size then
                error("index <"..index.."> is out of bounds!", 2)
            end
            self._c_pointer[index] = value
        end,

        get = function(self, index)
            if index<0 or index>=self._size then
                error("index <"..index.."> is out of bounds!", 2)
            end
            return self._c_pointer
        end,

        ptr = function(self)
            return self._c_pointer
        end,

        itersize = function(self)
            return self._size-1
        end,

        iterindex = function(self)
            local index = -1
            local count = self._size-1
            return function()
                index = index+1
                if index<=count then
                    return index
                end
            end
        end,

        tostr = function(self)
            return ffi.string(self._c_pointer)
        end,
    }
}


local function new_vec(type)
    local self = {
        _c_pointer = nil,
        _c_type = type,
        _capacity = 0,
        _size = 0
    }
    return setmetatable(self, _vec_mt)
end


local function hash(cdata, size)
    --local size = ffi.sizeof(type)
    local s = ffi.string(cdata)
    local read = ffi.cast("uint8_t*", s)
    local hash = 0
    for i = 0, #s do
        hash = hash + read[i]*2654435761
    end
    
    return hash
end

_hash_mt = {
    __index = {
        allocate = function(self)
            if self._size<self._capacity/1.8 then
                return
            end
            
            local new_capacity = math.max(8, self._capacity*2)
            local new_data = alloc(new_capacity, self._bucket_type)
            if not new_data then
                error("allocation failed!",3)
            end
            if self._c_pointer then
                
                local old = self._c_pointer
                local old_capacity = self._capacity
                self._capacity = new_capacity
                self._c_pointer = new_data
                self._size = 0
                for i=0,old_capacity-1 do
                    if old[i].occupied == 1 then
                        self:put(old[i].key,old[i].val)
                    end
                end
            else
                
                self._capacity = new_capacity
                self._c_pointer = new_data
            end

        end,

        put = function(self, key, value)
            self:allocate()
            key = ffi.cast(self._key_type, key)
            local i = (hash(key, ffi.sizeof(self._key_type)) % self._capacity)
            local entry = self._bucket_new(1, 0, key, value)
            local c = i
            while true do
                if self._c_pointer[c].occupied == 0 then
                    
                    self._c_pointer[c] = entry
                    self._size = self._size+1
                    self._max_distance = math.max(self._max_distance, entry.distance)
                    return
                else
                    if self._c_pointer[c].key == key then--replace value with same key
                        self._c_pointer[c] = entry
                        return
                    end
                    if self._c_pointer[c].distance<entry.distance then
                        self._c_pointer[c], entry = entry, self._c_pointer[c]
                    end
                end
                c = (c + 1) %self._capacity
                entry.distance = entry.distance + 1
            end
        end,

        get = function(self, key)
            key = ffi.cast(self._key_type, key)
            local i = (hash(key, ffi.sizeof(self._key_type)) % self._capacity)
            local entry
            local c = i
            local d = 0
            while d<=self._max_distance+1 do
                entry = self._c_pointer[c]
                if entry.key == key then
                    return entry.val
                end
                c = (c + 1)%self._capacity
                d = d + 1
            end
            return nil
        end,

        del = function(self, key)
            key = ffi.cast(self._key_type, key)
            local i = hash(key, ffi.sizeof(self._key_type)) % self._size
            local entry
            local c = i
            while c<=self._max_distance do
                entry = self._c_pointer[c]
                if entry.key == key then
                    entry.key = ffi.new(self._key_type)
                    entry.occupied = false
                end
            end
            return nil
        end,
    }
}

hashtable_counter = 0
local function new_hashtable_type(key_type,val_type)
    hashtable_counter = hashtable_counter+1
    local name = "__salds_hash_bucket_"..hashtable_counter
    ffi.cdef([[
        struct ]]..name..[[{
            uint8_t occupied;
            uint8_t distance;
            ]]..key_type..[[ key;
            ]]..val_type..[[ val;
        };
    ]])
    return function()
        local self = {
        _bucket_new = ffi.typeof("struct "..name),
        _bucket_type = "struct "..name,
        _key_type = key_type,
        _val_type = val_type,
        _max_distance = 0,
        _size = 0,
        _capacity = 0,
        _c_pointer = nil,

        }
        return setmetatable(self, _hash_mt)
    end
end


return {
    new_hashtable_type = new_hashtable_type,
    new_vec = new_vec
}
