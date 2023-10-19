-- VARS: {{{

---@alias Path string

local uv = vim.loop

---@class setup_opts
---@field path Path
---@field opt boolean
---@field verbose boolean
---@field log Path
---@field lock Path
---@field url_format string
---@field clone_args string[]
local Config = {
    path = vim.fn.stdpath("data") .. "/site/pack/paqs/",
    opt = false,
    verbose = false,
    url_format = "https://github.com/%s.git",
    log = vim.fn.stdpath(vim.fn.has("nvim-0.8") == 1 and "log" or "cache") .. "/paq.log",
    lock = vim.fn.stdpath("data") .. "/paq-lock.json",
    clone_args = { "--depth=1", "--recurse-submodules", "--shallow-submodules", "--no-single-branch" }
}

---@enum Messages
local Messages = {
    install = { ok = "Installed", err = "Failed to install" },
    update = { ok = "Updated", err = "Failed to update", nop = "(up-to-date)" },
    remove = { ok = "Removed", err = "Failed to remove" },
    build = { ok = "Built", err = "Failed to build" },
}

local Lock = {}     -- Table of pgks loaded from the lockfile
local Packages = {} -- Table of pkgs loaded from the user configuration

---@enum Status
local Status = {
    INSTALLED = 0,
    CLONED = 1,
    UPDATED = 2,
    REMOVED = 3,
    TO_INSTALL = 4,
    TO_MOVE = 5,
    TO_RECLONE = 6,
}

-- stylua: ignore
local Filter = {
    installed   = function(p) return p.status ~= Status.REMOVED and p.status ~= Status.TO_INSTALL end,
    not_removed = function(p) return p.status ~= Status.REMOVED end,
    removed     = function(p) return p.status == Status.REMOVED end,
    to_install  = function(p) return p.status == Status.TO_INSTALL end,
    to_update   = function(p) return p.status ~= Status.REMOVED and p.status ~= Status.TO_INSTALL and not p.pin end,
    to_move     = function(p) return p.status == Status.TO_MOVE end,
    to_reclone  = function(p) return p.status == Status.TO_RECLONE end,
}

-- Copy environment variables once. Doing it for every process seems overkill.
local Env = {}
for var, val in pairs(uv.os_environ()) do
    table.insert(Env, string.format("%s=%s", var, val))
end
table.insert(Env, "GIT_TERMINAL_PROMPT=0")

-- }}}
-- UTILS: {{{

---@return Package
local function find_unlisted()
    local unlisted = {}
    -- TODO(breaking): Replace with `vim.fs.dir`
    for _, packdir in pairs { "start", "opt" } do
        local path = Config.path .. packdir
        local handle = uv.fs_scandir(path)
        while handle do
            local name, t = uv.fs_scandir_next(handle)
            if t == "directory" and name ~= "paq-nvim" then
                local dir = path .. "/" .. name
                local pkg = Packages[name]
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

---@param dir Path
---@return string
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

---@param process string
---@param args string[]
---@param cwd string?
---@param cb function
---@param print_stdout boolean?
local function run(process, args, cwd, cb, print_stdout)
    local log = uv.fs_open(Config.log, "a+", 0x1A4)
    local stderr = uv.new_pipe(false)
    stderr:open(log)
    local handle, pid
    handle, pid = uv.spawn(
        process,
        { args = args, cwd = cwd, stdio = { nil, print_stdout and stderr, stderr }, env = Env },
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

---Return an interator that walks `dir` in post-order.
---@param dir Path
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

---@param dir Path
local function rmdir(dir)
    for name, t in walkdir(dir) do
        local ok = (t == "directory") and uv.fs_rmdir(name) or uv.fs_unlink(name)
        if not ok then
            return ok
        end
    end
    return uv.fs_rmdir(dir)
end


-- }}}
-- LOGGING: {{{

---@param pkg Package
---@param prev_hash string
---@param cur_hash string
local function log_update_changes(pkg, prev_hash, cur_hash)
    local output = { "\n\n" .. pkg.name .. " updated:\n" }
    local stdout = uv.new_pipe()
    local options = {
        args = { "log", "--pretty=format:* %s", prev_hash .. ".." .. cur_hash },
        cwd = pkg.dir,
        stdio = { nil, stdout, nil },
    }
    local handle
    handle, _ = uv.spawn("git", options, function(code)
        assert(code == 0, "Exited(" .. code .. ")")
        handle:close()
        local log = uv.fs_open(Config.log, "a+", 0x1A4)
        uv.fs_write(log, output, nil, nil)
        uv.fs_close(log)
    end)
    stdout:read_start(function(err, data)
        assert(not err, err)
        table.insert(output, data)
    end)
end

---@param name string
---@param msg_op Messages
---@param result boolean
---@param n integer
---@param total integer
local function report(name, msg_op, result, n, total)
    local count = n and string.format(" [%d/%d]", n, total) or ""
    vim.notify(
        string.format(" Paq:%s %s %s", count, msg_op[result], name),
        result == "err" and vim.log.levels.ERROR or vim.log.levels.INFO
    )
end

---Object to track result of operations (installs, updates, etc.)
---@param total integer
---@param callback function
local function new_counter(total, callback)
    return coroutine.wrap(function()
        local c = { ok = 0, err = 0, nop = 0 }
        while c.ok + c.err + c.nop < total do
            local name, msg_op, result = coroutine.yield(true)
            c[result] = c[result] + 1
            if result ~= "nop" or Config.verbose then
                report(name, msg_op, result, c.ok + c.nop, total)
            end
        end
        callback(c.ok, c.err, c.nop)
        return true
    end)
end


-- }}}
-- LOCKFILE: {{{

local function lock_write()
    -- remove run key since can have a function in it, and
    -- json.encode doesn't support functions
    local pkgs = vim.deepcopy(Packages)
    for p, _ in pairs(pkgs) do
        pkgs[p].build = nil
    end
    local file = uv.fs_open(Config.lock, "w", 438)
    if file then
        local ok, result = pcall(vim.json.encode, pkgs)
        if not ok then
            error(result)
        end
        assert(uv.fs_write(file, result))
        assert(uv.fs_close(file))
    end
    Lock = Packages
end

local function lock_load()
    -- don't really know why 438 see ':h uv_fs_t'
    local file = uv.fs_open(Config.lock, "r", 438)
    if file then
        local stat = assert(uv.fs_fstat(file))
        local data = assert(uv.fs_read(file, stat.size, 0))
        assert(uv.fs_close(file))
        local ok, result = pcall(vim.json.decode, data)
        if ok then
            Lock = not vim.tbl_isempty(result) and result or Packages
            -- Repopulate 'build' key so 'vim.deep_equal' works
            for name, pkg in pairs(result) do
                pkg.build = Packages[name] and Packages[name].build or nil
            end
        end
    else
        lock_write()
        Lock = Packages
    end
end

-- }}}
-- PKGS: {{{

---@class Package
---@field name string
---@field as string
---@field branch string
---@field dir string
---@field status Status
---@field hash string
---@field pin boolean
---@field build string | function
---@field url string

---@param pkg Package
---@param counter function
---@param build_queue table
local function clone(pkg, counter, build_queue)
    local args = vim.list_extend({ "clone", pkg.url }, Config.clone_args)
    if pkg.branch then
        vim.list_extend(args, { "-b", pkg.branch })
    end
    table.insert(args, pkg.dir)
    run("git", args, nil, function(ok)
        if ok then
            pkg.status = Status.CLONED
            lock_write()
            if pkg.build then
                table.insert(build_queue, pkg)
            end
        end
        counter(pkg.name, Messages.install, ok and "ok" or "err")
    end)
end

---@param pkg Package
---@param counter function
---@param build_queue table
local function pull(pkg, counter, build_queue)
    local prev_hash = Lock[pkg.name] and Lock[pkg.name].hash or pkg.hash
    run("git", { "pull", "--recurse-submodules", "--update-shallow" }, pkg.dir, function(ok)
        if not ok then
            counter(pkg.name, Messages.update, "err")
        else
            local cur_hash = pkg.hash
            if cur_hash ~= prev_hash then
                log_update_changes(pkg, prev_hash, cur_hash)
                pkg.status = Status.UPDATED
                lock_write()
                counter(pkg.name, Messages.update, "ok")
                if pkg.build then
                    table.insert(build_queue, pkg)
                end
            else
                counter(pkg.name, Messages.update, "nop")
            end
        end
    end)
end

---@param pkg Package
---@param counter function
---@param build_queue table
local function clone_or_pull(pkg, counter, build_queue)
    if Filter.to_update(pkg) then
        pull(pkg, counter, build_queue)
    elseif Filter.to_install(pkg) then
        clone(pkg, counter, build_queue)
    end
end

---Move package to wanted location.
---@param src Package
---@param dst Package
local function move(src, dst)
    local ok = uv.fs_rename(src.dir, dst.dir)
    if ok then
        dst.status = Status.INSTALLED
        lock_write()
    end
end

---@param pkg Package
local function run_build(pkg)
    local t = type(pkg.build)
    if t == "function" then
        local ok = pcall(pkg.build)
        report(pkg.name, Messages.build, ok and "ok" or "err")
    elseif t == "string" and pkg.build:sub(1, 1) == ":" then
        local ok = pcall(vim.cmd, pkg.build)
        report(pkg.name, Messages.build, ok and "ok" or "err")
    elseif t == "string" then
        local args = {}
        for word in pkg.build:gmatch("%S+") do
            table.insert(args, word)
        end
        run(table.remove(args, 1), args, pkg.dir, function(ok)
            report(pkg.name, Messages.build, ok and "ok" or "err")
        end)
    end
end

---@param pkg Package
local function reclone(pkg, counter, build_queue)
    local ok = rmdir(pkg.dir)
    if not ok then
        return
    end
    local args = vim.list_extend({ "clone", pkg.url }, Config.clone_args)
    if pkg.branch then
        vim.list_extend(args, { "-b", pkg.branch })
    end
    table.insert(args, pkg.dir)
    run("git", args, nil, function(ok)
        if ok then
            pkg.status = Status.INSTALLED
            pkg.hash = get_git_hash(pkg.dir)
            lock_write()
            if pkg.build then
                table.insert(build_queue, pkg)
            end
        end
    end)
end

local function resolve(pkg, counter, build_queue)
    if Filter.to_move(pkg) then
        move(pkg, Packages[pkg.name])
    elseif Filter.to_reclone(pkg) then
        reclone(Packages[pkg.name], counter, build_queue)
    end
end

---@param pkg Package
local function register(pkg)
    if type(pkg) == "string" then
        pkg = { pkg }
    end
    local url = pkg.url
        or (pkg[1]:match("^https?://") and pkg[1])                      -- [1] is a URL
        or string.format(Config.url_format, pkg[1])                     -- [1] is a repository name
    local name = pkg.as or url:gsub("%.git$", ""):match("/([%w-_.]+)$") -- Infer name from `url`
    if not name then
        return vim.notify(" Paq: Failed to parse " .. vim.inspect(pkg), vim.log.levels.ERROR)
    end
    local opt = pkg.opt or Config.opt and pkg.opt == nil
    local dir = Config.path .. (opt and "opt/" or "start/") .. name
    Packages[name] = {
        name = name,
        branch = pkg.branch,
        dir = dir,
        status = uv.fs_stat(dir) and Status.INSTALLED or Status.TO_INSTALL,
        hash = get_git_hash(dir),
        pin = pkg.pin,
        build = pkg.build or pkg.run,
        url = url,
    }
    if pkg.run then
        vim.deprecate("`run` option", "`build`", "3.0", "Paq", false)
    end
end

---@param pkg Package
---@param counter function
local function remove(pkg, counter)
    local ok = rmdir(pkg.dir)
    counter(pkg.name, Messages.remove, ok and "ok" or "err")
    if ok then
        Packages[pkg.name] = { name = pkg.name, status = Status.REMOVED }
        lock_write()
    end
end

---@alias Operation
---| '"install"'
---| '"update"'
---| '"remove"'
---| '"build"'
---| '"resolve"'
---| '"sync"'

---Boilerplate around operations (autocmds, counter initialization, etc.)
---@param op Operation
---@param fn function
---@param pkgs Package[]
---@param silent boolean?
local function exe_op(op, fn, pkgs, silent)
    if #pkgs == 0 then
        if not silent then
            vim.notify(" Paq: Nothing to " .. op)
        end
        vim.cmd("doautocmd User PaqDone" .. op:gsub("^%l", string.upper))
        return
    end

    local build_queue = {}

    local function after(ok, err, nop)
        local summary = " Paq: %s complete. %d ok; %d errors;" .. (nop > 0 and " %d no-ops" or "")
        vim.notify(string.format(summary, op, ok, err, nop))
        vim.cmd("packloadall! | silent! helptags ALL")
        if #build_queue ~= 0 then
            exe_op("build", run_build, build_queue)
        end
        vim.cmd("doautocmd User PaqDone" .. op:gsub("^%l", string.upper))
    end

    local counter = new_counter(#pkgs, after)
    counter() -- Initialize counter

    for _, pkg in pairs(pkgs) do
        fn(pkg, counter, build_queue)
    end
end

-- }}}
-- DIFFS: {{{

local function diff_gather()
    local diffs = {}
    for name, lock_pkg in pairs(Lock) do
        local pack_pkg = Packages[name]
        if pack_pkg and Filter.not_removed(lock_pkg) and not vim.deep_equal(lock_pkg, pack_pkg) then
            for k, v in pairs {
                dir = Status.TO_MOVE,
                branch = Status.TO_RECLONE,
                url = Status.TO_RECLONE,
            } do
                if lock_pkg[k] ~= pack_pkg[k] then
                    lock_pkg.status = v
                    table.insert(diffs, lock_pkg)
                end
            end
        end
    end
    return diffs
end


-- }}}
-- PUBLIC API: {{{

local paq = {}

---Installs all packages listed in your configuration. If a package is already
---installed, the function ignores it. If a package has a `build` argument,
---it'll be executed after the package is installed.
function paq.install() exe_op("install", clone, vim.tbl_filter(Filter.to_install, Packages)) end

---Updates the installed packages listed in your configuration. If a package
---hasn't been installed with |PaqInstall|, the function ignores it. If a
---package had changes and it has a `build` argument, then the `build` argument
---will be executed.
function paq.update() exe_op("update", pull, vim.tbl_filter(Filter.to_update, Packages)) end

---Removes packages found on |paq-dir| that aren't listed in your
---configuration.
function paq.clean() exe_op("remove", remove, find_unlisted()) end

---Executes |paq.clean|, |paq.update|, and |paq.install|. Note that all
---paq operations are performed asynchronously, so messages might be printed
---out of order.
function paq:sync()
    self:clean()
    exe_op("sync", clone_or_pull, vim.tbl_filter(Filter.not_removed, Packages))
end

---@param opts setup_opts
function paq:setup(opts)
    for k, v in pairs(opts) do
        Config[k] = v
    end
    return self
end

function paq.list()
    local installed = vim.tbl_filter(Filter.installed, Lock)
    local removed = vim.tbl_filter(Filter.removed, Lock)
    local function sort_by_name(t)
        table.sort(t, function(a, b) return a.name < b.name end)
    end
    sort_by_name(installed)
    sort_by_name(removed)
    local markers = { "+", "*" }
    for header, pkgs in pairs { ["Installed packages:"] = installed, ["Recently removed:"] = removed } do
        if #pkgs ~= 0 then
            print(header)
            for _, pkg in ipairs(pkgs) do
                print(" ", markers[pkg.status] or " ", pkg.name)
            end
        end
    end
end

function paq.log_open() vim.cmd("sp " .. Config.log) end

function paq.log_clean() return assert(uv.fs_unlink(Config.log)) and vim.notify(" Paq: log file deleted") end

local meta = {}

---The `paq` module is itself a callable object. It takes as argument a list of
---packages. Each element of the list can be a table or a string.
---
---When the element is a table, the first value has to be a string with the
---name of the repository, like: `'<GitHub-username>/<repository-name>'`.
---The other key-value pairs in the table have to be named explicitly, see
---|paq-options|. When the element is a string, it works as if it was the first
---value of the table, and all other options will be set to their default
---values.
---
---Note: Lua can elide parentheses when passing a single table argument to a
---function, so you can always call `paq` without parentheses.
---See |luaref-langFuncCalls|.
function meta:__call(pkgs)
    Packages = {}
    vim.tbl_map(register, pkgs)
    lock_load()
    exe_op("resolve", resolve, diff_gather(), true)
    return self
end

setmetatable(paq, meta)

for cmd_name, fn in pairs {
    PaqInstall = paq.install,
    PaqUpdate = paq.update,
    PaqClean = paq.clean,
    PaqList = paq.list,
    PaqLogOpen = paq.log_open,
    PaqLogClean = paq.log_clean,
}
do
    vim.api.nvim_create_user_command(cmd_name, function(_) fn() end, { bar = true })
end

-- stylua: ignore
do
    local build_cmd_opts = {
        bar = true,
        nargs = 1,
        complete = function() return vim.tbl_keys(vim.tbl_map(function(pkg) return pkg.build end, Packages)) end,
    }
    vim.api.nvim_create_user_command("PaqSync", function() paq:sync() end, { bar = true })
    vim.api.nvim_create_user_command("PaqBuild", function(a) run_build(Packages[a.args]) end, build_cmd_opts)
    vim.api.nvim_create_user_command("PaqRunHook", function(a)
        vim.deprecate("`PaqRunHook` command", "`PaqBuild`", "3.0", "Paq", false)
        run_build(Packages[a.args])
    end, build_cmd_opts)
end

return paq

-- }}}
-- vim: foldmethod=marker foldlevel=1
