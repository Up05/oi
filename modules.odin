#+feature dynamic-literals
package main

import "core:fmt"
import "core:slice"
import "core:strings"
import docl "doc-loader"

Module :: struct {
    name     : string,
    userdata : rawptr,
    function : proc(data: rawptr)
}

module_functions: map [string] proc(data: rawptr) = {
    "nexus" = open_nexus,
} 

module_name_list: [dynamic] string

get_module_function_by_name :: proc(name: string) -> proc(data: rawptr) {
    if func, ok := module_functions[name]; ok {
        return func
    }
    return open_odin_package
}

entity_table: [] docl.FileEntities
load_entity_table :: proc() {
    if entity_table != nil do return

    do_async(proc(task: Task) {
        progress := &progress_metrics.nexus_loader
        temp_table, ok := docl.fetch_all_entity_names("cache", progress = progress, allocator = make_arena())
        assert(ok)
        slice.sort_by(temp_table, proc(a, b: docl.FileEntities) -> bool { return a.file < b.file })
        entity_table = temp_table
    })
}

// === USE THESE FUNCTION INSTEAD OF RAW MODULES ===
open_module_by_name :: proc(name: string) {
    // a little bit insane, but whatever, maybe will redo later
    // this does not at all need to be fast.
    box := get_child_box_recursive(window.boxes.sidebar, name)
    if box != nil do box.click(box)
}

// === USE THESE FUNCTION INSTEAD OF RAW MODULES ===
open_sidebar_module :: proc(module: Module) {
    
    new_tab(module.name)

    tab := current_tab()

    clear_box(window.boxes.content)
    tab.box_table    = make(map [string] ^Box, tab.allocator)
    tab.search       = make([dynamic] ^Box,    tab.allocator)
    tab.cache_queue  = make([dynamic] ^Box,    tab.allocator)

    module.function(module.userdata)
}

