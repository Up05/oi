package main

import "base:runtime"
import "core:fmt"
import "core:reflect"
import "core:strings"
import "core:math"
import "core:time"
import "core:mem"
import "core:mem/virtual"
import "core:unicode/utf8"
import "core:thread"

ThreadPool :: thread.Pool
Task       :: thread.Task
Builder    :: strings.Builder
Allocator  :: mem.Allocator

Tick       :: time.Tick
Duration   :: time.Duration
tick_now   :: time.tick_now
tick_diff  :: time.tick_diff

string_dist :: strings.levenshtein_distance

fperf: map [string] time.Duration

trap :: runtime.debug_trap
cat :: strings.concatenate

start_main_thread_pool :: proc() {
    thread.pool_init(&window.thread_pool, context.allocator, 3) 
    thread.pool_start(&window.thread_pool)
}

do_async :: proc(procedure: thread.Task_Proc, data: rawptr = nil) {
    thread.pool_add_task(&window.thread_pool, context.allocator, procedure, data)
}

// I believe that the most useful feature of Regex is easily the '.*'
// as of right now, odin-lang does not have the "full" regex compiler
// and so this is an implementation of `matches()` with ONLY the '.*'
dotstar :: proc(plaintext, dotstar_regex: string) -> bool {
    A := plaintext
    B := dotstar_regex

    for piece in strings.split_iterator(&B, ".*") {
        cursor := strings.index(A, piece)
        if cursor == -1 do return false

        A = A[cursor + len(piece):]
    }
    
    return true
}

eat :: proc(value: $T, error: $E) -> T {
    return value
}

package_name_from_path :: proc(file: string) -> string {
    file := file
    
    if strings.ends_with(file, ".odin-doc") { 
        file = file[:len(file) - len(".odin-doc")] 
    }
    
    levels := strings.count(file, "@") - 1
    if levels > -1 {
        file = file[strings.last_index(file, "@")+1:]
    }
    
    return file
}

abs_vector :: proc(a: Vector) -> Vector { return { math.abs(a.x), math.abs(a.y) } }
min_vector :: proc(a, b: Vector) -> Vector { return { min(a.x, b.x), min(a.y, b.y) } }
max_vector :: proc(a, b: Vector) -> Vector { return { max(a.x, b.x), max(a.y, b.y) } }
max_abs_vector :: proc(a, b: Vector) -> Vector {
    a2 := abs_vector(a)
    b2 := abs_vector(b)
    return { a.x if a2.x > b2.x else b.x, a.y if a2.y > b2.y else b.y } 
}

get_smoothed_frame_time :: proc() -> Duration {
    a := scale64(cast(i64) frame_time_taken, 0.3)
    b := scale64(cast(i64) other_frame_times, 0.7)
    return cast(Duration) (a + b)
}

// box <-> box collision detection (used for rendering text only when box is visible on screen)
AABB :: proc(a, a_size, b, b_size: Vector) -> bool {
    return  (a.x <= b.x + b_size.x && a.x + a_size.x >= b.x) &&
            (a.y <= b.y + b_size.y && a.y + a_size.y >= b.y)
}

intersects :: proc(a: Vector, b: Vector, b_size: Vector) -> bool {
    return a.x >= b.x && a.y >= b.y   &&   a.x <= b.x + b_size.x && a.y <= b.y + b_size.y
}

scale64 :: proc(x: i64, y: f64) -> i64 {
    return i64(f64(x) * y)
}
scale8 :: proc(x: u8, y: f32) -> u8 {
    return u8(min(f32(x) * y, 255))
}

scale :: proc(x: i32, y: f32) -> i32 {
    return i32(f32(x) * y)
}

scale_vec :: proc(a: [2] i32, b: [2] f32) -> [2] i32 {
    return { scale(a.x, b.x), scale(a.y, b.y) }
}

brighten :: proc(color: Color, percent: f32) -> Color {
    return { scale8(color.r, percent), scale8(color.g, percent), scale8(color.b, percent), color.a }
}

// convert hex to [4] u8 (actually sdl.Color)
rgba :: proc(hex: u32) -> Color {
    r : u8 = u8( (hex & 0xFF000000) >> 24 )
    g : u8 = u8( (hex & 0x00FF0000) >> 16 )
    b : u8 = u8( (hex & 0x0000FF00) >>  8 )
    a : u8 = u8( (hex & 0x000000FF) )
    return { r, g, b, a }
}

// merge two structs (overrides first's non zero members with second's)
// +-------------------------------------------------------------------
// | A := Box { font = .REGULAR, background = .BG4 }
// | B := Box {                  background = .BG1, border = true }
// | C := merge(A, B)
// | assert(C == { font = .REGULAR, background = .BG1, border = true })
// +---
merge :: proc(a: $T, b: T) -> T {
    assert(reflect.is_struct(type_info_of(T)) )
    a, b := a, b

    type_info := reflect.struct_field_types(T)
    offsets   := reflect.struct_field_offsets(T)
    
    for i in 0..<len(offsets) {
        a_member := rawptr(uintptr(&a) + offsets[i])
        b_member := rawptr(uintptr(&b) + offsets[i])
        size := type_info[i].size

        // if !mem.check_zero_ptr(a_member, size) do continue // yes to overriding
        if  mem.check_zero_ptr(b_member, size) do continue
        
        mem.copy(a_member, b_member, size)
    }
    return a
}

set_dynamic_array_length :: proc(array: ^[dynamic] $T, length: int) {
    (transmute(^runtime.Raw_Dynamic_Array) array).len = length
}

last_rune_size :: proc(bytes: [] byte) -> int {
    _, n := utf8.decode_last_rune_in_bytes(bytes)
    return n
}

up_to :: proc(text: string, limit: int) -> string { return text[:min(len(text), limit)] }
cstr :: proc(text: string) -> cstring { return strings.clone_to_cstring(text, context.temp_allocator) }
input_empty :: proc(box: ^Box) -> bool { return len(box.input.buffer.buf) == 0 }

make_arena :: proc() -> Allocator {
    arena := new(virtual.Arena)
    _ = virtual.arena_init_growing(arena)
    return virtual.arena_allocator(arena) 
}


