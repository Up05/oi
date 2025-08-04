package main

import "core:fmt"
import "core:slice"
import "core:strings"
import os "core:os/os2"

setup_sidebar :: proc(parent: ^Box) {
    
    template := Box {
        type   = .LIST,
        font   = .REGULAR,
        foreground = .FG2,
        indent = { 16, 0 },
        click = sidebar_click_event_handler,
    }

    append_box(parent, { text = "meta", font = .LARGE })
    append_box(parent, template, { text = "nexus" })
    
    file_details, err1 := os.read_all_directory_by_path("cache", context.temp_allocator)
    if err1 != nil { /*rebuild cache*/ panic("need to rebuild .../oi/cache/") }
    file_names := make([] string, len(file_details), context.temp_allocator)
    for file, i in file_details {
        file_names[i] = file.name
    }

    slice.sort(file_names[:])
    
    last_category: string

    prev_parent := parent
    prev_levels : int
    for file in file_names {
        template.userdata = new_clone(cat({ "cache/", file }))

        file := file
        if strings.ends_with(file, ".odin-doc") { 
            file = file[:len(file) - len(".odin-doc")] 
        }
        
        if category := strings.index(file, "@"); category != -1 {
            if last_category != file[:category] {
                append_box(parent, template, { font = .LARGE, foreground = .FG1, text = file[:category] })
                prev_parent = parent
            }
            last_category = file[:category]
        }

        levels := strings.count(file, "@") - 1
        
        if levels > -1 {
            file = file[strings.last_index(file, "@")+1:]
        }
        for level in 0..<max(prev_levels - levels, 0) {
            if prev_parent.parent == nil do break
            prev_parent = prev_parent.parent
        }

        prev_parent = append_box(parent, template, { position = { 16 * i32(levels), 0 }, text = file })
        prev_levels = levels
    }



}
