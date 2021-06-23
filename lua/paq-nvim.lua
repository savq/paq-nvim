local uv  = vim.loop --alias for Neovim's event loop (libuv)

-- nvim 0.4 compatibility
local cmd = vim.api.nvim_command
local vfn = vim.api.nvim_call_function
local print_err = vim.api.nvim_err_writeln

local compat = require('paq-nvim.compat')

----- Constants
local LOGFILE = vfn('stdpath', {'cache'}) .. '/paq.log'

----- Globals
local paq_dir  = vfn('stdpath', {'data'}) .. '/site/pack/paqs/'
local packages = {} --table of 'name':{options} pairs
local last_ops = {} -- table of 'name':'op' pairs where 'op' is the last operation performed on packages['name']
local num_pkgs = 0

local ops;

local msgs = {
    install = {
        ok = 'installed %s',
        err = 'failed to install %s',
    },
    update = {
        ok = 'updated %s',
        err = 'failed to update %s',
        nop = '(up-to-date) %s',
    },
    remove = {
        ok = 'removed %s',
        err = 'failed to remove %s',
    },
    hook = {
        ok = 'ran hook for %s (%s)',
        err = 'failed to run hook for %s (%s)',
    },
}

local function ops_counter()
    return {
        install = {ok=0, err=0, nop=0},
        update  = {ok=0, err=0, nop=0},
        remove  = {ok=0, err=0, nop=0},
    }
end

ops = ops_counter() -- FIXME: This is a hack to keep the old paq system and the new __call system working

local function update_count(op, result, total)
    local c, t = ops[op]
    if not c then return end
    c[result] = c[result] + 1
    t = c[result]
    if c.ok + c.err + c.nop == total then
        c.ok, c.err, c.nop = 0, 0, 0
        cmd('packloadall! | helptags ALL')
    end
    return t
end

local function report(op, name, total, ok, hook)
    local result = (ok and 'ok') or (ok == false and 'err' or 'nop')

    local cur = update_count(op, result, total)
    local count = total ~= -1 and string.format('%d/%d', cur, total) or ''
    if msgs[op] and cur then
        local msg = msgs[op][result]
        if ok == false then
            print_err(string.format('Paq [%s] ' .. msg, count, name, hook))
        else
            print(string.format('Paq [%s] ' .. msg, count, name, hook))
        end
    end
end

local function call_proc(process, args, cwd, cb)
    local log, stderr, handle
    log = uv.fs_open(LOGFILE, 'a+', 0x1A4)
    stderr = uv.new_pipe(false)
    stderr:open(log)
    handle = uv.spawn(
        process,
        {args=args, cwd=cwd, stdio = {nil, nil, stderr}},
        vim.schedule_wrap(function(code)
            uv.fs_write(log, '\n', -1) --space out error messages
            uv.fs_close(log)
            stderr:close()
            handle:close()
            cb(code == 0)
        end)
    )
end

local function run_hook(pkg)
    local t = type(pkg.run)
    if t == 'function' then
        cmd('packadd ' .. pkg.name)
        local ok = pcall(pkg.run)
        report('hook', pkg.name, -1, ok, 'function')
    elseif t == 'string' then
        local args = {}
        for word in pkg.run:gmatch('%S+') do
            table.insert(args, word)
        end
        local process = table.remove(args, 1)
        local post_hook = function(ok)
            report('hook', pkg.name, -1, ok, args[1])
        end
        call_proc(process, args, pkg.dir, post_hook)
    end
end

local function install(pkg)
    if pkg.exists then return update_count('install', 'nop', num_pkgs) end
    local args;
    if pkg.branch then
        args = {'clone', pkg.url, '--depth=1', '-b',  pkg.branch, pkg.dir}
    else
        args = {'clone', pkg.url, '--depth=1', pkg.dir}
    end
    local post_install = function(ok)
        if ok then
            pkg.exists = true
            last_ops[pkg.name] = 'install'
            if pkg.run then run_hook(pkg) end
        end
        report('install', pkg.name, num_pkgs, ok)
    end
    call_proc('git', args, nil, post_install)
