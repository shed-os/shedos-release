-- ═══════════════════════════════════════════════════════════
--                   GLOBAL ERROR HANDLER
-- ═══════════════════════════════════════════════════════════
--
-- Suppress non-critical transient errors that don't affect functionality
-- These errors are typically race conditions in plugins during window/buffer operations
--
-- ═══════════════════════════════════════════════════════════

-- Patterns of errors to suppress (these don't affect functionality)
local suppressed_patterns = {
  "Invalid window id", -- nvim-bqf, nvim-ufo, Trouble.nvim race conditions
  "handle .* is already closing", -- auto-save timer cleanup
  "Expected Lua number", -- Trouble.nvim promise rejection
  "BufLeave Autocommands for", -- auto-save during rapid buffer changes
  "Scheme is missing", -- LSP initialization with invalid URI (transient)
  "RPC%[Error%].*InternalError", -- LSP internal errors during initialization
}

-- Store original notify function
local original_notify = vim.notify

-- Override vim.notify to filter out suppressed errors
vim.notify = function(msg, level, opts)
  -- Convert message to string if it isn't already
  local message = tostring(msg)

  -- Check if message matches any suppressed pattern
  for _, pattern in ipairs(suppressed_patterns) do
    if message:match(pattern) then
      -- Silently ignore this error
      return
    end
  end

  -- Call original notify for non-suppressed messages
  return original_notify(message, level, opts)
end

-- Also hook into vim.schedule error handling for async errors
local original_schedule = vim.schedule
vim.schedule = function(fn)
  return original_schedule(function()
    local ok, err = pcall(fn)
    if not ok then
      local error_msg = tostring(err)
      local should_suppress = false

      -- Check if error matches suppressed patterns
      for _, pattern in ipairs(suppressed_patterns) do
        if error_msg:match(pattern) then
          should_suppress = true
          break
        end
      end

      -- Only report non-suppressed errors
      if not should_suppress then
        vim.notify("Error in scheduled function: " .. error_msg, vim.log.levels.ERROR)
      end
    end
  end)
end

return {}
