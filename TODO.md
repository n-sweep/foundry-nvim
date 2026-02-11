# Foundry-nvim Refactor TODO

## Phase 1: Independent refactors

### cell_handler.lua (tested - see tests/lua/cell_handler_spec.lua)
- [ ] Refactor `handle_execution_result` to parse new Jupyter message format
  - Iterate `msg.messages` array
  - Handle `output_type`: stream, execute_result, error
  - Aggregate output lines into single `cell:update()` call

## Phase 2: Filetype infrastructure

### init.lua
- [ ] Store filetype/mode at buffer setup time
  - Module-level table keyed by bufnr (e.g., `M.buffer_modes = {}`)
  - Detect `.qmd` → quarto, `.py` → jupytext

## Phase 3: Filetype-aware functions

Quarto uses otter.nvim APIs, jupytext uses existing delimiter detection.
These functions will likely remain untested (otter mocking is non-trivial).

### Otter API mapping for quarto
| foundry function                        | otter API                                                                                       |
|-----------------------------------------|-------------------------------------------------------------------------------------------------|
| `get_cell_under_cursor()`               | `keeper.get_current_language_context()` returns `lang, start_row, start_col, end_row, end_col`  |
| `get_execution_input()`                 | `keeper.get_language_lines_around_cursor()` returns code as string                              |
| `goto_next_cell()` / `goto_prev_cell()` | `keeper.extract_code_chunks()` + find next/prev chunk, or search for `` ```{python} `` patterns |

### cell_handler.lua
- [ ] `get_cell_under_cursor()` - filetype dispatch
- [ ] `get_execution_input()` - filetype dispatch
- [ ] `goto_next_cell()` - filetype dispatch
- [ ] `goto_prev_cell()` - filetype dispatch

### cell.lua
- [ ] `is_valid()` - filetype-aware delimiter check (currently hardcoded `^# %%`)

## Phase 4: Entry point

### init.lua
- [ ] Add `run_cell()` entry point with filetype dispatch
