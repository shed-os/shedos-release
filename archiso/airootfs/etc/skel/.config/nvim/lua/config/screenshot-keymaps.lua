-- ═══════════════════════════════════════════════════════════
--              SCREENSHOT KEYBINDINGS OVERRIDE
-- ═══════════════════════════════════════════════════════════
--
-- This file explicitly overrides LazyVim's default keybindings
-- to ensure screenshot keybindings work correctly
--
-- ═══════════════════════════════════════════════════════════

-- Delete any conflicting keybindings from LazyVim (ignore errors if they don't exist)
pcall(vim.keymap.del, "n", "<leader>sC")
pcall(vim.keymap.del, "n", "<leader>sc")

-- Helper function to call silicon CLI directly
local function take_screenshot(range_start, range_end)
  -- Ensure screenshots directory exists
  local dir = os.getenv("HOME") .. "/Pictures/Screenshots"
  vim.fn.mkdir(dir, "p")

  -- Generate output path with timestamp
  local timestamp = os.date("!%Y%m%d_%H%M%S")
  local output = string.format("%s/code_screenshot_%s.png", dir, timestamp)

  -- Check if silicon is available
  if vim.fn.executable("silicon") == 0 then
    vim.notify("Silicon not installed! Install with: cargo install silicon", vim.log.levels.WARN)
    return
  end

  -- Get current buffer content
  local lines
  if range_start and range_end then
    lines = vim.api.nvim_buf_get_lines(0, range_start - 1, range_end, false)
  else
    lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  end

  -- Get file type for syntax highlighting
  local filetype = vim.bo.filetype

  -- Write content to temp file
  local temp_file = vim.fn.tempname()
  vim.fn.writefile(lines, temp_file)

  -- Build silicon command (using only supported flags)
  local cmd = string.format(
    "silicon --output %s --language %s --font 'JetBrainsMono Nerd Font=34' --theme 'Dracula' --shadow-blur-radius 16 --shadow-offset-x 8 --shadow-offset-y 8 --pad-horiz 80 --pad-vert 100 %s",
    vim.fn.shellescape(output),
    vim.fn.shellescape(filetype ~= "" and filetype or "txt"),
    vim.fn.shellescape(temp_file)
  )

  -- Execute silicon
  local result = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error

  -- Clean up temp file
  vim.fn.delete(temp_file)

  if exit_code == 0 then
    vim.notify("Screenshot saved to: " .. output, vim.log.levels.INFO)

    -- Optionally open the screenshot
    if vim.fn.executable("xdg-open") == 1 then
      vim.fn.jobstart({"xdg-open", output}, {detach = true})
    end
  else
    vim.notify("Failed to create screenshot: " .. result, vim.log.levels.ERROR)
  end
end

-- Set our screenshot keybindings with explicit priority
vim.keymap.set("n", "<leader>sC", function()
  take_screenshot()
end, { desc = "Screenshot: Capture File", silent = true })

vim.keymap.set("v", "<leader>sc", function()
  -- Get visual selection range
  local start_line = vim.fn.line("v")
  local end_line = vim.fn.line(".")

  -- Ensure start is before end
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  take_screenshot(start_line, end_line)
end, { desc = "Screenshot: Capture Selection", silent = true })

vim.keymap.set("v", "<leader>sb", function()
  -- Check if silicon is available
  if vim.fn.executable("silicon") == 0 then
    vim.notify("Silicon not installed! Install with: cargo install silicon", vim.log.levels.WARN)
    return
  end

  -- Check if xclip is available (needed for clipboard)
  if vim.fn.executable("xclip") == 0 then
    vim.notify("xclip not installed! Install with: sudo pacman -S xclip", vim.log.levels.WARN)
    return
  end

  -- Get visual selection range
  local start_line = vim.fn.line("v")
  local end_line = vim.fn.line(".")

  -- Ensure start is before end
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  -- Get selected lines
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

  -- Get file type for syntax highlighting
  local filetype = vim.bo.filetype

  -- Write content to temp file
  local temp_file = vim.fn.tempname()
  vim.fn.writefile(lines, temp_file)

  -- Build silicon command with output to clipboard (using only supported flags)
  local cmd = string.format(
    "silicon --to-clipboard --language %s --font 'JetBrainsMono Nerd Font=34' --theme 'Dracula' --shadow-blur-radius 16 --shadow-offset-x 8 --shadow-offset-y 8 --pad-horiz 80 --pad-vert 100 %s",
    vim.fn.shellescape(filetype ~= "" and filetype or "txt"),
    vim.fn.shellescape(temp_file)
  )

  -- Execute silicon
  local result = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error

  -- Clean up temp file
  vim.fn.delete(temp_file)

  if exit_code == 0 then
    vim.notify("Screenshot copied to clipboard", vim.log.levels.INFO)
  else
    vim.notify("Failed to copy screenshot: " .. result, vim.log.levels.ERROR)
  end
end, { desc = "Screenshot: Copy to Clipboard", silent = true })

return {}
