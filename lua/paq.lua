--[[ TODOS:
-- fix paq-clean regression (weird path in vimtex tests)
-- Respond all other issues
-- deprecate nvim 0.4
-- deprecate logfile
-- ]]

local uv = vim.loop
local vim = vim.api.nvim_call_function("has", { "nvim-0.5" }) and vim or require("paq.compat") -- TODO: Deprecate
local cfg = {
    paqdir = vim.fn.stdpath("data") .. "/site/pack/paqs/",
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
for var, val in pairs(uv.os_environ()) do
    table.insert(env, ("%s=%s"):format(var, val))
end
table.insert(env, "GIT_TERMINAL_PROMPT=0")

vim.cmd [[
    command! PaqInstall  lua require('paq'):install()
    command! PaqUpdate   lua require('paq'):update()
    command! PaqClean    lua require('paq'):clean()
    command! PaqSync     lua require('paq'):sync()
    command! PaqList     lua require('paq').list()
    command! PaqLogOpen  lua require('paq').log_open()
    command! PaqLogClean lua require('paq').log_clean()
    command! PaqRunHooks lua require('paq'):run_hooks()  " TODO: DEPRECATE
    command! -nargs=1 -complete=customlist,v:lua.require'paq'._get_hooks PaqRunHook lua require('paq')._run_hook(<f-args>)
]]

local function report(op, name, res, n, total)
    local count = n and (" [%d/%d]"):format(n, total) or ""
    vim.notify(("Paq:%s %s %s"):format(count, messages[op][res], name), res == "err" and vim.log.levels.ERROR)
end

local function new_counter()
    return coroutine.wrap(function(op, total)
        local c = { ok = 0, err = 0, nop = 0 }
        while c.ok + c.err + c.nop < total do
            local name, res = coroutine.yield()
            c[res] = c[res] + 1
            if res ~= "nop" or cfg.verbose then
                report(op, name, res, c[res], total)
            end
        end
        local summary = "Paq: %s complete. %d ok; %d errors;"
        if c.nop > 0 then
            summary = summary .. " %d no-ops"
        end
        vim.notify(summary:format(op, c.ok, c.err, c.nop))
        vim.cmd("packloadall! | silent! helptags ALL")
        vim.cmd("doautocmd User PaqDone" .. op)
    end)
end

local function call_proc(process, args, cwd, cb)
    local log, stderr, handle
    log = uv.fs_open(LOGFILE, "a+", 0x1A4)
    stderr = uv.new_pipe(false)
    stderr:open(log)
    -- TODO: There's no error handling here!
    handle = uv.spawn(
        process,
        { args = args, cwd = cwd, stdio = { nil, nil, stderr }, env = env },
        vim.schedule_wrap(function(code)
            uv.fs_close(log)
            stderr:close()
            handle:close()
            cb(code == 0)
        end)
    )
end

local function run_hook(pkg)
    local t = type(pkg.run)
    if t == "function" then
        vim.cmd("packadd " .. pkg.name)
        local ok = pcall(pkg.run)
        report("hook", pkg.name, ok and "ok" or "err")
    elseif t == "string" then
        local args = {}
        for word in pkg.run:gmatch("%S+") do
            table.insert(args, word)
        end
        call_proc(table.remove(args, 1), args, pkg.dir, function(ok)
            report("hook", pkg.name, ok and "ok" or "err")
        end)
    end
end

local function clone(pkg, counter)
    local args = { "clone", pkg.url, "--depth=1", "--recurse-submodules", "--shallow-submodules" }
    if pkg.branch then
        vim.list_extend(args, { "-b", pkg.branch })
    end
    vim.list_extend(args, { pkg.dir })
    call_proc("git", args, nil, function(ok)
        counter(pkg.name, ok and "ok" or "err")
        if ok then
            pkg.exists = true
            pkg.status = "installed"
            return pkg.run and run_hook(pkg)
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

local function pull(pkg, counter)
    local hash = get_git_hash(pkg.dir)
    call_proc("git", { "pull", "--recurse-submodules", "--update-shallow" }, pkg.dir, function(ok)
        if not ok then
            counter(pkg.name, "err")
        elseif get_git_hash(pkg.dir) ~= hash then
            pkg.status = "updated"
            counter(pkg.name, "ok")
            return pkg.run and run_hook(pkg)
        else
            counter(pkg.name, "nop")
        end
    end)
end

local function check_rm()
    local to_remove = {}
    for _, packdir in pairs({ "start/", "opt/" }) do
        local path = cfg.paqdir .. packdir
        local handle = uv.fs_scandir(path)
        while handle do
            local name = uv.fs_scandir_next(handle)
            if not name then
                break
            end
            local pkg = packages[name]
            local dir = path .. name
            if not (pkg and pkg.dir == dir) then
                table.insert(to_remove, { name = name, dir = dir })
            end
        end
    end
    return to_remove
end

local function remove(p, counter)
    if p.name ~= "paq-nvim" then
        local ok = vim.fn.delete(p.dir, "rf") -- TODO(regression): This fails for weird paths
        counter(p.name, ok == 0 and "ok" or "err")
        if ok then
            packages[p.name] = {name = p.name, status = "removed"}
        end
    end
end

local function exe_op(op, fn, pkgs)
    if #pkgs == 0 then
        vim.notify("Paq: Nothing to " .. op)
        vim.cmd("doautocmd User PaqDone" .. op)
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
        return vim.notify("Paq: Failed to parse " .. src, vim.log.levels.ERROR)
    elseif packages[name] then
        return
    end
    local dir = cfg.paqdir .. (args.opt and "opt/" or "start/") .. name
    packages[name] = {
        name = name,
        branch = args.branch,
        dir = dir,
        exists = vim.fn.isdirectory(dir) ~= 0,
        status = "listed",   -- TODO: should probably merge this with `exists` in the future...
        pin = args.pin,
        run = args.run or args.hook, -- TODO(cleanup): remove `hook` option
        url = args.url or "https://github.com/" .. args[1] .. ".git",
    }
end

-- stylua: ignore
return setmetatable({
    install = function (self)
        exe_op("install", clone, vim.tbl_filter(function(pkg) return not (pkg.exists or pkg.status == "removed") end, packages))
        return self
    end;
    update = function (self)
        exe_op("update", pull, vim.tbl_filter(function(pkg) return pkg.exists and not pkg.pin end, packages)) return self
    end;
    clean = function (self)
        exe_op("remove", remove, check_rm()) return self
    end;
    sync = function(self) self:clean():update():install() return self end;

    _run_hook = function(pkgname) return run_hook(packages[pkgname]) end;
    _get_hooks = function()
        return vim.tbl_keys(vim.tbl_map(function(pkg) return pkg.run end, packages))
    end;
    run_hooks = function(self) vim.tbl_map(run_hook, packages) return self end; -- TODO: DEPRECATE

    list = list;
    -- TODO: is there an error here with paqdir/path?
    setup = function(self, args) for k, v in pairs(args) do cfg[k] = v end return self end;
    cfg = cfg;
    -- TODO: deprecate logs. not urgent
    log_open = function(self) vim.cmd("sp " .. LOGFILE) return self end;
    log_clean = function(self) uv.fs_unlink(LOGFILE) vim.notify("Paq log file deleted") return self end;

    -- TODO: deprecate. not urgent
    paq = register,
}, { __call = function(self, tbl) packages = {} vim.tbl_map(register, tbl) return self end,
})
