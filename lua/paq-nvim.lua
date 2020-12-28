-- Constants
local PATH    = vim.fn.stdpath('data') .. '/site/pack/paqs/'
local GITHUB  = 'https://github.com/'
local REPO_RE = '^[%w-]+/([%w-_.]+)$'

local uv = vim.loop -- Alias for Neovim's event loop (libuv)
local packages = {} -- Table of 'name':{options} pairs
local run_hook      -- To handle mutual funtion recursion

local msgs = {clone = 'cloned', pull = 'pulled changes for', remove = 'removed'}

local num_pkgs = 0
local counters = {
    clone = {ok = 0, fail = 0},
    pull = {ok = 0, fail = 0},
    remove = {ok = 0, fail = 0},
}

local function inc(counter, result)
    counters[counter][result] = counters[counter][result] + 1
end

local function output_result(num, total, operation, name, ok)
    local result = ok and msgs[operation] or 'Failed to ' .. operation
    print(string.format('Paq [%d/%d] %s %s', num, total, result, name))
    --TODO: Write log
    return ok
end

local function count_ops(operation, name, ok)
    local result = ok and 'ok' or 'fail'
    inc(operation, result)
    output_result(counters[operation][result], num_pkgs, operation, name,  ok)
    if counters[operation].ok + counters[operation].fail == num_pkgs then
        counters[operation].ok, counters[operation].fail = 0, 0
        vim.cmd 'packloadall! | helptags ALL'
    end
    return ok
end

local function call_proc(process, pkg, args, cwd)
    local handle, t, num
    handle =
        uv.spawn(process, {args=args, cwd=cwd},
            vim.schedule_wrap( function (code)
                handle:close()
                count_ops(args[1] or process, pkg.name, code == 0)
                t = type(pkg.hook)
                if t == 'function' then
                    run_fn_hook(pkg.name, pkg.hook)
                elseif t == 'string' then
                    run_shell_hook(pkg)
                end
            end)
        )
end

local function run_fn_hook(name, hook)
    local ok = pcall(hook)
    --print('run hook for', name, ok) -- TODO
end

local function run_shell_hook(pkg)
    local process
    local args = {}
    for word in pkg.hook:gmatch("%S+") do
        table.insert(args, word)
    end
    process = table.remove(hook_args, 1)
    call_proc(process, pkg, args, pkg.dir)
end

local function install_pkg(pkg)
    local install_args = {'clone', pkg.url}
    if pkg.exists then return inc('clone', 'ok') end
    if pkg.branch then
        vim.list_extend(install_args, {'-b',  pkg.branch})
    end
    vim.list_extend(install_args, {pkg.dir})
    call_proc('git', pkg, install_args)
end

local function update_pkg(pkg)
    if pkg.exists then
        call_proc('git', pkg, {'pull'}, pkg.dir)
    end
end

local function rmdir(dir, is_pack_dir) --pack_dir = start | opt
    local name, t, child, ok
    local handle = uv.fs_scandir(dir)
    while handle do
        name, t = uv.fs_scandir_next(handle)
        if not name then break end
        child = dir .. '/' .. name
        if is_pack_dir then --check which packages are listed
            if packages[name] then --do nothing
                ok = true
            else --package isn't listed, remove it
                ok = rmdir(child)
                count_ops('remove', name, ok)
            end
        else --it's an arbitrary directory or file
            ok = (t == 'directory') and rmdir(child) or uv.fs_unlink(child)
        end
        if not ok then return end
    end
    return is_pack_dir or uv.fs_rmdir(dir) --don't delete start/opt
end

local function paq(args)
    if type(args) == 'string' then args = {args} end

    num_pkgs = num_pkgs + 1

    local reponame = args[1]:match(REPO_RE)
    if not reponame then
        return output_result(num_pkgs, num_pkgs, 'parse', args[1])
    end

    local dir = PATH .. (args.opt and 'opt/' or 'start/') .. reponame

    packages[reponame] = {
        name   = reponame,
        branch = args.branch,
        dir    = dir,
        exists = (vim.fn.isdirectory(dir) ~= 0),
        hook   = args.hook,
        url    = args.url or GITHUB .. args[1] .. '.git',
    }
end

return {
    install = function() vim.tbl_map(install_pkg, packages) end,
    update  = function() vim.tbl_map(update_pkg, packages) end,
    clean   = function() rmdir(PATH..'start', 1); rmdir(PATH..'opt', 1) end,
    paq     = paq,
}
