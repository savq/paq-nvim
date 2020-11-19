local loop = vim.loop
-- Constants
local PATH = vim.fn.stdpath('data') .. '/site/pack/paqs/'
local GITHUB = 'https://github.com/'
local REPO_RE = '^[%w-]+/([%w-_.]+)$'

-- Table of 'name':{options} pairs
local packages = {}

local function get_dir(name, opt)
    return PATH .. (opt and 'opt/' or 'start/') .. name
end

local function is_pkg_dir(dir)
    return vim.fn.isdirectory(dir) ~= 0
end

local function print_res(action, args, ok)
    local res = ok and 'Paq: ' or 'Paq: Failed to '
    print(res .. action .. ' ' .. args)
end

local function call_git(action, name, ...)
    local args = {...}
    local handle
    handle = loop.spawn('git',
        {args=args},
        vim.schedule_wrap(
            function(code, signal)
                print_res(action, name, code == 0)
                handle:close()
            end
        )
    )
end

local function install_pkg(name, dir, args)
    if not is_pkg_dir(dir) then
        if args.branch then
            call_git('install', name, 'clone', args.url, '-b',  args.branch, '--single-branch', dir)
        else
            call_git('install', name, 'clone', args.url, dir)
        end
    end
end

local function update_pkg(name, dir)
    if is_pkg_dir(dir) then
        call_git('update', name, '-C', dir, 'pull')
    end
end

local function map_pkgs(fn)
    for name, args in pairs(packages) do
        fn(name, get_dir(name, args.opt), args)
    end
end

local function rmdir(dir, ispkgdir)
    local name, t, child, ok
    local handle = loop.fs_scandir(dir)
    while handle do
        name, t = loop.fs_scandir_next(handle)
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
            ok = (t == 'directory') and rmdir(child) or loop.fs_unlink(child)
        end

        if not ok then return end
    end
    return ispkgdir or loop.fs_rmdir(dir) -- Don't delete start or opt
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
