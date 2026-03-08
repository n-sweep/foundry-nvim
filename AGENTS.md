# foundry-nvim

A Neovim plugin for interactive Python code execution inside Quarto (`.qmd`) documents
and Jupyter notebooks (`.ipynb`) opened via jupytext.nvim. Cells are defined by document
delimiters (<code>```{python}</code>  for Quarto, `# %%` for jupytext) rather than manual selection.
The plugin communicates with a Python subprocess that manages Jupyter kernels via
`jupyter-client`/`ipykernel`, exchanging JSON messages over stdio.

## Project management

- Python dependencies are managed with **uv** (`pyproject.toml`, `uv.lock`)
- The dev environment is a **Nix flake** using uv2nix (`flake.nix`)
- Lua dependencies are provided by the Nix shell (vusted, lua-language-server)

## Running tests

Always run tests inside the Nix dev shell:

```sh
nix develop -c vusted tests/    # all Lua tests
nix develop -c pytest           # all Python tests
```
