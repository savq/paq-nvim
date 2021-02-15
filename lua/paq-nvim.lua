-- Constants
local PATH    = vim.api.nvim_call_function('stdpath', {'data'}) .. '/site/pack/paqs/'
local LOGFILE = vim.api.nvim_call_function('stdpath', {'cache'}) .. '/paq.log'
local GITHUB  = 'https://github.com/'
local REPO_RE = '^[%w-]+/([%w-_.]+)$'
local DATEFMT = '%F T %H:%M:%S%z'

local uv = vim.loop -- Alias for Neovim's event loop (libuv)
local packages = {} -- Table of 'name':{options} pairs
local run_hook      -- To handle mutual funtion recursion

local msgs = {
    clone = 'cloned',
    pull = 'pulled changes for',
    remove = 'removed',
    ['run hook for'] = 'ran hook for',
}

local num_pkgs = 0
local counters = {
    clone = {ok = 0, fail = 0},
    pull = {ok = 0, fail = 0},
    remove = {ok = 0, fail = 0},
}

-- Helper functions to replace 0.5 features

local function tbl_map(func, t)
    if vim.api.nvim_call_function('has', {'nvim-0.5'}) == 1 then
        return vim.tbl_map(func, t)
    end
    local rettab = {}
    for k, v in pairs(t) do
        rettab[k] = func(v)
    end
    return rettab
end

-- Warning: This mutates dst!
local function list_extend(dst, src, start, finish)
    if vim.api.nvim_call_function('has', {'nvim-0.5'}) == 1 then
        return vim.list_extend(dst, src, start, finish)
    end
    for i = start or 1, finish or #src do
        table.insert(dst, src[i])
    end
    return dst
end


local function inc(counter, result)
    counters[counter][result] = counters[counter][result] + 1
end

local function output_result(num, total, operation, name, ok)
    local result = ok and msgs[operation] or 'Failed to ' .. operation
    print(string.format('Paq [%d/%d] %s %s', num, total, result, name))
    return ok
end

local function count_ops(operation, name, ok)
    local op = counters[operation]
    local result = ok and 'ok' or 'fail'
    inc(operation, result)
    output_result(op[result], num_pkgs, operation, name,  ok)
    if op.ok + op.fail == num_pkgs then
        op.ok, op.fail = 0, 0
        vim.api.nvim_command 'packloadall! | helptags ALL'
    end
    return ok
end

local function call_proc(process, pkg, args, cwd, ishook)
    local log, stderr, handle, ok

    log = uv.fs_open(LOGFILE, 'a+', 0x1A4) -- FIXME: Write in terms of uv.constants
    stderr = uv.new_pipe(false)
    stderr:open(log)

    handle =
        uv.spawn(process,
            {args=args, cwd=cwd, stdio = {nil, nil, stderr}},
            vim.schedule_wrap( function (code)
                uv.fs_write(log, '\n\n', -1) --space out error messages
                stderr:close()
                handle:close()
                uv.fs_close(log)

                ok = (code == 0)
                if not ishook then
                    run_hook(pkg)
                    count_ops(args[1] or process, pkg.name, ok)
                else --hooks aren't counted
                    output_result(0, 0, 'run hook for', pkg.name, ok)
                end
            end)
        )
end

function run_hook(pkg) --(already defined as local)
    local t = type(pkg.hook)
    if t == 'function' then
        local ok = pcall(pkg.hook)
        output_result(0, 0, 'run hook for', pkg.name, ok)
    elseif t == 'string' then
        local process
        local args = {}
        for word in pkg.hook:gmatch("%S+") do
            table.insert(args, word)
        end
        process = table.remove(args, 1)
        call_proc(process, pkg, args, pkg.dir, true)
    end
end

local function install_pkg(pkg)
    local install_args = {'clone', pkg.url}
    if pkg.exists then return inc('clone', 'ok') end
    if pkg.branch then
        list_extend(install_args, {'-b',  pkg.branch})
    end
    list_extend(install_args, {pkg.dir})
    call_proc('git', pkg, install_args)
end

local function update_pkg(pkg)
    if pkg.exists then
        call_proc('git', pkg, {'pull'}, pkg.dir)
    end
end

local function rmdir(dir, is_pack_dir) --pack_dir = start | opt
    local name, t, child, ok
    local handle = uv.fs_scandir(dir)
    while handle do
        name, t = uv.fs_scandir_next(handle)
        if not name then break end
        child = dir .. '/' .. name
        if is_pack_dir then --check which packages are listed
            if packages[name] and packages[name].dir == child then --do nothing
                ok = true
            else --package isn't listed, remove it
                ok = rmdir(child)
                count_ops('remove', name, ok)
            end
        else --it's an arbitrary directory or file
            ok = (t == 'directory') and rmdir(child) or uv.fs_unlink(child)
        end
        if not ok then return end
    end
    return is_pack_dir or uv.fs_rmdir(dir) --don't delete start/opt
end

local function paq(args)
    if type(args) == 'string' then args = {args} end

    num_pkgs = num_pkgs + 1

    local reponame = args.as or args[1]:match(REPO_RE)
    if not reponame then
        return output_result(num_pkgs, num_pkgs, 'parse', args[1])
    end

    local dir = PATH .. (args.opt and 'opt/' or 'start/') .. reponame

    packages[reponame] = {
        name   = reponame,
        branch = args.branch,
        dir    = dir,
        exists = (vim.api.nvim_call_function('isdirectory', {dir}) ~= 0),
        hook   = args.hook,
        url    = args.url or GITHUB .. args[1] .. '.git',
    }
end

local function setup(args)
    assert(type(args) == 'table', 'Paq.setup takes a single table argument')

    if type(args.path) == 'string' then
        PATH = args.path --FIXME: should probably rename PATH
    end
end

return {
    install = function() tbl_map(install_pkg, packages) end,
    update  = function() tbl_map(update_pkg, packages) end,
    clean   = function() rmdir(PATH..'start', 1); rmdir(PATH..'opt', 1) end,
    paq     = paq,
}
