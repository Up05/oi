package main

import "base:runtime"
import "core:fmt"
import "core:time"
import "core:strings"
import "core:unicode/utf8"

import sdl "vendor:sdl2"
import "vendor:sdl2/ttf"

tick_now  :: time.tick_now
tick_diff :: time.tick_diff
fperf: map [string] time.Duration

/*
    when MEASURE_PERFORMANCE {
        __start := tick_now() 
        defer fperf[#location().procedure] += tick_diff(__start, tick_now())
    }    
*/ 

intersects :: proc(a: Vector, b: Vector, b_size: Vector) -> bool {
    return a.x >= b.x && a.y >= b.y   &&   a.x <= b.x + b_size.x && a.y <= b.y + b_size.y
}

proper_to_rgba :: proc(hex: u32) -> RGBA {
    r : u8 = u8( (hex & 0xFF000000) >> 24 )
    g : u8 = u8( (hex & 0x00FF0000) >> 16 )
    b : u8 = u8( (hex & 0x0000FF00) >>  8 )
    a : u8 = u8( (hex & 0x000000FF) )
    return { r, g, b, a }
}

to_rgba :: proc(hex: string) -> RGBA {
    to_digit :: proc(ch: byte) -> byte {
        return (ch - 'a' + 10) if ch >= 'a' else (ch - 'A' + 10) if ch >= 'A' else ch - '0'
    }

    result: RGBA
    result.r = to_digit(hex[0]) * 16 + to_digit(hex[1])
    result.g = to_digit(hex[2]) * 16 + to_digit(hex[3])
    result.b = to_digit(hex[4]) * 16 + to_digit(hex[5])
    result.a = to_digit(hex[6]) * 16 + to_digit(hex[7])

    return result
}

or_die :: proc(value: $T, error: $E) -> T {
    assert(error == nil)
    return value
}

eat :: proc(value: $T, error: $E) -> T {
    return value
}

is_any :: proc(a: $T, b: ..T) -> bool {
    for possibility in b {
        if a == possibility do return true
    }
    return false
}

is_identifier_char :: proc(ch: byte) -> bool {
    return (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || ch == '_' || ch == '#' || ch == '@'
}

last_rune_size :: proc(bytes: [] byte) -> int {
    _, n := utf8.decode_last_rune_in_bytes(bytes)
    return n
}

clone_and_replace_chars :: proc(str: string, from: byte, to: byte, allocator := context.allocator) -> string {
    new_str := fmt.aprint(str, allocator = allocator)
    for i in 0..<len(new_str) {
        if new_str[i] == from do  (transmute([]byte) new_str)[i] = to
    }
    return new_str
}

corrupt_to_cstr :: proc(str: string) -> (out: cstring, original: byte, original_at: int) {
    // If the segfault points to this function
    // it means the passed string was stack allocated.
    // just don't use this function for whatever you're using it for...
    buf := transmute([] byte) str
    #no_bounds_check original = buf[len(str)]
    #no_bounds_check buf[len(str)] = 0
    return cstring(raw_data(str)), original, len(str)
}

uncorrupt_cstr :: proc(cstr: cstring, original: byte, original_at: int) -> string {
    slice := runtime.Raw_Slice { data = rawptr(cstr), len = original_at }
    #no_bounds_check (transmute([] byte) slice) [original_at] = original
    return transmute(string) slice
}

concat_to_cstr :: proc(strings: ..string) -> cstring {
    buffer_length: int
    for s in strings { buffer_length += len(s) }
    
    buffer := make_slice([] byte, buffer_length + 1)

    pos: int
    for s in strings {
        runtime.mem_copy_non_overlapping(raw_data(buffer[pos:]), raw_data(s), len(s))
        pos += len(s)
    }

    buffer[pos] = 0
    return cstring(raw_data(buffer))
}

// should clone a string if it was allocated on the stack!
// otherwise you will get a silent segfault and be sad
text_to_texture :: proc(text: string, should_clone: bool, font := fonts.regular) -> (texture: Texture, size: Vector) {
    draw_text :: ttf.RenderUTF8_Blended

    if should_clone {
        cstr := strings.clone_to_cstring(text)
        defer delete(cstr)

        text_surface := draw_text(font, cstr, colorscheme[.FG1])
        if text_surface == nil do return nil, {}
        defer sdl.FreeSurface(text_surface)
        return sdl.CreateTextureFromSurface(window.renderer, text_surface), { text_surface.w, text_surface.h } 

    } else {
        cstr, original, original_at := corrupt_to_cstr(text)
        defer uncorrupt_cstr(cstr, original, original_at)
    
        text_surface := draw_text(font, cstr, colorscheme[.FG1])
        if text_surface == nil do return nil, {}
        defer sdl.FreeSurface(text_surface)
        return sdl.CreateTextureFromSurface(window.renderer, text_surface), { text_surface.w, text_surface.h } 
    }
}


