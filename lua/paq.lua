local uv = vim.loop
local cfg = {
    path = vim.fn.stdpath("data") .. "/site/pack/paqs/",
    opt = false,
    verbose = false,
    url_format = "https://github.com/%s.git",
}
local logpath = vim.fn.has("nvim-0.8") == 1 and vim.fn.stdpath("log") or vim.fn.stdpath("cache")
local logfile = logpath .. "/paq.log"
local lockfile = vim.fn.stdpath("data") .. "/paq-lock.json"
local packages = {} -- "name" = {options...} pairs
local lock = {}

-- This is done only once. Doing it for every process seems overkill
local env = {}
local envfn = vim.fn.has("nvim-0.6") == 1 and uv.os_environ or vim.fn.environ
for var, val in pairs(envfn()) do
    table.insert(env, string.format("%s=%s", var, val))
end
table.insert(env, "GIT_TERMINAL_PROMPT=0")

vim.cmd([[
    command! -bar PaqInstall  lua require('paq'):install()
    command! -bar PaqUpdate   lua require('paq'):update()
    command! -bar PaqClean    lua require('paq'):clean()
    command! -bar PaqSync     lua require('paq'):sync()
    command! -bar PaqList     lua require('paq').list()
    command! -bar PaqLogOpen  lua require('paq').log_open()
    command! -bar PaqLogClean lua require('paq').log_clean()
    command! -bar -nargs=1 -complete=customlist,v:lua.require'paq'._get_hooks PaqRunHook lua require('paq')._run_hook(<f-args>)
]])

local function report(op, name, res, n, total)
    local messages = {
        install = { ok = "Installed", err = "Failed to install" },
        update = { ok = "Updated", err = "Failed to update", nop = "(up-to-date)" },
        remove = { ok = "Removed", err = "Failed to remove" },
        hook = { ok = "Ran hook for", err = "Failed to run hook for" },
    }
    local count = n and string.format(" [%d/%d]", n, total) or ""
    vim.notify(
        string.format(" Paq:%s %s %s", count, messages[op][res], name),
        res == "err" and vim.log.levels.ERROR
    )
end

local function find_unlisted()
    local unlisted = {}
    -- TODO(breaking): Replace with `vim.fs.dir`
    for _, packdir in pairs { "start", "opt" } do
        local path = cfg.path .. packdir
        local handle = uv.fs_scandir(path)
        while handle do
            local name, t = uv.fs_scandir_next(handle)
            if t == "directory" and name ~= "paq-nvim" then
                local dir = path .. "/" .. name
                local pkg = packages[name]
                if not pkg or pkg.dir ~= dir then
                    table.insert(unlisted, { name = name, dir = dir })
                end
            elseif not name then
                break
            end
        end
    end
    return unlisted
end

local function find_uninstalled()
    local uninstalled = {}
    for key, pkg in pairs(packages) do
        if not lock[key] then
            table.insert(uninstalled, pkg)
        end
    end
    return vim.tbl_filter(function(pkg) return not pkg.exists end, uninstalled)
end


local function lock_load()
    -- don't really know why 438 see ':h uv_fs_t'
    local file = uv.fs_open(lockfile, "r", 438)
    if file then
        local stat = assert(uv.fs_fstat(file))
        local data = assert(uv.fs_read(file, stat.size, 0))
        assert(uv.fs_close(file))
        local ok, result = pcall(vim.json.decode, data)
        return ok and result or {}
    end
    return {}
end

local function state_write()
   -- remove run key since can have a function in it, and
    -- json.encode doesn't support functions
    local pkgs = vim.deepcopy(packages)
    for p, _ in pairs(pkgs) do
        pkgs[p].run = nil
    end
    local file = uv.fs_open(lockfile, "w", 438)
    if file then
        local ok, result = pcall(vim.json.encode, pkgs)
        if not ok then
            error(result)
        end
        assert(uv.fs_write(file, result))
        assert(uv.fs_close(file))
    end
end

local function state_diff()
    return { current = find_uninstalled(), lock = find_unlisted(), }
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
        local summary = " Paq: %s complete. %d ok; %d errors;" .. (c.nop > 0 and " %d no-ops" or "")
        vim.notify(string.format(summary, op, c.ok, c.err, c.nop))
        vim.cmd("packloadall! | silent! helptags ALL")
        vim.cmd("doautocmd User PaqDone" .. op:gsub("^%l", string.upper))
        return true
    end)
end

