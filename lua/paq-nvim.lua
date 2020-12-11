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

local function install_pkg(name, dir, isdir, args)
    local install_args
    if not isdir then
        if args.branch then
            install_args = {'clone', args.url, '-b',  args.branch, '--single-branch', dir}
        else
            install_args = {'clone', args.url, dir}
        end
        call_cmd('git', name, dir, 'install', install_args, args.hook)
    end
end

local function update_pkg(name, dir, isdir, args)
    if isdir then
        call_cmd('git', name, dir, 'update', {'pull'}, args.hook)
    end
end

local function map_pkgs(fn)
    local dir, isdir
    for name, args in pairs(packages) do
        dir = PATH .. (args.opt and 'opt/' or 'start/') .. name
        isdir = vim.fn.isdirectory(dir) ~= 0
        fn(name, dir, isdir, args)
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
    if type(args) == 'string' then
        args = {args}
    end

    local reponame = args[1]:match(REPO_RE)
    if not reponame then
        print_res('parse', args[1])
        return
    end

    packages[reponame] = {
        branch = args.branch,
        hook   = args.hook,
        opt    = args.opt,
        url    = args.url or GITHUB .. args[1] .. '.git',
    }
end

return {
    install = function() map_pkgs(install_pkg) end,
    update  = function() map_pkgs(update_pkg) end,
    clean   = function() rmdir(PATH..'start', 1); rmdir(PATH..'opt', 1) end,
    paq     = paq
}
