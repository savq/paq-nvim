local uv  = vim.loop --alias for Neovim's event loop (libuv)

-- nvim 0.4 compatibility
local cmd = vim.api.nvim_command
local vfn = vim.api.nvim_call_function
local compat = require("paq-nvim.compat")

----- Constants
local LOGFILE = vfn('stdpath', {"cache"}) .. "/paq.log"

----- Globals
local paq_dir   = vfn('stdpath', {"data"}) .. "/site/pack/paqs/"
local packages  = {} --table of 'name':{options} pairs
local changes   = {} --table of 'name':'change' pairs  ---TODO: Rename to states?
local num_pkgs  = 0
local num_to_rm = 0

local ops = {
    clone  = {ok=0, fail=0, past="cloned"},
    pull   = {ok=0, fail=0, past="pulled changes for"},
    remove = {ok=0, fail=0, past="removed"},
}

local function output_result(op, name, total, ok, ishook)
    local result, msg
    local count = ""
    local failstr = "Failed to "
    local c = ops[op]
    if c then
        result = ok and 'ok' or 'fail'
        c[result] = c[result] + 1
        count = string.format("%d/%d", c[result], total)
        msg = ok and c.past or failstr .. op
        if c.ok + c.fail == total then  --no more packages to update
            c.ok, c.fail = 0, 0
            cmd("packloadall! | helptags ALL")
        end
    elseif ishook then --hooks aren"t counted
        msg = (ok and "ran" or failstr .. "run") .. string.format(" `%s` for", op)
    else
        msg = failstr .. op
    end
    print(string.format("Paq [%s] %s %s", count, msg, name))
end

local function call_proc(process, pkg, args, cwd, cb)
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
            if cb then cb(code) end
        end)
    )
end

local function run_hook(pkg)
    local t, process, args, ok
    t = type(pkg.run)

    if t == 'function' then
        cmd("packadd " .. pkg.name)
        ok = pcall(pkg.run)
        output_result(t, pkg.name, 0, ok, true)

    elseif t == 'string' then
        args = {}
        for word in pkg.run:gmatch("%S+") do
            table.insert(args, word)
        end
        process = table.remove(args, 1)
        local post_hook = function(code)
            output_result(process, pkg.name, 0, code == 0, true)
        end
        call_proc(process, pkg, args, pkg.dir, post_hook)
    end
end

local function install(pkg)
    local op = 'clone'
    local args = {op, pkg.url}
    if pkg.exists then
        ops[op]['ok'] = ops[op]['ok'] + 1
        return
    elseif pkg.branch then
        compat.list_extend(args, {"-b",  pkg.branch})
    end
    compat.list_extend(args, {pkg.dir})
    local post_install = function(code)
        if code == 0 then
            pkg.exists = true
            changes[pkg.name] = 'installed'
            if pkg.run then run_hook(pkg) end
        end
        output_result(op, pkg.name, num_pkgs, code)
    end
    call_proc("git", pkg, args, nil, post_install)
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
    local post_update = function(code)
        if code == 0 and get_git_hash(pkg.dir) ~= hash then
            print("Updated " .. pkg.name)
            changes[pkg.name] = 'updated'
            if pkg.run then run_hook(pkg) end
        end
        output_result("pull", pkg.name, num_pkgs, code)
    end
    call_proc("git", pkg, {"pull"}, pkg.dir, post_update)
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
        output_result("remove", i.name, #rm_list, ok)
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
    if not name then return output_result("parse", args[1], 0) end

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
