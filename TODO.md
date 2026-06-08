# TODO: Fix large output parsing failure

## Problem

Neovim's `jobstart` pipe delivers stdout in OS-level chunks (~4–8 KB). The `on_stdout`
handler in `lua/foundry/ipy_bridge.lua` treats each chunk as a complete JSON record. When
a kernel response is large (e.g. a 1913-row pandas DataFrame), the single JSON line is
split across multiple chunks — each failing `vim.fn.json_decode` and logging
`ERR:failed to parse`.

---

## 1. Add NDJSON chunk reassembly in `lua/foundry/ipy_bridge.lua`

- Add a `_stdout_buf = ''` field to `M`
- In `on_stdout`, append each chunk to `_stdout_buf`, then loop extracting
  `\n`-terminated records to decode
- Only attempt `json_decode` on complete newline-delimited records

```lua
-- at module level:
local M = {
    handle = 0,
    _stdout_buf = '',
    on_result = function(_) logger:warn("Result handler not set") end
}

-- replace on_stdout:
local function on_stdout(_, data, _)
    for _, chunk in ipairs(data) do
        if chunk == '' then break end
        M._stdout_buf = M._stdout_buf .. chunk
        while true do
            local nl = M._stdout_buf:find('\n', 1, true)
            if not nl then break end
            local line = M._stdout_buf:sub(1, nl - 1)
            M._stdout_buf = M._stdout_buf:sub(nl + 1)
            if line ~= '' then
                local ok, result = pcall(vim.fn.json_decode, line)
                if ok then
                    M.on_result(result)
                else
                    logger:error('failed to parse: ' .. line)
                end
            end
        end
    end
end
```

---

## 2. Strip `text/html` before serialization in `python/kernel.py`

In `KernelManager.write()` (~line 298), filter `msg["data"]` to only keep `text/plain`
for `execute_result` messages before `json.dumps`. The Lua handler
(`cell_handler.lua:133`) only reads `text/plain` anyway; `text/html` is unused and
only bloats the pipe payload.

```python
def write(self, message: dict) -> None:
    if "messages" in message:
        message["messages"] = handle_datetimes(message["messages"])
        for msg in message["messages"]:
            if "data" in msg:
                msg["data"] = {
                    k: v for k, v in msg["data"].items()
                    if k == "text/plain"
                }
    sys.stdout.write(json.dumps(message) + "\n")
    sys.stdout.flush()
```

---

## 3. Expose `display_max_lines` as a user option in `lua/foundry/init.lua`

Currently hardcoded to `16` at line 24; read from `opts` instead:

```lua
function M.setup(opts)
    opts = opts or {}
    local ch = require('foundry.cell_handler').setup(plugin_dir, {
        display_max_lines = opts.display_max_lines or 16,
        border = opts.border or 'rounded'
    })
```
