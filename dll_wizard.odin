#+build windows
package main

// unfortunately need this here too :( for os.copy
import os "core:os/os2"

import "core:fmt"
import "core:strings"
import "core:path/filepath"

import rl "vendor:raylib"
import "rulti"

just_kinda_deal_with_sdl_dlls :: proc() -> bool {
    Library :: enum { SDL, SDL_TTF, SDL_IMAGE }
    DEPENDENCIES: [3] string = { "SDL2.dll", "SDL2_ttf.dll", "SDL2_image.dll" }
    missing_libs: bit_set [Library] = { }

    alloc := make_arena()
    defer free_all(alloc)

    set_correct_cwd()
    files, ok := list_dir(".", alloc)
    for dep, i in DEPENDENCIES {
        found: bool
        for file in files {
            if strings.ends_with(strings.to_lower(file.name, alloc), strings.to_lower(dep, alloc)) {
                found = true
                break
            }   
        }
        
        if !found { missing_libs += { Library(i) } }
    }

    if missing_libs == {} do return true

    write :: fmt.sbprintfln
    text: strings.Builder
    write(&text, "Unfortunately... You are missing some .dll files:")
    if .SDL       in missing_libs { write(&text, " - SDL (base SDL.dll library)") }
    if .SDL_TTF   in missing_libs { write(&text, " - SDL_ttf (SDL_ttf.dll font loading library") }
    if .SDL_IMAGE in missing_libs { write(&text, " - SDL_image (SDL_image.dll image loading library)") }
    write(&text, "")

    exe_path, _ := os.get_executable_directory(alloc)
    write(&text, "You may simply copy-paste the .dll files from your ODIN ROOT")
    write(&text, " - go to %s\\vendor\\sdl2\\ ", get_odin_root())
    if .SDL       in missing_libs { write(&text, " - copy SDL2.dll             to %s",  exe_path) } 
    if .SDL_TTF   in missing_libs { write(&text, " - copy ttf\\SDL2_ttf.dll     to %s", exe_path) }
    if .SDL_IMAGE in missing_libs { write(&text, " - copy image\\SDL2_image.dll to %s", exe_path) }

    rl.InitWindow(1280, 720, "oi library helper")
    rl.SetTraceLogLevel(.ERROR)
    rl.SetConfigFlags({ .WINDOW_RESIZABLE })
    rl.SetTargetFPS(30)

    font := rulti.LoadFontFromMemory(EMBEDDED_FONTS[1], 20)
    rendered_text: rl.RenderTexture2D
    rulti.DEFAULT_TEXT_OPTIONS.font = font
    rulti.DEFAULT_TEXT_OPTIONS.size = 20
    rulti.DEFAULT_TEXT_OPTIONS.color = transmute(rl.Color) COLORS[.FG1]
    rulti.DEFAULT_TEXT_OPTIONS.center_x = false
    rulti.DEFAULT_TEXT_OPTIONS.center_y = false
    rulti.DEFAULT_TEXT_OPTIONS.selectable = true
    rulti.DEFAULT_TEXT_OPTIONS.highlight = transmute(rl.Color) COLORS[.AQUA2]
    rulti.DEFAULT_TEXT_OPTIONS.spacing = 0

    tried_auto: bool
    success: bit_set [Library]
    errors: [Library] string

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()    
        rl.ClearBackground(transmute(rl.Color) COLORS[.BG1])

        window_size: [2] f32 = { cast(f32) rl.GetScreenWidth(), cast(f32) rl.GetScreenHeight() }
        offset := rulti.DrawTextWrapped(strings.to_string(text), { 8, 8 }, window_size - 8)

        if rulti.selection_in_progress && rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.C) {
            rl.SetClipboardText(strings.clone_to_cstring(rulti.selection))
        }

        {
            button := rulti.DrawTextBasic("Click to copy files automatically", { 8, offset.y + 8 })
            pos  : [2] f32 = { 6, offset.y + 6 }
            size : [2] f32 = button + 4
            rl.DrawRectangleLinesEx({ pos.x, pos.y, size.x, size.y }, 1, transmute(rl.Color) COLORS[.FG1])
            if rl.CheckCollisionPointRec(rl.GetMousePosition(), { pos.x, pos.y, size.x, size.y }) && rl.IsMouseButtonReleased(.LEFT) {
                tried_auto = true

                join :: filepath.join
                sdl := join({ get_odin_root(), "vendor\\sdl2" }, alloc)
                exe := exe_path
                fmt.println(missing_libs)
                if .SDL in missing_libs {
                    src := join({ sdl, "SDL2.dll" }, alloc)
                    dst := join({ exe, "SDL2.dll" }, alloc)
                    err := os.copy_file(dst, src)
                    if err == nil do success += { .SDL }
                    else do errors[.SDL] = fmt.aprint(err, allocator = alloc)
                }
                if .SDL_TTF in missing_libs {
                    src := join({ sdl, "ttf\\SDL2_ttf.dll" }, alloc)
                    dst := join({ exe, "SDL2_ttf.dll" }, alloc)
                    err := os.copy_file(dst, src)
                    if err == nil do success += { .SDL_TTF }
                    else do errors[.SDL_TTF] = fmt.aprint(err, allocator = alloc)
                }
                if .SDL_IMAGE in missing_libs {
                    src := join({ sdl, "image\\SDL2_image.dll" }, alloc)
                    dst := join({ exe, "SDL2_image.dll" }, alloc)
                    err := os.copy_file(dst, src)
                    if err == nil do success += { .SDL_IMAGE }
                    else do errors[.SDL_IMAGE] = fmt.aprint(err, allocator = alloc)
                }
            }
        }

        if tried_auto {
            pos: [2] f32 = { 8, offset.y + 20 + 16 }
            if .SDL not_in success {
                a := rulti.DrawTextBasic("Failed to automatically copy over SDL.dll", pos)
                b := rulti.DrawTextWrapped(errors[.SDL], pos + { 32, a.y }, window_size - 8)
                pos.y += a.y + b.y + 4
            }
            if .SDL_TTF not_in success {
                a := rulti.DrawTextBasic("Failed to automatically copy over ttf\\SDL_ttf.dll", pos)
                b := rulti.DrawTextWrapped(errors[.SDL], pos + { 32, a.y }, window_size - 8)
                pos.y += a.y + b.y + 4
            }
            if .SDL_IMAGE not_in success {
                a := rulti.DrawTextBasic("Failed to automatically copy over image\\SDL_image.dll", pos)
                     rulti.DrawTextWrapped(errors[.SDL], pos + { 32, a.y }, window_size - 8)
            }
            if success == { .SDL, .SDL_TTF, .SDL_IMAGE } {
                rl.EndDrawing()
                rl.UnloadRenderTexture(rendered_text)
                rl.CloseWindow()
                return true
            }
        }

        rulti.DrawTextBasic("(By the way, you can select and copy text here)", { 8, window_size.y - 28 })

        rl.EndDrawing()
    }

    rl.UnloadRenderTexture(rendered_text)
    rl.CloseWindow()
    return false
} 
