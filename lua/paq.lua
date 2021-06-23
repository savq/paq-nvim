local vim = require('paq.compat')
local uv = vim.loop
local print_err = vim.api.nvim_err_writeln

local LOGFILE = vim.fn.stdpath('cache') .. '/paq.log'
local paq_dir = vim.fn.stdpath('data') .. '/site/pack/paqs/'

local packages = {} -- 'name' = {options} pairs
local last_ops = {} -- 'name' = 'op' pairs
local num_pkgs = 0
local ops; -- DEPRECATE 1.0

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

ops = ops_counter() -- COMPATIBILTY

local function update_count(op, result, total)
    local c, t = ops[op]
    if not c then return end
    c[result] = c[result] + 1
    t = c[result]
    if c.ok + c.err + c.nop == total then
        c.ok, c.err, c.nop = 0, 0, 0
        vim.cmd('packloadall! | helptags ALL')
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
        vim.cmd('packadd ' .. pkg.name)
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
    if not pkg.exists or pkg.pin then update_count('update', 'nop', num_pkgs) return end
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

local function remove(packdir) -- where packdir = start | opt
    local name, dir, pkg;
    local to_rm = {}
    local c = 0

    local handle = uv.fs_scandir(packdir)
    while handle do
        name = uv.fs_scandir_next(handle)
        if not name then break end
        pkg = packages[name]
        dir = packdir .. name
        if not (pkg and pkg.dir == dir) then
            to_rm[name] = dir
            c = c + 1
        end
    end

    for name, dir in pairs(to_rm) do
        call_proc("rm", {"-r", "-f", dir}, packdir, function(ok) report("remove", name, c, ok) end)
    end
end

local function list(self)
    local installed = vim.tbl_filter(function(name) return packages[name].exists end, vim.tbl_keys(packages))
    local removed = vim.tbl_filter(function(name) return last_ops[name] == 'remove' end,  vim.tbl_keys(last_ops))
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
        exists = vim.fn.isdirectory(dir) ~= 0,
        pin    = args.pin,
        run    = args.run or args.hook, -- DEPRECATE 1.0
        url    = args.url or 'https://github.com/' .. args[1] .. '.git',
    }
end

local function set_cmds()
    vim.tbl_map(vim.cmd, {
        [[command! PaqInstall  lua require('paq').install()]],
        [[command! PaqUpdate   lua require('paq').update()]],
        [[command! PaqClean    lua require('paq').clean()]],
        [[command! PaqList     lua require('paq').list()]],
        [[command! PaqLogOpen  lua require('paq').log_open()]],
        [[command! PaqLogClean lua require('paq').log_clean()]],
    })
end

set_cmds() -- COMPATIBILTY

local function init(self, tbl)
    packages={}
    num_pkgs=0
    ops = ops_counter()
    vim.tbl_map(register, tbl)
    --set_cmds()
    return self
end

return setmetatable({
    paq       = register, -- DEPRECATE 1.0
    install   = function(self) vim.tbl_map(install, packages) return self end,
    update    = function(self) vim.tbl_map(update, packages) return self end,
    clean     = function(self)  remove(paq_dir .. 'start/'); remove(paq_dir .. 'opt/') end,
    list      = list,
    setup     = setup,
    log_open  = function(self) vim.cmd('sp ' .. LOGFILE) return self end,
    log_clean = function(self) uv.fs_unlink(LOGFILE); print('Paq log file deleted') return self end,
},{__call=init})
