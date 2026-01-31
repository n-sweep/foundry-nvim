# AGENTS.md - foundry-nvim Development Guide

## Build & Test Commands
- `uv sync` - Install/sync Python dependencies  
- `nix develop` - Enter development shell with all dependencies

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