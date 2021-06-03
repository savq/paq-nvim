local uv  = vim.loop
local cmd = vim.api.nvim_command
local vfn = vim.api.nvim_call_function

cmd('packadd paq-nvim')
local TESTPATH = vfn('stdpath', {'data'}) .. '/site/pack/test/'
local paq = require('paq-nvim'):setup{path=TESTPATH}

local function test_branch(path, branch)
    local stdout = uv.new_pipe(false)
    local handle = uv.spawn('git',
        {
            cwd  = TESTPATH .. path,
            args = {'branch', '--show-current'}, -- FIXME: This might not work with some versions of git
            stdio = {nil, stout, nil},
        },
        function(code)
            assert(code == 0, "Paq-test: failed to get git branch")
            stdout:read_stop()
            stdout:close()
        end
    )

    stdout:read_start(function(err, data)
        assert(not err, err)
        if data then
            assert(data == branch, string.format("Paq-test: %s does not equal %s", data, branch))
        end
    end)
end

local function load_pkgs()
    paq {
        {'badbadnotgood', opt=true};                                 -- should fail to parse
        {'rust-lang/rust.vim', opt=true};                            -- test opt
        {'JuliaEditorSupport/julia-vim', as='julia'};                -- test as

        {as='wiki', url='https://github.com/lervag/wiki.vim'};       -- test url + as

        {'junegunn/fzf', run=function() vfn('fzf#install', {}) end}; -- test run function

        {'autozimu/LanguageClient-neovim', branch='next', run='bash install.sh'}; -- branch + run command
    }
end

local function test_install()
    paq.install()
    uv.sleep(5000)
    assert(uv.fs_scandir(TESTPATH .. 'opt/rust.vim'))
    assert(uv.fs_scandir(TESTPATH .. 'start/julia'))
    assert(uv.fs_scandir(TESTPATH .. 'start/wiki'))
    assert(uv.fs_scandir(TESTPATH .. 'start/fzf'))
    assert(uv.fs_scandir(TESTPATH .. 'start/LanguageClient-neovim'))

    --test_branch('start/LanguageClient-neovim', 'next')
end

local function test_clean()
    paq {
        {'JuliaEditorSupport/julia-vim', as='julia'};
        {'autozimu/LanguageClient-neovim', branch='next', run='bash install.sh'};
    }
    paq.clean()
    assert(uv.fs_scandir(TESTPATH .. 'start/julia'))
end

local function main()
    load_pkgs()
    test_install()
    test_clean()
    uv.sleep(5000)
    --paq.clean()
end

main()

