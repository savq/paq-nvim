local TESTPATH = vim.fn.stdpath("data") .. "/site/pack/test/"
local uv = vim.loop
local vim = require("paq.compat")

package.loaded.paq = nil
local paq = require("paq"):setup({ path = TESTPATH })

local PACKAGES = {
    -- { "badbadnotgood", opt = true }, -- should fail to parse
    { "rust-lang/rust.vim", opt = true }, -- test opt
    { "JuliaEditorSupport/julia-vim", as = "julia" }, -- test as

    { as = "wiki", url = "https://github.com/lervag/wiki.vim" }, -- test url + as

    { "junegunn/fzf", run = vim.fn["fzf#install"] }, -- test run function

    { "autozimu/LanguageClient-neovim", branch = "next", run = "bash install.sh" }, -- branch + run command
}

local function test_branch(paq, dir, branch)
    local stdout = uv.new_pipe(false)
    local handle = uv.spawn("git", {
        cwd = TESTPATH .. dir,
        args = { "branch", "--show-current" }, -- FIXME: This might not work with some versions of git
        stdio = { nil, stdout, nil },
    }, function(code)
        assert(code == 0, "Paq-test: failed to get git branch")
        stdout:read_stop()
        stdout:close()
    end)
    stdout:read_start(function(err, data)
        assert(not err, err)
        if data then
            assert(data == branch, string.format("Paq-test: %s does not equal %s", data, branch))
        end
    end)
end


local function test_install()
    assert(uv.fs_scandir(TESTPATH .. "opt/rust.vim"))
    assert(uv.fs_scandir(TESTPATH .. "start/julia"))
    assert(uv.fs_scandir(TESTPATH .. "start/wiki"))
    assert(uv.fs_scandir(TESTPATH .. "start/fzf"))
    assert(uv.fs_scandir(TESTPATH .. "start/LanguageClient-neovim"))

    test_branch("start/LanguageClient-neovim", "next")
end


local function test_clean()
    paq({
        { "JuliaEditorSupport/julia-vim", as = "julia" },
        { "autozimu/LanguageClient-neovim", branch = "next" },
    })
    paq.clean()
    assert(uv.fs_scandir(TESTPATH .. "start/julia"))
end

function _paq_after_install()
    test_install()
    test_clean()
    paq({})
    paq.clean()
end

local function main()
    vim.cmd("autocmd! User PaqDoneInstall lua _paq_after_install()")
    paq(PACKAGES):install()
end

main()
