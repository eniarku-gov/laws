--[[
list-detect.lua: inside each section (everything after a Markdown header), turn
"(a) ... (b) ..." style runs into properly marked, nested items, ignoring
Markdown's indentation rules.

    ## Sec. 1.006 --- Title
    (1) Subsection text, which is left alone as a normal paragraph:
        (a) first item
        (b) second item
            (i) nested item

- A paragraph that BEGINS with a number marker such as "(1)" or "(2)" is a
  subsection: it is output as a normal, unindented paragraph, never as a list
  (Pandoc itself parses these as an ordered list, so the filter flattens it).
  Items inside it, "(a)", "(i)", ..., become "(a) text" paragraphs wrapped in a
  div carrying level classes (see below).
- Content before the first header is ignored. Divs inside a section are processed;
  opt out of one with  ::: {lists="false"}
- Fenced code blocks that declare a language are left alone.

Two output modes (set in the YAML header):

    list-detect:
      mode: paragraphs   # default: each item is a paragraph starting "(a) text",
                         #   with a single space after the marker
                         # "lists": real <ol> lists (markers sit outside the text)

No indentation is applied by this filter; style it in CSS. In paragraphs mode each
item paragraph is wrapped in
    <div class="list-item list-level-N"> <p>(a) text</p> </div>
where N is the nesting depth: "(a)" items are 1, "(i)" items are 2, and so on.
Subsection paragraphs, "(1)" etc., are depth 0 and stay plain, unwrapped paragraphs.
    .list-item { }                  /* every item (and its continuation blocks) */
    .list-level-1 { }  .list-level-2 { }  ...
In "lists" mode the output is ordinary nested <ol> elements: style them with
selectors such as "ol", "ol ol".

Markers are kept exactly as written ("(a)", "(i)", "1)", ...). Nesting is
inferred from the marker style, e.g. (a) -> (1) -> (A) -> (i).
]]

local stringify = pandoc.utils.stringify

local config = { mode = "paragraphs" }

local function from_roman(s)
  local vals = { i = 1, v = 5, x = 10, l = 50, c = 100, d = 500, m = 1000 }
  local total, prev = 0, 0
  for ch in s:lower():reverse():gmatch(".") do
    local v = vals[ch]
    if v < prev then total = total - v else total = total + v; prev = v end
  end
  return total
end

-- Work out the list style and numeric value of a marker. Single letters such as
-- "i" or "v" are ambiguous (alpha vs. roman), so the open lists are used as context.
local function classify(val, delim, stack)
  if val:match("^%d+$") then return "Decimal", tonumber(val) end
  local lower = val:match("^%l+$") ~= nil
  local upper = val:match("^%u+$") ~= nil
  if not (lower or upper) then return nil end
  local alpha_style = lower and "LowerAlpha" or "UpperAlpha"
  local roman_style = lower and "LowerRoman" or "UpperRoman"
  local is_roman = val:lower():match("^[ivxlcdm]+$") ~= nil
  if #val > 1 then
    if is_roman then return roman_style, from_roman(val) end
    return nil
  end
  local alpha_n = val:byte() - (lower and 96 or 64)
  if not is_roman then return alpha_style, alpha_n end
  local roman_n = from_roman(val)
  for _, lvl in ipairs(stack) do
    if lvl.delim == delim and lvl.style == alpha_style and lvl.last + 1 == alpha_n then
      return alpha_style, alpha_n
    end
  end
  for _, lvl in ipairs(stack) do
    if lvl.delim == delim and lvl.style == roman_style and lvl.last + 1 == roman_n then
      return roman_style, roman_n
    end
  end
  if val:lower() == "i" then return roman_style, 1 end
  return alpha_style, alpha_n
end

