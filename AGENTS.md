# AGENTS.md - foundry-nvim Development Guide

## Build & Test Commands
- `nix develop` - Enter development shell with all dependencies
- **IMPORTANT**: Do NOT run tests or make changes unless explicitly asked by the user

## Code Style Guidelines

### Python (python/)
- Use type hints for all functions and class methods
- Follow snake_case naming conventions  
- Add logging with descriptive messages using the logging module
- Handle errors explicitly with try/except blocks and proper error messages
- Import standard library first, then third-party, then local modules

### Lua (lua/foundry/)
- Prefix private functions with underscore (_function_name)
- Use local for all module functions and variables
- Follow existing module structure pattern with M table exports
- Use descriptive variable names (start_row vs sr)

## Error Handling
- Python: Use logging module for all debug/error output
- Lua: Use logger from foundry.logging for consistent logging

## Project Structure
- Python kernel management in python/
- Lua Neovim interface in lua/foundry/
- Main entry point: lua/foundry/init.lua

## Current Refactor: Quarto Support

### Goal
Integrate foundry-nvim as a code runner for quarto-nvim. Previously worked with jupytext `.py` files (detecting cells via `# %%`). Now integrating with quarto-nvim. Foundry uses otter.nvim directly for cell detection in quarto files.

Priority: Quarto integration. Retain jupytext support where practical.

### Message Format Change
Python kernel now emits standard Jupyter IOPub message format:
```lua
{
    cell_id = 1,
    status = "ok" | "error",
    execution_count = N,
    messages = {
        { output_type = "stream", name = "stdout", text = "..." },
        { output_type = "execute_result", data = { ["text/plain"] = "..." } },
        { output_type = "error", ename = "...", evalue = "...", traceback = { ["text/plain"] = {...} } }
    }
}
```

### Cell Delimiters by Filetype
- `.py` (jupytext): `# %%`
- `.qmd` (Quarto): `` ```{python} `` / `` ``` ``

### Testing Approach
- Unit tests only where valuable and decoupled from Neovim APIs
- `cell_handler_spec.lua` tests message parsing (mocks Cell and ipy_bridge)
- `cell.lua` has no unit tests—too tightly coupled to Neovim, logic is trivial

### Files Requiring Changes
- `cell_handler.lua`: message parsing, filetype-aware delimiter detection
- `cell.lua`: `is_valid()` needs filetype-aware delimiter check
- `init.lua`: detect filetype, pass to cell_handler via opts
