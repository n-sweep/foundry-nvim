# TODO

- [ ] goto next/previous error when wrapping at end/beginning of buffer

## backlog

- [ ] separate system logging from kernel-specific logging
    - [ ] send the latter to a temp file instead
- [ ] create a cell w/o executing
- [ ] execute skip empty cells

## DONE

- [x] logging
- [x] execute code (ipython)
    - [x] associate inputs with outputs (cell #s)
- [x] display the code in the buffer
- [x] automatic startup based on ipynb filetype
- [x] automatic shutdown of current kernel when buffer closes
- [x] automatic shutdown of all kernels when nvim closes
- [x] delete cell
    - deleting a cell means removing it's associted extmarks and therefore virtual text; it does not remove any of the buffer content
- [x] delete all cells
- [x] delete invalid cells on edit. cells are invalid when:
    - the start line of the cell is greater than or equal to the end line
    - when a cell's separator is deleted
- [x] output openable in a popup window
- [x] yank cell output
- [x] yank cell input?
- [x] max height of virtual lines
- [x] execute skip markdown cells
- [x] truncate virtual text output
- [x] shutdown / restart kernels
- [x] error when trying to open cell with no output
- [x] cells with both stream and execution output overwrite the output before completion
