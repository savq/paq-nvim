local uv  = vim.loop --alias for Neovim's event loop (libuv)

-- nvim 0.4 compatibility
local cmd = vim.api.nvim_command
local vfn = vim.api.nvim_call_function
local compat = require("paq-nvim.compat")

----- Constants
local LOGFILE = vfn('stdpath', {"cache"}) .. "/paq.log"

----- Globals
local paq_dir  = vfn('stdpath', {"data"}) .. "/site/pack/paqs/"
local packages = {} --table of 'name':{options} pairs
local changes  = {} --table of 'name':'change' pairs  ---TODO: Rename to states?
local num_pkgs = 0

local ops = {
    install = {ok=0, fail=0, nop=0},
    update  = {ok=0, fail=0, nop=0},
    remove  = {ok=0, fail=0, nop=0},
}

local msgs = {
    install = {
        ok = "installed %s",
        fail = "failed to install %s",
    },
    update = {
        ok = "updated %s",
        fail = "failed to update %s",
        nop = "(up-to-date) %s",
    },
    remove = {
        ok = "removed %s",
        fail = "failed to remove %s",
    },
    hook = {
        ok = "ran hook for %s (%s)",
        fail = "failed to run hook for %s (%s)",
    },
}

local function get_count(op, result, total)
    local c = ops[op]
    if c then
        if c.ok + c.fail + c.nop == total then
            c.ok, c.fail, c.nop = 0, 0, 0
            cmd("packloadall! | helptags ALL")
        end
        c[result] = c[result] + 1
        return c[result]
    end
end

local function output_msg(op, name, total, ok, hook)
    local result = (ok and 'ok') or (ok == false and 'fail' or 'nop')
    local cur = get_count(op, result, total)
    local count = total ~= -1 and string.format("%d/%d", cur, total) or ""
    if msgs[op] and cur then
        local msg = msgs[op][result]
        print(string.format("Paq [%s] " .. msg, count, name, hook))
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
            uv.fs_write(log, "\n", -1) --space out error messages
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
        cmd("packadd " .. pkg.name)
        local ok = pcall(pkg.run)
        output_msg("hook", pkg.name, -1, ok, "function")
    elseif t == 'string' then
        local args = {}
        for word in pkg.run:gmatch("%S+") do
            table.insert(args, word)
        end
        local process = table.remove(args, 1)
        local post_hook = function(ok)
            output_msg("hook", pkg.name, -1, ok, args[1])
        end
        call_proc(process, args, pkg.dir, post_hook)
    end
end

local function install(pkg)
    local args = {"clone", pkg.url}
    if pkg.exists then
        return get_count('install', 'nop', num_pkgs)
    elseif pkg.branch then
        compat.list_extend(args, {"-b",  pkg.branch})
    end
    compat.list_extend(args, {pkg.dir})
    local post_install = function(ok)
        if ok then
            pkg.exists = true
            changes[pkg.name] = 'installed'
            if pkg.run then run_hook(pkg) end
        end
        output_msg('install', pkg.name, num_pkgs, ok)
    end
    call_proc("git", args, nil, post_install)
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
    local head_ref = first_line(dir .. "/.git/HEAD")
    if head_ref then
        return first_line(dir .. "/.git/" .. head_ref:gsub("ref: ", ""))
    end
end

local function update(pkg)
    if not pkg.exists then return end
    local hash = get_git_hash(pkg.dir) -- TODO: Add setup option to disable hash checking
    local post_update = function(ok)
        if ok and get_git_hash(pkg.dir) ~= hash then
            changes[pkg.name] = 'updated'
            if pkg.run then run_hook(pkg) end
            output_msg('update', pkg.name, num_pkgs, ok)
        else
            output_msg('update', pkg.name, num_pkgs)
        end
    end
    call_proc("git", {"pull"}, pkg.dir, post_update)
end

local function iter_dir(fn, dir, args)
    local child, name, t, ok
    local handle = uv.fs_scandir(dir)
    while handle do
        name, t = uv.fs_scandir_next(handle)
        if not name then break end
        child = dir .. "/" .. name
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

local function clean()
    local ok
    local rm_list = {}
    iter_dir(mark_dir, paq_dir .. "start", rm_list)
    iter_dir(mark_dir, paq_dir .. "opt", rm_list)
    for _, i in ipairs(rm_list) do
        ok = iter_dir(rm_dir, i.dir) and uv.fs_rmdir(i.dir)
        output_msg("remove", i.name, #rm_list, ok)
        if ok then changes[i.name] = 'removed' end
    end
end

local function list()
    local installed = compat.tbl_filter(function(name) return packages[name].exists end, compat.tbl_keys(packages))
    local removed = compat.tbl_filter(function(name) return changes[name] == 'removed' end,  compat.tbl_keys(changes))

    table.sort(installed)
    table.sort(removed)

    local symb_tbl = {installed="+", updated="*", removed=" "}
    local prefix = function(name)
        return "   " .. (symb_tbl[changes[name]] or " ") .. name
    end

    local list_pkgs = function(header, pkgs)
        if #pkgs ~= 0 then print(header) end
        for _, v in ipairs(compat.tbl_map(prefix, pkgs)) do print(v) end
    end

    list_pkgs("Installed packages:", installed)
    list_pkgs("Recently removed:", removed)
end

local function paq(args)
    local name, dir
    if type(args) == 'string' then args = {args} end

    name = args.as or args[1]:match("^[%w-]+/([%w-_.]+)$")
    if not name then return print("Failed to parse " .. args[1]) end

    dir = paq_dir .. (args.opt and "opt/" or "start/") .. name

    if not packages[name] then
        num_pkgs = num_pkgs + 1
    end

    packages[name] = {
        name   = name,
        branch = args.branch,
        dir    = dir,
        exists = (vfn('isdirectory', {dir}) ~= 0),
        run    = args.run or args.hook, --wait for paq 1.0 to deprecate
        url    = args.url or "https://github.com/" .. args[1] .. ".git",
    }
end

local function setup(args)
    assert(type(args) == 'table')
    if type(args.path) == 'string' then
        paq_dir = args.path
    end
end

return {
    install   = function() compat.tbl_map(install, packages) end,
    update    = function() compat.tbl_map(update, packages) end,
    clean     = clean,
    list      = list,
    setup     = setup,
    paq       = paq,
    log_open  = function() cmd("sp " .. LOGFILE) end,
    log_clean = function() uv.fs_unlink(LOGFILE); print("Paq log file deleted") end,
}
