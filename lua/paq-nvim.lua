local uv  = vim.loop -- Alias for Neovim's event loop (libuv)
local cmd = vim.api.nvim_command       -- nvim 0.4 compat
local vfn = vim.api.nvim_call_function -- ""
local run_hook -- to handle mutual recursion

----- Constants
local PATH    = vfn('stdpath', {'data'}) .. '/site/pack/paqs/' --TODO: PATH is now configurable, rename!
local LOGFILE = vfn('stdpath', {'cache'}) .. '/paq.log'
local GITHUB  = 'https://github.com/'
local REPO_RE = '^[%w-]+/([%w-_.]+)$'
local DATEFMT = '%F T %H:%M:%S%z'

----- Globals
local packages = {} -- Table of 'name':{options} pairs
local num_pkgs  = 0
local num_to_rm = 0

local ops = {
    clone  = {ok=0, fail=0, past = 'cloned'            },
    pull   = {ok=0, fail=0, past = 'pulled changes for'},
    remove = {ok=0, fail=0, past = 'removed'           },
}

----- Neovim 0.4 compat
local _nvim = {} -- Helper functions to replace 0.5 features

function _nvim.tbl_map(func, t)
    if vfn('has', {'nvim-0.5'}) == 1 then
        return vim.tbl_map(func, t)
    end
    local rettab = {}
    for k, v in pairs(t) do
        rettab[k] = func(v)
    end
    return rettab
end

function _nvim.list_extend(dst, src, start, finish)
    if vfn('has', {'nvim-0.5'}) == 1 then
        return vim.list_extend(dst, src, start, finish)
    end
    for i = start or 1, finish or #src do
        table.insert(dst, src[i])
    end
    return dst
end

local function output_result(op, name, ok, ishook)
    local result, total, msg
    local count = ''
    local failstr = 'Failed to '
    local c = ops[op]
    if c then
        result = ok and 'ok' or 'fail'
        c[result] = c[result] + 1
        total = (op == 'remove') and num_to_rm or num_pkgs -- FIXME
        count = string.format('%d/%d', c[result], total)
        msg = ok and c.past or failstr .. op
        if c.ok + c.fail == total then  --no more packages to update
            c.ok, c.fail = 0, 0
            cmd('packloadall! | helptags ALL')
        end
    elseif ishook then --hooks aren't counted
        msg = (ok and 'ran' or failstr .. 'run') .. string.format(' `%s` for', op)
    else
        msg = failstr .. op
    end
    print(string.format('Paq [%s] %s %s', count, msg, name))
end

local function call_proc(process, pkg, args, cwd, ishook)
    local log, stderr, handle, op
    log = uv.fs_open(LOGFILE, 'a+', 0x1A4) -- FIXME: Write in terms of uv.constants
    stderr = uv.new_pipe(false)
    stderr:open(log)
    handle = uv.spawn(
        process,
        {args=args, cwd=cwd, stdio = {nil, nil, stderr}},
        vim.schedule_wrap( function(code)
            uv.fs_write(log, '\n', -1) --space out error messages
            uv.fs_close(log)
            stderr:close()
            handle:close()
            output_result(args[1] or process, pkg.name, code == 0, ishook)
            if not ishook then run_hook(pkg) end
        end)
    )
end

function run_hook(pkg) --(already defined as local)
    local t, process, args, ok
    t = type(pkg.run)

    if t == 'function' then
        cmd('packadd ' .. pkg.name)
        local ok = pcall(pkg.run)
        output_result(t, pkg.name, ok, true)

    elseif t == 'string' then
        args = {}
        for word in pkg.run:gmatch('%S+') do
            table.insert(args, word)
        end
        process = table.remove(args, 1)
        call_proc(process, pkg, args, pkg.dir, true)
    end
end

local function install(pkg)
    local args = {'clone', pkg.url}
    if pkg.exists then
        ops['clone']['ok'] = ops['clone']['ok'] + 1
        return
    elseif pkg.branch then
        _nvim.list_extend(args, {'-b',  pkg.branch})
    end
    _nvim.list_extend(args, {pkg.dir})
    call_proc('git', pkg, args)
end

local function update(pkg)
    if pkg.exists then
        call_proc('git', pkg, {'pull'}, pkg.dir)
    end
end

local function iter_dir(fn, dir, args)
    local child, name, t, ok
    local handle = uv.fs_scandir(dir)
    while handle do
        name, t = uv.fs_scandir_next(handle)
        if not name then break end
        child = dir .. '/' .. name
        ok = fn(child, name, t, args)
        if not ok then return end
    end
    return true
end

local function rm_dir(child, name, t)
    if t == 'directory' then
        return iter_dir(rm_dir, child) and uv.fs_rmdir(child)
    else
        return uv.fs_unlink(child)
    end
end

local function mark_dir(dir, name, _, list)
    local pkg = packages[name]
    if not (pkg and pkg.dir == dir) then
        table.insert(list, {name=name, dir=dir})
    end
    return true
end

local function clean_pkgs()
    local rm_list = {}
    iter_dir(mark_dir, PATH .. 'start', rm_list)
    iter_dir(mark_dir, PATH .. 'opt', rm_list)
    num_to_rm = #rm_list    -- update count of plugins to be deleted
    for _, i in ipairs(rm_list) do
        ok = iter_dir(rm_dir, i.dir) and uv.fs_rmdir(i.dir)
        output_result('remove', i.name, ok)
    end
end

local function paq(args)
    local name, dir
    if type(args) == 'string' then args = {args} end

    name = args.as or args[1]:match(REPO_RE)
    if not name then return output_result('parse', args[1]) end

    dir = PATH .. (args.opt and 'opt/' or 'start/') .. name

    if not packages[name] then
        num_pkgs = num_pkgs + 1
    end

    packages[name] = {
        name   = name,
        branch = args.branch,
        dir    = dir,
        exists = (vfn('isdirectory', {dir}) ~= 0),
        run    = args.run or args.hook, --wait for paq 1.0 to deprecate
        url    = args.url or GITHUB .. args[1] .. '.git',
    }
end

local function setup(args)
    assert(type(args) == 'table')
    if type(args.path) == 'string' then
        PATH = args.path --FIXME: should probably rename PATH
    end
end

return {
    install   = function() _nvim.tbl_map(install, packages) end,
    update    = function() _nvim.tbl_map(update, packages) end,
    clean     = clean_pkgs,
    setup     = setup,
    paq       = paq,
    log_open  = function() cmd('sp ' .. LOGFILE) end,
    log_clean = function() uv.fs_unlink(LOGFILE); print('Paq log file deleted') end,
}
