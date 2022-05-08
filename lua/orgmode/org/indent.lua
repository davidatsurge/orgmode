local config = require('orgmode.config')
local Files = require('orgmode.parser.files')
local ts_utils = require('nvim-treesitter.ts_utils')
local query = nil

local prev_section = nil
local function foldexpr()
  local line = vim.fn.getline(vim.v.lnum)

  local stars = line:match('^(%*+)%s+')

  if stars then
    local file = Files.get(vim.fn.expand('%:p'))
    if not file then
      return 0
    end
    local section = file.sections_by_line[vim.v.lnum]
    prev_section = section
    if not section.parent and section.level > 1 and not section:has_children() then
      return 0
    end
    return '>' .. section.level
  end

  if line:match('^%s*:END:%s*$') then
    return 's1'
  end

  if line:match('^%s*:[^:]*:%s*$') then
    return 'a1'
  end

  if vim.fn.getline(vim.v.lnum + 1):match('^(%*+)%s+') and prev_section then
    local file = Files.get(vim.fn.expand('%:p'))
    if not file then
      return 0
    end
    local section = file.sections_by_line[vim.v.lnum + 1]
    if section.level <= prev_section.level then
      return '<' .. prev_section.level
    end
  end

  return '='
end

local function noindent_mode()
  local prev_line = vim.fn.prevnonblank(vim.v.lnum - 1)
  if prev_line <= 0 then
    return 0
  end
  local line = vim.fn.getline(prev_line)

  local list_item = line:match('^(%s*[%+%-]%s+)')
  if list_item then
    return list_item:len()
  end

  return 0
end

local function get_is_list_item(line)
  local line_numbered_list_item = line:match('^%s*(%d+[%)%.]%s+)')
  local line_unordered_list_item = line:match('^%s*([%+%-]%s+)')
  return line_numbered_list_item or line_unordered_list_item
end

local get_indent_matches = ts_utils.memoize_by_buf_tick(function(bufnr)
  local tree = vim.treesitter.get_parser(bufnr, 'org'):parse()
  if not tree or not #tree then
    return {}
  end
  local matches = {}
  local root = tree[1]:root()
  local parent_item_cache = {}
  for _, match, _ in query:iter_matches(root, bufnr, 0, -1) do
    for id, node in pairs(match) do
      local range = ts_utils.node_to_lsp_range(node)
      local type = node:type()

      local opts = {
        type = type,
        line_nr = range.start.line + 1,
        name = query.captures[id],
        indent = vim.fn.indent(range.start.line + 1),
      }

      if type == 'headline' then
        opts.stars = vim.treesitter.query.get_node_text(node:field('stars')[1], bufnr):len()
        opts.indent = opts.indent + opts.stars + 1
        matches[range.start.line + 1] = opts
      end

      if type == 'listitem' then
        local text = vim.treesitter.query.get_node_text(node, bufnr)
        local parent_line = node:parent():start()
        local first_list_item = node:parent():named_child(0)
        local first_list_item_linenr = first_list_item:start()
        local first_list_item_text = vim.treesitter.query.get_node_text(first_list_item, bufnr)
        local first_item_indent = first_list_item_text:match(vim.pesc(vim.treesitter.query.get_node_text(first_list_item:field('bullet')[1], bufnr))..'%s+')
        local first_line_indent = vim.fn.indent(first_list_item_linenr + 1)
        opts.text = text

        opts.parent = {
          text = first_list_item_text,
          line_nr = parent_line,
          line_nr_item = first_list_item_linenr,
          real_indent = first_line_indent,
          first_item_indent = first_item_indent,
          indent = first_line_indent + (first_item_indent and first_item_indent:len() or 0)
        }

        local bullet = vim.treesitter.query.get_node_text(node:field('bullet')[1], bufnr)
        local indent = text:match(vim.pesc(bullet)..'%s+')
        opts.indent = opts.indent + (indent and indent:len() or 0)
        for i = range.start.line, range['end'].line do
          matches[i + 1] = opts
        end
      end

    end
  end

  return matches
end)

