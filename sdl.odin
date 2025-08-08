package main

import sdl "vendor:sdl2"
import "vendor:sdl2/ttf"
import "vendor:sdl2/image"
import "core:math"
import "core:fmt"

Texture   :: ^sdl.Texture
Surface   :: ^sdl.Surface
Font      :: ^ttf.Font
Window    :: ^sdl.Window
Renderer  :: ^sdl.Renderer
Event     ::  sdl.Event
Color     ::  sdl.Color
Key       ::  sdl.Keycode

destroy_texture :: sdl.DestroyTexture

// =======================================================================================
// ================================ WINDOW SETUP & RESIZE ================================
// =======================================================================================

// {{{

// just for performance
frame_start_time : Tick
frame_time_taken : Duration
other_frame_times : Duration

@(private="file")
next_frame_target: u32
take_break :: proc() {
    now := sdl.GetTicks()
    breaktime := max(next_frame_target - now, 0)
    if breaktime < 1000 do sdl.Delay(breaktime)
}

EMBEDDED_FONTS: [] [] byte = {
    #load("font-regular.ttf"),
    #load("font-monospace.ttf")
}

init_graphics :: proc() {

    assert( sdl.Init(sdl.INIT_VIDEO) >= 0, "Failed to initialize SDL!" )
    assert( sdl.CreateWindowAndRenderer(1280, 720, { .RESIZABLE } | { sdl.WindowFlag.OPENGL } if ODIN_OS != .Darwin else {}, 
            &window.handle, &window.renderer) >= 0, "Failed to start program!" )
    assert( ttf.Init() >= 0, "Failed to get True Type Font support" )

    FONTS[.REGULAR] = load_font(0, CONFIG_FONT_SIZE)
    FONTS[.MONO]    = load_font(1, CONFIG_FONT_SIZE)
    FONTS[.LARGE]   = load_font(0, CONFIG_LARGE_FONT_SIZE)

    sdl.SetRenderDrawBlendMode(window.renderer, .BLEND)
    sdl.SetWindowMinimumSize(window.handle, 600, 200)

    setup_window_icon()
}

poll_events :: proc() {

    event: sdl.Event

    for sdl.PollEvent(&event) {
        #partial switch event.type {
        case .QUIT:         window.should_exit = true
        case .WINDOWEVENT:  if event.window.event == .RESIZED  { handle_resize() }
        case .MOUSEWHEEL:   window.events.scroll = { event.wheel.x, event.wheel.y }
        case .MOUSEBUTTONDOWN: 
            window.events.click = auto_cast event.button.button
            window.pressed      = auto_cast event.button.button
        case .MOUSEBUTTONUP:
            window.pressed = .NONE
        case: 
        }
    }

    sdl.GetMouseState(&window.mouse.x, &window.mouse.y)

    window.events.base = event
}

begin_frame :: proc() {
    sdl.SetRenderDrawColor(window.renderer, 0, 0, 0, 255)
    sdl.RenderClear(window.renderer)
    frame_start_time = tick_now()
    window.onframe = true
}

end_frame :: proc() {
    window.onframe = false
    frame_time_taken = tick_diff(frame_start_time, tick_now())
    other_frame_times = get_smoothed_frame_time()
    debug.box_drawn = 0

    sdl.RenderPresent(window.renderer)
    take_break()
    next_frame_target += (1000 / CONFIG_MAX_FPS)

    window.events = {}
    window.frames += 1
    free_all(context.temp_allocator)
}

handle_resize :: proc() {
    prev_size := window.size
    sdl.GetWindowSize(window.handle, &window.size.x, &window.size.y)

    delta_size := prev_size - window.size
    if math.abs(delta_size.x) > 2 || math.abs(delta_size.y) > 2 {
        window.should_relayout = true
    }
}

