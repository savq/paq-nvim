-- Functions for nvim 0.4 compatibility.
-- This module will be removed once nvim 0.5 becomes stable.

local vfn = vim.api.nvim_call_function

local compat = {}

function tbl_map(func, t)
    if vfn('has', {'nvim-0.5'}) == 1 then
        return vim.tbl_map(func, t)
    end
    local rettab = {}
    for k, v in pairs(t) do
        rettab[k] = func(v)
    end
    return rettab
end

function tbl_keys(t)
    if vfn('has', {'nvim-0.5'}) == 1 then
        return vim.tbl_keys(t)
    end
    local rettab = {}
    for k, _ in pairs(t) do
        table.insert(rettab, k)
    end
    return rettab
end

function tbl_filter(func, t)
    if vfn('has', {'nvim-0.5'}) == 1 then
        return vim.tbl_filter(func, t)
    end
    local rettab = {}
    for _, v in pairs(t) do
        if func(v) then
            table.insert(rettab, v)
        end
    end
    return rettab
end

function list_extend(dst, src, start, finish)
    if vfn('has', {'nvim-0.5'}) == 1 then
        return vim.list_extend(dst, src, start, finish)
    end
    for i = start or 1, finish or #src do
        table.insert(dst, src[i])
    end
    return dst
end

return {
    tbl_map = tbl_map,
    tbl_keys = tbl_keys,
    tbl_filter = tbl_filter,
    list_extend = list_extend,
}
