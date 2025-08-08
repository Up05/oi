package main

MEASURE_PERFORMANCE          :: false

CONFIG_MAX_FPS               :: 60 
CONFIG_FONT_SIZE             :: 16 
CONFIG_LARGE_FONT_SIZE       :: 24 
CONFIG_SCROLLBAR_WIDTH       :: 15 
CONFIG_SEARCH_PANEL_CLOSED   :: 15 
CONFIG_SEARCH_PANEL_OPEN     :: 400
CONFIG_TAB_WIDTH             :: 32 
CONFIG_SEARCH_METHOD_WIDTH   :: 96 
CONFIG_EMPTY_TAB_NAME        :: "empty tab"
CONFIG_CURSOR_REFRESH_RATE   :: CONFIG_MAX_FPS // = 1s 
CONFIG_CODE_LINE_SPACING     :: 2
CONFIG_WHAT_IS_LONG_PROC     :: 50    // chars
CONFIG_SET_CHILDREN_STRAIGHT :: true  // whether ':' aligned in structs
CONFIG_CACHING_PKG_TIMEOUT   :: 7500  // fast, but may create ~200 processes, each "pinning" core
CONFIG_CACHING_DO_SERIALLY   :: false // very slow, but does not choke the machine


// almost all are untested: good luck!
// WIN10   = { "open",     "{FILE}"         }, 
// LINUX   = { "xdg-open", "{FILE}"         }, 
// MACOS   = { "open",     "-t",   "{FILE}" },
// NVIM    = { "nvim",        "+{LINE}",        "{FILE}"                   },
// EMACS   = { "emacsclient", "+{LINE}:0",      "{FILE}"                   },
// VSCODE  = { "code",        "--goto",         "{FILE}:{LINE}:0"          },
// SUBLIME = { "subl",        "{FILE}:{LINE}"                              },
// CLION   = { "clion",       "--line",         "{LINE}",         "{FILE}" },
// NPP     = { "notepad++",   "{FILE}",         "-n{LINE}"                 },
// KATE    = { "kate",        "--line",         "{LINE}",         "{FILE}" },
// ZED     = { "zed",         "{FILE}:{LINE}:0"                            },
// HELIX   = { "hx",          "{FILE}:{LINE}"                              },
// also, do not use double quotes for paths and etc. here " is the same as \"
EDITOR_COMMAND: [] string = 
    { "open",     "-t",   "{FILE}" } when ODIN_OS == .Darwin else
    { "xdg-open", "{FILE}"         } when ODIN_OS == .Linux  else
    { "open",     "{FILE}"         } 


COLORS := [Palette] Color {
    .TRANSPARENT = {},
    .BAD = rgba(0xFF0000FF),
    .DBG = rgba(0xFFFFFFFF),

    .BG1 = rgba(0x1D2021FF),
    .BG2 = rgba(0x282828FF),
    .BG3 = rgba(0x3C3836FF),
    .BG4 = rgba(0x504945FF),

    .FG1 = rgba(0xFBF1C7FF),
    .FG2 = rgba(0xEBDBB2FF),
    .FG3 = rgba(0xD5C4A1FF),
    .FG4 = rgba(0xBDAE93FF),

    .RED1    = rgba(0xCC241DFF),
    .RED2    = rgba(0xFB4934FF),
    .GREEN1  = rgba(0x98971AFF),
    .GREEN2  = rgba(0xB8BB26FF),
    .YELLOW1 = rgba(0xD79921FF),
    .YELLOW2 = rgba(0xFABD2FFF),
    .BLUE1   = rgba(0x458588FF),
    .BLUE2   = rgba(0x83A598FF),
    .PURPLE1 = rgba(0xB16286FF),
    .PURPLE2 = rgba(0xD3869BFF),
    .AQUA1   = rgba(0x689D6AFF),
    .AQUA2   = rgba(0x8EC07CFF),
    .GRAY1   = rgba(0x928374FF),
    .GRAY2   = rgba(0xA89984FF),
    .ORANGE1 = rgba(0xD65D0EFF),
    .ORANGE2 = rgba(0xFE8019FF),
}

KEYBINDS := [] Bind {
    { key = .ESCAPE, mods = {},         func = kb_exit_textbox,     name = "Exit active textbox" },
    { key = .TAB,    mods = {},         func = kb_goto_next_result, name = "Go to next search result" },
    { key = .TAB,    mods = { .SHIFT }, func = kb_goto_prev_result, name = "Go to previous search result" },

    { key = .W, mods = { .CTRL }, func = kb_close_tab,              name = "Close tab" },
    { key = .S, mods = { .CTRL }, func = kb_focus_search,           name = "Focus in-package search" },
    { key = .T, mods = { .CTRL }, func = kb_focus_address,          name = "Focus package address" },
    { key = .G, mods = { .CTRL }, func = kb_open_code_in_editor,    name = "View code block in editor" },

    { key = .N, mods = { .ALT },  func = kb_open_nexus,   name = "Open nexus" },
    { key = .R, mods = { .ALT },  func = kb_open_raylib,  name = "Open raylib" },
    { key = .V, mods = { .ALT },  func = kb_open_vulkan,  name = "Open vulkan" },
    { key = .O, mods = { .ALT },  func = kb_open_os2,     name = "Open os2" },
    { key = .S, mods = { .ALT },  func = kb_open_strings, name = "Open strings" },
    { key = .M, mods = { .ALT },  func = kb_open_math,    name = "Open math" },
    { key = .L, mods = { .ALT },  func = kb_open_linalg,  name = "Open linalg" },
    { key = .U, mods = { .ALT },  func = kb_open_utf8,    name = "Open utf8" },

    { key = .F1, mods = {}, func = kb_toggle_debug_menu,    name = "Toggle debug menu" },
    { key = .F5, mods = {}, func = kb_recache_everything,   name = "recache all code" },

    { key = .NUM1, mods = { .CTRL }, func = kb_switch_tab_1,   name = "Switch to tab 1" },
    { key = .NUM2, mods = { .CTRL }, func = kb_switch_tab_2,   name = "Switch to tab 2" },
    { key = .NUM3, mods = { .CTRL }, func = kb_switch_tab_3,   name = "Switch to tab 3" },
    { key = .NUM4, mods = { .CTRL }, func = kb_switch_tab_4,   name = "Switch to tab 4" },
    { key = .NUM5, mods = { .CTRL }, func = kb_switch_tab_5,   name = "Switch to tab 5" },
}

// fullpaths are valid
// plus, could just add libs to $ODIN_ROOT/user
CACHE_DIRECTORIES: [] string : {
    "base", "core", "vendor", "user", "/home/ulti/src/oi"
}


main :: proc() {
    permanent = make_arena()
    start_main_thread_pool()
    init_graphics()

    if !is_cache_ok() { recache() }
    setup_base_ui()

    for !window.should_exit {
        poll_events()
        begin_frame()
        defer end_frame()
        // ==================
        if window.should_relayout do update_layout()

        draw_window()
    
        // can, likely, be much more than 25 before FPS drops 
        for i in 0..<10 { pop_box_from_any_queue() }
        emit_events()    
    }
    
    free_all(permanent)

}