// its a mess, but also, just don't look, i guess
@(private="file") packages_done: int
@(private="file") done_packages: [dynamic] string
recache :: proc() {// {{{
    
    do_async(proc(task: Task) {
        cache_everything(&progress_metrics.the_recaching, &done_packages)
    })
    
    mid_frame := window.onframe
    if mid_frame do end_frame()

    Message :: struct { tex: Texture, size: Vector }
    message  : Message
    messages : [dynamic] Message
    
    sum_height :: proc(msgs: [dynamic] Message) -> (height: i32) {
        for m in msgs do height += m.size.y; return
    } 

    message.tex, message.size = render_text("CREATING ODIN PACKAGE CACHE:", .LARGE, .FG2)
    append(&messages, message)

    append(&messages, Message {})

    prev_cache_at_frame := window.frames
    prev_cache_progress := 0

    resume_requested_at := max(int)

    for !window.should_exit {
        poll_events()
        begin_frame()
        defer end_frame()
        if window.should_relayout do update_layout()
        draw_window()
        for i in 0..<10 { pop_box_from_any_queue() }
        progress := progress_metrics.the_recaching

        resume: bool
        resume |= window.frames - prev_cache_at_frame > CONFIG_MAX_FPS * 2
        resume |= progress[0] >= progress[1] 

        draw_rectangle({ 0, 0 }, window.size, .BG3)

        if messages[1].tex != nil { destroy_texture(messages[1].tex) }
        messages[1].tex, messages[1].size = render_text(
            fmt.aprintf("progress: %d / %d", progress[0], progress[1], allocator = context.temp_allocator), 
            .MONO, .FG2)

        for i in packages_done..<len(done_packages) {
            message.tex, message.size = render_text(
                fmt.aprintf("cached %s", done_packages[i], allocator = context.temp_allocator), 
                .MONO, .FG2)
            append(&messages, message)
        }
        packages_done = len(done_packages)

        pos: Vector = { 8, min(8, window.size.y - sum_height(messages)) }
        for msg in messages {
            draw_texture(pos, msg.size, msg.tex)
            pos.y += msg.size.y
        }
        
        if resume && resume_requested_at == max(int) do resume_requested_at = window.frames
        if window.frames - resume_requested_at > CONFIG_MAX_FPS * 4 do break

        if prev_cache_progress != progress[0] do prev_cache_at_frame = window.frames
        prev_cache_progress = progress[0]
    }

    if mid_frame do begin_frame()

    for message in messages {
        destroy_texture(message.tex)
    }
    delete(messages)
    // clear(&done_packages)
    // delete(done_packages)
}// }}}

setup_window_icon :: proc() {
    icon_data := #load("icon.png")
    image_data := sdl.RWFromConstMem(raw_data(icon_data), auto_cast len(icon_data))
    icon := image.Load_RW(image_data, false)
    sdl.SetWindowIcon(window.handle, icon)
}

load_font :: proc(font_index: int, size: i32) -> Font {
    the_font := EMBEDDED_FONTS[font_index]
    font_data := sdl.RWFromConstMem(raw_data(the_font), auto_cast len(the_font))
    return ttf.OpenFontRW(font_data, false, size)
}


// }}}

// =======================================================================================
// ================================   DRAWING    PROCS    ================================
// =======================================================================================

draw_rectangle :: proc(pos, size: Vector, color: Palette) {
    rgba := COLORS[color]
    if color == .TRANSPARENT do return
    sdl.SetRenderDrawColor(window.renderer, rgba.r, rgba.g, rgba.b, rgba.a)
    sdl.RenderFillRect(window.renderer, &{ pos.x, pos.y, size.x, size.y })
}

draw_rectangle_rgba :: proc(pos, size: Vector, color: Color) {
    sdl.SetRenderDrawColor(window.renderer, color.r, color.g, color.b, color.a)
    sdl.RenderFillRect(window.renderer, &{ pos.x, pos.y, size.x, size.y })
}

