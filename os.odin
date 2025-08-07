package main

import "core:fmt"
import "core:slice"
import os_old "core:os"
import os "core:os/os2"
import "core:path/filepath"

File_Info :: os.File_Info

execute_command :: proc(command: ..string) -> (ok: bool) {
    if len(command) == 0 do return false
    process: os.Process_Desc

    new_cwd := filepath.dir(command[0])
    if os.is_directory(new_cwd) do process.working_dir = new_cwd

    parent_env, err1 := os.environ(context.temp_allocator)
    if err1 == nil do process.env = parent_env

    process.command = command

    handle, err := os.process_start(process)
    if err != nil {
        fmt.println(err)
    }
    return err == nil
}   

list_dir :: proc(path: string, allocator := context.temp_allocator) -> (files: [] File_Info, ok: bool) {
    file_list, err := os.read_all_directory_by_path(path, allocator)
    return file_list, err == nil
}

