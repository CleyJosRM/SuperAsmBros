; >>> INICIO DO ARQUIVO: src/00_mario_main.asm
;========================================================================

; Os modulos sao compilados/concatenados separadamente pelo builder.
; Ordem recomendada:
; 00_mario_main.asm
; 01_mario_physics.asm
; 02_mario_render.asm
; 03_mario_player.asm
; 04_mario_enemies.asm
; 05_mario_blocks.asm
; 06_mario_powerups.asm
; 07_mario_maps.asm
; 08_mario_score.asm
; 98_mario_ram.asm
; 99_mario_rom.asm


main:
    call init_game
    jmp game_loop

init_game:
    push r0
    loadn r0, #1
    store game_active, r0
    store game_level, r0
    loadn r0, #0
    store score, r0
    store coins_collected, r0
    store frame_count, r0
    store game_won, r0
    loadn r0, #3
    store lives, r0
    call map_load_level
    call player_respawn
    pop r0
    rts

game_loop:
    loadn r0, #0
    store player_died_frame, r0
    load r0, invincibility_timer
    loadn r1, #0
    cmp r0, r1
    jeq game_input
    dec r0
    store invincibility_timer, r0
game_input:
    call player_handle_input
    load r0, game_active
    loadn r1, #0
    cmp r0, r1
    jeq end_game
    call physics_apply_gravity
    call physics_update_position
    call check_player_out_of_bounds
    load r0, player_died_frame
    loadn r1, #0
    cmp r0, r1
    jne game_render
    call check_player_hazard
    load r0, player_died_frame
    cmp r0, r1
    jne game_render
    call enemy_update
    call check_player_enemy_collision
    load r0, player_died_frame
    cmp r0, r1
    jne game_render
    call check_player_coin_collision
    call check_player_block_collision
    call check_player_powerup_collision
    call check_level_complete
game_render:
    call camera_follow_player
    call render_frame
    call frame_wait

    load r0, frame_count
    inc r0
    store frame_count, r0
    load r1, game_active
    loadn r2, #1
    cmp r1, r2
    jeq game_loop
    jmp end_game

end_game:
    call show_game_over_screen
    halt

frame_wait:
    push r0
    push r1

    ; Delay de compatibilidade enquanto nao ha timer dedicado.
    ; O valor pode ser recalibrado no FPGA sem alterar o game loop.
    loadn r0, #20000
    loadn r1, #0
frame_wait_loop:
    cmp r1, r0
    jeg frame_wait_done
    inc r1
    jmp frame_wait_loop
frame_wait_done:
    pop r1
    pop r0
    rts

check_player_out_of_bounds:
    push r0
    push r1
    push r2
    
    load r1, player_y
    
    load r2, map_height
    cmp r1, r2
    jle out_of_bounds_ok
    
    call player_die
    
out_of_bounds_ok:
    pop r2
    pop r1
    pop r0
    rts

player_die:
    push r0
    push r1
    push r2
    
    load r0, player_died_frame
    loadn r1, #1
    cmp r0, r1
    jeq player_die_end
    store player_died_frame, r1
    load r0, game_active
    loadn r1, #0
    cmp r0, r1
    jeq player_die_end
    loadn r0, #lives
    load r1, lives
    dec r1
    storei r0, r1
    
    loadn r2, #0
    cmp r1, r2
    jeq player_die_game_over
    
    call player_respawn
    jmp player_die_end
    
player_die_game_over:
    loadn r0, #0
    loadn r1, #game_active
    storei r1, r0
    
player_die_end:
    pop r2
    pop r1
    pop r0
    rts

player_respawn:
    push r0
    push r1
    loadn r0, #5
    store player_x, r0
    store player_prev_x, r0
    load r1, game_level
    loadn r0, #1
    cmp r1, r0
    jne respawn_castle
    loadn r0, #27                
    jmp respawn_y
respawn_castle:
    loadn r0, #24                
respawn_y:
    store player_y, r0
    store player_prev_y, r0
    loadn r0, #0
    store player_vel_x, r0
    store player_vel_y, r0
    store player_vel_x_mag, r0
    store player_vel_y_mag, r0
    store player_vel_y_dir, r0
    store player_run_active, r0
    store camera_x, r0
    store camera_y, r0
    loadn r0, #255
    store last_key, r0
    loadn r0, #1
    store player_on_ground, r0
    store player_facing, r0
    store player_vel_x_dir, r0
    store player_alive, r0
    loadn r0, #20
    store invincibility_timer, r0
    call enemy_init_level
    pop r1
    pop r0
    rts

show_game_over_screen:
    push r0
    push r1
    push r2
    push r3
    
    loadn r0, #' '
    loadn r1, #0
    loadn r2, #1200
    
clear_screen_loop:
    cmp r1, r2
    jeg show_game_over_text
    outchar r0, r1
    inc r1
    jmp clear_screen_loop
    
show_game_over_text:
    loadn r1, #575
    loadn r2, #message_game_over
    load r0, game_won
    loadn r3, #1
    cmp r0, r3
    jne end_message_loop
    loadn r2, #message_victory
end_message_loop:
    loadi r0, r2
    loadn r3, #0
    cmp r0, r3
    jeq end_message_done
    outchar r0, r1
    inc r1
    inc r2
    jmp end_message_loop
end_message_done:
    pop r3
    pop r2
    pop r1
    pop r0
    rts
