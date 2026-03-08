# TODO: Port ipynb/jupytext support into main

## Goal

Add `# %%` cell detection (for `.ipynb` files opened via jupytext.nvim) alongside the
existing Quarto `.qmd` support. The plugin auto-detects which backend to use based on
filetype. The Python layer (kernel, message format) is unchanged.

---

## 1. New file: `lua/foundry/ipynb_provider.lua`

Implement a chunk-provider module for jupytext-style `# %%` buffers.

**Interface to implement:**

```lua
--- Returns all chunks in the buffer.
--- Each chunk: { range = { from = {row, col}, to = {row, col} }, lang = 'python' }
---   range.from[1] : 1-indexed row of the first line of code (NOT the `# %%` line)
---   range.to[1]   : 1-indexed row of the last line of code before next delimiter/EOF
---   range.from[2], range.to[2] : column (always 0)
---   lang : always 'python' (jupytext only produces Python cells)
--- This shape matches otter.keeper.extract_code_chunks() output for compatibility.
M.get_all_chunks(bufnr) -> { [lang] = { chunk, ... } }

--- Returns the chunk containing `row` (0-indexed cursor position), or nil.
M.get_chunk_under_cursor(row) -> chunk|nil
```

**Detection logic (ported from legacy `cell_handler.lua`):**

- Scan buffer lines for `^# %%` (but skip any line also containing `markdown`)
- Each `# %%` line starts a cell; the cell content range is:
  - `from[1]` = delimiter line + 1 (first line of code)
  - `to[1]` = one line before the next `# %%`, or end-of-buffer for the last cell
- Skip cells where `from[1] > to[1]` (empty cells — adjacent delimiters)
- Return in the same nested table format as otter: `{ python = { chunk1, chunk2, ... } }`

**Implementation notes:**
- Use `vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)` to read buffer
- Iterate lines with 1-indexed Lua loop, build delimiter positions
- For each delimiter at line `d`, create chunk with `from = {d+1, 0}, to = {next_d-1 or EOF, 0}`
- Filter out markdown cells: `if line:match('^# %%') and not line:match('markdown') then`

---

## 2. Modify `lua/foundry/cell_handler.lua`

Replace hardcoded `otter.keeper` with a chunk provider selected by filetype.

**Changes:**

- [ ] Add `chunk_provider` field to `M` (initially `nil`)
- [ ] In `M.setup()`, after `M.opts = opts`:
  ```lua
  local ft = vim.bo.filetype
  if ft == 'quarto' then
      M.chunk_provider = M.keeper  -- keep using otter.keeper (already required at top)
  elseif ft == 'python' then
      M.chunk_provider = require('foundry.ipynb_provider')
  else
      vim.notify('Foundry: unsupported filetype "' .. ft .. '"', vim.log.levels.WARN)
      return M
  end
  ```
- [ ] Replace `get_chunks()` body with:
  ```lua
  local bn = vim.api.nvim_get_current_buf()
  local all_chunks = M.chunk_provider.extract_code_chunks(bn)
  local output = {}
  for _, chunks in pairs(all_chunks) do
      for _, chunk in ipairs(chunks) do
          if not (chunk.lang == 'yaml' and chunk.range.from[1] == 1) then
              table.insert(output, chunk)
          end
      end
  end
  return output
  ```
- [ ] **Fix the indexing bug** in `get_cell_under_cursor()`:
  - **Problem:** Line 92 computes `row` as 0-indexed (`cursor[1] - 1`), then passes it to
    `get_quarto_chunk_under_cursor()` which compares against 1-indexed otter chunk ranges.
    This causes cells to not be found when cursor is on the opening fence/delimiter line.
  - **Fix:** Keep `row` as 1-indexed throughout `get_cell_under_cursor()`:
    ```lua
    -- Change line 92 from:
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    
    -- To:
    local row = vim.api.nvim_win_get_cursor(0)[1]  -- keep as 1-indexed
    
    -- Change line 93 from:
    local cell_id = get_extmark_under_cursor(row)
    
    -- To:
    local cell_id = get_extmark_under_cursor(row - 1)  -- extmarks need 0-indexed
    ```
  - Update `get_extmark_under_cursor(row)` docstring to clarify it expects 0-indexed row
  - Update `get_quarto_chunk_under_cursor(row)` docstring to clarify it expects 1-indexed row
