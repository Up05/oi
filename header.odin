package main

import docl "doc-loader"
import "core:strings"
import "core:text/match"

Entity     :: docl.Entity
Everything :: docl.Everything

Vector      :: [2] i32
MouseButton :: enum { NONE, LEFT, MIDDLE, RIGHT }

KeyMod :: enum {
    CTRL, SHIFT, ALT, SUPER,
}

SearchMethod :: enum {
    CONTAINS,               // default
    STRICT, PREFIX, SUFFIX,
    // TODO later replace with substring fuzzy matching, like: 
    // https://en.wikipedia.org/wiki/Damerau%E2%80%93Levenshtein_distance#Optimal_string_alignment_distance
    FUZZY1, FUZZY2, FUZZY4, // 1, 2 and 4 are the string "distances" in levelshtein algorithm
    REGEX, DOTSTAR,         // dotstar is strings.contains + regex's '.*' only
}

Palette :: enum {
    TRANSPARENT,   BAD, DBG,
    FG1, FG2, FG3, FG4,
    BG1, BG2, BG3, BG4,

    RED1,    RED2,
    GREEN1,  GREEN2,
    YELLOW1, YELLOW2,
    BLUE1,   BLUE2,
    PURPLE1, PURPLE2,
    AQUA1,   AQUA2,
    GRAY1,   GRAY2,
    ORANGE1, ORANGE2
}

FontType :: enum {
    REGULAR, MONO, LARGE,
}

Direction :: enum {
    LEFT, TOP, RIGHT, BOTTOM,
}

Scroll :: struct {
    pos : Vector, 
    vel : [2] f32,
    max : [2] i32, // max is cached
}

HyperLink :: struct {
    pos    : Vector,
    size   : Vector,
    target : ^docl.Entity,
}

BoxType :: enum {
    UNKNOWN, 
    BASIC,
    CODE,        // code blocks
    TEXT_INPUT,  // e.g.: searchbars
    CONTAINER,   // used to store other boxes
    LIST,        // lists have recursive indentation + folding
}

search_method_procs: [SearchMethod] proc(a, b: string) -> bool = {
    .CONTAINS = proc(a, b: string) -> bool { return strings.contains(a, b) },
    .STRICT   = proc(a, b: string) -> bool { return a == b },
    .PREFIX   = proc(a, b: string) -> bool { return strings.starts_with(a, b) },
    .SUFFIX   = proc(a, b: string) -> bool { return strings.ends_with(a, b) },
    .FUZZY1   = proc(a, b: string) -> bool { return string_dist(a, b, context.temp_allocator) <= 1 },
    .FUZZY2   = proc(a, b: string) -> bool { return string_dist(a, b, context.temp_allocator) <= 2 },
    .FUZZY4   = proc(a, b: string) -> bool { return string_dist(a, b, context.temp_allocator) <= 4 },
    .REGEX    = proc(a, b: string) -> bool {
        a := a
        captures: [32] match.Match        
        res, ok := match.gfind(&a, b, &captures)
        return len(res) > 0
    },
    .DOTSTAR = dotstar,
    // .SYNONYMS = proc(a, b: string) -> bool { panic("NOT YET IMPLEMENTED") },
}

Box :: struct {
    type      : BoxType,
    allocator : Allocator,
    children  : [dynamic] ^Box,
    parent    : ^Box,

    margin    : Vector,
    padding   : Vector,
    position  : Vector,
    offset    : [2] ^i32,
    min_size  : Vector,
    old_size  : Vector, // basically just for collapsing sidebar & navbar
    tex_size  : Vector,
    mirror    : [2] bool,
    advance   : [2] f32,
    indent    : Vector,
    scroll    : Scroll,

    text      : string,
    font      : FontType,
    tex       : Texture,
    // icon      : Icon,

    using design : struct {
        foreground    : Palette,
        background    : Palette,
        active_color  : Palette, // background_color
        hovered_color : Palette,
        ghost_color   : Palette, // ghost text foreground
        loading_color : Palette, // used by progress bar for background
        border        : bool,
        border_in     : bool, // inset TODO rename
    },

    using events : struct {
        click    : MouseEvent,
        hover    : MouseEvent,
        unhover  : MouseEvent, 
    },

    using input : struct {
        submit  : proc(target: ^Box),
        buffer  : Builder,
        cursor  : int,              // cursor / selection start                 [bytes]
        select  : int,              // selection end (cursor is the null state) [bytes]
        offsets : [] int,           // rune x offsets in pixels, by byte (NOT RUNE)
    },

    format_code : bool,         // for code blocks 
    entity      : ^Entity,
    links       : [] HyperLink, 

    method      : SearchMethod, // for search text inputs
    ghost_text  : string,
    suggestions : ^[] string,
    ghost_tex   : Texture,
    ghost_size  : Vector,
    top_results : [10] string,
    curr_result : int,

    progress    : ^[2] int,     // progress bar info

    target        : ^Box,       // context menu parent box
    userdata      : rawptr,

    hidden : bool,
    folded : bool,

    box_queue     : ^[dynamic] ^Box, // only potentially there
    cached_pos    : Vector,
    cached_size   : Vector,
    cached_indent : [2] i32,
    cached_scroll : Vector,
    out_of_order  : bool, 

    rendered         : bool,
    render_scheduled : bool,

}

Tab :: struct {
    using box     : Box,
    toolbar_box   : ^Box,

    box_table     : map [string] ^Box,  // entity name to y offset
    cache_queue   : [dynamic] ^Box,
    search        : [dynamic] ^Box,     // search results for the tab

    search_cursor : int,
    search_scroll : Scroll,

    everything    : Everything,
    is_empty      : bool,
}

window : struct {
    handle   : Window,
    renderer : Renderer,

    should_exit     : bool,
    should_relayout : bool,
    should_relayout_later: bool,

    frames  : int,
    size    : Vector,
    mouse   : Vector,
    pressed : MouseButton, 

    events  : struct {
        base   : Event,
        scroll : Vector,
        click  : MouseButton,
    },

    using hot_boxes : struct { // look! We're missing a term here...
        hovered             : ^Box,
        dragged_scrollbar   : ^Box,
        active_input        : ^Box,
        active_context_menu : ^Box,
        active_toolbar_tab  : ^Box,
    },
    _: [64] u8,

    root  : Box,
    boxes : struct {
        sidebar : ^Box,
        toolbar : ^Box,
        content : ^Box,
        navbar  : ^Box,
        popup   : ^Box,
        search  : ^Box,
        address : ^Box,
    },

    // boxes that are waiting for a texture
    // this is the global version (see.: Tab)
    box_queue: [dynamic] ^Box,

    tabs : [dynamic] Tab,
    current_tab : int,

    text_cursor_change_state_in : int,
    text_cursor_visible : bool,

    thread_pool: ThreadPool,
}


debug : struct {
    show: bool,

    box_count  : int,
    box_drawn  : int,
    box_placed : int,
}

FONTS: [FontType] Font

progress_metrics : struct {
    nexus_loader  : [2] int // [0] progress [1] max


}





















