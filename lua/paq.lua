--[[ TODOS:
-- use coroutines to simplify logic
    -- refactor
    -- support for user auto-command #71
-- deprecate nvim 0.4
-- pkg.state instead of last_ops? (what about removed packages?)
-- fix paq-clean regression (weird path in vimtex tests)
-- extend instead of replace `env` in spawn #77
-- Respond all other issues
-- deprecate logfile?
-- ]]

local uv = vim.loop

-- TODO(cleanup): Deprecate
local vim = vim.api.nvim_call_function("has", { "nvim-0.5" }) and vim or require("paq.compat")
local ERROR = vim.log.levels.ERROR or 4

local cfg = {
    paqdir = vim.fn.stdpath("data") .. "/site/pack/paqs/",

    verbose = false,
}
local LOGFILE = vim.fn.stdpath("cache") .. "/paq.log"
local packages = {} -- 'name' = {options} pairs
local num_pkgs = 0
local last_ops = {} -- 'name' = 'op' pairs
local messages = {
    install = {
        ok = "installed %s",
        err = "failed to install %s",
    },
    update = {
        ok = "updated %s",
        err = "failed to update %s",
        nop = "(up-to-date) %s",
    },
    remove = {
        ok = "removed %s",
        err = "failed to remove %s",
    },
    hook = {
        ok = "ran hook for %s",
        err = "failed to run hook for %s",
    },
}

local function report(op, name, result, n, total)
    local count = n and string.format("%d/%d", n, total) or ""
    local msg = messages[op][result]
    vim.notify(
        string.format("Paq [%s] " .. msg, count, name),
        result == "err" and ERROR or nil -- 4 is error (check if nvim 0.4 has vim.log)
    )
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
        vim.notify(string.format("Paq: %s complete", op)) -- TODO: report summary
        vim.cmd("packloadall! | silent! helptags ALL")
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
        { args = args, cwd = cwd, stdio = { nil, nil, stderr }, env = { "GIT_TERMINAL_PROMPT=0" } },
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
        local post_hook = function(ok)
            report("hook", pkg.name, ok and "ok" or "err")
        end
        call_proc(table.remove(args, 1), args, pkg.dir, post_hook)
    end
end

local function clone(pkg, counter)
    local args = { "clone", pkg.url, "--depth=1", "--recurse-submodules", "--shallow-submodules" }
    if pkg.branch then
        vim.list_extend(args, { "-b", pkg.branch })
    end
    vim.list_extend(args, { pkg.dir })

    local post_install = function(ok)
        counter(pkg.name, ok and "ok" or "err")
        if ok then
            -- TODO: pkg.state
            pkg.exists = true
            last_ops[pkg.name] = "install"

            return pkg.run and run_hook(pkg)
        end
    end
    call_proc("git", args, nil, post_install)
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
    local post_update = function(ok)
        if not ok then
            counter(pkg.name, "err")
        elseif get_git_hash(pkg.dir) ~= hash then
            last_ops[pkg.name] = "update"
            counter(pkg.name, "ok")
            return pkg.run and run_hook(pkg)
        else
            counter(pkg.name, "nop")
        end
    end
    call_proc("git", { "pull", "--recurse-submodules", "--update-shallow" }, pkg.dir, post_update)
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
    end
end

local function exe_op(op, fn, pkgs)
    if #pkgs ~= 0 then
        local counter = new_counter()
        counter(op, #pkgs)
        for _, pkg in pairs(pkgs) do
            fn(pkg, counter)
        end
    else
        vim.notify("Paq: Nothing to " .. op)
    end
end

local function install(self)
    exe_op(
        "install",
        clone,
        vim.tbl_filter(function(pkg)
            return not pkg.exists
        end, packages)
    )
    return self
end

local function update(self)
    exe_op(
        "update",
        pull,
        vim.tbl_filter(function(pkg)
            return pkg.exists and not pkg.pin
        end, packages)
    )
    return self
end

function clean(self)
    exe_op("remove", remove, check_rm())
    return self
end

local function list()
    local installed = vim.tbl_filter(function(name)
        return packages[name].exists
    end, vim.tbl_keys(packages))
    local removed = vim.tbl_filter(function(name)
        return last_ops[name] == "remove"
    end, vim.tbl_keys(
        last_ops
    ))
    table.sort(installed)
    table.sort(removed)
    local sym_tbl = { install = "+", update = "*", remove = " " }
    for header, pkgs in pairs({ ["Installed packages:"] = installed, ["Recently removed:"] = removed }) do
        if #pkgs ~= 0 then
            print(header)
            for _, name in ipairs(pkgs) do
                print("  ", sym_tbl[last_ops[name]] or " ", name)
            end
        end
    end
end

local function register(args)
    if type(args) == "string" then
        args = { args }
    end
    local name, src
    if args.as then
        name = args.as
    elseif args.url then
        name = args.url:gsub("%.git$", ""):match("/([%w-_.]+)$")
        src = args.url
    else
        name = args[1]:match("^[%w-]+/([%w-_.]+)$")
        src = args[1]
    end
    if not name then
        return vim.notify("Paq: Failed to parse " .. src, 4)
    elseif packages[name] then
        return
    end

    local dir = cfg.paqdir .. (args.opt and "opt/" or "start/") .. name

    packages[name] = {
        name = name,
        branch = args.branch,
        dir = dir,
        exists = vim.fn.isdirectory(dir) ~= 0,
        pin = args.pin,
        run = args.run or args.hook, -- TODO(cleanup): remove `hook` option
        url = args.url or "https://github.com/" .. args[1] .. ".git",
    }
    num_pkgs = num_pkgs + 1
end

do
    vim.tbl_map(vim.cmd, {
        "command! PaqInstall  lua require('paq'):install()",
        "command! PaqUpdate   lua require('paq'):update()",
        "command! PaqClean    lua require('paq'):clean()",
        "command! PaqRunHooks lua require('paq'):run_hooks()",
        "command! PaqSync     lua require('paq'):sync()",
        "command! PaqList     lua require('paq').list()",
        "command! PaqLogOpen  lua require('paq').log_open()",
        "command! PaqLogClean lua require('paq').log_clean()",
    })
end

-- stylua: ignore
return setmetatable({
    -- TODO: deprecate. not urgent
    paq = register,
    debug_pkgs = function() return packages end,
    install = install,
    update = update,
    clean = clean,
    -- sync = function(self) self:clean():update():install() return self end,
    -- run_hooks = function(self) vim.tbl_map(run_hook, packages) return self end,
    list = list,
    -- TODO: is there an error here with paqdir/path?
    setup = function(self, args) for k, v in pairs(args) do cfg[k] = v end return self end,
    cfg = cfg,
    -- TODO: deprecate logs. not urgent
    log_open = function(self) vim.cmd("sp " .. LOGFILE) return self end,
    log_clean = function(self) uv.fs_unlink(LOGFILE) vim.notify("Paq log file deleted") return self end,
}, { __call = function(self, tbl) packages = {} num_pkgs = 0 vim.tbl_map(register, tbl) return self end,
})
