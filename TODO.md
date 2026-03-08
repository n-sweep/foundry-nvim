# TODO: Port ipynb/jupytext support into main

## Goal

Add `# %%` cell detection (for `.ipynb` files opened via jupytext.nvim) alongside the
existing Quarto `.qmd` support. The plugin auto-detects which backend to use based on
filetype. The Python layer (kernel, message format) is unchanged.

---

## 1. New file: `lua/foundry/ipynb_provider.lua`

Implement `extract_code_chunks(bufnr)` and `get_chunk_under_cursor(row)`.

**Chunk format** (same shape as otter, so cell_handler works unchanged):
- `from[1]` = 1-indexed line number of the `# %%` delimiter itself (same as otter puts
  the opening fence line in `from[1]` for Quarto)
- `to[1]`   = 1-indexed line number of the last content line before the next delimiter or EOF
- `from[2]`, `to[2]` = 0 (column, always)
- `lang` = `'python'`
- Return shape: `{ python = { chunk, ... } }`

**Detection logic:**
- Scan lines for `^# %%`, skipping lines that also match `markdown`
- For delimiter at line `d`, chunk is `from = {d, 0}, to = {next_d - 1 or EOF, 0}`
- Skip empty cells where `d + 1 > to[1]` (adjacent delimiters)

**`get_chunk_under_cursor(row)`:**
- `row` is **1-indexed** (matches vim cursor convention)
- Returns the chunk where `row >= from[1]` and `row <= to[1]`, or nil

---

## 2. Modify `lua/foundry/cell_handler.lua`

- Add `chunk_provider = nil` field to `M`
- In `setup()`, dispatch by filetype:
  - `quarto` → dynamic wrapper around `M.keeper` (must delegate at call time, not capture,
    so tests that reassign `cell_handler.keeper` still work)
  - `python` → `require('foundry.ipynb_provider')`
- Change `get_chunks()` to call `M.chunk_provider.extract_code_chunks(bn)` instead of
  `M.keeper.extract_code_chunks(bn)`
- Fix indexing bug in `get_cell_under_cursor()`:
  - Keep `row = vim.api.nvim_win_get_cursor(0)[1]` as **1-indexed**
  - Pass `row - 1` to `get_extmark_under_cursor()` (extmarks are 0-indexed)
  - Pass `row` (1-indexed) to chunk lookup (chunk ranges are 1-indexed)
- Rename local `get_quarto_chunk_under_cursor` → `get_chunk_under_cursor`

---

## 3. Modify `lua/foundry/cell.lua`

The current display uses two separate extmarks with `virt_text eol` for the output header.
For ipynb, `end_row` points to the next `# %%` line, so `Out[...]` appears on that line.

Fix: use a single output extmark with `virt_lines` + `virt_lines_above = true`, with the
`Out[...]` header as the first entry in `vlines`. This renders above the extmark line
regardless of what that line contains, so it works for both Quarto and ipynb.

Specific changes:
- `_update_display`: replace `output_header_id` + `output_text_id` extmarks with a single
  `output_id` extmark using `virt_lines` + `virt_lines_above = true`
- `Cell:new`: call `_update_display(start_row - 1, end_row - 1)` (both 0-indexed)
- `get_pos()`: use `em[3].end_row` from the main extmark instead of a separate output extmark
- `Cell:delete()`: delete only two extmarks (`id` and `output_id`)

---

## 4. Modify `lua/foundry/init.lua`

Line 84 crashes on python buffers because `RCodeBlock` doesn't exist outside Quarto:

```lua
-- current (crashes):
chl.bg = vim.api.nvim_get_hl(0, {name = 'RCodeBlock'}).bg

-- fix:
local rcode_hl = vim.api.nvim_get_hl(0, {name = 'RCodeBlock'})
if rcode_hl and rcode_hl.bg then
    chl.bg = rcode_hl.bg
end
```

---

## Status

- [ ] `lua/foundry/ipynb_provider.lua` — create
- [ ] `lua/foundry/cell_handler.lua` — chunk_provider dispatch + indexing fix
- [ ] `lua/foundry/cell.lua` — fix output display for ipynb
- [ ] `lua/foundry/init.lua` — guard RCodeBlock lookup
- All tests passing: `nix develop -c vusted tests/`
