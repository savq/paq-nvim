local Paq = {} -- Module
local packages = {} -- Table of 'name':{options} pairs

-- Constants
local PATH = vim.fn.stdpath('data') .. '/site/pack/paq/'
local GITHUB = 'https://github.com/'
local REPO_RE = '^[%w-]+/([%w-_.]+)$' --is this regex correct?

-- Some helper functions

local function get_dir(name, opt)
    return PATH .. (opt and 'opt/' or 'start/') .. name
end

local function is_pkg_dir(dir)
    return vim.fn.isdirectory(dir) ~= 0
end

-- Replace with contents of test.lua
local function call_git(str) -- Make async
    r = os.execute('git ' .. str .. '&>/dev/null')
    return r == 0
end

local function print_err(operation, args)
    print('Failed to ' .. operation .. ': '..args)
end

-- Clone repo if it doesn't exist locally
local function install_pkg(name, args)
    local dir = get_dir(name, args.opt)
    local b = args.branch and (' -b ' .. args.branch .. ' --single-branch ') or ' '
    if not is_pkg_dir(dir) then
        ok = call_git('clone ' .. args.url .. b .. dir)
        if not ok then
            print_err('install', name)
        end
    end
end

-- Pull changes from remote
local function update_pkg(name, args)
    local dir = get_dir(name, args.opt)
    if is_pkg_dir(dir) then
        ok = call_git(' -C ' .. dir .. ' pull')
        if not ok then
            print_err('update', name)
        end
    end
end

local function map_pkgs(fn)
    if not fn then return end
    for name, args in pairs(packages) do
        fn(name, args)
    end
end

-- Public functions

function Paq.install() map_pkgs(install_pkg) end

function Paq.update() map_pkgs(update_pkg) end

function Paq.paq(args)
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

return Paq