local function indentexpr_ts()
  if config.org_indent_mode == 'noindent' then
    return noindent_mode()
  end

  if not query then
    query = vim.treesitter.get_query('org', 'org_indent')
  end

  print('CHANGEDTICK', vim.api.nvim_buf_get_var(0, 'changedtick'))
  local prev_linenr = vim.fn.prevnonblank(vim.v.lnum - 1)

  local match = matches[vim.v.lnum]
  print('indentexpr > match', vim.inspect(match))
  local prev_line_match = matches[prev_linenr]
  print('indentexpr > prev_line_match', vim.inspect(prev_line_match))

  if not match and not prev_line_match then
    return -1
  end

  match = match or {}
  prev_line_match = prev_line_match or {}

  if match.type == 'headline' then
    return 0
  end

  if prev_line_match.type == 'headline' then
    return prev_line_match.indent
  end

  if prev_line_match.type == 'listitem' then
    if match.type ~= 'listitem' then
      return prev_line_match.indent
    end
    if match.parent.line_nr == prev_line_match.parent.line_nr then
      -- Multiline list item
      if match.line_nr == prev_line_match.line_nr then
        return prev_line_match.indent
      end

      return prev_line_match.parent.indent
    end
    return prev_line_match.parent.indent
  end

  return -1
end


local item_cache = {}

local function indentexpr()
  if config.org_indent_mode == 'noindent' then
    return noindent_mode()
  end

  if not query then
    query = vim.treesitter.get_query('org', 'org_indent')
  end

  local cur_line = vim.trim(vim.fn.getline(vim.v.lnum))
  local matches = get_indent_matches(0)

  -- Ignore comments and block markers (ex. #+begin_src)
  if cur_line:match('^%s*#%s+') or cur_line:match('^%s*#%+%S+') then
    return -1
  end

  -- Current line is headline, do not indent
  if cur_line:match('^%*+%s+') then
    return 0
  end

  local prev_linenr = vim.fn.prevnonblank(vim.v.lnum - 1)
  -- No previous line to compare with, default to 0
  if prev_linenr <= 0 then
    return 0
  end

  local prev_line = vim.fn.getline(prev_linenr)

  -- Do not indent after directives
  if prev_line:find('^%s*#%+%S+:') then
    return 0
  end

  local prev_line_headline = prev_line:match('^(%*+)%s+')
  local cur_line_list_item = get_is_list_item(cur_line)
  local prev_line_match = matches[prev_linenr] or {}
  print('indentexpr > prev_line_match', vim.inspect(prev_line_match))

  local indent_amount = vim.fn.indent(prev_linenr)

  if prev_line_headline then
    indent_amount = prev_line_headline:len() + 1
  end

  if prev_line_match.type == 'listitem' then
    indent_amount = prev_line_match.indent
  end

  if not cur_line_list_item then
    return indent_amount
  end

  local next_line = vim.fn.getline(vim.v.lnum + 1)
  local next_line_list_item = get_is_list_item(next_line)

  if next_line_list_item then
    item_cache[vim.v.lnum + 1] = vim.fn.indent(vim.v.lnum + 1) - vim.fn.indent(vim.v.lnum)
  end

  if prev_line_match.type ~= 'listitem' then
    return indent_amount
  end

  local diff = item_cache[vim.v.lnum] or 0
  item_cache[vim.v.lnum] = nil
  return vim.fn.indent(prev_linenr) + diff
end

local function foldtext()
  local line = vim.fn.getline(vim.v.foldstart)

  if config.org_hide_leading_stars then
    line = vim.fn.substitute(line, '\\(^\\*\\+\\)', '\\=repeat(" ", len(submatch(0))-1) . "*"', '')
  end

  if vim.opt.conceallevel:get() > 0 and string.find(line, '[[', 1, true) then
    line = string.gsub(line, '%[%[(.-)%]%[?(.-)%]?%]', function(link, text)
      if text == '' then
        return link
      else
        return text
      end
    end)
  end

  return line .. config.org_ellipsis
end

return {
  foldexpr = foldexpr,
  indentexpr = indentexpr,
  foldtext = foldtext,
}
