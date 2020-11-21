-- Constants
local PATH    = vim.fn.stdpath('data') .. '/site/pack/paqs/'
local GITHUB  = 'https://github.com/'
local REPO_RE = '^[%w-]+/([%w-_.]+)$'

local uv = vim.loop -- Alias for Neovim's event loop (libuv)
local packages = {} -- Table of 'name':{options} pairs

local function print_res(action, args, ok)
    local res = ok and 'Paq: ' or 'Paq: Failed to '
    print(res .. action .. ' ' .. args)
end

local function call_git(name, dir, action, ...)
    local args = {...}
    local handle
    handle = uv.spawn('git',
        {args=args, cwd=dir},
        vim.schedule_wrap(
            function(code, signal)
                print_res(action, name, code == 0)
                handle:close()
            end
        )
    )
end

local function install_pkg(name, dir, isdir, args)
    if not isdir then
        if args.branch then
            call_git(name, nil, 'install', 'clone', args.url, '-b',  args.branch, '--single-branch', dir)
        else
            call_git(name, nil, 'install', 'clone', args.url, dir)
        end
    end
end

local function update_pkg(name, dir, isdir)
    if isdir then
        call_git(name, dir, 'update', 'pull')
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
