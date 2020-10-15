-- Constants
local PATH = vim.fn.stdpath('data') .. '/site/pack/paqs/'
local GITHUB = 'https://github.com/'
local REPO_RE = '^[%w-]+/([%w-_.]+)$' --is this regex correct?

-- Table of 'name':{options} pairs
local packages = {}

-- Some helper functions

local function get_dir(name, opt)
    return PATH .. (opt and 'opt/' or 'start/') .. name
end

local function is_pkg_dir(dir)
    return vim.fn.isdirectory(dir) ~= 0
end

local function print_err(operation, args)
    print('Paq failed to ' .. operation .. ' ' .. args)
end

local function print_success(operation, args)
    print('Paq: ' .. operation .. ' ' .. args)
end

local function call_git(action, name, ...)
    local args = {...}
    local handle
    handle = vim.loop.spawn('git',
        {args=args},
        vim.schedule_wrap(
            function(code, signal)
                if code == 0 then
                    print_success(action, name)
                else
                    print_err(action, name)
                end
                handle:close()
            end
        )
    )
end

local function install_pkg(name, args)
    local dir = get_dir(name, args.opt)
    if not is_pkg_dir(dir) then
        local ok = true
        if args.branch then
            call_git('install', name, 'clone', args.url, '-b',  args.branch, '--single-branch', dir)
        else
            call_git('install', name, 'clone', args.url, dir)
        end
    end
end

local function update_pkg(name, args)
    local dir = get_dir(name, args.opt)
    if is_pkg_dir(dir) then
        call_git('update', name, '-C', dir, 'pull')
    end
end

local function map_pkgs(fn)
    if not fn then return end
    for name, args in pairs(packages) do
        fn(name, args)
    end
end

local function clean_pkgs(dir)
    local handle = vim.loop.fs_scandir(dir)
    local name, ok
    while handle do
        name = vim.loop.fs_scandir_next(handle)
        if not name then break end
        if not packages[name] then -- Package isn't listed
            ok = rmdir_rec(dir .. name)
            if not ok then
                print('error')
                return
            end
        end
    end
end

function rmdir_rec(dir) -- FIXME: Find alternative to this function
    local handle = vim.loop.fs_scandir(dir)
    local name, ok
    while handle do
        name, t = vim.loop.fs_scandir_next(handle)
        if not name then break end
        child = dir .. '/' .. name
        if t == 'directory' then
            ok = rmdir_rec(child)
        else
            ok = vim.loop.fs_unlink(child)
        end
        if not ok then return end
    end
    return vim.loop.fs_rmdir(dir)
end


local function paq(args)
    local a = type(args)
    if a == 'string' then
        args = {args}
    elseif a ~= 'table' then
        return
    end
    local reponame = args[1]:match(REPO_RE)
    packages[reponame] = {
        opt    = args.opt or false,
        url    = args.url or GITHUB .. args[1] .. '.git',
        branch = args.branch or nil
    }
end

return {
    install = function() map_pkgs(install_pkg) end,
    update  = function() map_pkgs(update_pkg) end,
    clean  = function() clean_pkgs('start/'); clean_pkgs('opt/') end,
    paq     = paq
}