-- "(a)" / "a)" / "a." -> value, delimiter  (nil if not a marker)
local function parse_marker(tok)
  local val, delim = tok:match("^%((%w+)%)$"), "TwoParens"
  if not val then val, delim = tok:match("^(%w+)%)$"), "OneParen" end
  if not val then
    val, delim = tok:match("^(%w+)%.$"), "Period"
    if val and not (val:match("^%d+$") or #val == 1) then val = nil end
  end
  if not val or #val > 6 or not classify(val, delim, {}) then return nil end
  return val, delim
end

-- Only treat a run of markers as a list if it starts at 1 / a / A / i / I
local function starts_list(val, delim)
  local _, n = classify(val, delim, {})
  return n == 1
end

-- Wrap a block in a div with level classes for CSS (depth 0 = unchanged).
-- No indentation is applied here.
local function at_level(block, depth)
  if depth < 1 then return block end
  return pandoc.Div({ block }, pandoc.Attr("", { "list-item", "list-level-" .. depth }))
end

-- items: array of {token=, val=, delim=, inlines=}  ->  Blocks
local function build_blocks(items, base)
  base = base or 0
  local stack = {}
  local out = pandoc.Blocks({})

  -- lists mode only: close the innermost list and attach it to its parent item
  local function close_top()
    local lvl = table.remove(stack)
    local ol = pandoc.OrderedList(lvl.items,
      pandoc.ListAttributes(lvl.start, lvl.style, lvl.delim))
    local parent = stack[#stack]
    if parent then
      parent.items[#parent.items]:insert(ol)
    else
      out:insert(ol)
    end
  end

  for _, it in ipairs(items) do
    local style, n = classify(it.val, it.delim, stack)
    local idx
    for i, lvl in ipairs(stack) do
      if lvl.style == style and lvl.delim == it.delim then idx = i end
    end
    if idx then
      while #stack > idx do
        if config.mode == "lists" then close_top() else table.remove(stack) end
      end
    else
      stack[#stack + 1] = { style = style, delim = it.delim, start = n, items = {}, last = 0 }
    end
    local lvl = stack[#stack]
    lvl.last = n

    if config.mode == "lists" then
      lvl.items[#lvl.items + 1] = pandoc.List({ pandoc.Plain(it.inlines) })
    else
      local ins = pandoc.Inlines({ pandoc.Str(it.token), pandoc.Space() })
      ins:extend(it.inlines)
      local para = pandoc.Para(ins)
      out:insert(at_level(para, base + #stack))
    end
  end
  if config.mode == "lists" then
    while #stack > 0 do close_top() end
  end
  return out
end

-- Paragraph with soft-broken "(a) ..." lines -> intro paragraph + items
-- base: nesting depth the paragraph sits at; skip_first: ignore a marker at the very start
local function split_para(para, base, skip_first)
  local inl = para.content
  local intro = pandoc.Inlines({})
  local items = {}
  local cur = intro
  local i = 1
  while i <= #inl do
    local el = inl[i]
    local nxt = inl[i + 1]
    local val, delim, token
    local skip = 0
    if i == 1 and el.t == "Str" and not skip_first then
      token = el.text
      val, delim = parse_marker(token)
      -- a paragraph that starts with a number, "(1)", is a subsection, not a list
      if val and classify(val, delim, {}) == "Decimal" then val = nil end
      skip = 1
    elseif (el.t == "SoftBreak" or el.t == "LineBreak") and nxt and nxt.t == "Str" then
      token = nxt.text
      val, delim = parse_marker(token)
      skip = 2
    end
    if val and (#items > 0 or starts_list(val, delim)) then
      cur = pandoc.Inlines({})
      items[#items + 1] = { token = token, val = val, delim = delim, inlines = cur }
      i = i + skip
      if inl[i] and inl[i].t == "Space" then i = i + 1 end
    else
      cur:insert(el)
      i = i + 1
    end
  end
  if #items == 0 then return nil end
  local out = pandoc.Blocks({})
  if #intro > 0 then out:insert(pandoc.Para(intro)) end
  out:extend(build_blocks(items, base))
  return out
end

local function read_inlines(text)
  local b = pandoc.read(text, "markdown").blocks[1]
  if b and b.content and (b.t == "Para" or b.t == "Plain") then return b.content end
  return pandoc.Inlines({ pandoc.Str(text) })
end

-- Code block (4-space indented list) -> intro paragraph + items
local function split_code(cb, base)
  local intro_lines, items = {}, {}
  for line in (cb.text .. "\n"):gmatch("(.-)\n") do
    local tok, rest = line:match("^%s*(%S+)%s*(.*)$")
    if tok then
      local val, delim = parse_marker(tok)
      if val and (#items > 0 or starts_list(val, delim)) then
        items[#items + 1] = { token = tok, val = val, delim = delim, text = rest }
      elseif #items > 0 then
        items[#items].text = items[#items].text .. " " .. line:match("^%s*(.-)%s*$")
      else
        intro_lines[#intro_lines + 1] = line:match("^%s*(.-)%s*$")
      end
    end
  end
  if #items == 0 then return nil end
  local out = pandoc.Blocks({})
  if #intro_lines > 0 then
    out:insert(pandoc.Para(read_inlines(table.concat(intro_lines, " "))))
  end
  for _, it in ipairs(items) do it.inlines = read_inlines(it.text) end
  out:extend(build_blocks(items, base))
  return out
end

-- ---------------------------------------------------------------------------
-- Lists that Pandoc already parsed (e.g. paragraphs starting "(1)", with nested
-- "(a)" lines indented underneath). The outermost "(1)" list is just a series of
-- subsection paragraphs, so it is flattened to plain paragraphs; deeper levels
-- become "(a) text" paragraphs in level divs (or stay real lists in "lists" mode).
-- ---------------------------------------------------------------------------

local function to_roman(n)
  local map = { {1000,"M"},{900,"CM"},{500,"D"},{400,"CD"},{100,"C"},{90,"XC"},
                {50,"L"},{40,"XL"},{10,"X"},{9,"IX"},{5,"V"},{4,"IV"},{1,"I"} }
  local out = ""
  for _, p in ipairs(map) do
    while n >= p[1] do out = out .. p[2]; n = n - p[1] end
  end
  return out
end

local function format_marker(style, n, delim)
  local v
  if style == "LowerAlpha" then v = string.char(96 + n)
  elseif style == "UpperAlpha" then v = string.char(64 + n)
  elseif style == "LowerRoman" then v = to_roman(n):lower()
  elseif style == "UpperRoman" then v = to_roman(n)
  else v = tostring(n) end
  if delim == "TwoParens" then return "(" .. v .. ")" end
  if delim == "OneParen" then return v .. ")" end
  return v .. "."
end

local function list_attrs(ol)
  local la = ol.listAttributes
  return (ol.start or la.start), (ol.style or la.style), (ol.delimiter or la.delimiter)
end

local flatten_ol

local function flatten_item_blocks(item, from, depth, out)
  for j = from, #item do
    local b = item[j]
    if b.t == "OrderedList" and select(3, list_attrs(b)) == "TwoParens" then
      if config.mode == "lists" then out:insert(b) else out:extend(flatten_ol(b, depth + 1)) end
    elseif b.t == "CodeBlock" and #b.classes == 0 then
      local repl = split_code(b, depth)
      if repl then out:extend(repl) else out:insert(at_level(b, depth)) end
    else
      out:insert(at_level(b, depth))
    end
  end
end

flatten_ol = function(ol, depth)
  local out = pandoc.Blocks({})
  local start, style, delim = list_attrs(ol)
  for i, item in ipairs(ol.content) do
    local token = format_marker(style, start + i - 1, delim)
    local first = item[1]
    local ins = pandoc.Inlines({ pandoc.Str(token) })
    local from = 1
    if first and (first.t == "Plain" or first.t == "Para") then
      ins:insert(pandoc.Space())
      ins:extend(first.content)
      from = 2
    end
    local lead = pandoc.Para(ins)
    -- unindented "(a)" lines inside the item's paragraph
    local repl = split_para(lead, depth, true)
    if repl then
      out:insert(at_level(repl[1], depth))
      for k = 2, #repl do out:insert(repl[k]) end
    else
      out:insert(at_level(lead, depth))
    end
    flatten_item_blocks(item, from, depth, out)
  end
  return out
end

-- Convert blocks in place; recurse into divs. Headers switch conversion on.
local function process(blocks, in_section)
  local out = pandoc.Blocks({})
  for _, b in ipairs(blocks) do
    if b.t == "Header" then
      in_section = true
      out:insert(b)
    elseif not in_section then
      out:insert(b)
    elseif b.t == "Div" then
      if b.attributes["lists"] ~= "false" then
        b.content = process(b.content, true)
      end
      out:insert(b)
    elseif b.t == "OrderedList" and select(3, list_attrs(b)) == "TwoParens" then
      -- an outermost "(1), (2), ..." list is a run of subsection paragraphs (depth 0);
      -- any other outermost "(a)"-style list is one indent in
      local _, style = list_attrs(b)
      out:extend(flatten_ol(b, style == "Decimal" and 0 or 1))
    else
      local repl
      if b.t == "Para" then repl = split_para(b)
      elseif b.t == "CodeBlock" and #b.classes == 0 then repl = split_code(b) end
      if repl then out:extend(repl) else out:insert(b) end
    end
  end
  return out
end

local function Pandoc(doc)
  local cfg = doc.meta["list-detect"]
  if type(cfg) == "table" then
    if cfg.mode then config.mode = stringify(cfg.mode) end
  end
  doc.blocks = process(doc.blocks, false)
  return doc
end

return { { Pandoc = Pandoc } }