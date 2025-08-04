package main

import "core:fmt"

MEASURE_PERFORMANCE          :: false

CONFIG_MAX_FPS               :: 60   
CONFIG_FONT_SIZE             :: 16
CONFIG_LARGE_FONT_SIZE       :: 24
CONFIG_SCROLLBAR_WIDTH       :: 15
CONFIG_SEARCH_PANEL_CLOSED   :: 15  // in pixels
CONFIG_SEARCH_PANEL_OPEN     :: 400 
CONFIG_TAB_WIDTH             :: 32 
CONFIG_SEARCH_METHOD_WIDTH   :: 96
// CONFIG_INITIAL_SEARCH_METHOD :: SearchMethod.CONTAINS
CONFIG_EMPTY_TAB_NAME        :: "empty tab"
CONFIG_CURSOR_REFRESH_RATE   :: CONFIG_MAX_FPS

CONFIG_UI_BG1       :: "282828FF"
CONFIG_UI_BG2       :: "3C3836FF"
CONFIG_UI_BG3       :: "504945FF"
CONFIG_UI_FG1       :: "FBF1C7FF"
CONFIG_UI_FG2       :: "EBDBB2FF"
CONFIG_UI_CODE      :: "B8BB26FF"
CONFIG_UI_BLUE      :: "458588FF"

CONFIG_CODE_SYMBOL    : u32 : 0xFFFF00FF
CONFIG_CODE_KEYWORD   : u32 : 0xFF0000FF
CONFIG_CODE_NAME      : u32 : 0x77FFBBFF
CONFIG_CODE_DIRECTIVE : u32 : 0x7700FFFF
CONFIG_CODE_STRING    : u32 : 0x770000FF
CONFIG_CODE_NUMBER    : u32 : 0xCC00CCFF

CONFIG_SET_THE_CHILDREN_STRAIGHT :: true
CONFIG_CODE_LINE_SPACING :: 2
CONFIG_WHAT_IS_LONG_PROC :: 50

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

main :: proc() {

    start_main_thread_pool()

    init_graphics()
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

}

// TODO before merge:
//   + allocate the text box string and assure that it is 0 terminated
//   + (only)  onscreen/lazy collapsing of boxes
//   + codeblocks
//   + context menus
//   + get all of the gruvbox palette
//   (after LATE) command palette
//   (after) ghost text?

