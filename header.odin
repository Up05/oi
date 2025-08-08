package main

import "base:runtime"
import docl "doc-loader"
import "core:strings"
import "core:text/match"

Entity     :: docl.Entity
Everything :: docl.Everything

Vector      :: [2] i32
MouseButton :: enum { NONE, LEFT, MIDDLE, RIGHT }
KeyMod      :: enum { CTRL, SHIFT, ALT, SUPER, }
FontType    :: enum { REGULAR, MONO, LARGE }

SearchMethod :: enum {
    DOTSTAR,         // (default) dotstar is strings.contains + regex's '.*' only
    CONTAINS,
    STRICT, PREFIX, SUFFIX,
    // TODO later replace with substring fuzzy matching, like: 
    // https://en.wikipedia.org/wiki/Damerau%E2%80%93Levenshtein_distance#Optimal_string_alignment_distance
    FUZZY1, FUZZY2, FUZZY4, // 1, 2 and 4 are the string "distances" in levelshtein algorithm
    REGEX, 
}

// higher number = brighter
// may be used with brighten(COLORS[palette], percent) in *_rgba functions
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
    BASIC,      // basic text elements
    CODE,       // code blocks
    TEXT_INPUT, // e.g.: searchbars
    CONTAINER,  // used to store other boxes
    LIST,       // lists have recursive indentation + folding
}

Record :: struct { src: runtime.Source_Code_Location, size: int, count: int }

Box :: struct {
    type      : BoxType,
    allocator : Allocator,      // the arena allocator used by box, unique to .CONTAINER, otherwise inherited
    children  : [dynamic] ^Box,
    parent    : ^Box,           

    margin    : Vector,         // distance between the following sibblings and this box * advance
    padding   : Vector,         // by how much should the background and border be expanded (diameter)
    position  : Vector,         // pixel offset (top-left unless mirror)
    offset    : [2] ^i32,       // responsive offset (top-left unless mirror)
    min_size  : Vector,         // the minimum size for the container, set automatically in text elements
    old_size  : Vector,         // basically, just for collapsing sidebar & navbar
    tex_size  : Vector,         // texture size (done automatically and only for text elements)
    mirror    : [2] bool,       // whether the position offset should be mirrored to other side of screen/parent element
    advance   : [2] f32,        // in what direction should sibbling elements be offset, by default set to: { x = 0, y = 1 }, toolbar tabs = { 1, 0 }
    indent    : Vector,         // for collapsable lists, by how much should children elements be indented. y MIGHT be ignored, idk?
    scroll    : Scroll,         // mouse wheel (or other) scrolling info. If scroll.max.y > window.size.y then scrollbar is shown
        
    text      : string,         // used in BASIC text elements and in text input as "placeholder" text (see: HTML placeholder)
    font      : FontType,       // one of (currently) 3 fonts: REGULAR (default), MONO or LARGE
    tex       : Texture,        // texture, should be rendered automtically in pop_queued_box()
    // icon      : Icon,

    using design : struct {
        foreground    : Palette,    // text color (default: FG1)
        background    : Palette,    // ... (default: TRANSPARENT)
        active_color  : Palette,    // pressed/... color
        hovered_color : Palette,    // mouseover color
        ghost_color   : Palette,    // ghost text foreground (in TEXT_INPUTs)
        loading_color : Palette,    // used by progress bar for background (in nexus)
        border        : bool,       // whether to enable border (does not work with .BASIC text boxes)
        border_in     : bool,       // whether border should look like it is inset
    },

    using events : struct {
        click    : MouseEvent,      // function pointer
    },

    using input : struct {          // .TEXT_INPUT type boxes
        submit  : InputEvent,       // fired when ENTER is pressed
        buffer  : Builder,          // automatically re-renders and handles buffer contents (for window.active_input)
        cursor  : int,              // cursor / selection start                 [bytes] (could be that: cursor > select)
        select  : int,              // selection end (cursor is the null state) [bytes]
        offsets : [] int,           // rune x offsets in pixels, by byte (NOT RUNE), offsets[0] = 0
    },

    format_code : bool,         // .CODE type boxes (code blocks, there is no inline code here)
    entity      : ^Entity,      // associated odin declaration
    links       : [] HyperLink, // pos+size overlay for the block, that, when clicked, scrolls to the target

    method      : SearchMethod, // .TEXT_INPUT boxes used as searches (default: DOTSTAR)
    ghost_text  : string,       // suggestion based on box.buffer as inline ghost text
    suggestions : ^[] string,   
    ghost_tex   : Texture,      
    ghost_size  : Vector,

    progress    : ^[2] int,     // progress bar info [0] = progress, [1] = max. See: 'progress_metrics'

    target        : ^Box,       // context menu invoker box i.e.: the box that was right clicked to bring up the context menu
    userdata      : rawptr,     // generic user data, rarely used here

    hidden : bool,              // whether text box should be hidden and removed from layout
    folded : bool,              // whether children boxes in .LIST should be hidden

    box_queue     : ^[dynamic] ^Box, // only potentially there, link to tab queue (if I am not mistaken)
    cached_pos    : Vector,     // automaticallly reset each time relayout-ing occurs (may be read though)
    cached_size   : Vector,     // ...
    cached_indent : [2] i32,    // 
    cached_scroll : Vector,
    out_of_order  : bool,       // optimization thing to skip trying to draw children that would have been off-screen

    rendered         : bool,    // whether tex is rendered (only for the first time, rerendering is not lazy)
    render_scheduled : bool,    // bug fix, to not schedule 20 renderings for the same box

}

