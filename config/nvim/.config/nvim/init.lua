-- Inherit Ghostty's Vantablack palette through ANSI colors.
vim.opt.termguicolors = false

-- Your own settings, from ~/.config/omv/nvim.lua when it exists. An error in it is shown,
-- and the lines above still apply.
local personal = vim.fn.expand("~/.config/omv/nvim.lua")
if vim.fn.filereadable(personal) == 1 then
  local ok, problem = pcall(dofile, personal)
  if not ok then vim.notify("omv: " .. tostring(problem), vim.log.levels.ERROR) end
end
