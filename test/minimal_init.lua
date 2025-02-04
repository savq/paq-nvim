vim.cmd([[set runtimepath+=.]])

vim.o.swapfile = false
vim.bo.swapfile = false

vim.api.nvim_create_user_command("RunTests", function(opts)
    local path = opts.fargs[1] or "tests"
    require("plenary.test_harness").test_directory(
        path,
        { minimal_init = "./test/minimal_init.lua" }
    )
end, { nargs = "?" })