open_odin_package :: proc(userdata: rawptr) {// {{{
    when MEASURE_PERFORMANCE {
        __start := tick_now() 
        defer fperf[#location().procedure] += tick_diff(__start, tick_now())
    }    
    if userdata == nil {
        fmt.println("Trying to open_odin_package without any usedata")
        fmt.println("userdata should contain the path: ^string")
        return
    }

    ok: bool
    current_tab().everything, ok = docl.load((transmute(^string) userdata)^, current_tab().allocator)
    assert(ok)

    everything := &current_tab().everything
    tab := current_tab()

    template      : Box = { margin = { 0, 4 }, scroll = tab.scroll } 
    template_code : Box = {
        type   = .CODE,
        font   = .MONO,
        border = true,
        foreground = .AQUA2,
        background = .BG2,
        border_in  = true,
        padding = { 8, 2 },
        margin  = { 0, 4 }, 
        click   = codeblock_click_handler,
    }

    the_package := everything.initial_package
    if the_package == nil {
        for k, v in everything.packages {
            if strings.ends_with(k, package_name_from_path((transmute(^string) userdata)^)) {
                everything.initial_package = v
                the_package = v
                break
            }
        }
        if the_package == nil {
            panic("ok, but okay, like okay, I mean, nu but okay but okay")
        }
    }

    append_box(tab, { font = .LARGE, margin = { 0, 12 }, scroll = tab.scroll, text = the_package.name })
    if len(the_package.docs) > 0 {
        append_box(tab, template, { font = .MONO, text = the_package.docs })
    }

    append_box(tab, { font = .LARGE, margin = { 0, 12 }, scroll = tab.scroll, text = "TYPES" })
    for _, entity in the_package.entities {
        if entity.kind == .Type_Name { // <--
            box := append_box(tab, template_code, { text = format_code_block(entity), entity = entity })
            if box != nil { tab.box_table[entity.name] = box }
            if len(entity.docs) > 0 { append_box(tab, template, { text = entity.docs }) }
        }
    }

    append_box(tab, { font = .LARGE, margin = { 0, 12 }, scroll = tab.scroll, text = "PROCEDURES" })
    for _, entity in the_package.entities {
        if entity.kind == .Procedure {
            box := append_box(tab, template_code, { text = format_code_block(entity), entity = entity })
            if box != nil { tab.box_table[entity.name] = box }
            if len(entity.docs) > 0 { append_box(tab, template, { text = entity.docs }) }
        }
    }

    append_box(tab, { font = .LARGE, margin = { 0, 12 }, scroll = tab.scroll, text = "PROCEDURE GROUPS" })
    for _, entity in the_package.entities {
        if entity.kind == .Proc_Group {
            box := append_box(tab, template_code, { text = format_code_block(entity), entity = entity })
            if box != nil { tab.box_table[entity.name] = box }
            if len(entity.docs) > 0 { append_box(tab, template, { text = entity.docs }) }
        }
    }

    append_box(tab, { font = .LARGE, margin = { 0, 12 }, scroll = tab.scroll, text = "VARIABLES / CONSTANTS" })
    for _, entity in the_package.entities {
        if entity.kind == .Constant || entity.kind == .Variable {
            box := append_box(tab, template_code, { text = format_code_block(entity), entity = entity })
            if box != nil { tab.box_table[entity.name] = box }
            if len(entity.docs) > 0 { append_box(tab, template, { text = entity.docs }) }
        }
    }


}// }}}

open_nexus :: proc(userdata: rawptr) {// {{{
    tab := current_tab()

    append_box(tab, { font = .LARGE, text = "nexus" })

    nexus_search := append_box(tab, {
        type      = .TEXT_INPUT,
        min_size  = { 0, CONFIG_FONT_SIZE + 4 },
        position  = { 2, 2 },
        padding   = { 4, 1 },
        design    = { 
            foreground    = .FG2, 
            background    = .BG3, 
            active_color  = .BG4, 
            hovered_color = .BG4,
            ghost_color   = .FG4,
            loading_color = .BG1,
        }, 
        border    = true,
        border_in = true,
        font      = .MONO,
        text      = "search in any package",
        click     = search_click_handler,
        submit    = nexus_submit_handler,
        progress  = &progress_metrics.nexus_loader,
    })

    window.active_input = nexus_search

    load_entity_table()

}// }}}


// Kind of a bad place for this...
setup_sidebar :: proc(parent: ^Box) {// {{{
    module_name_list = make([dynamic] string, permanent)

    // it's not really a search should rename later
    sidebar_search := append_box(window.boxes.sidebar, {
        type      = .TEXT_INPUT,
        min_size  = { -4, CONFIG_FONT_SIZE + 4 }, //  - sidebar.min_size.x
        position  = { 2, 2 },
        padding   = { 4, 1 },
        margin    = { 0, 8 },
        design    = { 
            foreground    = .FG2, 
            background    = .BG3, 
            active_color  = .BG4, 
            hovered_color = .BG4,
            ghost_color   = .FG4,
        },  
        border    = true,
        border_in = true,
        font      = .MONO,
        text      = "open module",
        click     = search_click_handler,
        submit    = proc(target: ^Box) {
            lo := string(target.buffer.buf[:])
            hi := target.ghost_text
            module_name := cat({ lo, hi }, allocator = context.temp_allocator)
            open_module_by_name(module_name)
        },

        // no one will ever swap about { data, len } or { data, len, cap, alloc } members, right?
        suggestions = transmute(^[] string) &module_name_list,
    })
    window.boxes.address = sidebar_search



    template := Box {
        type   = .LIST,
        font   = .REGULAR,
        foreground = .FG2,
        indent = { 16, 0 },
        click = sidebar_click_event_handler,
    }

    append_box(parent, { text = "meta", font = .LARGE })

    append_box(parent, template, { text = "nexus" })
    
    append(&module_name_list, "nexus")

    file_details, ok := list_dir("cache")
    if !ok { panic("need to rebuild .../oi/cache/") }

    file_names := make([] string, len(file_details), context.temp_allocator)
    for file, i in file_details {
        file_names[i] = file.name
    }

    slice.sort(file_names[:])
    
    last_category: string

    prev_parent := parent
    prev_levels : int
    for file in file_names {
        path := cat({ "cache/", file }, permanent)
        template.userdata = new_clone(path, permanent)

        file := file
        if strings.ends_with(file, ".odin-doc") { 
            file = file[:len(file) - len(".odin-doc")] 
        }
        
        if category := strings.index(file, "@"); category != -1 {
            if last_category != file[:category] {
                append_box(parent, template, { 
                    font = .LARGE, foreground = .FG1, 
                    text = file[:category],
                })
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

        prev_parent = append_box(parent, template, { 
            position = { 16 * i32(levels), 0 }, 
            text = file, 
            hidden = strings.starts_with(file, "_")
        })
        prev_levels = levels
        append(&module_name_list, strings.clone(file, permanent))
    }

}// }}}