Tab :: struct {
    using box     : Box,
    toolbar_box   : ^Box,       // the associated box inside of the toolbar

    box_table     : map [string] ^Box,  // entity name to Box (most commonly: scroll_to y-offset)
    cache_queue   : [dynamic] ^Box,     // queue for boxes that have not yet been rendered first time
    search        : [dynamic] ^Box,     // search results for the tab
    search_cursor : int,                // navbar active search result (for tab navigation)    
    search_scroll : Scroll,             // I guess, for saving + loading of navbar scroll 

    everything    : Everything, // (all entities in open package), may be empty if tab is not a module of type "odin package"
    is_empty      : bool,       // Yes, many ctrl + W results in "empty tab", I should consolidate this shit but whatever...
}


FONTS: [FontType] Font

search_method_procs: [SearchMethod] proc(a, b: string) -> bool = {
    .DOTSTAR  = dotstar,
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
    // .SYNONYMS = proc(a, b: string) -> bool { panic("NOT YET IMPLEMENTED") },
}

window : struct {
    handle   : Window,      // SDL window handle
    renderer : Renderer,    // SDL renderer handle

    should_exit     : bool,
    should_relayout : bool,
    should_relayout_later: bool,

    onframe : bool,         // true when in the middle of rendering a frame
    frames  : int,          // amount of frames since window was launched
    size    : Vector,       // window size
    mouse   : Vector,       // mouse position (relative to top-left corner of window)
    pressed : MouseButton,  // which mouse button is currently pressed (usually .NONE) 

    events  : struct {      // single-frame events
        base   : Event,     // mostly for keyboard
        scroll : Vector,    // mousewheel scrolling
        click  : MouseButton,
    },

    using hot_boxes : struct { // look! We're missing a term here...
        hovered             : ^Box, // Currently hovered box
        dragged_scrollbar   : ^Box, // Currently dragged scrollbar thumb
        active_input        : ^Box, // Currently active text input
        active_context_menu : ^Box, // Currently shown right click menu
        active_toolbar_tab  : ^Box, // Current tab
    },
    _: [64] u8, // padding, probley unnecessary by now

    root  : Box,            // The root UI element
    boxes : struct {        // children of root and (some of their children)
        sidebar : ^Box,     // panel on the left
        toolbar : ^Box,     // panel on the top...
        content : ^Box,     // the main body element
        navbar  : ^Box,     // right side search result panel
        popup   : ^Box,     // context menu (currently only)
        search  : ^Box,     // toolbar search
        address : ^Box,     // sidebar text input
    },

    // boxes that are waiting for a texture
    // this is the global version (see.: Tab)
    box_queue: [dynamic] ^Box,

    tabs : [dynamic] Tab,
    current_tab : int,

    // for text cursor blinking
    text_cursor_change_state_in : int,
    text_cursor_visible : bool,

    // use: do_async(proc(task: Task) { ... your code ... })
    thread_pool: ThreadPool,
}

debug : struct {
    show: bool,

    box_count  : int,
    box_drawn  : int,
    box_placed : int,
}


progress_metrics : struct {
    // [0] progress [1] max
    nexus_loader  : [2] int, // loading of all entities from all packages
    the_recaching : [2] int, // not really used as a progress bar
}

// Used to appease the tracking allocator
// + it is, probably, slightly faster
permanent: Allocator



















