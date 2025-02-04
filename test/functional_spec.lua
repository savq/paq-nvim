local packdir = vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "site", "pack", "paqs")
local paq = require("paq")

local function pack_isinstalled(name)
    local path = vim.fs.joinpath(packdir, name)
    return vim.uv.fs_stat(path)
end

describe("PaqInstall", function()
    it("fresh", function()
        paq {
            "neovim/nvim-lspconfig",
            { "rust-lang/rust.vim", opt = true },
            { "JuliaEditorSupport/julia-vim", as = "julia" },
        }
        paq.install()

        vim.api.nvim_create_autocmd("User", {
            once = true,
            pattern = "PaqDoneInstall",
            callback = function()
                assert.truthy(pack_isinstalled("start/nvim-lspconfig"))
                assert.truthy(pack_isinstalled("opt/rust.vim"))
                assert.truthy(pack_isinstalled("start/julia"))
            end,
        })
    end)

    it("dirty", function()
        paq {
            "gpanders/nvim-parinfer",
            "neovim/nvim-lspconfig",
            { "rust-lang/rust.vim", opt = true },
            { "JuliaEditorSupport/julia-vim", as = "julia" },
        }

        paq.install()

        vim.api.nvim_create_autocmd("User", {
            once = true,
            pattern = "PaqDoneInstall",
            callback = function()
                assert.truthy(pack_isinstalled("start/nvim-lspconfig"))
                assert.truthy(pack_isinstalled("opt/rust.vim"))
                assert.truthy(pack_isinstalled("start/julia"))
                assert.truthy(pack_isinstalled("start/nvim-parinfer"))
            end,
        })
    end)
end)

describe("PaqClean", function()
    it("single", function()
        paq {
            "neovim/nvim-lspconfig",
            { "rust-lang/rust.vim", opt = true },
            { "JuliaEditorSupport/julia-vim", as = "julia" },
        }
        paq.clean()

        vim.api.nvim_create_autocmd("User", {
            once = true,
            pattern = "PaqDoneClean",
            callback = function()
                assert.truthy(pack_isinstalled("start/nvim-lspconfig"))
                assert.truthy(pack_isinstalled("opt/rust.vim"))
                assert.truthy(pack_isinstalled("start/julia"))
                assert.falsy(pack_isinstalled("start/nvim-parinfer"))
            end,
        })
    end)

    it("multiple", function()
        paq {}
        paq.clean()

        vim.api.nvim_create_autocmd("User", {
            once = true,
            pattern = "PaqDoneClean",
            callback = function()
                assert.falsy(pack_isinstalled("start/nvim-lspconfig"))
                assert.falsy(pack_isinstalled("opt/rust.vim"))
                assert.falsy(pack_isinstalled("start/julia"))
                assert.falsy(pack_isinstalled("start/nvim-parinfer"))
            end,
        })
    end)
end)
