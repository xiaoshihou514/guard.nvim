local api = vim.api
local spawn = require('guard.spawn').spawn
local filetype = require('guard.filetype')

local function ignored(buf, patterns)
  local fname = api.nvim_buf_get_name(buf)
  if #fname == 0 then
    return false
  end

  for _, pattern in pairs(patterns) do
    if fname:find(pattern) then
      return true
    end
  end
  return false
end

local function update_buffer(bufnr, new_lines)
  if #new_lines == 0 or not api.nvim_buf_is_valid(bufnr) then
    return
  end

  local prev_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
  new_lines = vim.split(new_lines, '\n')
  if new_lines[#new_lines] == 0 then
    new_lines[#new_lines] = nil
  end
  local diffs = vim.diff(table.concat(new_lines, '\n'), table.concat(prev_lines, '\n'), {
    algorithm = 'minimal',
    ctxlen = 0,
    result_type = 'indices',
  })

  -- Apply diffs in reverse order.
  for i = #diffs, 1, -1 do
    local new_start, new_count, prev_start, prev_count = unpack(diffs[i])
    local replacement = {}
    for j = new_start, new_start + new_count - 1, 1 do
      replacement[#replacement + 1] = new_lines[j]
    end
    local s, e
    if prev_count == 0 then
      s = prev_start
      e = s
    else
      s = prev_start - 1
      e = s + prev_count
    end
    api.nvim_buf_set_lines(bufnr, s, e, false, replacement)
  end
  api.nvim_command('noautocmd write!')
end

local function get_prev_lines(bufnr)
  local tbl = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local res = {}
  for _, text in ipairs(tbl) do
    res[#res + 1] = text .. '\n'
  end
  return res
end

local function do_fmt(buf)
  buf = buf or api.nvim_get_current_buf()
  if not filetype[vim.bo[buf].filetype] then
    vim.notify('[Guard] missing config for filetype ' .. vim.bo[buf].filetype, vim.log.levels.ERROR)
    return
  end
  local fmt_configs = filetype[vim.bo[buf].filetype].format
  local formatter = require('guard.tools.formatter')
  fmt_configs = vim.tbl_map(function(item)
    if type('item') == 'string' and formatter[item] then
      return vim.deepcopy(formatter[item])
    else
      return item
    end
  end, fmt_configs)

  -- local fname = vim.fn.fnameescape(api.nvim_buf_get_name(buf))
  local prev_lines = get_prev_lines(buf)

  coroutine.resume(coroutine.create(function()
    local new_lines
    for _, config in ipairs(fmt_configs) do
      config = vim.deepcopy(config)
      local can_run = true
      if config.ignore_patterns and ignored(buf, configs.ignore_patterns) then
        can_run = false
      end
      if config.ignore_error and #vim.diagnostic.get(buf, { severity = 1 }) ~= 0 then
        if can_run then
          can_run = false
        end
      end

      if can_run then
        config.lines = new_lines and new_lines or prev_lines
        new_lines = spawn(config)
      end
    end

    vim.schedule(function()
      update_buffer(buf, new_lines)
    end)
  end))
end

return {
  do_fmt = do_fmt,
}