-- TODO Jobs

local Paq = {} -- Module
local packages = {} -- Table of 'name':{options} pairs

-- Magic constants
local GITHUB = 'https://github.com/'
local PATH = vim.fn.stdpath('data') .. '/site/pack/paq/'

-- Some helper functions

local function is_pkg_dir(dirname)
    return vim.fn.isdirectory(dirname) ~= 0
end

local function call_git(str)
    r = os.execute('git '..str..'&>/dev/null')
    return r == 0
end

local function print_err(operation, args)
    print('Failed to '..operation..': '..args)
end

-- Clone repo if it doesn't exist locally
function install_pkg(name, args)
    local dir = PATH .. (args.opt and 'opt/' or 'start/') .. name
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
    local dir = PATH .. (args.opt and 'opt/' or 'start/') .. name
    if is_pkg_dir(dir) then
        ok = call_git('-C '.. dir .. ' pull')
        if not ok then
            print_err('update', name)
        end
    end
end

local function map_pkgs(fn)
    if not fn then return -1 end
    for name, args in pairs(packages) do
        fn(name, args)
    end
end

-- Public functions

function Paq.install() map_pkgs(install_pkg) end

function Paq.update() map_pkgs(install_pkg) end

function Paq.auto()
    map_pkgs(install_pkg)
    map_pkgs(update)
end

-- Add a package to the packages table
function Paq.paq(args)
    local a = type(args)
    if a == 'string' then
        args = {args}
    elseif a ~= 'table' then
        return
    end
    local reponame = args[1]:match'^[%w-]+/([%w-_.]+)$' --is this regex correct?
    packages[reponame] = {
        opt    = args.opt or false,
        url    = args.url or GITHUB .. args[1] .. '.git',
        branch = args.branch or nil
    }
end

return Paq

