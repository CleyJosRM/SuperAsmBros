; >>> INICIO DO ARQUIVO: src/00_mario_main.asm
;========================================================================

; Os modulos sao compilados/concatenados separadamente pelo builder.
# Ordem recomendada:
; 00_mario_main.asm
; 01_mario_physics.asm
; 02_mario_render.asm
; 03_mario_player.asm
; 04_mario_enemies.asm
; 05_mario_blocks.asm
; 06_mario_powerups.asm
; 98_mario_ram.asm
; 99_mario_rom.asm


main:
    call init_game
    jmp game_loop

init_game:
    push r0
    push r1
    push r2

    loadn r0, #1
    loadn r1, #game_active
    storei r1, r0

    loadn r0, #0
    loadn r1, #score
    storei r1, r0
    
    loadn r0, #3
    loadn r1, #lives
    storei r1, r0
    
    loadn r0, #0
    loadn r1, #coins_collected
    storei r1, r0

    loadn r0, #0
    loadn r1, #frame_count
    storei r1, r0

    loadn r0, #5                ; PLAYER_SPAWN_X
    loadn r1, #player_x
    storei r1, r0
    
    loadn r0, #25               ; PLAYER_SPAWN_Y (acima do chão na linha 26)
    loadn r1, #player_y
    storei r1, r0
    
    loadn r0, #0
    loadn r1, #player_vel_x
    storei r1, r0
    
    loadn r0, #0
    loadn r1, #player_vel_y
    storei r1, r0
    
    loadn r0, #1                ; spawn já está sobre o chão da linha 26
    loadn r1, #player_on_ground
    storei r1, r0
    
    loadn r0, #1                ; DIR_RIGHT
    loadn r1, #player_facing
    storei r1, r0

    loadn r0, #0
    loadn r1, #camera_x
    storei r1, r0
    
    loadn r0, #0
    loadn r1, #camera_y
    storei r1, r0

    loadn r0, #35               ; ENEMY_SPAWN_X_WORLD
    loadn r1, #enemy_x
    storei r1, r0
    
    loadn r0, #25               ; ENEMY_SPAWN_Y (acima do chão na linha 26)
    loadn r1, #enemy_y
    storei r1, r0
    
    loadn r0, #0
    loadn r1, #enemy_vel_x
    storei r1, r0
    
    loadn r0, #0
    loadn r1, #enemy_vel_y
    storei r1, r0
    
    loadn r0, #0                ; DIR_LEFT
    loadn r1, #enemy_dir
    storei r1, r0
    
    loadn r0, #1
    loadn r1, #enemy_alive
    storei r1, r0

    loadn r0, #map_data
    loadn r1, #map_ptr
    storei r1, r0

    ; Metadados do mapa: preparados para mapas N x 30.
    loadn r0, #120
    loadn r1, #map_width
    storei r1, r0
    loadn r0, #30
    loadn r1, #map_height
    storei r1, r0
    loadn r0, #121
    loadn r1, #map_stride
    storei r1, r0

    ; Estado de velocidade do inimigo (direcao + magnitude).
    loadn r0, #0
    loadn r1, #enemy_vel_x_dir
    storei r1, r0
    loadn r1, #enemy_vel_y_dir
    storei r1, r0
    loadn r1, #enemy_vel_x_mag
    storei r1, r0
    loadn r1, #enemy_vel_y_mag
    storei r1, r0

    pop r2
    pop r1
    pop r0
    rts

game_loop:
    call player_handle_input
    call physics_apply_gravity
    call physics_update_position
    call enemy_update
    call check_player_enemy_collision
    call check_player_coin_collision
    call check_player_block_collision
    call check_player_out_of_bounds
    call camera_follow_player
    call render_frame
    call frame_wait

    ; Contador global de frames, mantido fora dos modulos de renderizacao.
    load r0, frame_count
    inc r0
    loadn r1, #frame_count
    storei r1, r0
    
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
    dec r2
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
    
    loadn r0, #lives
    load r1, lives
    dec r1
    storei r0, r1
    
    loadn r2, #0
    cmp r1, r2
    jle player_die_game_over
    
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
    
    loadn r0, #5                ; PLAYER_SPAWN_X
    loadn r1, #player_x
    storei r1, r0
    
    loadn r0, #25               ; PLAYER_SPAWN_Y (acima do chão na linha 26)
    loadn r1, #player_y
    storei r1, r0
    
    loadn r0, #0
    loadn r1, #player_vel_x
    storei r1, r0
    
    loadn r0, #0
    loadn r1, #player_vel_y
    storei r1, r0
    
    loadn r0, #1                ; spawn já está sobre o chão da linha 26
    loadn r1, #player_on_ground
    storei r1, r0
    
    pop r1
    pop r0
    rts

show_game_over_screen:
    push r0
    push r1
    push r2
    
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
    loadn r1, #577
    
    loadn r0, #'G'
    outchar r0, r1
    inc r1
    loadn r0, #'A'
    outchar r0, r1
    inc r1
    loadn r0, #'M'
    outchar r0, r1
    inc r1
    loadn r0, #'E'
    outchar r0, r1
    inc r1
    loadn r0, #' '
    outchar r0, r1
    inc r1
    loadn r0, #'O'
    outchar r0, r1
    inc r1
    loadn r0, #'V'
    outchar r0, r1
    inc r1
    loadn r0, #'E'
    outchar r0, r1
    inc r1
    loadn r0, #'R'
    outchar r0, r1
    
    pop r2
    pop r1
    pop r0
    rts

;========================================================================