local function call_proc(process, args, cwd, cb, print_stdout)
    local log = uv.fs_open(logfile, "a+", 0x1A4)
    local stderr = uv.new_pipe(false)
    stderr:open(log)
    local handle, pid
    handle, pid = uv.spawn(
        process,
        { args = args, cwd = cwd, stdio = { nil, print_stdout and stderr, stderr }, env = env },
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
        if pkg.run:sub(1, 1) == ":" then
            vim.cmd(pkg.run)
        else
            for word in pkg.run:gmatch("%S+") do
                table.insert(args, word)
            end
            call_proc(table.remove(args, 1), args, pkg.dir, function(ok)
                local res = ok and "ok" or "err"
                report("hook", pkg.name, res)
                return counter and counter(pkg.name, res, sync)
            end)
        end
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

local function log_update_changes(pkg, prev_hash, cur_hash)
    local output = {"\n\n" .. pkg.name .. " updated:\n"}
    local stdout = uv.new_pipe()
    local options = {
        args = {"log", "--pretty=format:* %s", prev_hash .. ".." .. cur_hash},
        cwd = pkg.dir, stdio = {nil, stdout, nil},
    }
    local handle
    handle, _ = uv.spawn('git', options, function(code)
        assert(code == 0, "Exited(" .. code .. ")")
        handle:close()
        local log = uv.fs_open(logfile, "a+", 0x1A4)
        uv.fs_write(log, output, nil, nil)
        uv.fs_close(log)
    end)
    stdout:read_start(function(err, data)
        assert(not err, err)
        table.insert(output, data)
    end)
end

local function pull(pkg, counter, sync)
    local prev_hash = lock[pkg.name] and lock[pkg.name].hash or pkg.hash
    call_proc("git", { "pull", "--recurse-submodules", "--update-shallow" }, pkg.dir, function(ok)
        if not ok then
            counter(pkg.name, "err", sync)
        else
            local cur_hash = pkg.hash
            if cur_hash ~= prev_hash then
                log_update_changes(pkg, prev_hash, cur_hash)
                pkg.status = "updated"
                return pkg.run and run_hook(pkg, counter, sync) or counter(pkg.name, "ok", sync)
            else
                counter(pkg.name, "nop", sync)
            end
        end
    end)
end

local function clone_or_pull(pkg, counter)
    if pkg.exists and not pkg.pin then
        pull(pkg, counter, "update")
    elseif not pkg.exists then
        clone(pkg, counter, "install")
    end
end

-- Return an interator that walks `dir` in post-order.
local function walkdir(dir)
    return coroutine.wrap(function()
        local handle = uv.fs_scandir(dir)
        while handle do
            local name, t = uv.fs_scandir_next(handle)
            if not name then
                return
            elseif t == "directory" then
                for child, t in walkdir(dir .. "/" .. name) do
                    coroutine.yield(child, t)
                end
            end
            coroutine.yield(dir .. "/" .. name, t)
        end
    end)
end

local function rmdir(dir)
    for name, t in walkdir(dir) do
        local ok = (t == "directory") and uv.fs_rmdir(name) or uv.fs_unlink(name)
        if not ok then
            return ok
        end
    end
    return uv.fs_rmdir(dir)
end


local function remove(p, counter)
    local ok = rmdir(p.dir)
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
    state_write()
    lock = packages
end

local function sort_by_name(t)
    table.sort(t, function(a, b) return a.name < b.name end)
end

-- stylua: ignore
local function list()
    local installed = vim.tbl_filter(function(pkg) return pkg.exists end, packages)
    local removed = vim.tbl_filter(function(pkg) return pkg.status == "removed" end, lock)
    sort_by_name(installed)
    sort_by_name(removed)
    local markers = { installed = "+", updated = "*" }
    for header, pkgs in pairs { ["Installed packages:"] = installed, ["Recently removed:"] = removed } do
        if #pkgs ~= 0 then
            print(header)
            for _, pkg in ipairs(pkgs) do
                print(" ", markers[pkg.status] or " ", pkg.name)
            end
        end
    end
end

local function register(args)
    if type(args) == "string" then
        args = { args }
    end
    local url = args.url
        or (args[1]:match("^https?://") and args[1]) -- [1] is a URL
        or string.format(cfg.url_format, args[1]) -- [1] is a repository name
    local name = args.as
        or url:gsub("%.git$", ""):match("/([%w-_.]+)$") -- Infer name from `url`
    if not name then
        return vim.notify(" Paq: Failed to parse " .. vim.inspect(args), vim.log.levels.ERROR)
    end
    local opt = args.opt or cfg.opt and args.opt == nil
    local dir = cfg.path .. (opt and "opt/" or "start/") .. name
    packages[name] = {
        name = name,
        branch = args.branch,
        dir = dir,
        exists = vim.fn.isdirectory(dir) ~= 0,
        status = "listed", -- TODO: should probably merge this with `exists` in the future...
        hash = get_git_hash(dir),
        pin = args.pin,
        run = args.run, -- TODO(breaking): Rename
        url = url,
    }
end

-- stylua: ignore
return setmetatable({
    install = function() exe_op("install", clone, vim.tbl_filter(function(pkg) return not pkg.exists and pkg.status ~= "removed" end, packages)) end,
    update = function() exe_op("update", pull, vim.tbl_filter(function(pkg) return pkg.exists and not pkg.pin end, packages)) end,
    clean = function() exe_op("remove", remove, state_diff().lock) end,
    sync = function(self) self:clean() exe_op("sync", clone_or_pull, vim.tbl_filter(function(pkg) return pkg.status ~= "removed" end, packages)) end,
    setup = function(self, args) for k, v in pairs(args) do cfg[k] = v end return self end,
    _run_hook = function(name) return run_hook(packages[name]) end,
    _get_hooks = function() return vim.tbl_keys(vim.tbl_map(function(pkg) return pkg.run end, packages)) end,
    list = list,
    log_open = function() vim.cmd("sp " .. logfile) end,
    log_clean = function() return assert(uv.fs_unlink(logfile)) and vim.notify(" Paq: log file deleted") end,
    register = register,
    paq = register, -- TODO: deprecate. not urgent
}, {__call = function(self, tbl) packages = {} lock = lock_load() or packages vim.tbl_map(register, tbl) return self end,
})