- [ ] Rename `get_quarto_chunk_under_cursor()` to `get_chunk_under_cursor()` (not Quarto-specific anymore)
- [ ] Keep `M.keeper` field for now (otter.keeper) — removing it would break tests that mock it
- [ ] Update function docstrings to clarify indexing expectations

---

## 3. Modify `lua/foundry/cell.lua`

No changes needed. The current `Cell:get_execution_input()` uses `start_row + 2` which works for both:
- Quarto: skip the opening fence line
- ipynb: skip the `# %%` delimiter line

Both providers will return `range.from[1]` pointing to the first code line, so `Cell:new(cstart, cend, lang)` 
at line 45 of cell_handler receives the fence/delimiter row, and `start_row + 2` correctly skips it.

---

## 4. Modify `lua/foundry/init.lua`

**Fix the `FoundryCellHL` setup:**

Line 84 currently assumes `RCodeBlock` exists (Quarto-specific highlight group).
This will error on Python buffers.

```lua
local chl = vim.api.nvim_get_hl(0, {name = 'Comment'})
local rcode_hl = vim.api.nvim_get_hl(0, {name = 'RCodeBlock'})
if rcode_hl and rcode_hl.bg then
    chl.bg = rcode_hl.bg
end
vim.api.nvim_set_hl(0, 'FoundryCellHL', chl)
```

---

## 5. Tests

- [ ] Add `tests/lua/ipynb_provider_spec.lua` — unit tests for `# %%` chunk detection:
  - Basic cell detection (single cell, multiple cells)
  - Last cell (no trailing delimiter)
  - Empty cell skip (adjacent `# %%` lines)
  - Markdown cell skip (`# %% markdown`)
  - Correct `range.from` / `range.to` values (1-indexed)
  - Correct nesting: `{ python = { ... } }`
- [ ] Update `tests/lua/cell_handler_spec.lua`:
  - Add test for filetype dispatch (mock `vim.bo.filetype` as 'python', verify ipynb_provider is used)
  - Add test that verifies indexing fix (cursor at row N finds chunk correctly)
- [ ] Add `tests/test_ipynb.py` sample file for manual testing:
  ```python
  # %%
  x = 1
  y = 2
  
  # %%
  print(x + y)
  
  # %% markdown
  # This is a markdown cell and should be ignored
  
  # %%
  z = x * y
  z
  ```

---

## 6. Known Issues / Future Work

- [ ] The test suite mocks `cell_handler.keeper` directly (line 132 in cell_handler_spec.lua).
      After this refactor, tests should mock `cell_handler.chunk_provider` instead, but that
      requires updating all tests. For now, keep `M.keeper` as an alias.
- [ ] `prune_cells()` builds a key as `start_row + 1 .. ":" .. end_row` (line 295) — mixing
      0-indexed extmark positions with 1-indexed chunk positions. This works by accident but
      is fragile. Consider normalizing everything to 0-indexed internally.

---

## Summary of Changes

| File | Change |
|------|--------|
| `lua/foundry/ipynb_provider.lua` | New file: `# %%` chunk detection |
| `lua/foundry/cell_handler.lua` | Add `chunk_provider` dispatch, fix indexing bug |
| `lua/foundry/cell.lua` | No changes needed |
| `lua/foundry/init.lua` | Guard `RCodeBlock` highlight lookup |
| `tests/lua/ipynb_provider_spec.lua` | New file: unit tests |
| `tests/lua/cell_handler_spec.lua` | Add filetype dispatch tests |
| `tests/test_ipynb.py` | New file: manual test sample |
