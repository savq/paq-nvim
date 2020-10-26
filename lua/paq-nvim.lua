local loop = vim.loop
-- Constants
local PATH = vim.fn.stdpath('data') .. '/site/pack/paqs/'
local GITHUB = 'https://github.com/'
local REPO_RE = '^[%w-]+/([%w-_.]+)$' --is this regex correct?

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
    local dir
    for name, args in pairs(packages) do
        dir = get_dir(name, args.opt)
        fn(name, dir, args)
    end
end

function rmdir(dir, ispkg)
    local name, child
    local ok = true
    local handle = loop.fs_scandir(dir)
    while handle do
        name, t = loop.fs_scandir_next(handle)
        if not name then break end
        child = dir .. '/' .. name
        if ispkg then
            if not packages[name] then --package isn't listed
                ok = rmdir(child)
                print_res('uninstall', name, ok)
            end
        else
            ok = (t == 'directory') and rmdir(child) or loop.fs_unlink(child)
        end
        if not ok then return end
    end
    return ispkg or loop.fs_rmdir(dir)
end

local function paq(args)
    local t = type(args)
    if t == 'string' then
        args = {args}
    elseif t ~= 'table' then
        return
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
