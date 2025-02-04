local ts_utils = require('nvim-treesitter.ts_utils')
local config = require('orgmode.config')
local M = {}

-- walks the tree to find a headline
function M.find_headline(node)
  if node:type() == 'headline' then
    return node
  elseif node:type() == 'section' then
    -- The headline is always the first child of a section
    return ts_utils.get_named_children(node)[1]
  elseif node:parent() then
    return M.find_headline(node:parent())
  else
    return nil
  end
end

-- returns the nearest headline
function M.closest_headline()
  vim.treesitter.get_parser(0, 'org'):parse()
  return M.find_headline(ts_utils.get_node_at_cursor(vim.api.nvim_get_current_win()))
end

-- @param front_trim boolean
function M.set_node_text(node, text, front_trim)
  local sr, sc, er, ec = node:range()
  if string.len(text) == 0 then
    if front_trim then
      sc = sc - 1
    else
      ec = ec + 1
    end
  end
  vim.api.nvim_buf_set_text(0, sr, sc, er, ec, { text })
end

return M
