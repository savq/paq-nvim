-- Neovim 0.4 compat
local _nvim = {} -- Helper functions to replace 0.5 features
local cmd = vim.api.nvim_command
local vfn = vim.api.nvim_call_function

-- Constants
local PATH    = vfn('stdpath', {'data'}) .. '/site/pack/paqs/'
local LOGFILE = vfn('stdpath', {'cache'}) .. '/paq.log'
local GITHUB  = 'https://github.com/'
local REPO_RE = '^[%w-]+/([%w-_.]+)$'
local DATEFMT = '%F T %H:%M:%S%z'

-- Globals
local packages = {} -- Table of 'name':{options} pairs
local num_pkgs = 0
local ops = {
    clone            = {ok = 0, fail = 0, past = 'cloned'            },
    pull             = {ok = 0, fail = 0, past = 'pulled changes for'},
    remove           = {ok = 0, fail = 0, past = 'removed'           },
    ['run hook for'] = {ok = 0, fail = 0, past = 'ran hook for'      },
}

local uv = vim.loop -- Alias for Neovim's event loop (libuv)
local run_hook      -- To handle mutual funtion recursion


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

-- Warning: This mutates dst!
function _nvim.list_extend(dst, src, start, finish)
    if vfn('has', {'nvim-0.5'}) == 1 then
        return vim.list_extend(dst, src, start, finish)
    end
    for i = start or 1, finish or #src do
        table.insert(dst, src[i])
    end
    return dst
end

local function output_result(op, name, ok)
    local c, result, msg, total

    result = ok and 'ok' or 'fail'
    c = ops[op]
    c[result] = c[result] + 1

    total = (op == 'run hook for') and 0 or num_pkgs
    msg = ok and c.past or 'Failed to ' .. op

    print(string.format('Paq [%d/%d] %s %s', c[result], total, msg, name))

    if c.ok + c.fail == num_pkgs then
        c.ok, c.fail = 0, 0
        cmd('packloadall! | helptags ALL')
    end
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
            op = ishook and 'run hook for' or args[1] or process
            output_result(op, pkg.name, code == 0)
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
        output_result('run hook for', pkg.name, ok)

    elseif t == 'string' then
        args = {}
        for word in pkg.run:gmatch('%S+') do
            table.insert(args, word)
        end
        process = table.remove(args, 1)
        call_proc(process, pkg, args, pkg.dir, true)
    end
end

local function install_pkg(pkg)
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
                output_result('remove', name, ok)
            end
        else --it's an arbitrary directory or file
            ok = (t == 'directory') and rmdir(child) or uv.fs_unlink(child)
        end
        if not ok then return end
    end
    return is_pack_dir or uv.fs_rmdir(dir) --don't delete start/opt
end

local function paq(args)
    local name, dir
    if type(args) == 'string' then args = {args} end

    num_pkgs = num_pkgs + 1

    name = args.as or args[1]:match(REPO_RE)
    if not name then return output_result('parse', args[1]) end

    dir = PATH .. (args.opt and 'opt/' or 'start/') .. name

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
    install   = function() _nvim.tbl_map(install_pkg, packages) end,
    update    = function() _nvim.tbl_map(update_pkg, packages) end,
    clean     = function() rmdir(PATH..'start', 1); rmdir(PATH..'opt', 1) end,
    setup     = setup,
    paq       = paq,
    log_open  = function() cmd('sp ' .. LOGFILE) end,
    log_clean = function() uv.fs_unlink(LOGFILE); print('Paq log file deleted') end,
}
