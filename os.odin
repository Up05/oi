package main

import "core:fmt"
import "core:slice"
import "core:thread"
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

    // fmt.println("command:", command)
    // state, stdout, stderr, err := os.process_exec(process, permanent)
    // fmt.println("stdout", string(stdout))
    // fmt.println("stderr", string(stderr))

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

join_paths :: proc(paths: [] string) -> string { 
    when ODIN_OS != .Windows {
        value, _ := filepath.join(paths, context.temp_allocator) 
        return value
    } else {
        return filepath.join(paths, context.temp_allocator) 
    }
}
cache_everything :: proc(progress: ^[2] int, finished: ^[dynamic] string) {
    progress[1] = 200 + len(CACHE_DIRECTORIES) // more or less 203 packages, hard to be specific right now, cause doc-format
    alloc := make_arena()
    defer {
        thread.pool_finish(&window.thread_pool)
        free_all(alloc)
    }

    cache_directory :: proc(source: string, odin_root: string, alloc: Allocator, progress: ^[2] int, finished: ^[dynamic] string) {
        if !os.is_directory(source) do return 

        in_root := strings.starts_with(source, odin_root)

        destination := eat(filepath.rel(odin_root, source, alloc)) if in_root else cat({ "user@", filepath.base(source) }, alloc) 

        encoded_destination := eat(strings.replace(strings.clone(destination), "/", "@", -1))
        encoded_destination  = eat(strings.replace(encoded_destination, "\\", "@", -1))

        process_info: os.Process_Desc
        process_info.command = { 
            "odin", "doc", source, 
            "-doc-format", "-all-packages", // temp
            fmt.aprintf("-out=./cache/%s.odin-doc", encoded_destination, allocator = alloc) 
        }

        state, stdout, stderr, _ := os.process_exec(process_info, alloc)
        when CONFIG_LISTEN_TO_CHILDREN { 
            for p in process_info.command {
                fmt.print(p, "")
            }; fmt.println()
            fmt.println("stderr:", string(stderr))
            fmt.println("stdout:", string(stdout))
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

        CacheData :: struct {
            source: string, 
            odin_root: string, 
            alloc: Allocator, 
            progress: ^[2]int, 
            finished: ^[dynamic]string
        }

        for file in files {
            if file.type != .Directory do continue
            data: CacheData = {
                source = file.fullpath,
                odin_root = odin_root,
                alloc = alloc,
                progress = progress,
                finished = finished
            }
            do_async(proc(task: Task) {
                data := cast(^CacheData) task.data
                cache_directory(data.source, data.odin_root, data.alloc, data.progress, data.finished)
            }, data = new_clone(data, alloc))
        }
        
        // thread.pool_finish(&window.thread_pool)
    }

    set_correct_cwd()

    odin_root := get_odin_root()

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
    set_correct_cwd()

    if !os.is_directory("cache") do return false
    if files, ok := list_dir("cache"); len(files) == 0 || !ok do return false

    return true
}

set_correct_cwd :: proc() {
    @static already_set: bool
    if already_set do return

    exe_path, err1  := os.get_executable_directory(context.allocator)
    err2 := os.set_working_directory(exe_path)
    assert(err1 == nil && err2 == nil)
    already_set = true
}

get_odin_root :: proc() -> string {

    @static cached_odin_root: string

    if path, ok := os.lookup_env("ODIN_ROOT", context.temp_allocator); ok {
        if path != cached_odin_root {
            cached_odin_root = strings.clone(path, permanent) // "average memeory leak"
        }
        return cached_odin_root
    }
    
    proccess: os.Process_Desc
    proccess.command = { "odin", "root" }
    state, stdout, stderr, err := os.process_exec(proccess, context.temp_allocator) // pausing here sucks a little bit, but it should be fine...
    if err != nil {
        fmt.println("command 'odin root' failed, is the odin compiler in your PATH?")
    }

    path := string(stdout)
    if path != cached_odin_root {
        cached_odin_root = strings.clone(path, permanent)
    }

    return cached_odin_root
}

