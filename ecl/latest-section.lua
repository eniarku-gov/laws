-- latest-section.lua
--
-- Keeps only the most recent version of each "Sec. N.NNN" section (by the
-- `date` attribute), sorts sections by number, inserts one chapter heading per
-- run of sections sharing a `chapter` attribute), and appends a
-- "History: ..." line to every surviving section, e.g.
--   History: Add. 2026 AS 1 (eff. Jan 1, 2026);—Am. 2026 AS 17 (imd. eff. Nov 23, 2026).
--
-- Expects the output of generate.R: literal date="YYYY-MM-DD" (the effective date,
-- or the assent date when effect is immediate), cr="26CR2", enacted-as="2026 AS 17",
-- imd="true" (immediate effect) and, on repealed sections, status="repealed".
-- Document metadata `instrument-slug` is used to build chapter IDs.
-- Chapters are NOT derived from the section number (its first part is the Title).

local ISO = "^%d%d%d%d%-%d%d%-%d%d$"
local SEP = " ;— "   -- between History entries
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

-- "2026-10-10" -> "Oct 10, 2026"
local function fmt_date(iso)
  local y, m, d = iso:match("^(%d+)%-(%d+)%-(%d+)$")
  return MONTHS[tonumber(m)] .. " " .. tonumber(d) .. ", " .. y
end

local function warn(msg)
  io.stderr:write("WARNING [latest-section]: " .. msg .. "\n")
end

-- Resolves "{{< meta a.b >}}" for source CRs rendered standalone.
local function resolve(val, meta)
  local key = val:match("^{{<%s*meta%s+([%w%.%-_]+)%s*>}}$")
  if key then
    local node = meta
    for part in key:gmatch("[^.]+") do
      if node == nil then return val end
      node = node[part]
    end
    if node ~= nil then return pandoc.utils.stringify(node) end
  end
  return val
end