draw_two_lines_rgba :: proc(pos, size: Vector, color: Color) {
    v2p :: proc(v: Vector) -> sdl.Point { return transmute(sdl.Point) v } 

    sdl.SetRenderDrawColor(window.renderer, color.r, color.g, color.b, color.a)
    pos, size := pos, size-1
    points: [4] sdl.Point = {  v2p(pos), { pos.x + size.x, pos.y }, v2p(pos), { pos.x, pos.y + size.y } }
    sdl.RenderDrawLines(window.renderer, auto_cast &points, len(points))
}

draw_line_rgba :: proc(pos, size: Vector, color: Color) {
    sdl.SetRenderDrawColor(window.renderer, color.r, color.g, color.b, color.a)
    sdl.RenderDrawLine(window.renderer, pos.x, pos.y, size.x, size.y)
}

draw_texture :: proc(pos, size: Vector, texture: Texture) {
    sdl.RenderCopy(window.renderer, texture, &{ 0, 0, size.x, size.y }, &{ pos.x, pos.y, size.x, size.y })
}

render_text :: proc(text: string, font: FontType, color: Palette) -> (t: Texture, size: Vector) {
    if len(text) == 0 do return
    rgba := COLORS[color]
    font := FONTS[font]
    surface := ttf.RenderUTF8_Blended_Wrapped(font, cstr(text), rgba, 0)
    defer sdl.FreeSurface(surface)
    texture := sdl.CreateTextureFromSurface(window.renderer, surface)
    sdl.SetTextureBlendMode(texture, .BLEND)
    return texture, { surface.w, surface.h }
}

render_text_onto :: proc(out: Surface, pos: Vector, text: string, font: FontType, color: Palette) -> (size: Vector) {
    rgba := COLORS[color]
    font := FONTS[font]
    surface := ttf.RenderUTF8_Blended_Wrapped(font, cstr(text), rgba, 0)
    defer sdl.FreeSurface(surface)
    sdl.BlitSurface(surface, &surface.clip_rect, out, &{ pos.x, pos.y, surface.w, surface.h })
    return { surface.w, surface.h }
}

measure_rune_advance :: proc(r: rune, font: FontType) -> int {
    font := FONTS[font]
    minx, maxx, miny, maxy, advance: i32
    glyph := ttf.GlyphMetrics32(font, r, &minx, &maxx, &miny, &maxy, &advance)
    return int(advance)
}

measure_text :: proc(text: string, font: FontType) -> Vector {
    font := FONTS[font]
    width, height: i32
    glyph := ttf.SizeUTF8(font, cstr(text), &width, &height)
    lines: i32 = 1
    for i in 0..<len(text) {
        if text[i] == '\n' do lines += 1
    }
    return { width, height * lines }
}

set_clip_area :: proc(pos: Vector, size: Vector) {
    sdl.RenderSetClipRect(window.renderer, &{ pos.x, pos.y, size.x, size.y })
}

get_clip_area_size :: proc() -> Vector {
    rect: sdl.Rect
    sdl.RenderGetClipRect(window.renderer, &rect)
    return { rect.w, rect.h }
}

unset_clip_area :: proc() {
    sdl.RenderSetClipRect(window.renderer, nil)
} 

handle_premultiplied_alpha_compositing :: proc(texture: Texture) {
    sdl.SetTextureBlendMode(
        texture, 
        sdl.ComposeCustomBlendMode(.ONE, .ONE_MINUS_SRC_ALPHA, .ADD, .ONE, .ONE_MINUS_SRC_ALPHA, .ADD)
        //                       src rgb ->  dest rgb                src a  ->  dest a
    )
}

copy :: proc(text: string) {
    sdl.SetClipboardText(cstr(text))
}



// =======================================================================================
// =================================      DEBUGGING       ================================
// =======================================================================================

print_valid_texture_formats :: proc() {

    info: sdl.RendererInfo
    sdl.GetRendererInfo(window.renderer, &info)
    fmt.println(info)
    fmt.println("[DEBUG] Valid SDL Texture Formats: ")
    for format in info.texture_formats {
        if format == 0 do continue
        fmt.println("[DEBUG]   ", sdl.GetPixelFormatName(format))
    }
}


