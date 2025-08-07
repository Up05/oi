package main

import "core:fmt"
import "core:slice"
import "core:strings"
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

join_paths :: proc(paths: [] string) -> string { return filepath.join(paths, context.temp_allocator) }
cache_everything :: proc(progress: ^[2] int, finished: ^[dynamic] string) {
    progress[1] = 200 + len(CACHE_DIRECTORIES) // more or less 203 packages, hard to be specific right now, cause doc-format
    alloc := make_arena()
    defer free_all(alloc)

    cache_directory :: proc(source: string, odin_root: string, alloc: Allocator, progress: ^[2] int, finished: ^[dynamic] string) {
        if !os.is_directory(source) do return 

        in_root := strings.starts_with(source, odin_root)

        destination := eat(filepath.rel(odin_root, source, alloc)) if in_root else cat({ "user@", filepath.base(source) }, alloc) 

        process_info: os.Process_Desc
        process_info.command = { 
            "odin", "doc", source, 
            "-doc-format", "-all-packages", // temp
            fmt.aprintf("-out=./cache/%s", eat(strings.replace(strings.clone(destination), "/", "@", -1)), allocator = alloc) 
        }

        when CONFIG_CACHING_DO_SERIALLY {
            state, _, _, _ := os.process_exec(process_info, alloc)
        } else { // probably, this:
            process, err2 := os.process_start(process_info)
            proc_state, err3 := os.process_wait(process, CONFIG_CACHING_PKG_TIMEOUT)
        }

        files, err4 := os.read_all_directory_by_path(source, alloc)
        has_odin_files: bool
        for file in files {
            if strings.ends_with(file.fullpath, ".odin") { 
                has_odin_files = true
                break
            }
        }
        if has_odin_files {
            progress[0] += 1
            append(finished, destination)
        }

        for file in files {
            if file.type != .Directory do continue
            cache_directory(file.fullpath, odin_root, alloc, progress, finished)
        }
    }

    exe_path, err1  := os.get_executable_directory(context.allocator)
    err2 := os.set_working_directory(exe_path)
    assert(err1 == nil && err2 == nil)

    odin_root := os.get_env("ODIN_ROOT", context.temp_allocator)

    os.remove_all("cache")
    os.make_directory("cache")

    for dir in CACHE_DIRECTORIES {
        if filepath.is_abs(dir) {  
            cache_directory(dir, odin_root, alloc, progress, finished)
        } else {
            cache_directory(join_paths({ odin_root, dir }), odin_root, alloc, progress, finished)
        }
    }    
}

is_cache_ok :: proc() -> bool {
    exe_path, err1  := os.get_executable_directory(context.allocator)
    err2 := os.set_working_directory(exe_path)
    assert(err1 == nil && err2 == nil)

    if !os.is_directory("cache") do return false
    if files, ok := list_dir("cache"); len(files) == 0 || !ok do return false

    return true
}
