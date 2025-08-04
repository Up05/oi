#+feature dynamic-literals
package main

import "core:fmt"
import "core:slice"
import "core:strings"
import "core:thread"
import docl "doc-loader"

Module :: struct {
    name     : string,
    userdata : rawptr,
    function : proc(data: rawptr)
}

module_functions: map [string] proc(data: rawptr) = {
    "nexus" = open_nexus,

} 

get_module_function_by_name :: proc(name: string) -> proc(data: rawptr) {
    if func, ok := module_functions[name]; ok {
        return func
    }
    return open_odin_package
}

entity_table: [] docl.FileEntities

// I would honestly prefer this to be a map of string* <-> function pointer
// and in sidebar.click
open_sidebar_module :: proc(module: Module) {
    
    new_tab(module.name)

    tab := current_tab()

    clear_box(window.boxes.content)
    tab.box_table    = make(map [string] ^Box, tab.allocator)
    // tab.children     = make([dynamic] ^Box,    tab.allocator)
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
    fmt.println((transmute(^string) userdata)^)
    current_tab().everything, ok = docl.load((transmute(^string) userdata)^, current_tab().allocator)
    assert(ok)

    everything := &current_tab().everything
    tab := current_tab()

    template      : Box = { margin = { 0, 4 }, scroll = tab.scroll } 
    template_code : Box = {
        type = .CODE,
        foreground = .AQUA2,
        background = .BG2,
        font = .MONO,
        border = true,
        border_in = true,
        padding = { 8, 2 },
        margin  = { 0, 4 }, 
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

    box := append_box(tab, { font = .LARGE, margin = { 0, 12 }, scroll = tab.scroll, text = the_package.name })
    if len(the_package.docs) > 0 {
        append_box(tab, template, { text = the_package.docs })
    }

    for _, entity in the_package.entities {
        if entity.kind == .Type_Name { // <--
            box := append_box(tab, template_code, { text = format_code_block(entity) })
            if box != nil { tab.box_table[entity.name] = box }
            if len(entity.docs) > 0 { append_box(tab, template, { text = entity.docs }) }
        }
    }

    for _, entity in the_package.entities {
        if entity.kind == .Procedure {
            box := append_box(tab, template_code, { text = format_code_block(entity) })
            if box != nil { tab.box_table[entity.name] = box }
            if len(entity.docs) > 0 { append_box(tab, template, { text = entity.docs }) }
        }
    }

    for _, entity in the_package.entities {
        if entity.kind == .Proc_Group {
            box := append_box(tab, template_code, { text = format_code_block(entity) })
            if box != nil { tab.box_table[entity.name] = box }
            if len(entity.docs) > 0 { append_box(tab, template, { text = entity.docs }) }
        }
    }

    for _, entity in the_package.entities {
        if entity.kind == .Constant || entity.kind == .Variable {
            box := append_box(tab, template_code, { text = format_code_block(entity) })
            if box != nil { tab.box_table[entity.name] = box }
            if len(entity.docs) > 0 { append_box(tab, template, { text = entity.docs }) }
        }
    }


}// }}}

open_nexus :: proc(userdata: rawptr) {
    tab := current_tab()

    append_box(tab, { font = .LARGE, text = "nexus" })

    append_box(tab, {
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


}