end


local function get_git_hash(dir)
    local function first_line(path)
        local file = uv.fs_open(path, 'r', 0x1A4)
        if file then
            local line = uv.fs_read(file, 41, -1) --FIXME: this might fail
            uv.fs_close(file)
            return line
        end
    end
    local head_ref = first_line(dir .. '/.git/HEAD')
    if head_ref then
        return first_line(dir .. '/.git/' .. head_ref:gsub('ref: ', ''))
    end
end

local function update(pkg)
    if not pkg.exists then update_count('update', 'nop', num_pkgs) return end
    local hash = get_git_hash(pkg.dir) -- TODO: Add setup option to disable hash checking
    local post_update = function(ok)
        if ok and get_git_hash(pkg.dir) ~= hash then
            last_ops[pkg.name] = 'update'
            if pkg.run then run_hook(pkg) end
            report('update', pkg.name, num_pkgs, ok)
        else
            report('update', pkg.name, num_pkgs)
        end
    end
    call_proc('git', {'pull'}, pkg.dir, post_update)
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

local function rm_dir(child, _, t)
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

local function clean(self)
    local ok
    local rm_list = {}
    iter_dir(mark_dir, paq_dir .. 'start', rm_list)
    iter_dir(mark_dir, paq_dir .. 'opt', rm_list)
    for _, i in ipairs(rm_list) do
        ok = iter_dir(rm_dir, i.dir) and uv.fs_rmdir(i.dir)
        report('remove', i.name, #rm_list, ok)
        if ok then last_ops[i.name] = 'remove' end
    end
    return self
end

local function list(self)
    local installed = compat.tbl_filter(function(name) return packages[name].exists end, compat.tbl_keys(packages))
    local removed = compat.tbl_filter(function(name) return last_ops[name] == 'remove' end,  compat.tbl_keys(last_ops))
    table.sort(installed)
    table.sort(removed)

    local sym_tbl = {install='+', update='*', remove=' '}
    for header, pkgs in pairs{['Installed packages:']=installed, ['Recently removed:']=removed} do
        if #pkgs ~= 0 then
            print(header)
            for _, name in ipairs(pkgs) do
                print('  ', sym_tbl[last_ops[name]] or ' ', name)
            end
        end
    end

    return self
end

local function setup(self, args)
    assert(type(args) == 'table')
    if type(args.path) == 'string' then
        paq_dir = args.path
    end
    return self
end

local function register(args)
    local name, dir
    if type(args) == 'string' then args = {args} end

    if args.as then
        name = args.as
    elseif args.url then
        name = args.url:gsub('%.git$', ''):match('/([%w-_.]+)$')
        if not name then print_err('Paq: Failed to parse ' .. args.url) return end
    else
        name = args[1]:match('^[%w-]+/([%w-_.]+)$')
        if not name then print_err('Paq: Failed to parse ' .. args[1]) return end
    end

    dir = paq_dir .. (args.opt and 'opt/' or 'start/') .. name

    if not packages[name] then
        num_pkgs = num_pkgs + 1
    end

    packages[name] = {
        name   = name,
        branch = args.branch,
        dir    = dir,
        exists = (vfn('isdirectory', {dir}) ~= 0),
        run    = args.run or args.hook, -- DEPRECATE 1.0
        url    = args.url or 'https://github.com/' .. args[1] .. '.git',
    }
end

local function init(self, tbl)
    packages={}
    num_pkgs=0
    ops = ops_counter()
    compat.tbl_map(register, tbl)
    return self
end

return setmetatable({
    paq       = register, -- DEPRECATE 1.0
    install   = function(self) compat.tbl_map(install, packages) return self end,
    update    = function(self) compat.tbl_map(update, packages) return self end,
    clean     = clean,
    list      = list,
    setup     = setup,
    log_open  = function(self) cmd('sp ' .. LOGFILE) return self end,
    log_clean = function(self) uv.fs_unlink(LOGFILE); print('Paq log file deleted') return self end,
},{__call=init})
