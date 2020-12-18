-- Constants
local PATH    = vim.fn.stdpath('data') .. '/site/pack/paqs/'
local GITHUB  = 'https://github.com/'
local REPO_RE = '^[%w-]+/([%w-_.]+)$'

local uv = vim.loop -- Alias for Neovim's event loop (libuv)
local packages = {} -- Table of 'name':{options} pairs
local call_cmd      -- To handle mutual funtion recursion (Lua shenanigans)

local function print_res(action, args, ok)
    local res = ok and 'Paq: ' or 'Paq: Failed to '
    print(res .. action .. ' ' .. args)
    return ok
end

local function run_hook(hook, name, dir)
    local t = type(hook)
    if t == 'function' then
        vim.cmd('packloadall!')
        local ok = pcall(hook)
        print_res('run hook for', name, ok) -- FIXME: How to print an interned string?

    elseif t == 'string' then
        local hook_args = {}
        local hook_cmd
        for word in hook:gmatch("%S+") do
            table.insert(hook_args, word)
        end
        hook_cmd = table.remove(hook_args, 1)
        call_cmd(hook_cmd, name, dir, "run `"..hook.."` for", hook_args)
    end
end

function call_cmd(cmd, name, dir, action, args, hook)
    local handle
    handle =
        uv.spawn(cmd,
            {args=args, cwd=(action ~= 'install' and dir or nil)}, -- FIXME: Handle install case better
            vim.schedule_wrap(
                function(code)
                    print_res(action, name, code == 0)
                    if hook then run_hook(hook, name, dir) end
                    handle:close()
                end
            )
        )
end

local function install_pkg(pkg)
    if pkg.exists then return end
    local install_args = {'clone', pkg.url}
    if pkg.branch then
        vim.list_extend(install_args, {'-b',  pkg.branch})
    end
    vim.list_extend(install_args, {pkg.dir})
    call_cmd('git', pkg.name, pkg.dir, 'install', install_args, pkg.hook)
end

local function update_pkg(pkg)
    if not pkg.exists then
        call_cmd('git', pkg.name, pkg.dir, 'update', {'pull'}, pkg.hook)
    end
end

local function rmdir(dir, ispkgdir)
    local name, t, child, ok
    local handle = uv.fs_scandir(dir)
    while handle do
        name, t = uv.fs_scandir_next(handle)
        if not name then break end
        child = dir .. '/' .. name
        if ispkgdir then --check which packages are listed
            if packages[name] then --do nothing
                ok = true
            else --package isn't listed, remove it
                ok = rmdir(child)
                print_res('uninstall', name, ok)
            end
        else --it's an arbitrary directory or file
            ok = (t == 'directory') and rmdir(child) or uv.fs_unlink(child)
        end
        if not ok then return end
    end
    return ispkgdir or uv.fs_rmdir(dir) -- Don't delete start or opt
end

local function paq(args)
    if type(args) == 'string' then args = {args} end

    local reponame = args[1]:match(REPO_RE)
    if not reponame then return print_res('parse', args[1]) end

    local dir = PATH .. (args.opt and 'opt/' or 'start/') .. reponame

    packages[reponame] = {
        name   = reponame,
        branch = args.branch,
        dir    = dir,
        exists = vim.fn.isdirectory(dir) ~= 0,
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
