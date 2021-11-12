--[[ TODOS:
-- use coroutines to simplify logic
    -- refactor
    -- support for user auto-command #71
-- deprecate nvim 0.4
    -- use vim.notify #65
-- fix paq-clean regression (weird path in vimtex tests)
-- extend instead of replace `env` in spawn #77
-- Respond all other issues
-- deprecate logfile?
-- ]]

local uv = vim.loop

-- TODO(cleanup): Deprecate
local vim = vim.api.nvim_call_function("has", { "nvim-0.5" }) and vim or require("paq.compat")

-- TODO(notify): Replace with vim.notify
local print_err = vim.api.nvim_err_writeln

local cfg = {
    paqdir = vim.fn.stdpath("data") .. "/site/pack/paqs/",
    -- TODO(notify): Default to verbose=false
    verbose = true,
}
local LOGFILE = vim.fn.stdpath("cache") .. "/paq.log"
local packages = {} -- 'name' = {options} pairs
local num_pkgs = 0
local last_ops = {} -- 'name' = 'op' pairs
local counters = {}
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

local function Counter(op)
    counters[op] = { ok = 0, err = 0, nop = 0 }
end

local function update_count(op, result, _, total)
    local c, t = counters[op]
    if not c then
        return
    end
    c[result] = c[result] + 1
    t = c[result]
    if c.ok + c.err + c.nop == total then
        Counter(op)
        vim.cmd("packloadall! | silent! helptags ALL")
    end
    return t
end

local function report(op, result, name, total)
    local total = total or num_pkgs
    local cur = update_count(op, result, nil, total)
    local count = cur and string.format("%d/%d", cur, total) or ""
    local msg = messages[op][result]
    local p = result == "err" and print_err or print
    p(string.format("Paq [%s] " .. msg, count, name))
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
        report("hook", ok and "ok" or "err", pkg.name)
    elseif t == "string" then
        local args = {}
        for word in pkg.run:gmatch("%S+") do
            table.insert(args, word)
        end
        local post_hook = function(ok)
            report("hook", ok and "ok" or "err", pkg.name)
        end
        call_proc(table.remove(args, 1), args, pkg.dir, post_hook)
    end
end

local function install(pkg)
    if pkg.exists then
        return update_count("install", "nop", nil, num_pkgs)
    end
    local args = { "clone", pkg.url, "--depth=1", "--recurse-submodules", "--shallow-submodules" }
    if pkg.branch then
        vim.list_extend(args, { "-b", pkg.branch })
    end
    vim.list_extend(args, { pkg.dir })
    local post_install = function(ok)
        if ok then
            pkg.exists = true
            last_ops[pkg.name] = "install"
            if pkg.run then
                run_hook(pkg)
            end
        end
        report("install", ok and "ok" or "err", pkg.name)
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

local function update(pkg)
    if not pkg.exists or pkg.pin then
        return update_count("update", "nop", nil, num_pkgs)
    end
    local hash = get_git_hash(pkg.dir)
    local post_update = function(ok)
        if not ok then
            return report("update", "err", pkg.name)
        elseif get_git_hash(pkg.dir) ~= hash then
            last_ops[pkg.name] = "update"
            report("update", "ok", pkg.name)
            if pkg.run then
                run_hook(pkg)
            end
        else
            (cfg.verbose and report or update_count)("update", "nop", pkg.name, num_pkgs) -- blursed
        end
    end
    call_proc("git", { "pull", "--recurse-submodules", "--update-shallow" }, pkg.dir, post_update)
end

local function remove(packdir)
    local name, dir, pkg
    local to_rm = {}
    local c = 0
    local handle = uv.fs_scandir(packdir)
    while handle do
        name = uv.fs_scandir_next(handle)
        if not name then
            break
        end
        pkg = packages[name]
        dir = packdir .. name
        if not (pkg and pkg.dir == dir) then
            to_rm[name] = dir
            c = c + 1
        end
    end
    for name, dir in pairs(to_rm) do
        if name ~= "paq-nvim" then
            local ok = vim.fn.delete(dir, "rf")
            report("remove", ok == 0 and "ok" or "err", name, c)
        end
    end
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
        return print_err("Paq: Failed to parse " .. src)
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
    install = function(self) Counter("install") vim.tbl_map(install, packages) return self end,
    update = function(self) Counter("update") vim.tbl_map(update, packages) return self end,
    clean = function(self) Counter("remove") remove(cfg.paqdir .. "start/") remove(cfg.paqdir .. "opt/") return self end,
    sync = function(self) self:clean():update():install() return self end,
    run_hooks = function(self) vim.tbl_map(run_hook, packages) return self end,
    list = list, setup = function(self, args) for k, v in pairs(args) do cfg[k] = v end return self end,
    -- TODO: deprecate logs. not urgent
    log_open = function(self) vim.cmd("sp " .. LOGFILE) return self end,
    log_clean = function(self) uv.fs_unlink(LOGFILE) print("Paq log file deleted") return self end,
}, { __call = function(self, tbl) packages = {} num_pkgs = 0 vim.tbl_map(register, tbl) return self end,
})
