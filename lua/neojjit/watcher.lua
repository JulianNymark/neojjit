-- File system watcher for auto-refresh
local M = {}
local config = require("neojjit.config")

local watcher = nil
local callback = nil
local debounce_timer = nil
local is_refreshing = false

-- Start watching a directory
function M.start(dir, cb)
  if watcher then
    if config.values.debug then
      vim.notify("[WATCHER] Already watching", vim.log.levels.DEBUG)
    end
    return true
  end

  -- Store callback
  callback = cb

  -- Watch the working directory itself for file changes
  local watch_dir = dir

  if vim.fn.isdirectory(watch_dir) == 0 then
    if config.values.debug then
      vim.notify(string.format("[WATCHER] Watch directory does not exist: %s", watch_dir), vim.log.levels.WARN)
    end
    return false
  end

  -- Create fs_event watcher
  watcher = vim.uv.new_fs_event()
  if not watcher then
    if config.values.debug then
      vim.notify("[WATCHER] Failed to create fs_event handle", vim.log.levels.ERROR)
    end
    return false
  end

  local function on_change(err, filename, events)
    if err then
      if config.values.debug then
        vim.notify(string.format("[WATCHER] Error: %s", err), vim.log.levels.ERROR)
      end
      return
    end

    if config.values.debug then
      local event_str = ""
      if events then
        if events.change then event_str = event_str .. "change " end
        if events.rename then event_str = event_str .. "rename " end
      end
      vim.notify(
        string.format("[WATCHER] Event: %s, File: %s", event_str, filename or "unknown"),
        vim.log.levels.DEBUG
      )
    end

    -- Debounce: wait 300ms before calling callback
    -- This prevents multiple rapid-fire calls when jj updates multiple files
    -- jj typically fires 6-8 events per status update (lock files, temp files, tree_state, checkout)
    if debounce_timer then
      debounce_timer:stop()
    else
      debounce_timer = vim.uv.new_timer()
    end

    debounce_timer:start(300, 0, function()
      vim.schedule(function()
        -- Prevent infinite loop: temporarily stop watching during refresh
        if callback and not is_refreshing then
          is_refreshing = true
          
          if config.values.debug then
            vim.notify("[WATCHER] Pausing during refresh", vim.log.levels.DEBUG)
          end
          
          local ok, result = pcall(callback)
          if not ok and config.values.debug then
            vim.notify(string.format("[WATCHER] Callback error: %s", result), vim.log.levels.ERROR)
          end
          
          -- Wait for jj operations to complete before re-enabling watcher
          -- This prevents the watcher from detecting its own jj status call
          vim.defer_fn(function()
            is_refreshing = false
            if config.values.debug then
              vim.notify("[WATCHER] Resumed watching", vim.log.levels.DEBUG)
            end
          end, 500)
        elseif config.values.debug and is_refreshing then
          vim.notify("[WATCHER] Skipping refresh (already in progress)", vim.log.levels.DEBUG)
        end
      end)
    end)
  end

  -- Start watching the directory
  local success, err = pcall(function()
    -- Note: recursive flag is not supported on all platforms, but doesn't hurt to set
    watcher:start(watch_dir, {}, vim.schedule_wrap(on_change))
  end)

  if not success then
    if config.values.debug then
      vim.notify(string.format("[WATCHER] Failed to start: %s", tostring(err)), vim.log.levels.WARN)
    end
    watcher:close()
    watcher = nil
    return false
  end

  if config.values.debug then
    vim.notify(string.format("[WATCHER] Started watching %s", watch_dir), vim.log.levels.DEBUG)
  end

  return true
end

-- Stop watching
function M.stop()
  -- Clean up debounce timer first
  if debounce_timer then
    if not debounce_timer:is_closing() then
      debounce_timer:stop()
      debounce_timer:close()
    end
    debounce_timer = nil
  end

  -- Clean up watcher
  if watcher then
    if not watcher:is_closing() then
      watcher:stop()
      watcher:close()
    end
    watcher = nil
  end

  callback = nil
  is_refreshing = false

  if config.values.debug then
    vim.notify("[WATCHER] Stopped", vim.log.levels.DEBUG)
  end
end

-- Check if watcher is running
function M.is_running()
  return watcher ~= nil
end

return M
