local uv = vim.loop
local cfg = {
    path = vim.fn.stdpath("data") .. "/site/pack/paqs/",
    verbose = false,
}
local LOGFILE = vim.fn.stdpath("cache") .. "/paq.log"
local packages = {} -- 'name' = {options...} pairs
local messages = {
    install = { ok = "Installed", err = "Failed to install" },
    update = { ok = "Updated", err = "Failed to update", nop = "(up-to-date)" },
    remove = { ok = "Removed", err = "Failed to remove" },
    hook = { ok = "Ran hook for", err = "Failed to run hook for" },
}

-- This is done only once. Doing it for every process seems overkill
local env = {}
local envfn = vim.fn.has('nvim-0.6') == 1 and uv.os_environ or vim.fn.environ  -- compat
for var, val in pairs(envfn()) do
    table.insert(env, ("%s=%s"):format(var, val))
end
table.insert(env, "GIT_TERMINAL_PROMPT=0")

vim.cmd([[
    command! PaqInstall  lua require('paq'):install()
    command! PaqUpdate   lua require('paq'):update()
    command! PaqClean    lua require('paq'):clean()
    command! PaqSync     lua require('paq'):sync()
    command! PaqList     lua require('paq').list()
    command! PaqLogOpen  lua require('paq').log_open()
    command! PaqLogClean lua require('paq').log_clean()
    command! -nargs=1 -complete=customlist,v:lua.require'paq'._get_hooks PaqRunHook lua require('paq')._run_hook(<f-args>)
]])

local function report(op, name, res, n, total)
    local count = n and (" [%d/%d]"):format(n, total) or ""
    vim.notify((" Paq:%s %s %s"):format(count, messages[op][res], name), res == "err" and vim.log.levels.ERROR)
end

local function new_counter()
    return coroutine.wrap(function(op, total)
        local c = { ok = 0, err = 0, nop = 0 }
        while c.ok + c.err + c.nop < total do
            local name, res, over_op = coroutine.yield(true)
            c[res] = c[res] + 1
            if res ~= "nop" or cfg.verbose then
                report(over_op or op, name, res, c.ok + c.nop, total)
            end
        end
        local summary = (" Paq: %s complete. %d ok; %d errors;" .. (c.nop > 0 and " %d no-ops" or ""))
        vim.notify(summary:format(op, c.ok, c.err, c.nop))
        vim.cmd("packloadall! | silent! helptags ALL")
        vim.cmd("doautocmd User PaqDone" .. op:gsub("^%l", string.upper))
    end)
end

local function call_proc(process, args, cwd, cb)
    local log = uv.fs_open(LOGFILE, "a+", 0x1A4)
    local stderr = uv.new_pipe(false)
    stderr:open(log)
    local handle, pid
    handle, pid = uv.spawn(
        process,
        { args = args, cwd = cwd, stdio = { nil, nil, stderr }, env = env },
        vim.schedule_wrap(function(code)
            uv.fs_close(log)
            stderr:close()
            handle:close()
            cb(code == 0)
        end)
    )
    if not handle then
        vim.notify(string.format(" Paq: Failed to spawn %s (%s)", process, pid))
    end
end

local function run_hook(pkg, counter, sync)
    local t = type(pkg.run)
    if t == "function" then
        vim.cmd("packadd " .. pkg.name)
        local res = pcall(pkg.run) and "ok" or "err"
        report("hook", pkg.name, res)
        return counter and counter(pkg.name, res, sync)
    elseif t == "string" then
        local args = {}
        for word in pkg.run:gmatch("%S+") do
            table.insert(args, word)
        end
        call_proc(table.remove(args, 1), args, pkg.dir, function(ok)
            local res = ok and "ok" or "err"
            report("hook", pkg.name, res)
            return counter and counter(pkg.name, res, sync)
        end)
        return true
    end
end

local function clone(pkg, counter, sync)
    local args = { "clone", pkg.url, "--depth=1", "--recurse-submodules", "--shallow-submodules" }
    if pkg.branch then
        vim.list_extend(args, { "-b", pkg.branch })
    end
    vim.list_extend(args, { pkg.dir })
    call_proc("git", args, nil, function(ok)
        if ok then
            pkg.exists = true
            pkg.status = "installed"
            return pkg.run and run_hook(pkg, counter, sync) or counter(pkg.name, "ok", sync)
        else
            counter(pkg.name, "err", sync)
        end
    end)
end

local function get_git_hash(dir)
    local first_line = function(path)
        local file = io.open(path)
        if file then
            local line = file:read()
            file:close()
            return line
        end
    end
    local head_ref = first_line(dir .. "/.git/HEAD")
    return head_ref and first_line(dir .. "/.git/" .. head_ref:gsub("ref: ", ""))
end

