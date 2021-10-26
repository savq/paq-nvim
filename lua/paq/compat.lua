-- Functions for nvim 0.4 compatibility.
-- This module will be removed once nvim 0.5 becomes stable.

local fn = setmetatable({}, {
    __index = function(_, key)
        return function(...)
            return vim.api.nvim_call_function(key, { ... })
        end
    end,
})

local function tbl_map(func, t)
    local rettab = {}
    for k, v in pairs(t) do
        rettab[k] = func(v)
    end
    return rettab
end

local function tbl_keys(t)
    local rettab = {}
    for k, _ in pairs(t) do
        table.insert(rettab, k)
    end
    return rettab
end

local function tbl_filter(func, t)
    local rettab = {}
    for _, v in pairs(t) do
        if func(v) then
            table.insert(rettab, v)
        end
    end
    return rettab
end

local function list_extend(dst, src, start, finish)
    for i = start or 1, finish or #src do
        table.insert(dst, src[i])
    end
    return dst
end

return setmetatable({
    fn = fn,
    cmd = vim.api.nvim_command,
    tbl_map = tbl_map,
    tbl_keys = tbl_keys,
    tbl_filter = tbl_filter,
    list_extend = list_extend,
}, {
    __index = function(self, key)
        return vim[key] or self[key]
    end,
})
