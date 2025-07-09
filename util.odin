package main

import "core:fmt"

intersects :: proc(a: Vector, b: Vector, b_size: Vector) -> bool {
    return a.x >= b.x && a.y >= b.y   &&   a.x <= b.x + b_size.x && a.y <= b.y + b_size.y
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

// 

is_identifier_char :: proc(ch: byte) -> bool {
    return (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || ch == '_' || ch == '#' || ch == '@'
}

clone_and_replace_chars :: proc(str: string, from: byte, to: byte, allocator := context.allocator) -> string {
    new_str := fmt.aprint(str, allocator = allocator)
    for i in 0..<len(new_str) {
        if new_str[i] == from do  (transmute([]byte) new_str)[i] = to
    }
    return new_str
}