local function pull(pkg, counter, sync)
    local hash = get_git_hash(pkg.dir)
    call_proc("git", { "pull", "--recurse-submodules", "--update-shallow" }, pkg.dir, function(ok)
        if not ok then
            counter(pkg.name, "err", sync)
        elseif get_git_hash(pkg.dir) ~= hash then
            pkg.status = "updated"
            return pkg.run and run_hook(pkg, counter, sync) or counter(pkg.name, "ok", sync)
        else
            counter(pkg.name, "nop", sync)
        end
    end)
end

local function clone_or_pull(pkg, counter)
    if pkg.exists and not pkg.pin then
        pull(pkg, counter, "update")
    else
        clone(pkg, counter, "install")
    end
end

local function walk_dir(path, fn)
    local handle = uv.fs_scandir(path)
    while handle do
        local name, t = uv.fs_scandir_next(handle)
        if not name then
            break
        end
        if not fn(path .. "/" .. name, name, t) then
            return
        end
    end
    return true
end

local function check_rm()
    local to_remove = {}
    for _, packdir in pairs({ "start", "opt" }) do
        walk_dir(cfg.path .. packdir, function(dir, name)
            if name == "paq-nvim" then
                return true
            end
            local pkg = packages[name]
            if not (pkg and pkg.dir == dir) then
                table.insert(to_remove, { name = name, dir = dir })
            end
            return true
        end)
    end
    return to_remove
end

local function rmdir(dir, name, t)
    if t == "directory" then
        return walk_dir(dir, rmdir) and uv.fs_rmdir(dir)
    else
        return uv.fs_unlink(dir)
    end
end

local function remove(p, counter)
    local ok = walk_dir(p.dir, rmdir) and uv.fs_rmdir(p.dir)
    counter(p.name, ok and "ok" or "err")

    if ok then
        packages[p.name] = { name = p.name, status = "removed" }
    end
end

local function exe_op(op, fn, pkgs)
    if #pkgs == 0 then
        vim.notify(" Paq: Nothing to " .. op)
        vim.cmd("doautocmd User PaqDone" .. op:gsub("^%l", string.upper))
        return
    end
    local counter = new_counter()
    counter(op, #pkgs)
    for _, pkg in pairs(pkgs) do
        fn(pkg, counter)
    end
end

-- stylua: ignore
local function list()
    local installed = vim.tbl_filter(function(pkg) return pkg.exists end, packages)
    table.sort(installed, function(a, b) return a.name < b.name end)

    local removed = vim.tbl_filter(function(pkg) return pkg.status == "removed" end, packages)
    table.sort(removed, function(a, b) return a.name < b.name end)

    local sym_tbl = { installed = "+", updated = "*", removed = " " }
    for header, pkgs in pairs({ ["Installed packages:"] = installed, ["Recently removed:"] = removed }) do
        if #pkgs ~= 0 then
            print(header)
            for _, pkg in ipairs(pkgs) do
                print(" ", sym_tbl[pkg.status] or " ", pkg.name)
            end
        end
    end
end

local function parse_name(args)
    if args.as then
        return args.as
    elseif args.url then
        return args.url:gsub("%.git$", ""):match("/([%w-_.]+)$"), args.url
    else
        return args[1]:match("^[%w-]+/([%w-_.]+)$"), args[1]
    end
end

local function register(args)
    if type(args) == "string" then
        args = { args }
    end
    local name, src = parse_name(args)
    if not name then
        return vim.notify(" Paq: Failed to parse " .. src, vim.log.levels.ERROR)
    elseif packages[name] then
        return
    end
    local dir = cfg.path .. (args.opt and "opt/" or "start/") .. name
    packages[name] = {
        name = name,
        branch = args.branch,
        dir = dir,
        exists = vim.fn.isdirectory(dir) ~= 0,
        status = "listed", -- TODO: should probably merge this with `exists` in the future...
        pin = args.pin,
        run = args.run,
        url = args.url or "https://github.com/" .. args[1] .. ".git",
    }
end

-- stylua: ignore
return setmetatable({
    install = function() exe_op("install", clone, vim.tbl_filter(function(pkg) return not pkg.exists and pkg.status ~= "removed" end, packages)) end,
    update = function() exe_op("update", pull, vim.tbl_filter(function(pkg) return pkg.exists and not pkg.pin end, packages)) end,
    clean = function() exe_op("remove", remove, check_rm()) end,
    sync = function(self) self:clean() exe_op("sync", clone_or_pull, vim.tbl_filter(function(pkg) return pkg.status ~= "removed" end, packages)) end,
    setup = function(self, args) for k, v in pairs(args) do cfg[k] = v end return self end,
    _run_hook = function(name) return run_hook(packages[name]) end,
    _get_hooks = function() return vim.tbl_keys(vim.tbl_map(function(pkg) return pkg.run end, packages)) end,
    list = list,
    log_open = function() vim.cmd("sp " .. LOGFILE) end,
    log_clean = function() return assert(uv.fs_unlink(LOGFILE)) and vim.notify(" Paq: log file deleted") end,
    paq = register, -- TODO: deprecate. not urgent
}, {__call = function(self, tbl) packages = {} vim.tbl_map(register, tbl) return self end,
})