-- "Sec. 1.002 --- Title" -> "1.002", {1, 2}
local function parse_num(text)
  local num = text:match("^%s*Sec%.?%s+([%d%.]+)")
  if not num then return nil end
  num = (num:gsub("%.$", ""))
  local parts = {}
  for p in num:gmatch("%d+") do parts[#parts + 1] = tonumber(p) end
  return num, parts
end

local function less(a, b)
  local n = math.max(#a.parts, #b.parts)
  for k = 1, n do
    local x, y = a.parts[k] or 0, b.parts[k] or 0
    if x ~= y then return x < y end
  end
  return a.order < b.order  -- stable tie-break
end

local function chapter_header(text, first_num, meta)
  local blocks = pandoc.read("# " .. text, "markdown").blocks
  local h = blocks[1]
  if not h or h.t ~= "Header" then
    h = pandoc.Header(1, { pandoc.Str(text) })
  end
  h.classes:insert("code-chapter")   -- styling hook
  local slug = meta["instrument-slug"]
  if slug then
    h.identifier = "ch-" .. pandoc.utils.stringify(slug) .. "-" ..
      (first_num:gsub("%.", "-"))
  end
  return h
end

function Pandoc(doc)
  local blocks = doc.blocks
  local items = {}          -- loose blocks and sections, in document order
  local best = {}           -- key -> index into `items` of the winning version
  local history = {}        -- key -> list of {date, cr}

  local i = 1
  while i <= #blocks do
    local b = blocks[i]
    local num, parts
    if b.t == "Header" then
      num, parts = parse_num(pandoc.utils.stringify(b.content))
    end

    if num then
      -- A section runs until the next header of the same or higher level
      local j = i + 1
      while j <= #blocks
        and not (blocks[j].t == "Header" and blocks[j].level <= b.level) do
        j = j + 1
      end

      local section = {}
      for k = i, j - 1 do section[#section + 1] = blocks[k] end

      -- Date: resolve, validate; anything unusable is treated as "oldest"
      local date = b.attributes["date"]
      date = date and resolve(date, doc.meta) or ""
      if date == "" then
        warn("Sec. " .. num .. " has no date; treating as oldest")
      elseif not date:match(ISO) then
        warn("Sec. " .. num .. " has bad date '" .. date .. "'; treating as oldest")
        date = ""
      end

      local cr = b.attributes["cr"]
      local key = b.level .. ":" .. num
      history[key] = history[key] or {}
      table.insert(history[key], {
        date = date, cr = cr, n = #history[key] + 1,
        enacted = b.attributes["enacted-as"],
        imd = (b.attributes["imd"] == "true"),
        href = b.attributes["cr-href"],
        status = b.attributes["status"],
      })

      local idx = #items + 1
      items[idx] = {
        section = section, key = key, date = date, cr = cr,
        parts = parts, order = idx, num = num,
      }

      local cur = best[key]
      if cur ~= nil and items[cur].date == date and items[cur].cr ~= cr then
        warn("Sec. " .. num .. ": versions from " .. tostring(items[cur].cr) ..
             " and " .. tostring(cr) .. " share date '" .. date ..
             "'; the later one wins")
      end
      -- ISO dates compare as strings; ties go to the later one
      if cur == nil or date >= items[cur].date then best[key] = idx end

      i = j
    else
      items[#items + 1] = { block = b }
      i = i + 1
    end
  end

  -- Keep winners (repeal stubs are ordinary winners), annotate them
  local kept = {}
  for idx, item in ipairs(items) do
    if item.block then
      kept[#kept + 1] = item
    elseif best[item.key] == idx then
      local h = item.section[1]
      item.chapter = h.attributes["chapter"]   -- the winning version's chapter
      h.attributes["chapter"] = nil
      h.classes:insert("code-section")   -- styling hook
      h.attributes["enacted-as"] = nil
      h.attributes["imd"] = nil
      h.attributes["cr-href"] = nil

      local hist = history[item.key]
      table.sort(hist, function(x, y)
        if x.date ~= y.date then return x.date < y.date end
        return x.n < y.n
      end)
      local entries = {}
      local prev_repealed = true   -- the first version is an addition
      for _, v in ipairs(hist) do
        local label, class
        if v.status == "repealed" then
          label, class = "Rep.", "history-rep"; prev_repealed = true
        elseif prev_repealed then
          label, class = "Add.", "history-add"; prev_repealed = false
        else
          label, class = "Am.", "history-am"
        end
        local who = v.enacted or v.cr
        if who then
          local when = ""
          if v.date ~= "" then
            when = " (" .. (v.imd and "imd. eff. " or "eff. ") .. fmt_date(v.date) .. ")"
          end
          entries[#entries + 1] = {
            label = label .. " ", who = who, when = when, href = v.href, class = class,
          }
        end
      end
      if #entries > 0 then
        -- <div class="history"><p><span class="history-label"><strong>History:</strong></span>
        --   <span class="history-entry history-add">Add. ...</span>;—<span class="history-entry history-am">Am. ...</span>.</p></div>
        local inl = pandoc.List {
          pandoc.Span({ pandoc.Strong { pandoc.Str("History:") } },
                      pandoc.Attr("", { "history-label" })),
          pandoc.Space(),
        }
        for n, e in ipairs(entries) do
          if n > 1 then inl:insert(pandoc.Str(SEP)) end
          -- "Am. " + <a class="history-link" href=CR page>2026 AS 17</a> + " (eff. ...)"
          local content = { pandoc.Str(e.label) }
          if e.href then
            content[#content + 1] = pandoc.Link({ pandoc.Str(e.who) }, e.href, "",
                                                pandoc.Attr("", { "history-link" }))
          else
            content[#content + 1] = pandoc.Str(e.who)
          end
          content[#content + 1] = pandoc.Str(e.when)
          inl:insert(pandoc.Span(content, pandoc.Attr("", { "history-entry", e.class })))
        end
        inl:insert(pandoc.Str("."))
        item.section[#item.section + 1] =
          pandoc.Div({ pandoc.Para(inl) }, pandoc.Attr("", { "history" }))
      end
      kept[#kept + 1] = item
    end
  end

  -- Emit, sorting each contiguous run of sections; other blocks stay put.
  -- A chapter heading is inserted whenever the chapter number changes.
  local out = pandoc.List()
  local last_ch = nil   -- chapter text most recently emitted
  local k = 1
  while k <= #kept do
    if kept[k].block then
      out:insert(kept[k].block)
      k = k + 1
    else
      local run = {}
      while k <= #kept and kept[k].section do
        run[#run + 1] = kept[k]
        k = k + 1
      end
      table.sort(run, less)
      for _, item in ipairs(run) do
        local ch = item.chapter
        if ch and ch ~= "" and ch ~= last_ch then
          last_ch = ch
          out:insert(chapter_header(ch, item.num, doc.meta))
        end
        out:extend(item.section)
      end
    end
  end

  doc.blocks = out
  return doc
end