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

; >>> INICIO DO ARQUIVO: src/01_mario_physics.asm
;========================================================================
;
; MODULE: Mario Physics Engine
;
; Objetivos deste modulo:
;   1. Posicao do player sempre limitada pelo mapa (N x 30).
;   2. Movimento horizontal sem overflow/"teleporte" em colisao.
;   3. Movimento vertical discreto, um tile por frame, evitando atravessar
;      plataformas quando a magnitude da velocidade for grande.
;   4. Gravidade com estado explicito: 0=baixo, 1=cima.
;   5. Ao cair atraves de um buraco ate a ultima linha do mapa, o player
;      recebe Y=map_height e o modulo main/out-of-bounds trata a morte.
;   6. Nenhum literal negativo e necessario.
;
; Convencao usada pelas variaveis de fisica:
;   player_vel_x_dir = 0 esquerda, 1 direita
;   player_vel_x_mag = magnitude solicitada pelo input
;   player_vel_y_dir = 0 descendo, 1 subindo
;   player_vel_y_mag = estado/magnitude vertical
;   player_vel_x/y    = valores assinados de compatibilidade.
;
; IMPORTANTE:
;========================================================================

;------------------------------------------------------------------------
; physics_apply_gravity
;
; Chamado uma vez por frame ANTES de physics_update_position.
;
; Regra:
;   grounded -> velocidade vertical zerada.
;   subindo  -> reduz magnitude; ao chegar a 0 inicia queda.
;   descendo -> aumenta magnitude ate MAX_FALL_SPEED.
;------------------------------------------------------------------------
physics_apply_gravity:
    push r0
    push r1
    push r2

    load r0, player_on_ground
    loadn r1, #1
    cmp r0, r1
    jeq physics_gravity_grounded

    load r0, player_vel_y_dir
    load r1, player_vel_y_mag
    loadn r2, #1
    cmp r0, r2
    jeq physics_gravity_up

    ; =============================== DOWN ===============================
    ; Aumenta a magnitude de queda em 1 por frame, limitada a 4.
    ; O deslocamento real sera no maximo 1 tile/frame.
    loadn r2, #1
    add r1, r1, r2
    loadn r2, #4
    cmp r1, r2
    jel physics_gravity_store_down
    mov r1, r2

physics_gravity_store_down:
    loadn r0, #player_vel_y_dir
    loadn r2, #0
    storei r0, r2
    loadn r0, #player_vel_y_mag
    storei r0, r1

    ; Compatibilidade: player_vel_y = +mag em queda.
    loadn r0, #player_vel_y
    storei r0, r1
    jmp physics_gravity_done

    ; ================================ UP ================================
physics_gravity_up:
    ; Reduz a magnitude em 1. Ao chegar a zero, troca para queda.
    loadn r2, #1
    cmp r1, r2
    jel physics_gravity_apex

    sub r1, r1, r2
    loadn r0, #player_vel_y_mag
    storei r0, r1

    ; Compatibilidade: player_vel_y = -(magnitude).
    loadn r0, #player_vel_y
    loadn r2, #0
    sub r2, r2, r1
    storei r0, r2
    jmp physics_gravity_done

physics_gravity_apex:
    loadn r0, #player_vel_y_dir
    loadn r2, #0
    storei r0, r2

    loadn r0, #player_vel_y_mag
    loadn r1, #1
    storei r0, r1

    loadn r0, #player_vel_y
    storei r0, r1
    jmp physics_gravity_done

physics_gravity_grounded:
    loadn r0, #player_vel_y_dir
    loadn r1, #0
    storei r0, r1

    loadn r0, #player_vel_y_mag
    storei r0, r1

    loadn r0, #player_vel_y
    storei r0, r1

physics_gravity_done:
    pop r2
    pop r1
    pop r0
    rts

;------------------------------------------------------------------------
; physics_update_position
;
; Atualiza a posicao do jogador em dois eixos.
;
; Vertical:
;   - no maximo 1 tile por frame;
;   - verifica o tile de destino ANTES de mover;
;   - ao bater por baixo: interrompe o pulo e inicia queda;
;   - ao pousar: grounded=1 e velocidade vertical=0;
;   - se cair para alem da ultima linha: player_y=map_height, permitindo
;     que check_player_out_of_bounds, no main, execute player_die.
;
; Horizontal:
;   - cada eixo verifica colisao antes do deslocamento;
;   - colisao mantem a coordenada original (NAO corrige adicionando/sub-
;     traindo novamente).
;------------------------------------------------------------------------
physics_update_position:
    push r0
    push r1
    push r2
    push r3
    push r4
    push r5

    load r0, player_x
    store player_prev_x, r0
    load r0, player_y
    store player_prev_y, r0

    ; =========================== VERTICAL ===============================
    load r1, player_y
    load r3, player_vel_y_mag
    load r4, player_vel_y_dir

    ; --------------------------------------------------------------------
    ; Caso especial: o player estava apoiado, mas pode ter saído da borda
    ; de uma plataforma durante o movimento horizontal. O estado
    ; grounded nao pode permanecer em 1 se o tile abaixo estiver livre.
    ; --------------------------------------------------------------------
    load r5, player_on_ground
    loadn r0, #1
    cmp r5, r0
    jne physics_vertical_has_velocity

    ; Se Y+1 estiver fora do mapa ou solido, continua grounded.
    mov r0, r1
    inc r0
    load r5, player_x
    mov r2, r5
    mov r5, r0
    mov r0, r2
    mov r1, r5
    call physics_check_collision_tile

    loadn r5, #1
    cmp r2, r5
    jeq physics_vertical_done

    ; Borda da plataforma: inicia queda imediatamente.
    loadn r0, #player_on_ground
    loadn r5, #0
    storei r0, r5
    loadn r0, #player_vel_y_dir
    storei r0, r5
    loadn r0, #player_vel_y_mag
    loadn r3, #1
    storei r0, r3
    loadn r0, #player_vel_y
    storei r0, r3

    load r1, player_y
    load r3, player_vel_y_mag
    load r4, player_vel_y_dir

physics_vertical_has_velocity:
    loadn r5, #0
    cmp r3, r5
    jeq physics_vertical_done

    loadn r5, #1
    cmp r4, r5
    jeq physics_vertical_up

; ------------------------------ DOWN ------------------------------------
physics_vertical_down:
    ; Se ja esta na ultima linha, proximo movimento significa queda fora
    ; do mapa. Sinaliza isso com Y=map_height para o main matar o player.
    load r5, map_height
    dec r5
    cmp r1, r5
    jgr physics_vertical_out
    jeq physics_down_last_row

    ; Destino = Y + 1.
    mov r4, r1
    inc r4
    load r0, player_x
    mov r5, r4
    mov r1, r5
    call physics_check_collision_tile

    loadn r5, #1
    cmp r2, r5
    jeq physics_land_from_down

    ; Tile livre: move exatamente 1 tile neste frame.
    mov r1, r4
    jmp physics_vertical_store_air_down

physics_down_last_row:
    ; Chegar na ultima linha so e possivel atraves de um buraco, pois um
    ; tile solido nessa linha seria detectado como colisao antes do passo.
    load r5, map_height
    mov r1, r5
    jmp physics_vertical_out_state

physics_vertical_out:
    ; Ja esta fora do mapa.
    load r5, map_height
    mov r1, r5
    jmp physics_vertical_out_state

physics_vertical_out_state:
    loadn r0, #player_on_ground
    loadn r5, #0
    storei r0, r5
    loadn r0, #player_vel_y_dir
    storei r0, r5
    loadn r0, #player_vel_y_mag
    storei r0, r5
    loadn r0, #player_vel_y
    storei r0, r5
    jmp physics_vertical_store_position

physics_vertical_store_air_down:
    ; Ainda no ar. Consome apenas um passo da magnitude.
    loadn r5, #1
    cmp r3, r5
    jel physics_down_zero_velocity
    sub r3, r3, r5

    loadn r0, #player_vel_y_mag
    storei r0, r3
    loadn r0, #player_on_ground
    loadn r5, #0
    storei r0, r5
    jmp physics_vertical_store_position

physics_down_zero_velocity:
    loadn r0, #player_vel_y_mag
    loadn r5, #0
    storei r0, r5
    loadn r0, #player_on_ground
    storei r0, r5
    jmp physics_vertical_store_position

physics_land_from_down:
    ; O player permanece exatamente na celula acima do tile solido.
    mov r1, r4    ; r1 recebe destino colidido (Y+1)
    dec r1        ; r1 = (Y+1) - 1 = Y
    loadn r0, #player_vel_y_dir
    loadn r5, #0
    storei r0, r5
    loadn r0, #player_vel_y_mag
    storei r0, r5
    loadn r0, #player_vel_y
    storei r0, r5
    loadn r0, #player_on_ground
    loadn r5, #1
    storei r0, r5
    jmp physics_vertical_store_position

; ------------------------------- UP -------------------------------------
physics_vertical_up:
    ; Nao permite Y menor que 0.
    loadn r5, #0
    cmp r1, r5
    jel physics_hit_ceiling

    ; Destino = Y - 1.
    mov r4, r1
    dec r4
    load r0, player_x
    mov r5, r4
    mov r1, r5
    call physics_check_collision_tile

    loadn r5, #1
    cmp r2, r5
    jeq physics_hit_ceiling

    mov r1, r4

    ; Consome um passo do impulso de subida.
    loadn r5, #1
    cmp r3, r5
    jel physics_up_zero_velocity
    sub r3, r3, r5

    loadn r0, #player_vel_y_mag
    storei r0, r3
    loadn r0, #player_on_ground
    loadn r5, #0
    storei r0, r5
    jmp physics_vertical_store_position

physics_up_zero_velocity:
    ; Se a magnitude zerar neste frame, a proxima chamada de gravidade
    ; colocara o player em queda com magnitude 1.
    loadn r0, #player_vel_y_mag
    loadn r5, #0
    storei r0, r5
    loadn r0, #player_on_ground
    storei r0, r5
    jmp physics_vertical_store_position

physics_hit_ceiling:
    load r0, player_x
    load r1, player_y
    loadn r5, #0
    cmp r1, r5
    jeq physics_ceiling_restore
    dec r1
    call block_hit_from_below
physics_ceiling_restore:
    load r1, player_y
    ; Bater no teto encerra a subida. O player permanece na posicao atual.
    loadn r0, #player_vel_y_dir
    loadn r5, #0
    storei r0, r5
    loadn r0, #player_vel_y_mag
    storei r0, r5
    loadn r0, #player_vel_y
    storei r0, r5
    loadn r0, #player_on_ground
    storei r0, r5

physics_vertical_store_position:
    loadn r0, #player_y
    storei r0, r1

physics_vertical_done:
    ; =========================== HORIZONTAL ============================
    load r0, player_x
    load r1, player_y
    call map_read_tile
    call map_tile_class
    loadn r5, #2
    cmp r2, r5
    jeq physics_horizontal_done
    load r3, player_vel_x_mag
    loadn r5, #2
    cmp r3, r5
    jel physics_horizontal_step
    mov r3, r5
physics_horizontal_step:
    loadn r5, #0
    cmp r3, r5
    jeq physics_horizontal_done
    load r1, player_x
    load r4, player_vel_x_dir
    loadn r5, #1
    cmp r4, r5
    jeq physics_horizontal_right
physics_horizontal_left:
    loadn r5, #0
    cmp r1, r5
    jeq physics_horizontal_blocked
    mov r4, r1
    dec r4
    jmp physics_horizontal_test
physics_horizontal_right:
    load r5, map_width
    dec r5
    cmp r1, r5
    jeg physics_horizontal_blocked
    mov r4, r1
    inc r4
physics_horizontal_test:
    mov r0, r4
    load r1, player_y
    call physics_check_collision_tile
    loadn r5, #1
    cmp r2, r5
    jeq physics_horizontal_blocked
    store player_x, r4
    call check_player_coin_collision
    call check_player_powerup_collision
    call map_read_tile
    call map_tile_class
    loadn r5, #2
    cmp r2, r5
    jeq physics_horizontal_done
    dec r3
    jmp physics_horizontal_step
physics_horizontal_blocked:
physics_horizontal_done:
    loadn r5, #0
    store player_vel_x_mag, r5
    store player_vel_x, r5
    load r0, player_vel_y_dir
    loadn r5, #1
    cmp r0, r5
    jeq physics_position_done
    call player_check_ground
physics_position_done:
    pop r5
    pop r4
    pop r3
    pop r2
    pop r1
    pop r0
    rts

;------------------------------------------------------------------------
; physics_check_collision_tile
;
; Entrada:  r0 = X, r1 = Y
; Retorno:  r2 = 1 se solido, 0 se livre
;
; Fora do mapa e tratado como solido para impedir movimento invalido.
; IMPORTANTE: esta rotina NAO altera r0/r1 observaveis pelo chamador,
; exceto registradores temporarios protegidos internamente.
;------------------------------------------------------------------------
physics_check_collision_tile:
    push r0
    push r1
    push r3
    push r4
    push r5

    ; Fora da largura -> bloqueado.
    load r4, map_width
    cmp r0, r4
    jeg physics_collision_solid

    ; Fora da altura inferior -> bloqueado.
    load r4, map_height
    cmp r1, r4
    jeg physics_collision_solid

    call map_read_tile
    call map_tile_class
    loadn r4, #1
    cmp r2, r4
    jeq physics_collision_solid
    loadn r2, #0
    jmp physics_collision_done

physics_collision_solid:
    loadn r2, #1

physics_collision_done:
    pop r5
    pop r4
    pop r3
    pop r1
    pop r0
    rts

;========================================================================
; FIM DO MODULO 01_mario_physics
;========================================================================

; >>> INICIO DO ARQUIVO: src/02_mario_render.asm
;========================================================================

;════════════════════════════════════════════════════════════
; MODULE: Mario Render Engine
;════════════════════════════════════════════════════════════

render_frame:
    push r0
    push r1
    push r2

    ; O mapa ja pinta os espacos: nao ha clear_screen separado.
    ; Isso reduz o frame a um unico percurso 40x30.
    call render_background
    call render_player
    call render_enemy
    call render_hud

    pop r2
    pop r1
    pop r0
    rts

; -----------------------------------------------------------------------
; Renderer V12
; - Nunca usa div/mod por tile.
; - Percorre 30 linhas x 40 colunas com ponteiros incrementais.
; - camera_x aponta para a janela do mapa; map_width pode ser N > 40.
; -----------------------------------------------------------------------
render_background:
    push r0
    push r1
    push r2
    push r3
    push r4
    push r5

    ; r2 = ponteiro para o primeiro tile visivel.
    ; Suporta camera_x e camera_y sem div/mod no loop.
    load r2, map_ptr
    load r3, camera_y
    load r0, map_stride
    mul r3, r3, r0
    add r2, r2, r3
    load r3, camera_x
    add r2, r2, r3
    loadn r3, #render_row_ptr
    storei r3, r2

    ; r4 = linhas restantes; r5 = indice da tela.
    loadn r4, #30
    loadn r5, #0

render_bg_row:
    ; r0 = contador de colunas; r1 = x mundial atual.
    loadn r0, #40
    load r1, camera_x

render_bg_col:
    load r3, map_width
    cmp r1, r3
    jeg render_bg_blank

    loadi r3, r2
    outchar r3, r5
    inc r2
    jmp render_bg_next

render_bg_blank:
    loadn r3, #' '
    outchar r3, r5

render_bg_next:
    inc r1
    inc r5
    dec r0
    loadn r3, #0
    cmp r0, r3
    jgr render_bg_col

    ; Avanca para a proxima linha do mapa.
    ; O ponteiro da linha e preservado para que a largura da janela (40)
    load r2, render_row_ptr
    load r3, map_stride
    add r2, r2, r3
    loadn r3, #render_row_ptr
    storei r3, r2
    dec r4
    loadn r3, #0
    cmp r4, r3
    jgr render_bg_row

    pop r5
    pop r4
    pop r3
    pop r2
    pop r1
    pop r0
    rts

render_player:
    push r0
    push r1
    push r2
    push r3

    load r2, player_x
    load r3, camera_x
    cmp r2, r3
    jeq render_player_x_ok
    jle render_player_skip
render_player_x_ok:
    sub r2, r2, r3
    loadn r3, #40
    cmp r2, r3
    jeg render_player_skip

    load r3, player_y
    load r1, camera_y
    cmp r3, r1
    jeq render_player_y_ok
    jle render_player_skip
render_player_y_ok:
    sub r3, r3, r1
    loadn r1, #30
    cmp r3, r1
    jeg render_player_skip

    loadn r1, #40
    mul r1, r3, r1
    add r1, r1, r2
    load r0, player_facing
    loadn r2, #0
    cmp r0, r2
    jeq render_player_sprite
    loadn r2, #80               
render_player_sprite:
    loadn r0, #Characters       
    add r0, r0, r2
    loadi r0, r0
    outchar r0, r1

render_player_skip:
    pop r3
    pop r2
    pop r1
    pop r0
    rts

render_enemy:
    push r0
    push r1
    loadn r0, #0
    store enemy_index, r0
render_enemies_loop:
    load r0, enemy_index
    load r1, enemy_count
    cmp r0, r1
    jeg render_enemies_done
    call enemy_load_slot
    call render_enemy_one
    load r0, enemy_index
    inc r0
    store enemy_index, r0
    jmp render_enemies_loop
render_enemies_done:
    pop r1
    pop r0
    rts

render_enemy_one:
    push r0
    push r1
    push r2
    push r3

    load r0, enemy_alive
    loadn r1, #1
    cmp r0, r1
    jne render_enemy_skip

    load r2, enemy_x
    load r3, camera_x
    cmp r2, r3
    jeq render_enemy_x_ok
    jle render_enemy_skip
render_enemy_x_ok:
    sub r2, r2, r3
    loadn r3, #40
    cmp r2, r3
    jeg render_enemy_skip

    load r3, enemy_y
    load r1, camera_y
    cmp r3, r1
    jeq render_enemy_y_ok
    jle render_enemy_skip
render_enemy_y_ok:
    sub r3, r3, r1
    loadn r1, #30
    cmp r3, r1
    jeg render_enemy_skip

    loadn r1, #40
    mul r1, r3, r1
    add r1, r1, r2
    load r0, enemy_type
    loadn r3, #0
    loadn r2, #2                
    cmp r0, r3
    jeq render_enemy_sprite
    loadn r3, #3
    loadn r2, #10               
    cmp r0, r3
    jeq render_enemy_sprite
    loadn r2, #4                
    loadn r3, #1
    cmp r0, r3
    jeq render_enemy_direction
    loadn r2, #8                
render_enemy_direction:
    load r0, enemy_dir
    loadn r3, #0
    cmp r0, r3
    jeq render_enemy_sprite
    loadn r3, #80               
    add r2, r2, r3
render_enemy_sprite:
    loadn r0, #Characters
    add r0, r0, r2
    loadi r0, r0
    outchar r0, r1

render_enemy_skip:
    pop r3
    pop r2
    pop r1
    pop r0
    rts

render_hud:
    push r0
    push r1
    push r2

    loadn r1, #0
    loadn r0, #'S'
    outchar r0, r1
    inc r1
    loadn r0, #'C'
    outchar r0, r1
    inc r1
    loadn r0, #'O'
    outchar r0, r1
    inc r1
    loadn r0, #'R'
    outchar r0, r1
    inc r1
    loadn r0, #'E'
    outchar r0, r1
    inc r1
    loadn r0, #':'
    outchar r0, r1
    inc r1
    load r0, score
    loadn r1, #10
    loadn r2, #5
    call render_number

    loadn r1, #15
    loadn r0, #'L'
    outchar r0, r1
    inc r1
    loadn r0, #'I'
    outchar r0, r1
    inc r1
    loadn r0, #'V'
    outchar r0, r1
    inc r1
    loadn r0, #'E'
    outchar r0, r1
    inc r1
    loadn r0, #'S'
    outchar r0, r1
    inc r1
    loadn r0, #':'
    outchar r0, r1
    load r0, lives
    loadn r1, #21
    loadn r2, #1
    call render_number
    loadn r1, #28
    loadn r0, #'F'
    outchar r0, r1
    inc r1
    loadn r0, #':'
    outchar r0, r1
    loadn r1, #30
    load r0, game_level
    call render_number
render_hud_done:
    pop r2
    pop r1
    pop r0
    rts

render_number:
    push r0
    push r1
    push r2
    push r3
    push r4
render_number_loop:
    loadn r3, #10
    mod r4, r0, r3
    div r0, r0, r3
    loadn r3, #'0'
    add r4, r4, r3
    outchar r4, r1
    dec r1
    dec r2
    loadn r3, #0
    cmp r2, r3
    jne render_number_loop
    pop r4
    pop r3
    pop r2
    pop r1
    pop r0
    rts

camera_follow_player:
    push r0
    push r1
    push r2
    push r3

    ; Mapas <= 40 tiles nao fazem scroll.
    load r0, map_width
    loadn r1, #40
    cmp r0, r1
    jle camera_zero

    ; Mantem Mario por volta da coluna 20 quando houver espaco.
    load r2, player_x
    loadn r3, #20
    cmp r2, r3
    jle camera_zero
    sub r2, r2, r3

    ; max_camera = map_width - 40
    loadn r3, #40
    sub r0, r0, r3
    cmp r2, r0
    jle camera_store
    mov r2, r0

camera_store:
    loadn r0, #camera_x
    storei r0, r2
    jmp camera_done

camera_zero:
    loadn r0, #camera_x
    loadn r2, #0
    storei r0, r2

camera_done:
    ; camera_y reservado para futura rolagem vertical.
    loadn r0, #camera_y
    loadn r2, #0
    storei r0, r2

    pop r3
    pop r2
    pop r1
    pop r0
    rts

;========================================================================
; >>> INICIO DO ARQUIVO: src/03_mario_player.asm
;========================================================================
; MODULE: Mario Player Control V12.2
; Responsabilidades:
;   - Ler o teclado sem deixar velocidade residual.
;   - Configurar direção/magnitude horizontal.
;   - Iniciar salto somente quando grounded.
;   - Permitir salto enquanto modo corrida estiver ativo.
;   - Manter compatibilidade com o solver físico.
;
; Observação sobre CORRIDA:
; O periférico inchar fornece uma tecla por leitura. Portanto não é possível
; distinguir simultaneamente "corrida segurada" + "W" com a interface atual.
; Para manter a mecânica disponível, 's' funciona como TOGGLE de corrida.
; Pressione 's' uma vez para ativar e novamente para desativar.
; O pulo ('w') nunca é bloqueado pelo estado de corrida.
;========================================================================

player_handle_input:
    push r0
    push r1
    push r2
    push r3

    ; Cada frame começa sem deslocamento horizontal residual.
    loadn r0, #0
    loadn r1, #player_vel_x
    storei r1, r0
    loadn r1, #player_vel_x_mag
    storei r1, r0

    inchar r0
    load r3, last_key
    store last_key, r0

    loadn r1, #255
    cmp r0, r1
    jeq input_done

    loadn r1, #'q'
    cmp r0, r1
    jeq player_input_quit

    loadn r1, #'a'
    cmp r0, r1
    jeq player_input_left

    loadn r1, #'d'
    cmp r0, r1
    jeq player_input_right

    loadn r1, #'w'
    cmp r0, r1
    jeq player_input_jump

    jmp input_done

player_input_quit:
    loadn r0, #0
    loadn r1, #game_active
    storei r1, r0
    jmp input_done

player_input_left:
    call player_move_left
    jmp input_done

player_input_right:
    call player_move_right
    jmp input_done

player_input_jump:
    ; Corrida NÃO impede o pulo.
    call player_attempt_jump
    jmp input_done

input_done:
    pop r3
    pop r2
    pop r1
    pop r0
    rts

;-----------------------------------------------------------------------
; Movimento para a esquerda.
; Velocidade normal = 1 tile/frame.
; Corrida ativa = 2 tiles/frame.
;-----------------------------------------------------------------------
player_move_left:
    push r0
    push r1
    push r2

    loadn r0, #0
    loadn r1, #player_vel_x_dir
    storei r1, r0

player_left_normal:
    loadn r0, #1
    jmp player_left_store_mag

player_left_store_mag:
    loadn r1, #player_vel_x_mag
    storei r1, r0

    ; Compatibilidade: player_vel_x guarda magnitude negativa.
    loadn r1, #player_vel_x
    loadn r2, #0
    sub r2, r2, r0
    storei r1, r2

    loadn r0, #0
    loadn r1, #player_facing
    storei r1, r0

    pop r2
    pop r1
    pop r0
    rts

;-----------------------------------------------------------------------
; Movimento para a direita.
; Velocidade normal = 1 tile/frame.
; Corrida ativa = 2 tiles/frame.
;-----------------------------------------------------------------------
player_move_right:
    push r0
    push r1

    loadn r0, #1
    loadn r1, #player_vel_x_dir
    storei r1, r0

player_right_normal:
    loadn r0, #1
    jmp player_right_store_mag

player_right_store_mag:
    loadn r1, #player_vel_x_mag
    storei r1, r0

    ; Compatibilidade: player_vel_x guarda magnitude positiva.
    loadn r1, #player_vel_x
    storei r1, r0

    loadn r0, #1
    loadn r1, #player_facing
    storei r1, r0

    pop r1
    pop r0
    rts

;-----------------------------------------------------------------------
; Salto.
; O estado de corrida não participa da decisão.
;-----------------------------------------------------------------------
player_attempt_jump:
    push r0
    push r1
    push r2

    load r0, player_on_ground
    loadn r1, #1
    cmp r0, r1
    jne jump_not_allowed

    ; Direção vertical: 1 = cima.
    loadn r0, #1
    loadn r1, #player_vel_y_dir
    storei r1, r0

    ; Magnitude inicial do salto.
    loadn r0, #15
    loadn r1, #player_vel_y_mag
    storei r1, r0

    ; Compatibilidade: player_vel_y = -12.
    loadn r1, #player_vel_y
    loadn r2, #0
    sub r2, r2, r0
    storei r1, r2

    ; Sai do estado grounded imediatamente.
    loadn r0, #0
    loadn r1, #player_on_ground
    storei r1, r0

jump_not_allowed:
    pop r2
    pop r1
    pop r0
    rts

;-----------------------------------------------------------------------
; Atualiza grounded consultando o solver físico.
; physics_check_collision_tile retorna r2=1 sólido / r2=0 livre.
;-----------------------------------------------------------------------
player_check_ground:
    push r0
    push r1
    push r2

    load r0, player_x
    load r1, player_y
    inc r1
    load r2, map_height
    cmp r1, r2
    jeg player_ground_missing
    call physics_check_collision_tile
    jmp player_ground_store
player_ground_missing:
    loadn r2, #0
player_ground_store:
    loadn r0, #player_on_ground
    storei r0, r2

    pop r2
    pop r1
    pop r0
    rts

;========================================================================
; MODULE: Mario Enemies

enemy_init_level:
    push r0
    push r1
    push r2
    push r3
    push r4
    push r5
    loadn r0, #enemy_spawns_1
    load r1, game_level
    loadn r2, #1
    cmp r1, r2
    jeq enemy_init_source
    loadn r0, #enemy_spawns_2
enemy_init_source:
    loadn r1, #enemy_list
    loadn r3, #6
    store enemy_count, r3
enemy_init_record:
    loadn r4, #5
    mov r5, r0
enemy_init_field:
    loadi r2, r0
    storei r1, r2
    inc r0
    inc r1
    dec r4
    loadn r2, #0
    cmp r4, r2
    jne enemy_init_field
    loadi r2, r5
    storei r1, r2               
    inc r1
    inc r5
    loadi r2, r5
    storei r1, r2               
    inc r1
    dec r3
    loadn r2, #0
    cmp r3, r2
    jne enemy_init_record
    pop r5
    pop r4
    pop r3
    pop r2
    pop r1
    pop r0
    rts

enemy_update:
    push r0
    push r1
    push r2
    loadn r0, #0
    store enemy_index, r0
enemy_update_loop:
    load r0, enemy_index
    load r1, enemy_count
    cmp r0, r1
    jeg enemy_update_done
    call enemy_load_slot
    load r0, enemy_x
    store enemy_prev_x, r0
    load r0, enemy_y
    store enemy_prev_y, r0
    load r0, enemy_alive
    loadn r1, #0
    cmp r0, r1
    jeq enemy_update_next
    load r0, enemy_x
    load r1, camera_x
    cmp r0, r1
    jle enemy_update_next
    loadn r2, #40
    add r1, r1, r2
    cmp r0, r1
    jeg enemy_update_next
    load r0, enemy_type
    loadn r1, #3
    cmp r0, r1
    jeq enemy_update_next       
    call enemy_patrol
    call enemy_apply_gravity
    call enemy_update_position
    call enemy_check_ground
enemy_update_next:
    call enemy_store_slot
    load r0, enemy_index
    inc r0
    store enemy_index, r0
    jmp enemy_update_loop
enemy_update_done:
    pop r2
    pop r1
    pop r0
    rts

enemy_apply_gravity:
    push r0
    loadn r0, #0
    store enemy_vel_y_dir, r0
    loadn r0, #1
    store enemy_vel_y_mag, r0
    store enemy_vel_y, r0
    pop r0
    rts

enemy_patrol:
    push r0
    push r1
    load r0, enemy_dir
    store enemy_vel_x_dir, r0
    load r0, frame_count
    loadn r1, #4
    mod r0, r0, r1
    loadn r1, #0
    cmp r0, r1
    jne enemy_patrol_wait
    loadn r0, #1
    jmp enemy_patrol_store
enemy_patrol_wait:
    loadn r0, #0
enemy_patrol_store:
    store enemy_vel_x_mag, r0
    store enemy_vel_x, r0
    pop r1
    pop r0
    rts

enemy_update_position:
    push r0
    push r1
    push r2
    push r3
    push r4
    load r1, enemy_y
    inc r1
    load r3, map_height
    cmp r1, r3
    jeg enemy_fall_out
    load r0, enemy_x
    call physics_check_collision_tile
    loadn r3, #1
    cmp r2, r3
    jeq enemy_land
    store enemy_y, r1           
    call map_read_tile
    call map_tile_class
    loadn r3, #2
    cmp r2, r3
    jeq enemy_fall_out
    jmp enemy_vertical_done
enemy_land:
    loadn r0, #0
    store enemy_vel_y_mag, r0
    store enemy_vel_y, r0
enemy_vertical_done:
    load r3, enemy_vel_x_mag
    loadn r4, #0
    cmp r3, r4
    jeq enemy_position_done     
    load r0, enemy_x
    load r4, enemy_dir
    loadn r3, #1
    cmp r4, r3
    jeq enemy_go_right
    loadn r3, #0
    cmp r0, r3
    jeq enemy_turn_right
    dec r0
    jmp enemy_test_x
enemy_go_right:
    load r3, map_width
    dec r3
    cmp r0, r3
    jeg enemy_turn_left
    inc r0
enemy_test_x:
    load r1, enemy_y
    call physics_check_collision_tile
    loadn r3, #1
    cmp r2, r3
    jeq enemy_x_blocked
    store enemy_x, r0           
    call map_read_tile
    call map_tile_class
    loadn r3, #2
    cmp r2, r3
    jeq enemy_fall_out
    jmp enemy_position_done
enemy_x_blocked:
    loadn r3, #0
    cmp r4, r3
    jeq enemy_turn_right
enemy_turn_left:
    loadn r0, #0
    store enemy_dir, r0
    jmp enemy_position_done
enemy_turn_right:
    loadn r0, #1
    store enemy_dir, r0
    jmp enemy_position_done
enemy_fall_out:
    loadn r0, #0
    store enemy_alive, r0
enemy_position_done:
    pop r4
    pop r3
    pop r2
    pop r1
    pop r0
    rts

enemy_check_ground:
    rts

check_player_enemy_collision:
    push r0
    push r1
    load r0, invincibility_timer
    loadn r1, #0
    cmp r0, r1
    jne enemy_collision_all_done
    loadn r0, #0
    store enemy_index, r0
enemy_collision_loop:
    load r0, enemy_index
    load r1, enemy_count
    cmp r0, r1
    jeg enemy_collision_all_done
    call enemy_load_slot
    call enemy_check_contact
    load r0, player_died_frame
    loadn r1, #0
    cmp r0, r1
    jne enemy_collision_all_done
    call enemy_store_slot
    load r0, enemy_index
    inc r0
    store enemy_index, r0
    jmp enemy_collision_loop
enemy_collision_all_done:
    pop r1
    pop r0
    rts

enemy_check_contact:
    push r0
    push r1
    push r2
    push r3
    push r4
    load r0, enemy_alive
    loadn r1, #1
    cmp r0, r1
    jne enemy_contact_done
    load r0, player_y
    load r1, enemy_y
    cmp r0, r1
    jne enemy_contact_done
    load r0, player_prev_x
    load r1, player_x
    cmp r0, r1
    jel enemy_player_interval
    mov r4, r0
    mov r0, r1
    mov r1, r4
enemy_player_interval:
    load r2, enemy_prev_x
    load r3, enemy_x
    cmp r2, r3
    jel enemy_intervals_ready
    mov r4, r2
    mov r2, r3
    mov r3, r4
enemy_intervals_ready:
    cmp r1, r2
    jle enemy_contact_done
    cmp r3, r0
    jle enemy_contact_done
    load r0, player_prev_y
    load r1, enemy_prev_y
    cmp r0, r1
    jeg player_enemy_kill_player
    load r0, player_vel_y_dir
    loadn r1, #0
    cmp r0, r1
    jne player_enemy_kill_player
    load r0, enemy_type
    loadn r1, #2
    cmp r0, r1
    jeg player_enemy_kill_player 
    loadn r0, #0
    store enemy_alive, r0
    store player_on_ground, r0
    loadn r0, #1
    store player_vel_y_dir, r0
    loadn r0, #6
    store player_vel_y_mag, r0
    loadn r1, #0
    sub r1, r1, r0
    store player_vel_y, r1
    load r0, score
    loadn r1, #500
    add r0, r0, r1
    store score, r0
    jmp enemy_contact_done
player_enemy_kill_player:
    call player_die
enemy_contact_done:
    pop r4
    pop r3
    pop r2
    pop r1
    pop r0
    rts

enemy_load_slot:
    push r0
    push r1
    push r2
    loadn r1, #7
    mul r1, r0, r1
    loadn r2, #enemy_list
    add r1, r1, r2
    store enemy_current_ptr, r1
    loadi r2, r1
    store enemy_x, r2
    inc r1
    loadi r2, r1
    store enemy_y, r2
    inc r1
    loadi r2, r1
    store enemy_dir, r2
    inc r1
    loadi r2, r1
    store enemy_alive, r2
    inc r1
    loadi r2, r1
    store enemy_type, r2
    inc r1
    loadi r2, r1
    store enemy_prev_x, r2
    inc r1
    loadi r2, r1
    store enemy_prev_y, r2
    pop r2
    pop r1
    pop r0
    rts

enemy_store_slot:
    push r1
    push r2
    load r1, enemy_current_ptr
    load r2, enemy_x
    storei r1, r2
    inc r1
    load r2, enemy_y
    storei r1, r2
    inc r1
    load r2, enemy_dir
    storei r1, r2
    inc r1
    load r2, enemy_alive
    storei r1, r2
    inc r1
    load r2, enemy_type
    storei r1, r2
    inc r1
    load r2, enemy_prev_x
    storei r1, r2
    inc r1
    load r2, enemy_prev_y
    storei r1, r2
    pop r2
    pop r1
    rts

; MODULE: Mario Blocks

check_player_coin_collision:
    push r0
    push r1
    push r2
    push r3
    load r0, player_x
    load r1, player_y
    call map_read_tile
    loadn r3, #256
    mod r2, r2, r3
    loadn r3, #'$'
    cmp r2, r3
    jne coin_no_collision
    call map_clear_player_tile
    call block_add_coin
coin_no_collision:
    pop r3
    pop r2
    pop r1
    pop r0
    rts

check_player_block_collision:
    rts

block_hit_from_below:
    push r0
    push r1
    push r2
    push r3
    push r4
    call map_read_tile
    loadn r3, #256
    mod r2, r2, r3
    loadn r3, #2                
    cmp r2, r3
    jne block_hit_done
    load r3, map_stride
    mul r3, r1, r3
    add r3, r3, r0
    load r4, map_ptr
    add r3, r3, r4
    loadn r2, #263              
    storei r3, r2
    call block_add_coin
block_hit_done:
    pop r4
    pop r3
    pop r2
    pop r1
    pop r0
    rts

block_add_coin:
    push r0
    push r1
    load r0, coins_collected
    inc r0
    store coins_collected, r0
    load r0, score
    loadn r1, #100
    add r0, r0, r1
    store score, r0
    pop r1
    pop r0
    rts

map_clear_player_tile:
    push r0
    push r1
    push r2
    load r0, player_x
    load r1, player_y
    load r2, map_width
    cmp r0, r2
    jeg map_clear_done
    load r2, map_height
    cmp r1, r2
    jeg map_clear_done
    load r2, map_stride
    mul r1, r1, r2
    add r1, r1, r0
    load r0, map_ptr
    add r1, r1, r0
    loadn r0, #127
    storei r1, r0
map_clear_done:
    pop r2
    pop r1
    pop r0
    rts

; MODULE: Mario Power-ups
check_player_powerup_collision:
    push r0
    push r1
    push r2
    load r0, player_x
    load r1, player_y
    call map_read_tile
    loadn r0, #256
    mod r2, r2, r0
    loadn r0, #'*'
    cmp r2, r0
    jne powerup_no_collision
    call map_clear_player_tile
    load r0, score
    loadn r1, #500
    add r0, r0, r1
    store score, r0
powerup_no_collision:
    pop r2
    pop r1
    pop r0
    rts

powerup_give_extra_life:
    push r0
    load r0, lives
    inc r0
    store lives, r0
    pop r0
    rts


map_load_level:
    push r0
    push r1
    push r2
    push r3
    push r4
    push r5
    push r6
    push r7

    loadn r0, #map_data
    store map_ptr, r0
    loadn r0, #120
    store map_width, r0
    store map_stride, r0
    loadn r0, #30
    store map_height, r0
    loadn r0, #0
    store camera_x, r0
    store camera_y, r0

    load r0, game_level
    dec r0
    loadn r1, #3
    mul r0, r0, r1
    loadn r6, #level_map_table
    add r6, r6, r0
    loadn r7, #0
map_load_page:
    loadi r0, r6                 
    loadn r1, #map_data
    loadn r2, #40
    mul r2, r7, r2
    add r1, r1, r2               
    loadn r3, #30
map_load_row:
    loadn r4, #40
map_load_cell:
    loadi r5, r0
    storei r1, r5
    inc r0
    inc r1
    dec r4
    loadn r2, #0
    cmp r4, r2
    jne map_load_cell
    loadn r2, #80                
    add r1, r1, r2
    dec r3
    loadn r2, #0
    cmp r3, r2
    jne map_load_row
    inc r6
    inc r7
    loadn r2, #3
    cmp r7, r2
    jle map_load_page

    pop r7
    pop r6
    pop r5
    pop r4
    pop r3
    pop r2
    pop r1
    pop r0
    rts

map_read_tile:
    push r3
    push r4
    loadn r2, #127
    load r3, map_width
    cmp r0, r3
    jeg map_read_done
    load r3, map_height
    cmp r1, r3
    jeg map_read_done
    load r3, map_stride
    mul r3, r1, r3
    add r3, r3, r0
    load r4, map_ptr
    add r3, r3, r4
    loadi r2, r3
map_read_done:
    pop r4
    pop r3
    rts

map_tile_class:
    push r3
    loadn r3, #256
    mod r2, r2, r3
    loadn r3, #128
    cmp r2, r3
    jeg map_class_free
    loadn r3, #tile_classes
    add r3, r3, r2
    loadi r2, r3
    jmp map_class_done
map_class_free:
    loadn r2, #0
map_class_done:
    pop r3
    rts

check_player_hazard:
    push r0
    push r1
    push r2
    load r0, player_x
    load r1, player_y
    call map_read_tile
    call map_tile_class
    loadn r0, #2
    cmp r2, r0
    jne map_hazard_done
    call player_die
map_hazard_done:
    pop r2
    pop r1
    pop r0
    rts

check_level_complete:
    push r0
    push r1
    load r0, game_level
    loadn r1, #1
    cmp r0, r1
    jne map_check_axe
    load r0, player_x
    loadn r1, #111
    cmp r0, r1
    jle map_level_done
map_check_flag_y:
    load r0, player_y
    loadn r1, #26
    cmp r0, r1
    jgr map_level_done
    loadn r0, #2
    store game_level, r0
    call map_load_level
    call player_respawn
    jmp map_level_done
map_check_axe:
    load r0, player_x
    loadn r1, #114
    cmp r0, r1
    jle map_level_done
map_check_axe_y:
    load r0, player_y
    loadn r1, #20
    cmp r0, r1
    jgr map_level_done
    loadn r0, #1
    store game_won, r0
    loadn r0, #0
    store game_active, r0
map_level_done:
    pop r1
    pop r0
    rts

; >>> INICIO DO ARQUIVO: data/98_mario_ram.asm
;========================================================================

;════════════════════════════════════════════════════════════
; MARIO RAM (Variáveis Globais)
; 
; Estas variáveis mudam durante a execução do jogo
;════════════════════════════════════════════════════════════

;════════════════════════════════════════════════════════════
; ESTADO DO JOGO
;════════════════════════════════════════════════════════════

game_active:        var #1          ; 1 = jogando, 0 = parado
game_paused:        var #1          ; 1 = pausado, 0 = rodando
game_level:         var #1          ; Nível atual (1, 2, 3...)
current_screen:     var #1          ; Tela atual (menu, playing, game_over)

;════════════════════════════════════════════════════════════
; MARIO - POSIÇÃO E MOVIMENTO
;════════════════════════════════════════════════════════════

player_x:           var #1          ; Posição X no mundo (0-map_width-1)
player_y:           var #1          ; Posição Y (0-29)
player_vel_x:       var #1          ; Velocidade X (-1, 0, +1, +2)
player_vel_y:       var #1          ; compatibilidade: velocidade Y
player_vel_x_dir:   var #1          ; 0=esquerda, 1=direita
player_vel_x_mag:   var #1          ; magnitude horizontal
player_vel_y_dir:   var #1          ; 0=baixo, 1=cima
player_vel_y_mag:   var #1          ; magnitude vertical
player_on_ground:   var #1          ; 1 = no chão, 0 = no ar
player_facing:      var #1          ; 0 = left, 1 = right
player_alive:       var #1          ; 1 = vivo, 0 = morto

;════════════════════════════════════════════════════════════
; MARIO - ANIMAÇÃO
;════════════════════════════════════════════════════════════

player_anim_frame:  var #1          ; Frame da animação (0-3)
player_anim_timer:  var #1          ; Contador de frames para animação

;════════════════════════════════════════════════════════════
; INIMIGOS - Posição e Movimento
;════════════════════════════════════════════════════════════

enemy_x:            var #1          ; Posição X
enemy_y:            var #1          ; Posição Y
enemy_vel_x:        var #1          ; Velocidade X (compatibilidade)
enemy_vel_y:        var #1          ; Velocidade Y (compatibilidade)
enemy_vel_x_dir:    var #1          ; 0=esquerda, 1=direita
enemy_vel_x_mag:    var #1          ; magnitude horizontal
enemy_vel_y_dir:    var #1          ; 0=baixo, 1=cima
enemy_vel_y_mag:    var #1          ; magnitude vertical
enemy_dir:          var #1          ; Direção (0=left, 1=right)
enemy_alive:        var #1          ; 1 = vivo, 0 = morto
enemy_type:         var #1          ; Tipo (0=goomba, 1=koopa, etc)

;════════════════════════════════════════════════════════════
; CÂMERA
;════════════════════════════════════════════════════════════

camera_x:           var #1          ; Posição X da câmera (scroll horizontal)
camera_y:           var #1          ; Posição Y da câmera (scroll vertical, geralmente 0)
camera_target_x:    var #1          ; Alvo de câmera (smooth follow)

;════════════════════════════════════════════════════════════
; MAPA
;════════════════════════════════════════════════════════════

map_ptr:            var #1          ; Ponteiro para dados do mapa atual
map_width:          var #1          ; Largura do mapa em tiles (N)
map_height:         var #1          ; Altura do mapa em tiles (30)
map_stride:         var #1          

;════════════════════════════════════════════════════════════
; PLACAR E VIDAS
;════════════════════════════════════════════════════════════

score:              var #1          ; Placar total
lives:              var #1          ; Vidas restantes (0-9)
coins_collected:    var #1          ; Moedas coletadas neste nível

;════════════════════════════════════════════════════════════
; FLAGS E CONTADORES
;════════════════════════════════════════════════════════════

invincibility_timer: var #1         ; Contador de invencibilidade após hit
jump_timer:         var #1          ; Contador para duração do pulo (não usado agora)
input_cooldown:     var #1          ; Debounce de input (evitar repetição rápida)
frame_count:        var #1          ; Contador global de frames

;════════════════════════════════════════════════════════════
; CACHE DE VALORES (para otimização)
;════════════════════════════════════════════════════════════

last_key:           var #1          ; Última tecla pressionada
is_solid_cache:     var #1          ; Cache de último tile verificado
render_row_ptr:     var #1          ; Ponteiro da linha corrente do mapa durante render

;════════════════════════════════════════════════════════════
; FIM DO ARQUIVO RAM
;════════════════════════════════════════════════════════════

;========================================================================
game_won:          var #1
player_died_frame: var #1
player_prev_x:     var #1
player_prev_y:     var #1
enemy_prev_x:      var #1
enemy_prev_y:      var #1
enemy_count:       var #1
enemy_index:       var #1
enemy_current_ptr: var #1
enemy_list:        var #42
map_data:          var #3600


level_map_table: var #6
    static level_map_table + #0, #Nivel11
    static level_map_table + #1, #Nivel12
    static level_map_table + #2, #Nivel13
    static level_map_table + #3, #NivelFinal1
    static level_map_table + #4, #NivelFinal2
    static level_map_table + #5, #NivelFinal3

tile_classes: var #128
    static tile_classes + #0, #1
    static tile_classes + #1, #1
    static tile_classes + #2, #1
    static tile_classes + #3, #1
    static tile_classes + #4, #1
    static tile_classes + #5, #1
    static tile_classes + #7, #1
    static tile_classes + #14, #1
    static tile_classes + #17, #1
    static tile_classes + #18, #1
    static tile_classes + #21, #1
    static tile_classes + #35, #1
    static tile_classes + #61, #1
    static tile_classes + #15, #2
    static tile_classes + #16, #2

enemy_spawns_1: var #30
    static enemy_spawns_1 + #0, #21
    static enemy_spawns_1 + #1, #27
    static enemy_spawns_1 + #2, #0
    static enemy_spawns_1 + #3, #1
    static enemy_spawns_1 + #4, #0
    static enemy_spawns_1 + #5, #35
    static enemy_spawns_1 + #6, #27
    static enemy_spawns_1 + #7, #0
    static enemy_spawns_1 + #8, #1
    static enemy_spawns_1 + #9, #0
    static enemy_spawns_1 + #10, #52
    static enemy_spawns_1 + #11, #27
    static enemy_spawns_1 + #12, #0
    static enemy_spawns_1 + #13, #1
    static enemy_spawns_1 + #14, #1
    static enemy_spawns_1 + #15, #70
    static enemy_spawns_1 + #16, #23
    static enemy_spawns_1 + #17, #0
    static enemy_spawns_1 + #18, #1
    static enemy_spawns_1 + #19, #3
    static enemy_spawns_1 + #20, #81
    static enemy_spawns_1 + #21, #27
    static enemy_spawns_1 + #22, #1
    static enemy_spawns_1 + #23, #1
    static enemy_spawns_1 + #24, #0
    static enemy_spawns_1 + #25, #87
    static enemy_spawns_1 + #26, #23
    static enemy_spawns_1 + #27, #0
    static enemy_spawns_1 + #28, #1
    static enemy_spawns_1 + #29, #1

enemy_spawns_2: var #30
    static enemy_spawns_2 + #0, #24
    static enemy_spawns_2 + #1, #24
    static enemy_spawns_2 + #2, #0
    static enemy_spawns_2 + #3, #1
    static enemy_spawns_2 + #4, #2
    static enemy_spawns_2 + #5, #31
    static enemy_spawns_2 + #6, #22
    static enemy_spawns_2 + #7, #0
    static enemy_spawns_2 + #8, #1
    static enemy_spawns_2 + #9, #3
    static enemy_spawns_2 + #10, #49
    static enemy_spawns_2 + #11, #24
    static enemy_spawns_2 + #12, #0
    static enemy_spawns_2 + #13, #1
    static enemy_spawns_2 + #14, #2
    static enemy_spawns_2 + #15, #66
    static enemy_spawns_2 + #16, #20
    static enemy_spawns_2 + #17, #0
    static enemy_spawns_2 + #18, #1
    static enemy_spawns_2 + #19, #3
    static enemy_spawns_2 + #20, #90
    static enemy_spawns_2 + #21, #24
    static enemy_spawns_2 + #22, #0
    static enemy_spawns_2 + #23, #1
    static enemy_spawns_2 + #24, #2
    static enemy_spawns_2 + #25, #105
    static enemy_spawns_2 + #26, #21
    static enemy_spawns_2 + #27, #0
    static enemy_spawns_2 + #28, #1
    static enemy_spawns_2 + #29, #2

message_game_over: string "GAME OVER"
message_victory:   string "VOCE VENCEU!"


Nivel11 : var #1200
  ;Linha 0
  static Nivel11 + #0, #1798
  static Nivel11 + #1, #1798
  static Nivel11 + #2, #1798
  static Nivel11 + #3, #1798
  static Nivel11 + #4, #1798
  static Nivel11 + #5, #1798
  static Nivel11 + #6, #1798
  static Nivel11 + #7, #1798
  static Nivel11 + #8, #1798
  static Nivel11 + #9, #1798
  static Nivel11 + #10, #1798
  static Nivel11 + #11, #127
  static Nivel11 + #12, #127
  static Nivel11 + #13, #127
  static Nivel11 + #14, #127
  static Nivel11 + #15, #127
  static Nivel11 + #16, #127
  static Nivel11 + #17, #127
  static Nivel11 + #18, #127
  static Nivel11 + #19, #127
  static Nivel11 + #20, #1798
  static Nivel11 + #21, #1798
  static Nivel11 + #22, #1798
  static Nivel11 + #23, #1798
  static Nivel11 + #24, #1798
  static Nivel11 + #25, #127
  static Nivel11 + #26, #127
  static Nivel11 + #27, #127
  static Nivel11 + #28, #127
  static Nivel11 + #29, #127
  static Nivel11 + #30, #127
  static Nivel11 + #31, #127
  static Nivel11 + #32, #1798
  static Nivel11 + #33, #1798
  static Nivel11 + #34, #1798
  static Nivel11 + #35, #1798
  static Nivel11 + #36, #1798
  static Nivel11 + #37, #1798
  static Nivel11 + #38, #1798
  static Nivel11 + #39, #1798

  ;Linha 1
  static Nivel11 + #40, #1798
  static Nivel11 + #41, #1798
  static Nivel11 + #42, #1798
  static Nivel11 + #43, #1798
  static Nivel11 + #44, #1798
  static Nivel11 + #45, #1798
  static Nivel11 + #46, #1798
  static Nivel11 + #47, #1798
  static Nivel11 + #48, #127
  static Nivel11 + #49, #127
  static Nivel11 + #50, #127
  static Nivel11 + #51, #127
  static Nivel11 + #52, #127
  static Nivel11 + #53, #127
  static Nivel11 + #54, #127
  static Nivel11 + #55, #127
  static Nivel11 + #56, #127
  static Nivel11 + #57, #127
  static Nivel11 + #58, #1798
  static Nivel11 + #59, #1798
  static Nivel11 + #60, #1798
  static Nivel11 + #61, #1798
  static Nivel11 + #62, #1798
  static Nivel11 + #63, #1798
  static Nivel11 + #64, #1798
  static Nivel11 + #65, #1798
  static Nivel11 + #66, #1798
  static Nivel11 + #67, #127
  static Nivel11 + #68, #127
  static Nivel11 + #69, #127
  static Nivel11 + #70, #127
  static Nivel11 + #71, #127
  static Nivel11 + #72, #127
  static Nivel11 + #73, #127
  static Nivel11 + #74, #1798
  static Nivel11 + #75, #1798
  static Nivel11 + #76, #1798
  static Nivel11 + #77, #1798
  static Nivel11 + #78, #127
  static Nivel11 + #79, #127

  ;Linha 2
  static Nivel11 + #80, #1798
  static Nivel11 + #81, #1798
  static Nivel11 + #82, #1798
  static Nivel11 + #83, #1798
  static Nivel11 + #84, #1798
  static Nivel11 + #85, #127
  static Nivel11 + #86, #127
  static Nivel11 + #87, #127
  static Nivel11 + #88, #127
  static Nivel11 + #89, #127
  static Nivel11 + #90, #127
  static Nivel11 + #91, #127
  static Nivel11 + #92, #127
  static Nivel11 + #93, #127
  static Nivel11 + #94, #127
  static Nivel11 + #95, #127
  static Nivel11 + #96, #127
  static Nivel11 + #97, #1798
  static Nivel11 + #98, #1798
  static Nivel11 + #99, #1798
  static Nivel11 + #100, #1798
  static Nivel11 + #101, #1798
  static Nivel11 + #102, #1798
  static Nivel11 + #103, #1798
  static Nivel11 + #104, #1798
  static Nivel11 + #105, #1798
  static Nivel11 + #106, #1798
  static Nivel11 + #107, #1798
  static Nivel11 + #108, #127
  static Nivel11 + #109, #127
  static Nivel11 + #110, #127
  static Nivel11 + #111, #127
  static Nivel11 + #112, #127
  static Nivel11 + #113, #127
  static Nivel11 + #114, #127
  static Nivel11 + #115, #127
  static Nivel11 + #116, #127
  static Nivel11 + #117, #127
  static Nivel11 + #118, #127
  static Nivel11 + #119, #127

  ;Linha 3
  static Nivel11 + #120, #127
  static Nivel11 + #121, #1798
  static Nivel11 + #122, #1798
  static Nivel11 + #123, #1798
  static Nivel11 + #124, #127
  static Nivel11 + #125, #127
  static Nivel11 + #126, #127
  static Nivel11 + #127, #127
  static Nivel11 + #128, #127
  static Nivel11 + #129, #127
  static Nivel11 + #130, #127
  static Nivel11 + #131, #127
  static Nivel11 + #132, #127
  static Nivel11 + #133, #127
  static Nivel11 + #134, #127
  static Nivel11 + #135, #127
  static Nivel11 + #136, #127
  static Nivel11 + #137, #127
  static Nivel11 + #138, #1798
  static Nivel11 + #139, #1798
  static Nivel11 + #140, #1798
  static Nivel11 + #141, #1798
  static Nivel11 + #142, #1798
  static Nivel11 + #143, #1798
  static Nivel11 + #144, #1798
  static Nivel11 + #145, #1798
  static Nivel11 + #146, #1798
  static Nivel11 + #147, #127
  static Nivel11 + #148, #127
  static Nivel11 + #149, #127
  static Nivel11 + #150, #127
  static Nivel11 + #151, #127
  static Nivel11 + #152, #127
  static Nivel11 + #153, #127
  static Nivel11 + #154, #127
  static Nivel11 + #155, #127
  static Nivel11 + #156, #127
  static Nivel11 + #157, #127
  static Nivel11 + #158, #127
  static Nivel11 + #159, #127

  ;Linha 4
  static Nivel11 + #160, #127
  static Nivel11 + #161, #127
  static Nivel11 + #162, #127
  static Nivel11 + #163, #127
  static Nivel11 + #164, #127
  static Nivel11 + #165, #127
  static Nivel11 + #166, #127
  static Nivel11 + #167, #127
  static Nivel11 + #168, #127
  static Nivel11 + #169, #127
  static Nivel11 + #170, #127
  static Nivel11 + #171, #127
  static Nivel11 + #172, #127
  static Nivel11 + #173, #127
  static Nivel11 + #174, #127
  static Nivel11 + #175, #127
  static Nivel11 + #176, #127
  static Nivel11 + #177, #127
  static Nivel11 + #178, #3967
  static Nivel11 + #179, #1798
  static Nivel11 + #180, #1798
  static Nivel11 + #181, #1798
  static Nivel11 + #182, #1798
  static Nivel11 + #183, #1798
  static Nivel11 + #184, #1798
  static Nivel11 + #185, #1798
  static Nivel11 + #186, #127
  static Nivel11 + #187, #127
  static Nivel11 + #188, #127
  static Nivel11 + #189, #127
  static Nivel11 + #190, #127
  static Nivel11 + #191, #127
  static Nivel11 + #192, #127
  static Nivel11 + #193, #127
  static Nivel11 + #194, #127
  static Nivel11 + #195, #127
  static Nivel11 + #196, #127
  static Nivel11 + #197, #127
  static Nivel11 + #198, #127
  static Nivel11 + #199, #127

  ;Linha 5
  static Nivel11 + #200, #127
  static Nivel11 + #201, #127
  static Nivel11 + #202, #127
  static Nivel11 + #203, #127
  static Nivel11 + #204, #127
  static Nivel11 + #205, #127
  static Nivel11 + #206, #127
  static Nivel11 + #207, #127
  static Nivel11 + #208, #127
  static Nivel11 + #209, #127
  static Nivel11 + #210, #127
  static Nivel11 + #211, #127
  static Nivel11 + #212, #127
  static Nivel11 + #213, #127
  static Nivel11 + #214, #127
  static Nivel11 + #215, #127
  static Nivel11 + #216, #127
  static Nivel11 + #217, #127
  static Nivel11 + #218, #3967
  static Nivel11 + #219, #3967
  static Nivel11 + #220, #3967
  static Nivel11 + #221, #3967
  static Nivel11 + #222, #3967
  static Nivel11 + #223, #3967
  static Nivel11 + #224, #3967
  static Nivel11 + #225, #127
  static Nivel11 + #226, #127
  static Nivel11 + #227, #127
  static Nivel11 + #228, #127
  static Nivel11 + #229, #127
  static Nivel11 + #230, #127
  static Nivel11 + #231, #127
  static Nivel11 + #232, #127
  static Nivel11 + #233, #127
  static Nivel11 + #234, #127
  static Nivel11 + #235, #127
  static Nivel11 + #236, #127
  static Nivel11 + #237, #127
  static Nivel11 + #238, #127
  static Nivel11 + #239, #127

  ;Linha 6
  static Nivel11 + #240, #127
  static Nivel11 + #241, #127
  static Nivel11 + #242, #127
  static Nivel11 + #243, #127
  static Nivel11 + #244, #127
  static Nivel11 + #245, #127
  static Nivel11 + #246, #127
  static Nivel11 + #247, #127
  static Nivel11 + #248, #127
  static Nivel11 + #249, #127
  static Nivel11 + #250, #127
  static Nivel11 + #251, #127
  static Nivel11 + #252, #127
  static Nivel11 + #253, #127
  static Nivel11 + #254, #127
  static Nivel11 + #255, #127
  static Nivel11 + #256, #127
  static Nivel11 + #257, #127
  static Nivel11 + #258, #127
  static Nivel11 + #259, #127
  static Nivel11 + #260, #127
  static Nivel11 + #261, #127
  static Nivel11 + #262, #127
  static Nivel11 + #263, #127
  static Nivel11 + #264, #127
  static Nivel11 + #265, #127
  static Nivel11 + #266, #127
  static Nivel11 + #267, #127
  static Nivel11 + #268, #127
  static Nivel11 + #269, #127
  static Nivel11 + #270, #127
  static Nivel11 + #271, #127
  static Nivel11 + #272, #127
  static Nivel11 + #273, #127
  static Nivel11 + #274, #127
  static Nivel11 + #275, #127
  static Nivel11 + #276, #127
  static Nivel11 + #277, #127
  static Nivel11 + #278, #127
  static Nivel11 + #279, #127

  ;Linha 7
  static Nivel11 + #280, #127
  static Nivel11 + #281, #127
  static Nivel11 + #282, #127
  static Nivel11 + #283, #127
  static Nivel11 + #284, #127
  static Nivel11 + #285, #127
  static Nivel11 + #286, #127
  static Nivel11 + #287, #127
  static Nivel11 + #288, #127
  static Nivel11 + #289, #127
  static Nivel11 + #290, #127
  static Nivel11 + #291, #127
  static Nivel11 + #292, #127
  static Nivel11 + #293, #127
  static Nivel11 + #294, #127
  static Nivel11 + #295, #127
  static Nivel11 + #296, #127
  static Nivel11 + #297, #127
  static Nivel11 + #298, #127
  static Nivel11 + #299, #127
  static Nivel11 + #300, #127
  static Nivel11 + #301, #127
  static Nivel11 + #302, #127
  static Nivel11 + #303, #127
  static Nivel11 + #304, #127
  static Nivel11 + #305, #127
  static Nivel11 + #306, #127
  static Nivel11 + #307, #127
  static Nivel11 + #308, #127
  static Nivel11 + #309, #127
  static Nivel11 + #310, #127
  static Nivel11 + #311, #127
  static Nivel11 + #312, #127
  static Nivel11 + #313, #127
  static Nivel11 + #314, #127
  static Nivel11 + #315, #127
  static Nivel11 + #316, #127
  static Nivel11 + #317, #127
  static Nivel11 + #318, #127
  static Nivel11 + #319, #127

  ;Linha 8
  static Nivel11 + #320, #127
  static Nivel11 + #321, #127
  static Nivel11 + #322, #127
  static Nivel11 + #323, #127
  static Nivel11 + #324, #127
  static Nivel11 + #325, #127
  static Nivel11 + #326, #127
  static Nivel11 + #327, #127
  static Nivel11 + #328, #127
  static Nivel11 + #329, #127
  static Nivel11 + #330, #127
  static Nivel11 + #331, #127
  static Nivel11 + #332, #127
  static Nivel11 + #333, #127
  static Nivel11 + #334, #127
  static Nivel11 + #335, #127
  static Nivel11 + #336, #127
  static Nivel11 + #337, #127
  static Nivel11 + #338, #127
  static Nivel11 + #339, #127
  static Nivel11 + #340, #127
  static Nivel11 + #341, #127
  static Nivel11 + #342, #127
  static Nivel11 + #343, #127
  static Nivel11 + #344, #127
  static Nivel11 + #345, #127
  static Nivel11 + #346, #127
  static Nivel11 + #347, #127
  static Nivel11 + #348, #127
  static Nivel11 + #349, #127
  static Nivel11 + #350, #127
  static Nivel11 + #351, #127
  static Nivel11 + #352, #127
  static Nivel11 + #353, #127
  static Nivel11 + #354, #127
  static Nivel11 + #355, #127
  static Nivel11 + #356, #127
  static Nivel11 + #357, #127
  static Nivel11 + #358, #127
  static Nivel11 + #359, #127

  ;Linha 9
  static Nivel11 + #360, #127
  static Nivel11 + #361, #127
  static Nivel11 + #362, #127
  static Nivel11 + #363, #127
  static Nivel11 + #364, #127
  static Nivel11 + #365, #127
  static Nivel11 + #366, #127
  static Nivel11 + #367, #127
  static Nivel11 + #368, #127
  static Nivel11 + #369, #127
  static Nivel11 + #370, #127
  static Nivel11 + #371, #127
  static Nivel11 + #372, #127
  static Nivel11 + #373, #127
  static Nivel11 + #374, #127
  static Nivel11 + #375, #127
  static Nivel11 + #376, #127
  static Nivel11 + #377, #127
  static Nivel11 + #378, #127
  static Nivel11 + #379, #127
  static Nivel11 + #380, #127
  static Nivel11 + #381, #127
  static Nivel11 + #382, #127
  static Nivel11 + #383, #127
  static Nivel11 + #384, #127
  static Nivel11 + #385, #127
  static Nivel11 + #386, #127
  static Nivel11 + #387, #127
  static Nivel11 + #388, #127
  static Nivel11 + #389, #127
  static Nivel11 + #390, #127
  static Nivel11 + #391, #127
  static Nivel11 + #392, #127
  static Nivel11 + #393, #127
  static Nivel11 + #394, #127
  static Nivel11 + #395, #127
  static Nivel11 + #396, #127
  static Nivel11 + #397, #127
  static Nivel11 + #398, #127
  static Nivel11 + #399, #127

  ;Linha 10
  static Nivel11 + #400, #127
  static Nivel11 + #401, #127
  static Nivel11 + #402, #127
  static Nivel11 + #403, #127
  static Nivel11 + #404, #127
  static Nivel11 + #405, #127
  static Nivel11 + #406, #127
  static Nivel11 + #407, #127
  static Nivel11 + #408, #127
  static Nivel11 + #409, #127
  static Nivel11 + #410, #127
  static Nivel11 + #411, #127
  static Nivel11 + #412, #127
  static Nivel11 + #413, #127
  static Nivel11 + #414, #127
  static Nivel11 + #415, #127
  static Nivel11 + #416, #127
  static Nivel11 + #417, #127
  static Nivel11 + #418, #127
  static Nivel11 + #419, #127
  static Nivel11 + #420, #127
  static Nivel11 + #421, #127
  static Nivel11 + #422, #127
  static Nivel11 + #423, #127
  static Nivel11 + #424, #127
  static Nivel11 + #425, #127
  static Nivel11 + #426, #127
  static Nivel11 + #427, #127
  static Nivel11 + #428, #127
  static Nivel11 + #429, #127
  static Nivel11 + #430, #127
  static Nivel11 + #431, #127
  static Nivel11 + #432, #127
  static Nivel11 + #433, #127
  static Nivel11 + #434, #127
  static Nivel11 + #435, #127
  static Nivel11 + #436, #127
  static Nivel11 + #437, #127
  static Nivel11 + #438, #127
  static Nivel11 + #439, #127

  ;Linha 11
  static Nivel11 + #440, #127
  static Nivel11 + #441, #127
  static Nivel11 + #442, #127
  static Nivel11 + #443, #127
  static Nivel11 + #444, #127
  static Nivel11 + #445, #127
  static Nivel11 + #446, #127
  static Nivel11 + #447, #127
  static Nivel11 + #448, #127
  static Nivel11 + #449, #127
  static Nivel11 + #450, #127
  static Nivel11 + #451, #127
  static Nivel11 + #452, #127
  static Nivel11 + #453, #127
  static Nivel11 + #454, #127
  static Nivel11 + #455, #127
  static Nivel11 + #456, #127
  static Nivel11 + #457, #127
  static Nivel11 + #458, #127
  static Nivel11 + #459, #127
  static Nivel11 + #460, #127
  static Nivel11 + #461, #127
  static Nivel11 + #462, #127
  static Nivel11 + #463, #127
  static Nivel11 + #464, #127
  static Nivel11 + #465, #127
  static Nivel11 + #466, #127
  static Nivel11 + #467, #127
  static Nivel11 + #468, #127
  static Nivel11 + #469, #127
  static Nivel11 + #470, #127
  static Nivel11 + #471, #127
  static Nivel11 + #472, #127
  static Nivel11 + #473, #127
  static Nivel11 + #474, #127
  static Nivel11 + #475, #127
  static Nivel11 + #476, #127
  static Nivel11 + #477, #127
  static Nivel11 + #478, #127
  static Nivel11 + #479, #127

  ;Linha 12
  static Nivel11 + #480, #127
  static Nivel11 + #481, #127
  static Nivel11 + #482, #127
  static Nivel11 + #483, #127
  static Nivel11 + #484, #127
  static Nivel11 + #485, #127
  static Nivel11 + #486, #127
  static Nivel11 + #487, #127
  static Nivel11 + #488, #127
  static Nivel11 + #489, #127
  static Nivel11 + #490, #127
  static Nivel11 + #491, #127
  static Nivel11 + #492, #127
  static Nivel11 + #493, #127
  static Nivel11 + #494, #127
  static Nivel11 + #495, #127
  static Nivel11 + #496, #127
  static Nivel11 + #497, #127
  static Nivel11 + #498, #127
  static Nivel11 + #499, #127
  static Nivel11 + #500, #127
  static Nivel11 + #501, #127
  static Nivel11 + #502, #127
  static Nivel11 + #503, #127
  static Nivel11 + #504, #127
  static Nivel11 + #505, #127
  static Nivel11 + #506, #127
  static Nivel11 + #507, #127
  static Nivel11 + #508, #127
  static Nivel11 + #509, #127
  static Nivel11 + #510, #127
  static Nivel11 + #511, #127
  static Nivel11 + #512, #127
  static Nivel11 + #513, #127
  static Nivel11 + #514, #127
  static Nivel11 + #515, #127
  static Nivel11 + #516, #127
  static Nivel11 + #517, #127
  static Nivel11 + #518, #127
  static Nivel11 + #519, #127

  ;Linha 13
  static Nivel11 + #520, #127
  static Nivel11 + #521, #127
  static Nivel11 + #522, #127
  static Nivel11 + #523, #127
  static Nivel11 + #524, #127
  static Nivel11 + #525, #127
  static Nivel11 + #526, #127
  static Nivel11 + #527, #127
  static Nivel11 + #528, #127
  static Nivel11 + #529, #127
  static Nivel11 + #530, #127
  static Nivel11 + #531, #127
  static Nivel11 + #532, #127
  static Nivel11 + #533, #127
  static Nivel11 + #534, #127
  static Nivel11 + #535, #127
  static Nivel11 + #536, #127
  static Nivel11 + #537, #127
  static Nivel11 + #538, #127
  static Nivel11 + #539, #127
  static Nivel11 + #540, #127
  static Nivel11 + #541, #127
  static Nivel11 + #542, #127
  static Nivel11 + #543, #127
  static Nivel11 + #544, #127
  static Nivel11 + #545, #127
  static Nivel11 + #546, #127
  static Nivel11 + #547, #127
  static Nivel11 + #548, #127
  static Nivel11 + #549, #127
  static Nivel11 + #550, #127
  static Nivel11 + #551, #127
  static Nivel11 + #552, #127
  static Nivel11 + #553, #127
  static Nivel11 + #554, #127
  static Nivel11 + #555, #127
  static Nivel11 + #556, #127
  static Nivel11 + #557, #127
  static Nivel11 + #558, #127
  static Nivel11 + #559, #127

  ;Linha 14
  static Nivel11 + #560, #127
  static Nivel11 + #561, #127
  static Nivel11 + #562, #127
  static Nivel11 + #563, #127
  static Nivel11 + #564, #127
  static Nivel11 + #565, #127
  static Nivel11 + #566, #127
  static Nivel11 + #567, #127
  static Nivel11 + #568, #127
  static Nivel11 + #569, #127
  static Nivel11 + #570, #127
  static Nivel11 + #571, #127
  static Nivel11 + #572, #127
  static Nivel11 + #573, #127
  static Nivel11 + #574, #127
  static Nivel11 + #575, #127
  static Nivel11 + #576, #127
  static Nivel11 + #577, #127
  static Nivel11 + #578, #127
  static Nivel11 + #579, #127
  static Nivel11 + #580, #127
  static Nivel11 + #581, #127
  static Nivel11 + #582, #127
  static Nivel11 + #583, #127
  static Nivel11 + #584, #127
  static Nivel11 + #585, #127
  static Nivel11 + #586, #127
  static Nivel11 + #587, #127
  static Nivel11 + #588, #127
  static Nivel11 + #589, #127
  static Nivel11 + #590, #127
  static Nivel11 + #591, #127
  static Nivel11 + #592, #127
  static Nivel11 + #593, #127
  static Nivel11 + #594, #127
  static Nivel11 + #595, #127
  static Nivel11 + #596, #127
  static Nivel11 + #597, #127
  static Nivel11 + #598, #127
  static Nivel11 + #599, #127

  ;Linha 15
  static Nivel11 + #600, #127
  static Nivel11 + #601, #127
  static Nivel11 + #602, #127
  static Nivel11 + #603, #127
  static Nivel11 + #604, #127
  static Nivel11 + #605, #127
  static Nivel11 + #606, #127
  static Nivel11 + #607, #127
  static Nivel11 + #608, #127
  static Nivel11 + #609, #127
  static Nivel11 + #610, #127
  static Nivel11 + #611, #127
  static Nivel11 + #612, #127
  static Nivel11 + #613, #127
  static Nivel11 + #614, #127
  static Nivel11 + #615, #127
  static Nivel11 + #616, #127
  static Nivel11 + #617, #127
  static Nivel11 + #618, #127
  static Nivel11 + #619, #127
  static Nivel11 + #620, #127
  static Nivel11 + #621, #127
  static Nivel11 + #622, #127
  static Nivel11 + #623, #127
  static Nivel11 + #624, #127
  static Nivel11 + #625, #127
  static Nivel11 + #626, #127
  static Nivel11 + #627, #127
  static Nivel11 + #628, #127
  static Nivel11 + #629, #127
  static Nivel11 + #630, #127
  static Nivel11 + #631, #127
  static Nivel11 + #632, #127
  static Nivel11 + #633, #127
  static Nivel11 + #634, #127
  static Nivel11 + #635, #127
  static Nivel11 + #636, #127
  static Nivel11 + #637, #127
  static Nivel11 + #638, #127
  static Nivel11 + #639, #127

  ;Linha 16
  static Nivel11 + #640, #127
  static Nivel11 + #641, #127
  static Nivel11 + #642, #127
  static Nivel11 + #643, #127
  static Nivel11 + #644, #127
  static Nivel11 + #645, #127
  static Nivel11 + #646, #127
  static Nivel11 + #647, #127
  static Nivel11 + #648, #127
  static Nivel11 + #649, #127
  static Nivel11 + #650, #127
  static Nivel11 + #651, #127
  static Nivel11 + #652, #127
  static Nivel11 + #653, #127
  static Nivel11 + #654, #127
  static Nivel11 + #655, #127
  static Nivel11 + #656, #127
  static Nivel11 + #657, #127
  static Nivel11 + #658, #127
  static Nivel11 + #659, #127
  static Nivel11 + #660, #127
  static Nivel11 + #661, #127
  static Nivel11 + #662, #127
  static Nivel11 + #663, #127
  static Nivel11 + #664, #127
  static Nivel11 + #665, #127
  static Nivel11 + #666, #127
  static Nivel11 + #667, #127
  static Nivel11 + #668, #127
  static Nivel11 + #669, #127
  static Nivel11 + #670, #127
  static Nivel11 + #671, #127
  static Nivel11 + #672, #127
  static Nivel11 + #673, #127
  static Nivel11 + #674, #127
  static Nivel11 + #675, #127
  static Nivel11 + #676, #127
  static Nivel11 + #677, #127
  static Nivel11 + #678, #127
  static Nivel11 + #679, #127

  ;Linha 17
  static Nivel11 + #680, #127
  static Nivel11 + #681, #127
  static Nivel11 + #682, #127
  static Nivel11 + #683, #127
  static Nivel11 + #684, #127
  static Nivel11 + #685, #127
  static Nivel11 + #686, #127
  static Nivel11 + #687, #127
  static Nivel11 + #688, #127
  static Nivel11 + #689, #127
  static Nivel11 + #690, #127
  static Nivel11 + #691, #127
  static Nivel11 + #692, #127
  static Nivel11 + #693, #127
  static Nivel11 + #694, #127
  static Nivel11 + #695, #127
  static Nivel11 + #696, #127
  static Nivel11 + #697, #127
  static Nivel11 + #698, #127
  static Nivel11 + #699, #127
  static Nivel11 + #700, #127
  static Nivel11 + #701, #127
  static Nivel11 + #702, #127
  static Nivel11 + #703, #127
  static Nivel11 + #704, #127
  static Nivel11 + #705, #127
  static Nivel11 + #706, #127
  static Nivel11 + #707, #127
  static Nivel11 + #708, #127
  static Nivel11 + #709, #127
  static Nivel11 + #710, #127
  static Nivel11 + #711, #127
  static Nivel11 + #712, #127
  static Nivel11 + #713, #127
  static Nivel11 + #714, #127
  static Nivel11 + #715, #127
  static Nivel11 + #716, #127
  static Nivel11 + #717, #127
  static Nivel11 + #718, #127
  static Nivel11 + #719, #127

  ;Linha 18
  static Nivel11 + #720, #127
  static Nivel11 + #721, #127
  static Nivel11 + #722, #127
  static Nivel11 + #723, #127
  static Nivel11 + #724, #127
  static Nivel11 + #725, #127
  static Nivel11 + #726, #127
  static Nivel11 + #727, #127
  static Nivel11 + #728, #127
  static Nivel11 + #729, #127
  static Nivel11 + #730, #127
  static Nivel11 + #731, #127
  static Nivel11 + #732, #127
  static Nivel11 + #733, #127
  static Nivel11 + #734, #127
  static Nivel11 + #735, #127
  static Nivel11 + #736, #127
  static Nivel11 + #737, #127
  static Nivel11 + #738, #127
  static Nivel11 + #739, #127
  static Nivel11 + #740, #127
  static Nivel11 + #741, #127
  static Nivel11 + #742, #127
  static Nivel11 + #743, #127
  static Nivel11 + #744, #127
  static Nivel11 + #745, #127
  static Nivel11 + #746, #127
  static Nivel11 + #747, #127
  static Nivel11 + #748, #127
  static Nivel11 + #749, #127
  static Nivel11 + #750, #127
  static Nivel11 + #751, #127
  static Nivel11 + #752, #127
  static Nivel11 + #753, #127
  static Nivel11 + #754, #127
  static Nivel11 + #755, #127
  static Nivel11 + #756, #127
  static Nivel11 + #757, #127
  static Nivel11 + #758, #127
  static Nivel11 + #759, #127

  ;Linha 19
  static Nivel11 + #760, #127
  static Nivel11 + #761, #127
  static Nivel11 + #762, #127
  static Nivel11 + #763, #127
  static Nivel11 + #764, #127
  static Nivel11 + #765, #127
  static Nivel11 + #766, #127
  static Nivel11 + #767, #127
  static Nivel11 + #768, #127
  static Nivel11 + #769, #127
  static Nivel11 + #770, #127
  static Nivel11 + #771, #127
  static Nivel11 + #772, #127
  static Nivel11 + #773, #127
  static Nivel11 + #774, #127
  static Nivel11 + #775, #127
  static Nivel11 + #776, #127
  static Nivel11 + #777, #127
  static Nivel11 + #778, #127
  static Nivel11 + #779, #127
  static Nivel11 + #780, #127
  static Nivel11 + #781, #127
  static Nivel11 + #782, #127
  static Nivel11 + #783, #127
  static Nivel11 + #784, #127
  static Nivel11 + #785, #127
  static Nivel11 + #786, #127
  static Nivel11 + #787, #127
  static Nivel11 + #788, #127
  static Nivel11 + #789, #127
  static Nivel11 + #790, #127
  static Nivel11 + #791, #127
  static Nivel11 + #792, #127
  static Nivel11 + #793, #127
  static Nivel11 + #794, #127
  static Nivel11 + #795, #127
  static Nivel11 + #796, #127
  static Nivel11 + #797, #127
  static Nivel11 + #798, #127
  static Nivel11 + #799, #127

  ;Linha 20
  static Nivel11 + #800, #127
  static Nivel11 + #801, #127
  static Nivel11 + #802, #127
  static Nivel11 + #803, #127
  static Nivel11 + #804, #127
  static Nivel11 + #805, #127
  static Nivel11 + #806, #127
  static Nivel11 + #807, #127
  static Nivel11 + #808, #127
  static Nivel11 + #809, #2818
  static Nivel11 + #810, #127
  static Nivel11 + #811, #127
  static Nivel11 + #812, #127
  static Nivel11 + #813, #127
  static Nivel11 + #814, #127
  static Nivel11 + #815, #127
  static Nivel11 + #816, #127
  static Nivel11 + #817, #127
  static Nivel11 + #818, #127
  static Nivel11 + #819, #127
  static Nivel11 + #820, #127
  static Nivel11 + #821, #127
  static Nivel11 + #822, #127
  static Nivel11 + #823, #127
  static Nivel11 + #824, #127
  static Nivel11 + #825, #127
  static Nivel11 + #826, #127
  static Nivel11 + #827, #127
  static Nivel11 + #828, #127
  static Nivel11 + #829, #127
  static Nivel11 + #830, #127
  static Nivel11 + #831, #127
  static Nivel11 + #832, #127
  static Nivel11 + #833, #127
  static Nivel11 + #834, #127
  static Nivel11 + #835, #127
  static Nivel11 + #836, #127
  static Nivel11 + #837, #127
  static Nivel11 + #838, #127
  static Nivel11 + #839, #127

  ;Linha 21
  static Nivel11 + #840, #127
  static Nivel11 + #841, #127
  static Nivel11 + #842, #127
  static Nivel11 + #843, #127
  static Nivel11 + #844, #127
  static Nivel11 + #845, #127
  static Nivel11 + #846, #127
  static Nivel11 + #847, #127
  static Nivel11 + #848, #127
  static Nivel11 + #849, #127
  static Nivel11 + #850, #127
  static Nivel11 + #851, #127
  static Nivel11 + #852, #127
  static Nivel11 + #853, #127
  static Nivel11 + #854, #127
  static Nivel11 + #855, #127
  static Nivel11 + #856, #127
  static Nivel11 + #857, #127
  static Nivel11 + #858, #127
  static Nivel11 + #859, #127
  static Nivel11 + #860, #127
  static Nivel11 + #861, #127
  static Nivel11 + #862, #127
  static Nivel11 + #863, #127
  static Nivel11 + #864, #127
  static Nivel11 + #865, #127
  static Nivel11 + #866, #127
  static Nivel11 + #867, #127
  static Nivel11 + #868, #127
  static Nivel11 + #869, #127
  static Nivel11 + #870, #127
  static Nivel11 + #871, #127
  static Nivel11 + #872, #127
  static Nivel11 + #873, #127
  static Nivel11 + #874, #127
  static Nivel11 + #875, #127
  static Nivel11 + #876, #127
  static Nivel11 + #877, #127
  static Nivel11 + #878, #127
  static Nivel11 + #879, #127

  ;Linha 22
  static Nivel11 + #880, #127
  static Nivel11 + #881, #127
  static Nivel11 + #882, #127
  static Nivel11 + #883, #127
  static Nivel11 + #884, #127
  static Nivel11 + #885, #127
  static Nivel11 + #886, #127
  static Nivel11 + #887, #127
  static Nivel11 + #888, #127
  static Nivel11 + #889, #127
  static Nivel11 + #890, #127
  static Nivel11 + #891, #127
  static Nivel11 + #892, #127
  static Nivel11 + #893, #127
  static Nivel11 + #894, #127
  static Nivel11 + #895, #127
  static Nivel11 + #896, #127
  static Nivel11 + #897, #127
  static Nivel11 + #898, #127
  static Nivel11 + #899, #127
  static Nivel11 + #900, #127
  static Nivel11 + #901, #127
  static Nivel11 + #902, #127
  static Nivel11 + #903, #127
  static Nivel11 + #904, #127
  static Nivel11 + #905, #127
  static Nivel11 + #906, #127
  static Nivel11 + #907, #127
  static Nivel11 + #908, #127
  static Nivel11 + #909, #127
  static Nivel11 + #910, #127
  static Nivel11 + #911, #127
  static Nivel11 + #912, #127
  static Nivel11 + #913, #127
  static Nivel11 + #914, #127
  static Nivel11 + #915, #127
  static Nivel11 + #916, #127
  static Nivel11 + #917, #127
  static Nivel11 + #918, #127
  static Nivel11 + #919, #127

  ;Linha 23
  static Nivel11 + #920, #127
  static Nivel11 + #921, #127
  static Nivel11 + #922, #127
  static Nivel11 + #923, #127
  static Nivel11 + #924, #127
  static Nivel11 + #925, #127
  static Nivel11 + #926, #127
  static Nivel11 + #927, #127
  static Nivel11 + #928, #127
  static Nivel11 + #929, #127
  static Nivel11 + #930, #127
  static Nivel11 + #931, #127
  static Nivel11 + #932, #127
  static Nivel11 + #933, #127
  static Nivel11 + #934, #127
  static Nivel11 + #935, #127
  static Nivel11 + #936, #127
  static Nivel11 + #937, #127
  static Nivel11 + #938, #127
  static Nivel11 + #939, #127
  static Nivel11 + #940, #127
  static Nivel11 + #941, #127
  static Nivel11 + #942, #127
  static Nivel11 + #943, #127
  static Nivel11 + #944, #127
  static Nivel11 + #945, #127
  static Nivel11 + #946, #127
  static Nivel11 + #947, #127
  static Nivel11 + #948, #127
  static Nivel11 + #949, #127
  static Nivel11 + #950, #127
  static Nivel11 + #951, #127
  static Nivel11 + #952, #127
  static Nivel11 + #953, #127
  static Nivel11 + #954, #127
  static Nivel11 + #955, #127
  static Nivel11 + #956, #127
  static Nivel11 + #957, #127
  static Nivel11 + #958, #127
  static Nivel11 + #959, #127

  ;Linha 24
  static Nivel11 + #960, #127
  static Nivel11 + #961, #127
  static Nivel11 + #962, #127
  static Nivel11 + #963, #127
  static Nivel11 + #964, #127
  static Nivel11 + #965, #127
  static Nivel11 + #966, #127
  static Nivel11 + #967, #257
  static Nivel11 + #968, #2818
  static Nivel11 + #969, #257
  static Nivel11 + #970, #2818
  static Nivel11 + #971, #257
  static Nivel11 + #972, #127
  static Nivel11 + #973, #127
  static Nivel11 + #974, #127
  static Nivel11 + #975, #127
  static Nivel11 + #976, #127
  static Nivel11 + #977, #127
  static Nivel11 + #978, #127
  static Nivel11 + #979, #127
  static Nivel11 + #980, #127
  static Nivel11 + #981, #127
  static Nivel11 + #982, #127
  static Nivel11 + #983, #127
  static Nivel11 + #984, #127
  static Nivel11 + #985, #127
  static Nivel11 + #986, #127
  static Nivel11 + #987, #127
  static Nivel11 + #988, #127
  static Nivel11 + #989, #127
  static Nivel11 + #990, #127
  static Nivel11 + #991, #127
  static Nivel11 + #992, #127
  static Nivel11 + #993, #127
  static Nivel11 + #994, #127
  static Nivel11 + #995, #127
  static Nivel11 + #996, #127
  static Nivel11 + #997, #127
  static Nivel11 + #998, #127
  static Nivel11 + #999, #127

  ;Linha 25
  static Nivel11 + #1000, #127
  static Nivel11 + #1001, #127
  static Nivel11 + #1002, #127
  static Nivel11 + #1003, #127
  static Nivel11 + #1004, #127
  static Nivel11 + #1005, #127
  static Nivel11 + #1006, #127
  static Nivel11 + #1007, #127
  static Nivel11 + #1008, #127
  static Nivel11 + #1009, #127
  static Nivel11 + #1010, #127
  static Nivel11 + #1011, #127
  static Nivel11 + #1012, #127
  static Nivel11 + #1013, #127
  static Nivel11 + #1014, #127
  static Nivel11 + #1015, #3967
  static Nivel11 + #1016, #516
  static Nivel11 + #1017, #516
  static Nivel11 + #1018, #3967
  static Nivel11 + #1019, #127
  static Nivel11 + #1020, #127
  static Nivel11 + #1021, #127
  static Nivel11 + #1022, #127
  static Nivel11 + #1023, #127
  static Nivel11 + #1024, #127
  static Nivel11 + #1025, #127
  static Nivel11 + #1026, #127
  static Nivel11 + #1027, #127
  static Nivel11 + #1028, #127
  static Nivel11 + #1029, #127
  static Nivel11 + #1030, #127
  static Nivel11 + #1031, #127
  static Nivel11 + #1032, #127
  static Nivel11 + #1033, #127
  static Nivel11 + #1034, #127
  static Nivel11 + #1035, #127
  static Nivel11 + #1036, #127
  static Nivel11 + #1037, #127
  static Nivel11 + #1038, #127
  static Nivel11 + #1039, #127

  ;Linha 26
  static Nivel11 + #1040, #127
  static Nivel11 + #1041, #127
  static Nivel11 + #1042, #127
  static Nivel11 + #1043, #127
  static Nivel11 + #1044, #127
  static Nivel11 + #1045, #127
  static Nivel11 + #1046, #127
  static Nivel11 + #1047, #127
  static Nivel11 + #1048, #127
  static Nivel11 + #1049, #127
  static Nivel11 + #1050, #127
  static Nivel11 + #1051, #127
  static Nivel11 + #1052, #127
  static Nivel11 + #1053, #127
  static Nivel11 + #1054, #127
  static Nivel11 + #1055, #3967
  static Nivel11 + #1056, #2563
  static Nivel11 + #1057, #2565
  static Nivel11 + #1058, #127
  static Nivel11 + #1059, #127
  static Nivel11 + #1060, #127
  static Nivel11 + #1061, #127
  static Nivel11 + #1062, #127
  static Nivel11 + #1063, #127
  static Nivel11 + #1064, #127
  static Nivel11 + #1065, #127
  static Nivel11 + #1066, #127
  static Nivel11 + #1067, #127
  static Nivel11 + #1068, #127
  static Nivel11 + #1069, #127
  static Nivel11 + #1070, #127
  static Nivel11 + #1071, #127
  static Nivel11 + #1072, #127
  static Nivel11 + #1073, #127
  static Nivel11 + #1074, #127
  static Nivel11 + #1075, #127
  static Nivel11 + #1076, #127
  static Nivel11 + #1077, #127
  static Nivel11 + #1078, #127
  static Nivel11 + #1079, #127

  ;Linha 27
  static Nivel11 + #1080, #127
  static Nivel11 + #1081, #127
  static Nivel11 + #1082, #127
  static Nivel11 + #1083, #127
  static Nivel11 + #1084, #127
  static Nivel11 + #1085, #127
  static Nivel11 + #1086, #127
  static Nivel11 + #1087, #127
  static Nivel11 + #1088, #127
  static Nivel11 + #1089, #127
  static Nivel11 + #1090, #127
  static Nivel11 + #1091, #127
  static Nivel11 + #1092, #127
  static Nivel11 + #1093, #127
  static Nivel11 + #1094, #127
  static Nivel11 + #1095, #3967
  static Nivel11 + #1096, #2563
  static Nivel11 + #1097, #2565
  static Nivel11 + #1098, #127
  static Nivel11 + #1099, #127
  static Nivel11 + #1100, #127
  static Nivel11 + #1101, #127
  static Nivel11 + #1102, #127
  static Nivel11 + #1103, #127
  static Nivel11 + #1104, #127
  static Nivel11 + #1105, #127
  static Nivel11 + #1106, #127
  static Nivel11 + #1107, #127
  static Nivel11 + #1108, #127
  static Nivel11 + #1109, #127
  static Nivel11 + #1110, #127
  static Nivel11 + #1111, #127
  static Nivel11 + #1112, #127
  static Nivel11 + #1113, #127
  static Nivel11 + #1114, #127
  static Nivel11 + #1115, #127
  static Nivel11 + #1116, #127
  static Nivel11 + #1117, #127
  static Nivel11 + #1118, #127
  static Nivel11 + #1119, #127

  ;Linha 28
  static Nivel11 + #1120, #256
  static Nivel11 + #1121, #256
  static Nivel11 + #1122, #256
  static Nivel11 + #1123, #256
  static Nivel11 + #1124, #256
  static Nivel11 + #1125, #256
  static Nivel11 + #1126, #256
  static Nivel11 + #1127, #256
  static Nivel11 + #1128, #256
  static Nivel11 + #1129, #256
  static Nivel11 + #1130, #256
  static Nivel11 + #1131, #256
  static Nivel11 + #1132, #256
  static Nivel11 + #1133, #256
  static Nivel11 + #1134, #256
  static Nivel11 + #1135, #256
  static Nivel11 + #1136, #256
  static Nivel11 + #1137, #256
  static Nivel11 + #1138, #256
  static Nivel11 + #1139, #256
  static Nivel11 + #1140, #256
  static Nivel11 + #1141, #256
  static Nivel11 + #1142, #256
  static Nivel11 + #1143, #256
  static Nivel11 + #1144, #256
  static Nivel11 + #1145, #256
  static Nivel11 + #1146, #256
  static Nivel11 + #1147, #3967
  static Nivel11 + #1148, #3967
  static Nivel11 + #1149, #3967
  static Nivel11 + #1150, #3967
  static Nivel11 + #1151, #256
  static Nivel11 + #1152, #256
  static Nivel11 + #1153, #256
  static Nivel11 + #1154, #256
  static Nivel11 + #1155, #256
  static Nivel11 + #1156, #256
  static Nivel11 + #1157, #256
  static Nivel11 + #1158, #256
  static Nivel11 + #1159, #256

  ;Linha 29
  static Nivel11 + #1160, #256
  static Nivel11 + #1161, #256
  static Nivel11 + #1162, #256
  static Nivel11 + #1163, #256
  static Nivel11 + #1164, #256
  static Nivel11 + #1165, #256
  static Nivel11 + #1166, #256
  static Nivel11 + #1167, #256
  static Nivel11 + #1168, #256
  static Nivel11 + #1169, #256
  static Nivel11 + #1170, #256
  static Nivel11 + #1171, #256
  static Nivel11 + #1172, #256
  static Nivel11 + #1173, #256
  static Nivel11 + #1174, #256
  static Nivel11 + #1175, #256
  static Nivel11 + #1176, #256
  static Nivel11 + #1177, #256
  static Nivel11 + #1178, #256
  static Nivel11 + #1179, #256
  static Nivel11 + #1180, #256
  static Nivel11 + #1181, #256
  static Nivel11 + #1182, #256
  static Nivel11 + #1183, #256
  static Nivel11 + #1184, #256
  static Nivel11 + #1185, #256
  static Nivel11 + #1186, #256
  static Nivel11 + #1187, #3967
  static Nivel11 + #1188, #3967
  static Nivel11 + #1189, #3967
  static Nivel11 + #1190, #3967
  static Nivel11 + #1191, #256
  static Nivel11 + #1192, #256
  static Nivel11 + #1193, #256
  static Nivel11 + #1194, #256
  static Nivel11 + #1195, #256
  static Nivel11 + #1196, #256
  static Nivel11 + #1197, #256
  static Nivel11 + #1198, #256
  static Nivel11 + #1199, #256

printNivel11Screen:
  push R0
  push R1
  push R2
  push R3

  loadn R0, #Nivel11
  loadn R1, #0
  loadn R2, #1200

  printNivel11ScreenLoop:

    add R3,R0,R1
    loadi R3, R3
    outchar R3, R1
    inc R1
    cmp R1, R2

    jne printNivel11ScreenLoop

  pop R3
  pop R2
  pop R1
  pop R0
  rts

Nivel12 : var #1200
  ;Linha 0
  static Nivel12 + #0, #3967
  static Nivel12 + #1, #3967
  static Nivel12 + #2, #3967
  static Nivel12 + #3, #3967
  static Nivel12 + #4, #3967
  static Nivel12 + #5, #3967
  static Nivel12 + #6, #3967
  static Nivel12 + #7, #3967
  static Nivel12 + #8, #1798
  static Nivel12 + #9, #1798
  static Nivel12 + #10, #1798
  static Nivel12 + #11, #1798
  static Nivel12 + #12, #3967
  static Nivel12 + #13, #3967
  static Nivel12 + #14, #3967
  static Nivel12 + #15, #127
  static Nivel12 + #16, #127
  static Nivel12 + #17, #127
  static Nivel12 + #18, #127
  static Nivel12 + #19, #1798
  static Nivel12 + #20, #1798
  static Nivel12 + #21, #1798
  static Nivel12 + #22, #1798
  static Nivel12 + #23, #1798
  static Nivel12 + #24, #1798
  static Nivel12 + #25, #1798
  static Nivel12 + #26, #1798
  static Nivel12 + #27, #1798
  static Nivel12 + #28, #1798
  static Nivel12 + #29, #3967
  static Nivel12 + #30, #3967
  static Nivel12 + #31, #3967
  static Nivel12 + #32, #3967
  static Nivel12 + #33, #3967
  static Nivel12 + #34, #3967
  static Nivel12 + #35, #3967
  static Nivel12 + #36, #3967
  static Nivel12 + #37, #3967
  static Nivel12 + #38, #3967
  static Nivel12 + #39, #3967

  ;Linha 1
  static Nivel12 + #40, #3967
  static Nivel12 + #41, #3967
  static Nivel12 + #42, #3967
  static Nivel12 + #43, #3967
  static Nivel12 + #44, #3967
  static Nivel12 + #45, #3967
  static Nivel12 + #46, #3967
  static Nivel12 + #47, #1798
  static Nivel12 + #48, #1798
  static Nivel12 + #49, #1798
  static Nivel12 + #50, #1798
  static Nivel12 + #51, #1798
  static Nivel12 + #52, #1798
  static Nivel12 + #53, #127
  static Nivel12 + #54, #127
  static Nivel12 + #55, #127
  static Nivel12 + #56, #3967
  static Nivel12 + #57, #3967
  static Nivel12 + #58, #3967
  static Nivel12 + #59, #3967
  static Nivel12 + #60, #3967
  static Nivel12 + #61, #1798
  static Nivel12 + #62, #1798
  static Nivel12 + #63, #1798
  static Nivel12 + #64, #1798
  static Nivel12 + #65, #1798
  static Nivel12 + #66, #1798
  static Nivel12 + #67, #1798
  static Nivel12 + #68, #3967
  static Nivel12 + #69, #127
  static Nivel12 + #70, #3967
  static Nivel12 + #71, #3967
  static Nivel12 + #72, #3967
  static Nivel12 + #73, #3967
  static Nivel12 + #74, #3967
  static Nivel12 + #75, #3967
  static Nivel12 + #76, #3967
  static Nivel12 + #77, #3967
  static Nivel12 + #78, #3967
  static Nivel12 + #79, #3967

  ;Linha 2
  static Nivel12 + #80, #3967
  static Nivel12 + #81, #3967
  static Nivel12 + #82, #3967
  static Nivel12 + #83, #3967
  static Nivel12 + #84, #3967
  static Nivel12 + #85, #3967
  static Nivel12 + #86, #3967
  static Nivel12 + #87, #3967
  static Nivel12 + #88, #1798
  static Nivel12 + #89, #1798
  static Nivel12 + #90, #1798
  static Nivel12 + #91, #1798
  static Nivel12 + #92, #127
  static Nivel12 + #93, #3967
  static Nivel12 + #94, #127
  static Nivel12 + #95, #127
  static Nivel12 + #96, #127
  static Nivel12 + #97, #3967
  static Nivel12 + #98, #3967
  static Nivel12 + #99, #3967
  static Nivel12 + #100, #3967
  static Nivel12 + #101, #3967
  static Nivel12 + #102, #1798
  static Nivel12 + #103, #1798
  static Nivel12 + #104, #1798
  static Nivel12 + #105, #1798
  static Nivel12 + #106, #3967
  static Nivel12 + #107, #3967
  static Nivel12 + #108, #3967
  static Nivel12 + #109, #127
  static Nivel12 + #110, #127
  static Nivel12 + #111, #127
  static Nivel12 + #112, #127
  static Nivel12 + #113, #127
  static Nivel12 + #114, #127
  static Nivel12 + #115, #127
  static Nivel12 + #116, #127
  static Nivel12 + #117, #127
  static Nivel12 + #118, #127
  static Nivel12 + #119, #127

  ;Linha 3
  static Nivel12 + #120, #127
  static Nivel12 + #121, #3967
  static Nivel12 + #122, #3967
  static Nivel12 + #123, #3967
  static Nivel12 + #124, #127
  static Nivel12 + #125, #127
  static Nivel12 + #126, #127
  static Nivel12 + #127, #127
  static Nivel12 + #128, #127
  static Nivel12 + #129, #127
  static Nivel12 + #130, #127
  static Nivel12 + #131, #127
  static Nivel12 + #132, #127
  static Nivel12 + #133, #127
  static Nivel12 + #134, #127
  static Nivel12 + #135, #127
  static Nivel12 + #136, #127
  static Nivel12 + #137, #3967
  static Nivel12 + #138, #3967
  static Nivel12 + #139, #3967
  static Nivel12 + #140, #3967
  static Nivel12 + #141, #3967
  static Nivel12 + #142, #3967
  static Nivel12 + #143, #3967
  static Nivel12 + #144, #3967
  static Nivel12 + #145, #3967
  static Nivel12 + #146, #3967
  static Nivel12 + #147, #3967
  static Nivel12 + #148, #3967
  static Nivel12 + #149, #3967
  static Nivel12 + #150, #127
  static Nivel12 + #151, #127
  static Nivel12 + #152, #127
  static Nivel12 + #153, #127
  static Nivel12 + #154, #127
  static Nivel12 + #155, #127
  static Nivel12 + #156, #127
  static Nivel12 + #157, #127
  static Nivel12 + #158, #127
  static Nivel12 + #159, #127

  ;Linha 4
  static Nivel12 + #160, #127
  static Nivel12 + #161, #127
  static Nivel12 + #162, #127
  static Nivel12 + #163, #127
  static Nivel12 + #164, #127
  static Nivel12 + #165, #127
  static Nivel12 + #166, #127
  static Nivel12 + #167, #127
  static Nivel12 + #168, #127
  static Nivel12 + #169, #127
  static Nivel12 + #170, #127
  static Nivel12 + #171, #127
  static Nivel12 + #172, #127
  static Nivel12 + #173, #127
  static Nivel12 + #174, #127
  static Nivel12 + #175, #127
  static Nivel12 + #176, #127
  static Nivel12 + #177, #127
  static Nivel12 + #178, #3967
  static Nivel12 + #179, #3967
  static Nivel12 + #180, #3967
  static Nivel12 + #181, #3967
  static Nivel12 + #182, #3967
  static Nivel12 + #183, #3967
  static Nivel12 + #184, #3967
  static Nivel12 + #185, #3967
  static Nivel12 + #186, #127
  static Nivel12 + #187, #127
  static Nivel12 + #188, #127
  static Nivel12 + #189, #3967
  static Nivel12 + #190, #3967
  static Nivel12 + #191, #127
  static Nivel12 + #192, #127
  static Nivel12 + #193, #127
  static Nivel12 + #194, #127
  static Nivel12 + #195, #127
  static Nivel12 + #196, #127
  static Nivel12 + #197, #127
  static Nivel12 + #198, #127
  static Nivel12 + #199, #127

  ;Linha 5
  static Nivel12 + #200, #127
  static Nivel12 + #201, #127
  static Nivel12 + #202, #127
  static Nivel12 + #203, #127
  static Nivel12 + #204, #127
  static Nivel12 + #205, #127
  static Nivel12 + #206, #127
  static Nivel12 + #207, #127
  static Nivel12 + #208, #127
  static Nivel12 + #209, #127
  static Nivel12 + #210, #127
  static Nivel12 + #211, #127
  static Nivel12 + #212, #127
  static Nivel12 + #213, #127
  static Nivel12 + #214, #127
  static Nivel12 + #215, #127
  static Nivel12 + #216, #127
  static Nivel12 + #217, #127
  static Nivel12 + #218, #3967
  static Nivel12 + #219, #3967
  static Nivel12 + #220, #3967
  static Nivel12 + #221, #3967
  static Nivel12 + #222, #3967
  static Nivel12 + #223, #3967
  static Nivel12 + #224, #3967
  static Nivel12 + #225, #3967
  static Nivel12 + #226, #127
  static Nivel12 + #227, #127
  static Nivel12 + #228, #127
  static Nivel12 + #229, #127
  static Nivel12 + #230, #127
  static Nivel12 + #231, #127
  static Nivel12 + #232, #127
  static Nivel12 + #233, #127
  static Nivel12 + #234, #127
  static Nivel12 + #235, #127
  static Nivel12 + #236, #127
  static Nivel12 + #237, #127
  static Nivel12 + #238, #127
  static Nivel12 + #239, #127

  ;Linha 6
  static Nivel12 + #240, #127
  static Nivel12 + #241, #127
  static Nivel12 + #242, #127
  static Nivel12 + #243, #127
  static Nivel12 + #244, #127
  static Nivel12 + #245, #127
  static Nivel12 + #246, #127
  static Nivel12 + #247, #127
  static Nivel12 + #248, #127
  static Nivel12 + #249, #127
  static Nivel12 + #250, #127
  static Nivel12 + #251, #127
  static Nivel12 + #252, #127
  static Nivel12 + #253, #127
  static Nivel12 + #254, #127
  static Nivel12 + #255, #127
  static Nivel12 + #256, #127
  static Nivel12 + #257, #127
  static Nivel12 + #258, #127
  static Nivel12 + #259, #127
  static Nivel12 + #260, #127
  static Nivel12 + #261, #127
  static Nivel12 + #262, #127
  static Nivel12 + #263, #127
  static Nivel12 + #264, #3967
  static Nivel12 + #265, #3967
  static Nivel12 + #266, #127
  static Nivel12 + #267, #127
  static Nivel12 + #268, #127
  static Nivel12 + #269, #127
  static Nivel12 + #270, #127
  static Nivel12 + #271, #127
  static Nivel12 + #272, #127
  static Nivel12 + #273, #127
  static Nivel12 + #274, #127
  static Nivel12 + #275, #127
  static Nivel12 + #276, #127
  static Nivel12 + #277, #127
  static Nivel12 + #278, #127
  static Nivel12 + #279, #127

  ;Linha 7
  static Nivel12 + #280, #127
  static Nivel12 + #281, #127
  static Nivel12 + #282, #127
  static Nivel12 + #283, #127
  static Nivel12 + #284, #127
  static Nivel12 + #285, #127
  static Nivel12 + #286, #127
  static Nivel12 + #287, #127
  static Nivel12 + #288, #127
  static Nivel12 + #289, #127
  static Nivel12 + #290, #127
  static Nivel12 + #291, #127
  static Nivel12 + #292, #127
  static Nivel12 + #293, #127
  static Nivel12 + #294, #127
  static Nivel12 + #295, #127
  static Nivel12 + #296, #127
  static Nivel12 + #297, #127
  static Nivel12 + #298, #127
  static Nivel12 + #299, #127
  static Nivel12 + #300, #127
  static Nivel12 + #301, #127
  static Nivel12 + #302, #127
  static Nivel12 + #303, #127
  static Nivel12 + #304, #127
  static Nivel12 + #305, #127
  static Nivel12 + #306, #127
  static Nivel12 + #307, #127
  static Nivel12 + #308, #127
  static Nivel12 + #309, #127
  static Nivel12 + #310, #127
  static Nivel12 + #311, #127
  static Nivel12 + #312, #127
  static Nivel12 + #313, #127
  static Nivel12 + #314, #127
  static Nivel12 + #315, #127
  static Nivel12 + #316, #127
  static Nivel12 + #317, #127
  static Nivel12 + #318, #127
  static Nivel12 + #319, #127

  ;Linha 8
  static Nivel12 + #320, #127
  static Nivel12 + #321, #127
  static Nivel12 + #322, #127
  static Nivel12 + #323, #127
  static Nivel12 + #324, #127
  static Nivel12 + #325, #127
  static Nivel12 + #326, #127
  static Nivel12 + #327, #127
  static Nivel12 + #328, #127
  static Nivel12 + #329, #127
  static Nivel12 + #330, #127
  static Nivel12 + #331, #127
  static Nivel12 + #332, #127
  static Nivel12 + #333, #127
  static Nivel12 + #334, #127
  static Nivel12 + #335, #127
  static Nivel12 + #336, #127
  static Nivel12 + #337, #127
  static Nivel12 + #338, #127
  static Nivel12 + #339, #127
  static Nivel12 + #340, #127
  static Nivel12 + #341, #127
  static Nivel12 + #342, #127
  static Nivel12 + #343, #127
  static Nivel12 + #344, #127
  static Nivel12 + #345, #127
  static Nivel12 + #346, #127
  static Nivel12 + #347, #127
  static Nivel12 + #348, #127
  static Nivel12 + #349, #127
  static Nivel12 + #350, #127
  static Nivel12 + #351, #127
  static Nivel12 + #352, #127
  static Nivel12 + #353, #127
  static Nivel12 + #354, #127
  static Nivel12 + #355, #127
  static Nivel12 + #356, #127
  static Nivel12 + #357, #127
  static Nivel12 + #358, #127
  static Nivel12 + #359, #127

  ;Linha 9
  static Nivel12 + #360, #127
  static Nivel12 + #361, #127
  static Nivel12 + #362, #127
  static Nivel12 + #363, #127
  static Nivel12 + #364, #127
  static Nivel12 + #365, #127
  static Nivel12 + #366, #127
  static Nivel12 + #367, #127
  static Nivel12 + #368, #127
  static Nivel12 + #369, #127
  static Nivel12 + #370, #127
  static Nivel12 + #371, #127
  static Nivel12 + #372, #127
  static Nivel12 + #373, #127
  static Nivel12 + #374, #127
  static Nivel12 + #375, #127
  static Nivel12 + #376, #127
  static Nivel12 + #377, #127
  static Nivel12 + #378, #127
  static Nivel12 + #379, #127
  static Nivel12 + #380, #127
  static Nivel12 + #381, #127
  static Nivel12 + #382, #127
  static Nivel12 + #383, #127
  static Nivel12 + #384, #127
  static Nivel12 + #385, #127
  static Nivel12 + #386, #127
  static Nivel12 + #387, #127
  static Nivel12 + #388, #127
  static Nivel12 + #389, #127
  static Nivel12 + #390, #127
  static Nivel12 + #391, #127
  static Nivel12 + #392, #127
  static Nivel12 + #393, #127
  static Nivel12 + #394, #127
  static Nivel12 + #395, #127
  static Nivel12 + #396, #127
  static Nivel12 + #397, #127
  static Nivel12 + #398, #127
  static Nivel12 + #399, #127

  ;Linha 10
  static Nivel12 + #400, #127
  static Nivel12 + #401, #127
  static Nivel12 + #402, #127
  static Nivel12 + #403, #127
  static Nivel12 + #404, #127
  static Nivel12 + #405, #127
  static Nivel12 + #406, #127
  static Nivel12 + #407, #127
  static Nivel12 + #408, #127
  static Nivel12 + #409, #127
  static Nivel12 + #410, #127
  static Nivel12 + #411, #127
  static Nivel12 + #412, #127
  static Nivel12 + #413, #127
  static Nivel12 + #414, #127
  static Nivel12 + #415, #127
  static Nivel12 + #416, #127
  static Nivel12 + #417, #127
  static Nivel12 + #418, #127
  static Nivel12 + #419, #127
  static Nivel12 + #420, #127
  static Nivel12 + #421, #127
  static Nivel12 + #422, #127
  static Nivel12 + #423, #127
  static Nivel12 + #424, #127
  static Nivel12 + #425, #127
  static Nivel12 + #426, #127
  static Nivel12 + #427, #127
  static Nivel12 + #428, #127
  static Nivel12 + #429, #127
  static Nivel12 + #430, #127
  static Nivel12 + #431, #127
  static Nivel12 + #432, #127
  static Nivel12 + #433, #127
  static Nivel12 + #434, #127
  static Nivel12 + #435, #127
  static Nivel12 + #436, #127
  static Nivel12 + #437, #127
  static Nivel12 + #438, #127
  static Nivel12 + #439, #127

  ;Linha 11
  static Nivel12 + #440, #127
  static Nivel12 + #441, #127
  static Nivel12 + #442, #127
  static Nivel12 + #443, #127
  static Nivel12 + #444, #127
  static Nivel12 + #445, #127
  static Nivel12 + #446, #127
  static Nivel12 + #447, #127
  static Nivel12 + #448, #127
  static Nivel12 + #449, #127
  static Nivel12 + #450, #127
  static Nivel12 + #451, #127
  static Nivel12 + #452, #127
  static Nivel12 + #453, #127
  static Nivel12 + #454, #127
  static Nivel12 + #455, #127
  static Nivel12 + #456, #127
  static Nivel12 + #457, #127
  static Nivel12 + #458, #127
  static Nivel12 + #459, #127
  static Nivel12 + #460, #127
  static Nivel12 + #461, #127
  static Nivel12 + #462, #127
  static Nivel12 + #463, #127
  static Nivel12 + #464, #127
  static Nivel12 + #465, #127
  static Nivel12 + #466, #127
  static Nivel12 + #467, #127
  static Nivel12 + #468, #127
  static Nivel12 + #469, #127
  static Nivel12 + #470, #127
  static Nivel12 + #471, #127
  static Nivel12 + #472, #127
  static Nivel12 + #473, #127
  static Nivel12 + #474, #127
  static Nivel12 + #475, #127
  static Nivel12 + #476, #127
  static Nivel12 + #477, #127
  static Nivel12 + #478, #127
  static Nivel12 + #479, #127

  ;Linha 12
  static Nivel12 + #480, #127
  static Nivel12 + #481, #127
  static Nivel12 + #482, #127
  static Nivel12 + #483, #127
  static Nivel12 + #484, #127
  static Nivel12 + #485, #127
  static Nivel12 + #486, #127
  static Nivel12 + #487, #127
  static Nivel12 + #488, #127
  static Nivel12 + #489, #127
  static Nivel12 + #490, #127
  static Nivel12 + #491, #127
  static Nivel12 + #492, #127
  static Nivel12 + #493, #127
  static Nivel12 + #494, #127
  static Nivel12 + #495, #127
  static Nivel12 + #496, #127
  static Nivel12 + #497, #127
  static Nivel12 + #498, #127
  static Nivel12 + #499, #127
  static Nivel12 + #500, #127
  static Nivel12 + #501, #127
  static Nivel12 + #502, #127
  static Nivel12 + #503, #127
  static Nivel12 + #504, #127
  static Nivel12 + #505, #127
  static Nivel12 + #506, #127
  static Nivel12 + #507, #127
  static Nivel12 + #508, #127
  static Nivel12 + #509, #127
  static Nivel12 + #510, #127
  static Nivel12 + #511, #127
  static Nivel12 + #512, #127
  static Nivel12 + #513, #127
  static Nivel12 + #514, #127
  static Nivel12 + #515, #127
  static Nivel12 + #516, #127
  static Nivel12 + #517, #127
  static Nivel12 + #518, #127
  static Nivel12 + #519, #127

  ;Linha 13
  static Nivel12 + #520, #127
  static Nivel12 + #521, #127
  static Nivel12 + #522, #127
  static Nivel12 + #523, #127
  static Nivel12 + #524, #127
  static Nivel12 + #525, #127
  static Nivel12 + #526, #127
  static Nivel12 + #527, #127
  static Nivel12 + #528, #127
  static Nivel12 + #529, #127
  static Nivel12 + #530, #127
  static Nivel12 + #531, #127
  static Nivel12 + #532, #127
  static Nivel12 + #533, #127
  static Nivel12 + #534, #127
  static Nivel12 + #535, #127
  static Nivel12 + #536, #127
  static Nivel12 + #537, #127
  static Nivel12 + #538, #127
  static Nivel12 + #539, #127
  static Nivel12 + #540, #127
  static Nivel12 + #541, #127
  static Nivel12 + #542, #127
  static Nivel12 + #543, #127
  static Nivel12 + #544, #127
  static Nivel12 + #545, #127
  static Nivel12 + #546, #127
  static Nivel12 + #547, #127
  static Nivel12 + #548, #127
  static Nivel12 + #549, #127
  static Nivel12 + #550, #127
  static Nivel12 + #551, #127
  static Nivel12 + #552, #127
  static Nivel12 + #553, #127
  static Nivel12 + #554, #127
  static Nivel12 + #555, #127
  static Nivel12 + #556, #127
  static Nivel12 + #557, #127
  static Nivel12 + #558, #127
  static Nivel12 + #559, #127

  ;Linha 14
  static Nivel12 + #560, #127
  static Nivel12 + #561, #127
  static Nivel12 + #562, #127
  static Nivel12 + #563, #127
  static Nivel12 + #564, #127
  static Nivel12 + #565, #127
  static Nivel12 + #566, #127
  static Nivel12 + #567, #127
  static Nivel12 + #568, #127
  static Nivel12 + #569, #127
  static Nivel12 + #570, #127
  static Nivel12 + #571, #127
  static Nivel12 + #572, #127
  static Nivel12 + #573, #127
  static Nivel12 + #574, #127
  static Nivel12 + #575, #127
  static Nivel12 + #576, #127
  static Nivel12 + #577, #127
  static Nivel12 + #578, #127
  static Nivel12 + #579, #127
  static Nivel12 + #580, #127
  static Nivel12 + #581, #127
  static Nivel12 + #582, #127
  static Nivel12 + #583, #127
  static Nivel12 + #584, #127
  static Nivel12 + #585, #127
  static Nivel12 + #586, #127
  static Nivel12 + #587, #127
  static Nivel12 + #588, #127
  static Nivel12 + #589, #127
  static Nivel12 + #590, #127
  static Nivel12 + #591, #127
  static Nivel12 + #592, #127
  static Nivel12 + #593, #127
  static Nivel12 + #594, #127
  static Nivel12 + #595, #127
  static Nivel12 + #596, #127
  static Nivel12 + #597, #127
  static Nivel12 + #598, #127
  static Nivel12 + #599, #127

  ;Linha 15
  static Nivel12 + #600, #127
  static Nivel12 + #601, #127
  static Nivel12 + #602, #127
  static Nivel12 + #603, #127
  static Nivel12 + #604, #127
  static Nivel12 + #605, #127
  static Nivel12 + #606, #127
  static Nivel12 + #607, #127
  static Nivel12 + #608, #127
  static Nivel12 + #609, #127
  static Nivel12 + #610, #127
  static Nivel12 + #611, #127
  static Nivel12 + #612, #127
  static Nivel12 + #613, #127
  static Nivel12 + #614, #127
  static Nivel12 + #615, #127
  static Nivel12 + #616, #127
  static Nivel12 + #617, #127
  static Nivel12 + #618, #127
  static Nivel12 + #619, #127
  static Nivel12 + #620, #127
  static Nivel12 + #621, #127
  static Nivel12 + #622, #127
  static Nivel12 + #623, #127
  static Nivel12 + #624, #127
  static Nivel12 + #625, #127
  static Nivel12 + #626, #127
  static Nivel12 + #627, #127
  static Nivel12 + #628, #127
  static Nivel12 + #629, #127
  static Nivel12 + #630, #127
  static Nivel12 + #631, #127
  static Nivel12 + #632, #127
  static Nivel12 + #633, #127
  static Nivel12 + #634, #127
  static Nivel12 + #635, #127
  static Nivel12 + #636, #127
  static Nivel12 + #637, #127
  static Nivel12 + #638, #127
  static Nivel12 + #639, #127

  ;Linha 16
  static Nivel12 + #640, #127
  static Nivel12 + #641, #127
  static Nivel12 + #642, #127
  static Nivel12 + #643, #127
  static Nivel12 + #644, #127
  static Nivel12 + #645, #127
  static Nivel12 + #646, #127
  static Nivel12 + #647, #127
  static Nivel12 + #648, #127
  static Nivel12 + #649, #127
  static Nivel12 + #650, #127
  static Nivel12 + #651, #127
  static Nivel12 + #652, #127
  static Nivel12 + #653, #127
  static Nivel12 + #654, #127
  static Nivel12 + #655, #127
  static Nivel12 + #656, #127
  static Nivel12 + #657, #127
  static Nivel12 + #658, #127
  static Nivel12 + #659, #127
  static Nivel12 + #660, #127
  static Nivel12 + #661, #127
  static Nivel12 + #662, #127
  static Nivel12 + #663, #127
  static Nivel12 + #664, #127
  static Nivel12 + #665, #127
  static Nivel12 + #666, #127
  static Nivel12 + #667, #127
  static Nivel12 + #668, #127
  static Nivel12 + #669, #127
  static Nivel12 + #670, #127
  static Nivel12 + #671, #127
  static Nivel12 + #672, #127
  static Nivel12 + #673, #127
  static Nivel12 + #674, #127
  static Nivel12 + #675, #127
  static Nivel12 + #676, #127
  static Nivel12 + #677, #127
  static Nivel12 + #678, #127
  static Nivel12 + #679, #127

  ;Linha 17
  static Nivel12 + #680, #127
  static Nivel12 + #681, #127
  static Nivel12 + #682, #127
  static Nivel12 + #683, #127
  static Nivel12 + #684, #127
  static Nivel12 + #685, #127
  static Nivel12 + #686, #127
  static Nivel12 + #687, #127
  static Nivel12 + #688, #127
  static Nivel12 + #689, #127
  static Nivel12 + #690, #127
  static Nivel12 + #691, #127
  static Nivel12 + #692, #127
  static Nivel12 + #693, #127
  static Nivel12 + #694, #127
  static Nivel12 + #695, #127
  static Nivel12 + #696, #127
  static Nivel12 + #697, #127
  static Nivel12 + #698, #127
  static Nivel12 + #699, #127
  static Nivel12 + #700, #127
  static Nivel12 + #701, #127
  static Nivel12 + #702, #127
  static Nivel12 + #703, #127
  static Nivel12 + #704, #127
  static Nivel12 + #705, #127
  static Nivel12 + #706, #127
  static Nivel12 + #707, #127
  static Nivel12 + #708, #127
  static Nivel12 + #709, #127
  static Nivel12 + #710, #127
  static Nivel12 + #711, #127
  static Nivel12 + #712, #127
  static Nivel12 + #713, #127
  static Nivel12 + #714, #127
  static Nivel12 + #715, #127
  static Nivel12 + #716, #127
  static Nivel12 + #717, #127
  static Nivel12 + #718, #127
  static Nivel12 + #719, #127

  ;Linha 18
  static Nivel12 + #720, #127
  static Nivel12 + #721, #127
  static Nivel12 + #722, #127
  static Nivel12 + #723, #127
  static Nivel12 + #724, #127
  static Nivel12 + #725, #127
  static Nivel12 + #726, #127
  static Nivel12 + #727, #127
  static Nivel12 + #728, #127
  static Nivel12 + #729, #127
  static Nivel12 + #730, #127
  static Nivel12 + #731, #127
  static Nivel12 + #732, #127
  static Nivel12 + #733, #127
  static Nivel12 + #734, #127
  static Nivel12 + #735, #127
  static Nivel12 + #736, #127
  static Nivel12 + #737, #127
  static Nivel12 + #738, #127
  static Nivel12 + #739, #127
  static Nivel12 + #740, #127
  static Nivel12 + #741, #127
  static Nivel12 + #742, #127
  static Nivel12 + #743, #127
  static Nivel12 + #744, #127
  static Nivel12 + #745, #127
  static Nivel12 + #746, #127
  static Nivel12 + #747, #127
  static Nivel12 + #748, #127
  static Nivel12 + #749, #127
  static Nivel12 + #750, #127
  static Nivel12 + #751, #127
  static Nivel12 + #752, #127
  static Nivel12 + #753, #127
  static Nivel12 + #754, #127
  static Nivel12 + #755, #127
  static Nivel12 + #756, #127
  static Nivel12 + #757, #127
  static Nivel12 + #758, #127
  static Nivel12 + #759, #127

  ;Linha 19
  static Nivel12 + #760, #127
  static Nivel12 + #761, #127
  static Nivel12 + #762, #127
  static Nivel12 + #763, #127
  static Nivel12 + #764, #127
  static Nivel12 + #765, #127
  static Nivel12 + #766, #127
  static Nivel12 + #767, #127
  static Nivel12 + #768, #127
  static Nivel12 + #769, #127
  static Nivel12 + #770, #3967
  static Nivel12 + #771, #127
  static Nivel12 + #772, #127
  static Nivel12 + #773, #127
  static Nivel12 + #774, #127
  static Nivel12 + #775, #127
  static Nivel12 + #776, #127
  static Nivel12 + #777, #127
  static Nivel12 + #778, #127
  static Nivel12 + #779, #127
  static Nivel12 + #780, #127
  static Nivel12 + #781, #127
  static Nivel12 + #782, #127
  static Nivel12 + #783, #127
  static Nivel12 + #784, #127
  static Nivel12 + #785, #127
  static Nivel12 + #786, #127
  static Nivel12 + #787, #127
  static Nivel12 + #788, #127
  static Nivel12 + #789, #127
  static Nivel12 + #790, #127
  static Nivel12 + #791, #127
  static Nivel12 + #792, #127
  static Nivel12 + #793, #127
  static Nivel12 + #794, #127
  static Nivel12 + #795, #127
  static Nivel12 + #796, #127
  static Nivel12 + #797, #127
  static Nivel12 + #798, #127
  static Nivel12 + #799, #127

  ;Linha 20
  static Nivel12 + #800, #127
  static Nivel12 + #801, #127
  static Nivel12 + #802, #127
  static Nivel12 + #803, #127
  static Nivel12 + #804, #127
  static Nivel12 + #805, #127
  static Nivel12 + #806, #127
  static Nivel12 + #807, #257
  static Nivel12 + #808, #257
  static Nivel12 + #809, #257
  static Nivel12 + #810, #2818
  static Nivel12 + #811, #257
  static Nivel12 + #812, #127
  static Nivel12 + #813, #127
  static Nivel12 + #814, #127
  static Nivel12 + #815, #127
  static Nivel12 + #816, #127
  static Nivel12 + #817, #127
  static Nivel12 + #818, #127
  static Nivel12 + #819, #127
  static Nivel12 + #820, #127
  static Nivel12 + #821, #127
  static Nivel12 + #822, #127
  static Nivel12 + #823, #127
  static Nivel12 + #824, #127
  static Nivel12 + #825, #127
  static Nivel12 + #826, #127
  static Nivel12 + #827, #127
  static Nivel12 + #828, #127
  static Nivel12 + #829, #127
  static Nivel12 + #830, #127
  static Nivel12 + #831, #127
  static Nivel12 + #832, #127
  static Nivel12 + #833, #127
  static Nivel12 + #834, #127
  static Nivel12 + #835, #127
  static Nivel12 + #836, #127
  static Nivel12 + #837, #127
  static Nivel12 + #838, #127
  static Nivel12 + #839, #127

  ;Linha 21
  static Nivel12 + #840, #127
  static Nivel12 + #841, #127
  static Nivel12 + #842, #127
  static Nivel12 + #843, #127
  static Nivel12 + #844, #127
  static Nivel12 + #845, #127
  static Nivel12 + #846, #127
  static Nivel12 + #847, #127
  static Nivel12 + #848, #3967
  static Nivel12 + #849, #127
  static Nivel12 + #850, #127
  static Nivel12 + #851, #127
  static Nivel12 + #852, #127
  static Nivel12 + #853, #127
  static Nivel12 + #854, #127
  static Nivel12 + #855, #127
  static Nivel12 + #856, #127
  static Nivel12 + #857, #127
  static Nivel12 + #858, #127
  static Nivel12 + #859, #127
  static Nivel12 + #860, #127
  static Nivel12 + #861, #127
  static Nivel12 + #862, #127
  static Nivel12 + #863, #127
  static Nivel12 + #864, #127
  static Nivel12 + #865, #127
  static Nivel12 + #866, #127
  static Nivel12 + #867, #127
  static Nivel12 + #868, #127
  static Nivel12 + #869, #127
  static Nivel12 + #870, #127
  static Nivel12 + #871, #127
  static Nivel12 + #872, #127
  static Nivel12 + #873, #127
  static Nivel12 + #874, #127
  static Nivel12 + #875, #127
  static Nivel12 + #876, #127
  static Nivel12 + #877, #127
  static Nivel12 + #878, #127
  static Nivel12 + #879, #127

  ;Linha 22
  static Nivel12 + #880, #127
  static Nivel12 + #881, #127
  static Nivel12 + #882, #127
  static Nivel12 + #883, #127
  static Nivel12 + #884, #127
  static Nivel12 + #885, #127
  static Nivel12 + #886, #127
  static Nivel12 + #887, #127
  static Nivel12 + #888, #127
  static Nivel12 + #889, #3967
  static Nivel12 + #890, #3967
  static Nivel12 + #891, #127
  static Nivel12 + #892, #127
  static Nivel12 + #893, #127
  static Nivel12 + #894, #127
  static Nivel12 + #895, #127
  static Nivel12 + #896, #127
  static Nivel12 + #897, #127
  static Nivel12 + #898, #127
  static Nivel12 + #899, #127
  static Nivel12 + #900, #127
  static Nivel12 + #901, #127
  static Nivel12 + #902, #127
  static Nivel12 + #903, #127
  static Nivel12 + #904, #127
  static Nivel12 + #905, #127
  static Nivel12 + #906, #127
  static Nivel12 + #907, #127
  static Nivel12 + #908, #127
  static Nivel12 + #909, #127
  static Nivel12 + #910, #127
  static Nivel12 + #911, #127
  static Nivel12 + #912, #127
  static Nivel12 + #913, #127
  static Nivel12 + #914, #127
  static Nivel12 + #915, #127
  static Nivel12 + #916, #127
  static Nivel12 + #917, #127
  static Nivel12 + #918, #127
  static Nivel12 + #919, #127

  ;Linha 23
  static Nivel12 + #920, #127
  static Nivel12 + #921, #127
  static Nivel12 + #922, #127
  static Nivel12 + #923, #127
  static Nivel12 + #924, #127
  static Nivel12 + #925, #127
  static Nivel12 + #926, #127
  static Nivel12 + #927, #127
  static Nivel12 + #928, #127
  static Nivel12 + #929, #127
  static Nivel12 + #930, #3967
  static Nivel12 + #931, #127
  static Nivel12 + #932, #127
  static Nivel12 + #933, #127
  static Nivel12 + #934, #127
  static Nivel12 + #935, #127
  static Nivel12 + #936, #127
  static Nivel12 + #937, #127
  static Nivel12 + #938, #127
  static Nivel12 + #939, #127
  static Nivel12 + #940, #127
  static Nivel12 + #941, #127
  static Nivel12 + #942, #127
  static Nivel12 + #943, #127
  static Nivel12 + #944, #127
  static Nivel12 + #945, #127
  static Nivel12 + #946, #127
  static Nivel12 + #947, #127
  static Nivel12 + #948, #127
  static Nivel12 + #949, #127
  static Nivel12 + #950, #127
  static Nivel12 + #951, #127
  static Nivel12 + #952, #127
  static Nivel12 + #953, #127
  static Nivel12 + #954, #127
  static Nivel12 + #955, #127
  static Nivel12 + #956, #127
  static Nivel12 + #957, #127
  static Nivel12 + #958, #127
  static Nivel12 + #959, #127

  ;Linha 24
  static Nivel12 + #960, #127
  static Nivel12 + #961, #127
  static Nivel12 + #962, #127
  static Nivel12 + #963, #127
  static Nivel12 + #964, #257
  static Nivel12 + #965, #2818
  static Nivel12 + #966, #257
  static Nivel12 + #967, #257
  static Nivel12 + #968, #257
  static Nivel12 + #969, #257
  static Nivel12 + #970, #2818
  static Nivel12 + #971, #257
  static Nivel12 + #972, #3967
  static Nivel12 + #973, #127
  static Nivel12 + #974, #127
  static Nivel12 + #975, #127
  static Nivel12 + #976, #127
  static Nivel12 + #977, #127
  static Nivel12 + #978, #263
  static Nivel12 + #979, #127
  static Nivel12 + #980, #127
  static Nivel12 + #981, #127
  static Nivel12 + #982, #127
  static Nivel12 + #983, #127
  static Nivel12 + #984, #127
  static Nivel12 + #985, #127
  static Nivel12 + #986, #127
  static Nivel12 + #987, #127
  static Nivel12 + #988, #3967
  static Nivel12 + #989, #516
  static Nivel12 + #990, #516
  static Nivel12 + #991, #127
  static Nivel12 + #992, #127
  static Nivel12 + #993, #127
  static Nivel12 + #994, #127
  static Nivel12 + #995, #127
  static Nivel12 + #996, #127
  static Nivel12 + #997, #127
  static Nivel12 + #998, #127
  static Nivel12 + #999, #127

  ;Linha 25
  static Nivel12 + #1000, #127
  static Nivel12 + #1001, #127
  static Nivel12 + #1002, #127
  static Nivel12 + #1003, #127
  static Nivel12 + #1004, #127
  static Nivel12 + #1005, #127
  static Nivel12 + #1006, #127
  static Nivel12 + #1007, #127
  static Nivel12 + #1008, #127
  static Nivel12 + #1009, #127
  static Nivel12 + #1010, #127
  static Nivel12 + #1011, #127
  static Nivel12 + #1012, #127
  static Nivel12 + #1013, #127
  static Nivel12 + #1014, #127
  static Nivel12 + #1015, #3967
  static Nivel12 + #1016, #3967
  static Nivel12 + #1017, #263
  static Nivel12 + #1018, #263
  static Nivel12 + #1019, #127
  static Nivel12 + #1020, #127
  static Nivel12 + #1021, #127
  static Nivel12 + #1022, #127
  static Nivel12 + #1023, #127
  static Nivel12 + #1024, #127
  static Nivel12 + #1025, #127
  static Nivel12 + #1026, #127
  static Nivel12 + #1027, #127
  static Nivel12 + #1028, #127
  static Nivel12 + #1029, #2563
  static Nivel12 + #1030, #2565
  static Nivel12 + #1031, #127
  static Nivel12 + #1032, #127
  static Nivel12 + #1033, #127
  static Nivel12 + #1034, #127
  static Nivel12 + #1035, #127
  static Nivel12 + #1036, #516
  static Nivel12 + #1037, #516
  static Nivel12 + #1038, #127
  static Nivel12 + #1039, #127

  ;Linha 26
  static Nivel12 + #1040, #127
  static Nivel12 + #1041, #127
  static Nivel12 + #1042, #127
  static Nivel12 + #1043, #127
  static Nivel12 + #1044, #127
  static Nivel12 + #1045, #127
  static Nivel12 + #1046, #127
  static Nivel12 + #1047, #127
  static Nivel12 + #1048, #127
  static Nivel12 + #1049, #127
  static Nivel12 + #1050, #127
  static Nivel12 + #1051, #127
  static Nivel12 + #1052, #127
  static Nivel12 + #1053, #127
  static Nivel12 + #1054, #127
  static Nivel12 + #1055, #3967
  static Nivel12 + #1056, #263
  static Nivel12 + #1057, #263
  static Nivel12 + #1058, #263
  static Nivel12 + #1059, #127
  static Nivel12 + #1060, #127
  static Nivel12 + #1061, #127
  static Nivel12 + #1062, #127
  static Nivel12 + #1063, #127
  static Nivel12 + #1064, #127
  static Nivel12 + #1065, #127
  static Nivel12 + #1066, #127
  static Nivel12 + #1067, #127
  static Nivel12 + #1068, #127
  static Nivel12 + #1069, #2563
  static Nivel12 + #1070, #2565
  static Nivel12 + #1071, #127
  static Nivel12 + #1072, #127
  static Nivel12 + #1073, #3967
  static Nivel12 + #1074, #3967
  static Nivel12 + #1075, #127
  static Nivel12 + #1076, #2563
  static Nivel12 + #1077, #2565
  static Nivel12 + #1078, #127
  static Nivel12 + #1079, #127

  ;Linha 27
  static Nivel12 + #1080, #127
  static Nivel12 + #1081, #127
  static Nivel12 + #1082, #127
  static Nivel12 + #1083, #127
  static Nivel12 + #1084, #127
  static Nivel12 + #1085, #127
  static Nivel12 + #1086, #127
  static Nivel12 + #1087, #127
  static Nivel12 + #1088, #127
  static Nivel12 + #1089, #127
  static Nivel12 + #1090, #127
  static Nivel12 + #1091, #127
  static Nivel12 + #1092, #127
  static Nivel12 + #1093, #127
  static Nivel12 + #1094, #127
  static Nivel12 + #1095, #263
  static Nivel12 + #1096, #263
  static Nivel12 + #1097, #263
  static Nivel12 + #1098, #263
  static Nivel12 + #1099, #127
  static Nivel12 + #1100, #127
  static Nivel12 + #1101, #127
  static Nivel12 + #1102, #127
  static Nivel12 + #1103, #127
  static Nivel12 + #1104, #127
  static Nivel12 + #1105, #3967
  static Nivel12 + #1106, #127
  static Nivel12 + #1107, #127
  static Nivel12 + #1108, #127
  static Nivel12 + #1109, #2563
  static Nivel12 + #1110, #2565
  static Nivel12 + #1111, #127
  static Nivel12 + #1112, #127
  static Nivel12 + #1113, #3967
  static Nivel12 + #1114, #3967
  static Nivel12 + #1115, #127
  static Nivel12 + #1116, #2563
  static Nivel12 + #1117, #2565
  static Nivel12 + #1118, #3967
  static Nivel12 + #1119, #127

  ;Linha 28
  static Nivel12 + #1120, #256
  static Nivel12 + #1121, #256
  static Nivel12 + #1122, #256
  static Nivel12 + #1123, #256
  static Nivel12 + #1124, #256
  static Nivel12 + #1125, #256
  static Nivel12 + #1126, #3967
  static Nivel12 + #1127, #3967
  static Nivel12 + #1128, #3967
  static Nivel12 + #1129, #3967
  static Nivel12 + #1130, #256
  static Nivel12 + #1131, #256
  static Nivel12 + #1132, #256
  static Nivel12 + #1133, #256
  static Nivel12 + #1134, #256
  static Nivel12 + #1135, #256
  static Nivel12 + #1136, #256
  static Nivel12 + #1137, #256
  static Nivel12 + #1138, #256
  static Nivel12 + #1139, #3967
  static Nivel12 + #1140, #3967
  static Nivel12 + #1141, #3967
  static Nivel12 + #1142, #3967
  static Nivel12 + #1143, #3967
  static Nivel12 + #1144, #256
  static Nivel12 + #1145, #256
  static Nivel12 + #1146, #256
  static Nivel12 + #1147, #256
  static Nivel12 + #1148, #256
  static Nivel12 + #1149, #256
  static Nivel12 + #1150, #256
  static Nivel12 + #1151, #256
  static Nivel12 + #1152, #256
  static Nivel12 + #1153, #256
  static Nivel12 + #1154, #256
  static Nivel12 + #1155, #256
  static Nivel12 + #1156, #256
  static Nivel12 + #1157, #256
  static Nivel12 + #1158, #256
  static Nivel12 + #1159, #256

  ;Linha 29
  static Nivel12 + #1160, #256
  static Nivel12 + #1161, #256
  static Nivel12 + #1162, #256
  static Nivel12 + #1163, #256
  static Nivel12 + #1164, #256
  static Nivel12 + #1165, #256
  static Nivel12 + #1166, #3967
  static Nivel12 + #1167, #3967
  static Nivel12 + #1168, #3967
  static Nivel12 + #1169, #3967
  static Nivel12 + #1170, #256
  static Nivel12 + #1171, #256
  static Nivel12 + #1172, #256
  static Nivel12 + #1173, #256
  static Nivel12 + #1174, #256
  static Nivel12 + #1175, #256
  static Nivel12 + #1176, #256
  static Nivel12 + #1177, #256
  static Nivel12 + #1178, #256
  static Nivel12 + #1179, #3967
  static Nivel12 + #1180, #3967
  static Nivel12 + #1181, #3967
  static Nivel12 + #1182, #3967
  static Nivel12 + #1183, #3967
  static Nivel12 + #1184, #256
  static Nivel12 + #1185, #256
  static Nivel12 + #1186, #256
  static Nivel12 + #1187, #256
  static Nivel12 + #1188, #256
  static Nivel12 + #1189, #256
  static Nivel12 + #1190, #256
  static Nivel12 + #1191, #256
  static Nivel12 + #1192, #256
  static Nivel12 + #1193, #256
  static Nivel12 + #1194, #256
  static Nivel12 + #1195, #256
  static Nivel12 + #1196, #256
  static Nivel12 + #1197, #256
  static Nivel12 + #1198, #256
  static Nivel12 + #1199, #256

printNivel12Screen:
  push R0
  push R1
  push R2
  push R3

  loadn R0, #Nivel12
  loadn R1, #0
  loadn R2, #1200

  printNivel12ScreenLoop:

    add R3,R0,R1
    loadi R3, R3
    outchar R3, R1
    inc R1
    cmp R1, R2

    jne printNivel12ScreenLoop

  pop R3
  pop R2
  pop R1
  pop R0
  rts

Nivel13 : var #1200
  ;Linha 0
  static Nivel13 + #0, #3967
  static Nivel13 + #1, #3967
  static Nivel13 + #2, #1798
  static Nivel13 + #3, #1798
  static Nivel13 + #4, #1798
  static Nivel13 + #5, #3967
  static Nivel13 + #6, #3967
  static Nivel13 + #7, #1798
  static Nivel13 + #8, #1798
  static Nivel13 + #9, #1798
  static Nivel13 + #10, #1798
  static Nivel13 + #11, #1798
  static Nivel13 + #12, #1798
  static Nivel13 + #13, #1798
  static Nivel13 + #14, #1798
  static Nivel13 + #15, #1798
  static Nivel13 + #16, #1798
  static Nivel13 + #17, #1798
  static Nivel13 + #18, #3967
  static Nivel13 + #19, #3967
  static Nivel13 + #20, #3967
  static Nivel13 + #21, #3967
  static Nivel13 + #22, #1798
  static Nivel13 + #23, #1798
  static Nivel13 + #24, #3967
  static Nivel13 + #25, #3967
  static Nivel13 + #26, #3967
  static Nivel13 + #27, #1798
  static Nivel13 + #28, #1798
  static Nivel13 + #29, #1798
  static Nivel13 + #30, #1798
  static Nivel13 + #31, #1798
  static Nivel13 + #32, #1798
  static Nivel13 + #33, #1798
  static Nivel13 + #34, #1798
  static Nivel13 + #35, #1798
  static Nivel13 + #36, #1798
  static Nivel13 + #37, #1798
  static Nivel13 + #38, #1798
  static Nivel13 + #39, #1798

  ;Linha 1
  static Nivel13 + #40, #3967
  static Nivel13 + #41, #3967
  static Nivel13 + #42, #3967
  static Nivel13 + #43, #1798
  static Nivel13 + #44, #3967
  static Nivel13 + #45, #3967
  static Nivel13 + #46, #3967
  static Nivel13 + #47, #3967
  static Nivel13 + #48, #3967
  static Nivel13 + #49, #1798
  static Nivel13 + #50, #1798
  static Nivel13 + #51, #1798
  static Nivel13 + #52, #1798
  static Nivel13 + #53, #1798
  static Nivel13 + #54, #1798
  static Nivel13 + #55, #1798
  static Nivel13 + #56, #3967
  static Nivel13 + #57, #3967
  static Nivel13 + #58, #3967
  static Nivel13 + #59, #3967
  static Nivel13 + #60, #3967
  static Nivel13 + #61, #3967
  static Nivel13 + #62, #3967
  static Nivel13 + #63, #3967
  static Nivel13 + #64, #3967
  static Nivel13 + #65, #3967
  static Nivel13 + #66, #3967
  static Nivel13 + #67, #3967
  static Nivel13 + #68, #3967
  static Nivel13 + #69, #127
  static Nivel13 + #70, #1798
  static Nivel13 + #71, #1798
  static Nivel13 + #72, #1798
  static Nivel13 + #73, #1798
  static Nivel13 + #74, #1798
  static Nivel13 + #75, #1798
  static Nivel13 + #76, #1798
  static Nivel13 + #77, #1798
  static Nivel13 + #78, #1798
  static Nivel13 + #79, #1798

  ;Linha 2
  static Nivel13 + #80, #3967
  static Nivel13 + #81, #3967
  static Nivel13 + #82, #3967
  static Nivel13 + #83, #3967
  static Nivel13 + #84, #3967
  static Nivel13 + #85, #3967
  static Nivel13 + #86, #3967
  static Nivel13 + #87, #3967
  static Nivel13 + #88, #3967
  static Nivel13 + #89, #3967
  static Nivel13 + #90, #1798
  static Nivel13 + #91, #1798
  static Nivel13 + #92, #1798
  static Nivel13 + #93, #3967
  static Nivel13 + #94, #127
  static Nivel13 + #95, #127
  static Nivel13 + #96, #127
  static Nivel13 + #97, #3967
  static Nivel13 + #98, #3967
  static Nivel13 + #99, #3967
  static Nivel13 + #100, #3967
  static Nivel13 + #101, #3967
  static Nivel13 + #102, #3967
  static Nivel13 + #103, #3967
  static Nivel13 + #104, #3967
  static Nivel13 + #105, #3967
  static Nivel13 + #106, #3967
  static Nivel13 + #107, #3967
  static Nivel13 + #108, #3967
  static Nivel13 + #109, #127
  static Nivel13 + #110, #127
  static Nivel13 + #111, #127
  static Nivel13 + #112, #127
  static Nivel13 + #113, #127
  static Nivel13 + #114, #1798
  static Nivel13 + #115, #1798
  static Nivel13 + #116, #1798
  static Nivel13 + #117, #1798
  static Nivel13 + #118, #1798
  static Nivel13 + #119, #1798

  ;Linha 3
  static Nivel13 + #120, #127
  static Nivel13 + #121, #3967
  static Nivel13 + #122, #3967
  static Nivel13 + #123, #3967
  static Nivel13 + #124, #127
  static Nivel13 + #125, #127
  static Nivel13 + #126, #127
  static Nivel13 + #127, #127
  static Nivel13 + #128, #127
  static Nivel13 + #129, #127
  static Nivel13 + #130, #127
  static Nivel13 + #131, #127
  static Nivel13 + #132, #127
  static Nivel13 + #133, #127
  static Nivel13 + #134, #127
  static Nivel13 + #135, #127
  static Nivel13 + #136, #127
  static Nivel13 + #137, #3967
  static Nivel13 + #138, #3967
  static Nivel13 + #139, #3967
  static Nivel13 + #140, #3967
  static Nivel13 + #141, #3967
  static Nivel13 + #142, #3967
  static Nivel13 + #143, #3967
  static Nivel13 + #144, #3967
  static Nivel13 + #145, #3967
  static Nivel13 + #146, #3967
  static Nivel13 + #147, #3967
  static Nivel13 + #148, #3967
  static Nivel13 + #149, #3967
  static Nivel13 + #150, #127
  static Nivel13 + #151, #127
  static Nivel13 + #152, #127
  static Nivel13 + #153, #127
  static Nivel13 + #154, #127
  static Nivel13 + #155, #1798
  static Nivel13 + #156, #1798
  static Nivel13 + #157, #1798
  static Nivel13 + #158, #1798
  static Nivel13 + #159, #1798

  ;Linha 4
  static Nivel13 + #160, #127
  static Nivel13 + #161, #127
  static Nivel13 + #162, #127
  static Nivel13 + #163, #127
  static Nivel13 + #164, #127
  static Nivel13 + #165, #127
  static Nivel13 + #166, #127
  static Nivel13 + #167, #127
  static Nivel13 + #168, #127
  static Nivel13 + #169, #127
  static Nivel13 + #170, #127
  static Nivel13 + #171, #127
  static Nivel13 + #172, #127
  static Nivel13 + #173, #127
  static Nivel13 + #174, #127
  static Nivel13 + #175, #127
  static Nivel13 + #176, #127
  static Nivel13 + #177, #127
  static Nivel13 + #178, #3967
  static Nivel13 + #179, #3967
  static Nivel13 + #180, #3967
  static Nivel13 + #181, #3967
  static Nivel13 + #182, #3967
  static Nivel13 + #183, #3967
  static Nivel13 + #184, #3967
  static Nivel13 + #185, #3967
  static Nivel13 + #186, #127
  static Nivel13 + #187, #127
  static Nivel13 + #188, #127
  static Nivel13 + #189, #3967
  static Nivel13 + #190, #3967
  static Nivel13 + #191, #127
  static Nivel13 + #192, #127
  static Nivel13 + #193, #127
  static Nivel13 + #194, #127
  static Nivel13 + #195, #1798
  static Nivel13 + #196, #1798
  static Nivel13 + #197, #1798
  static Nivel13 + #198, #1798
  static Nivel13 + #199, #127

  ;Linha 5
  static Nivel13 + #200, #127
  static Nivel13 + #201, #127
  static Nivel13 + #202, #127
  static Nivel13 + #203, #127
  static Nivel13 + #204, #127
  static Nivel13 + #205, #127
  static Nivel13 + #206, #127
  static Nivel13 + #207, #127
  static Nivel13 + #208, #127
  static Nivel13 + #209, #127
  static Nivel13 + #210, #127
  static Nivel13 + #211, #127
  static Nivel13 + #212, #127
  static Nivel13 + #213, #127
  static Nivel13 + #214, #127
  static Nivel13 + #215, #127
  static Nivel13 + #216, #127
  static Nivel13 + #217, #127
  static Nivel13 + #218, #3967
  static Nivel13 + #219, #3967
  static Nivel13 + #220, #3967
  static Nivel13 + #221, #3967
  static Nivel13 + #222, #3967
  static Nivel13 + #223, #3967
  static Nivel13 + #224, #3967
  static Nivel13 + #225, #3967
  static Nivel13 + #226, #127
  static Nivel13 + #227, #127
  static Nivel13 + #228, #127
  static Nivel13 + #229, #127
  static Nivel13 + #230, #127
  static Nivel13 + #231, #127
  static Nivel13 + #232, #127
  static Nivel13 + #233, #127
  static Nivel13 + #234, #127
  static Nivel13 + #235, #127
  static Nivel13 + #236, #1798
  static Nivel13 + #237, #1798
  static Nivel13 + #238, #127
  static Nivel13 + #239, #127

  ;Linha 6
  static Nivel13 + #240, #127
  static Nivel13 + #241, #127
  static Nivel13 + #242, #127
  static Nivel13 + #243, #127
  static Nivel13 + #244, #127
  static Nivel13 + #245, #127
  static Nivel13 + #246, #127
  static Nivel13 + #247, #127
  static Nivel13 + #248, #127
  static Nivel13 + #249, #127
  static Nivel13 + #250, #127
  static Nivel13 + #251, #127
  static Nivel13 + #252, #127
  static Nivel13 + #253, #127
  static Nivel13 + #254, #127
  static Nivel13 + #255, #127
  static Nivel13 + #256, #127
  static Nivel13 + #257, #127
  static Nivel13 + #258, #127
  static Nivel13 + #259, #127
  static Nivel13 + #260, #127
  static Nivel13 + #261, #127
  static Nivel13 + #262, #127
  static Nivel13 + #263, #127
  static Nivel13 + #264, #3967
  static Nivel13 + #265, #3967
  static Nivel13 + #266, #127
  static Nivel13 + #267, #127
  static Nivel13 + #268, #127
  static Nivel13 + #269, #127
  static Nivel13 + #270, #127
  static Nivel13 + #271, #127
  static Nivel13 + #272, #127
  static Nivel13 + #273, #127
  static Nivel13 + #274, #127
  static Nivel13 + #275, #127
  static Nivel13 + #276, #127
  static Nivel13 + #277, #127
  static Nivel13 + #278, #127
  static Nivel13 + #279, #127

  ;Linha 7
  static Nivel13 + #280, #127
  static Nivel13 + #281, #127
  static Nivel13 + #282, #127
  static Nivel13 + #283, #127
  static Nivel13 + #284, #127
  static Nivel13 + #285, #127
  static Nivel13 + #286, #127
  static Nivel13 + #287, #127
  static Nivel13 + #288, #127
  static Nivel13 + #289, #127
  static Nivel13 + #290, #127
  static Nivel13 + #291, #127
  static Nivel13 + #292, #127
  static Nivel13 + #293, #127
  static Nivel13 + #294, #127
  static Nivel13 + #295, #127
  static Nivel13 + #296, #127
  static Nivel13 + #297, #127
  static Nivel13 + #298, #127
  static Nivel13 + #299, #127
  static Nivel13 + #300, #127
  static Nivel13 + #301, #127
  static Nivel13 + #302, #127
  static Nivel13 + #303, #127
  static Nivel13 + #304, #127
  static Nivel13 + #305, #127
  static Nivel13 + #306, #127
  static Nivel13 + #307, #127
  static Nivel13 + #308, #127
  static Nivel13 + #309, #127
  static Nivel13 + #310, #127
  static Nivel13 + #311, #127
  static Nivel13 + #312, #127
  static Nivel13 + #313, #127
  static Nivel13 + #314, #127
  static Nivel13 + #315, #127
  static Nivel13 + #316, #127
  static Nivel13 + #317, #127
  static Nivel13 + #318, #127
  static Nivel13 + #319, #127

  ;Linha 8
  static Nivel13 + #320, #127
  static Nivel13 + #321, #127
  static Nivel13 + #322, #127
  static Nivel13 + #323, #127
  static Nivel13 + #324, #127
  static Nivel13 + #325, #127
  static Nivel13 + #326, #127
  static Nivel13 + #327, #127
  static Nivel13 + #328, #127
  static Nivel13 + #329, #127
  static Nivel13 + #330, #127
  static Nivel13 + #331, #127
  static Nivel13 + #332, #127
  static Nivel13 + #333, #127
  static Nivel13 + #334, #127
  static Nivel13 + #335, #127
  static Nivel13 + #336, #127
  static Nivel13 + #337, #127
  static Nivel13 + #338, #127
  static Nivel13 + #339, #127
  static Nivel13 + #340, #127
  static Nivel13 + #341, #127
  static Nivel13 + #342, #127
  static Nivel13 + #343, #127
  static Nivel13 + #344, #127
  static Nivel13 + #345, #127
  static Nivel13 + #346, #127
  static Nivel13 + #347, #127
  static Nivel13 + #348, #127
  static Nivel13 + #349, #127
  static Nivel13 + #350, #127
  static Nivel13 + #351, #127
  static Nivel13 + #352, #127
  static Nivel13 + #353, #127
  static Nivel13 + #354, #127
  static Nivel13 + #355, #127
  static Nivel13 + #356, #127
  static Nivel13 + #357, #127
  static Nivel13 + #358, #127
  static Nivel13 + #359, #127

  ;Linha 9
  static Nivel13 + #360, #127
  static Nivel13 + #361, #127
  static Nivel13 + #362, #127
  static Nivel13 + #363, #127
  static Nivel13 + #364, #127
  static Nivel13 + #365, #127
  static Nivel13 + #366, #127
  static Nivel13 + #367, #127
  static Nivel13 + #368, #127
  static Nivel13 + #369, #127
  static Nivel13 + #370, #127
  static Nivel13 + #371, #127
  static Nivel13 + #372, #127
  static Nivel13 + #373, #127
  static Nivel13 + #374, #127
  static Nivel13 + #375, #127
  static Nivel13 + #376, #127
  static Nivel13 + #377, #127
  static Nivel13 + #378, #127
  static Nivel13 + #379, #127
  static Nivel13 + #380, #127
  static Nivel13 + #381, #127
  static Nivel13 + #382, #127
  static Nivel13 + #383, #127
  static Nivel13 + #384, #127
  static Nivel13 + #385, #127
  static Nivel13 + #386, #127
  static Nivel13 + #387, #127
  static Nivel13 + #388, #127
  static Nivel13 + #389, #127
  static Nivel13 + #390, #127
  static Nivel13 + #391, #127
  static Nivel13 + #392, #127
  static Nivel13 + #393, #127
  static Nivel13 + #394, #127
  static Nivel13 + #395, #127
  static Nivel13 + #396, #127
  static Nivel13 + #397, #127
  static Nivel13 + #398, #127
  static Nivel13 + #399, #127

  ;Linha 10
  static Nivel13 + #400, #127
  static Nivel13 + #401, #127
  static Nivel13 + #402, #127
  static Nivel13 + #403, #127
  static Nivel13 + #404, #127
  static Nivel13 + #405, #127
  static Nivel13 + #406, #127
  static Nivel13 + #407, #127
  static Nivel13 + #408, #127
  static Nivel13 + #409, #127
  static Nivel13 + #410, #127
  static Nivel13 + #411, #127
  static Nivel13 + #412, #127
  static Nivel13 + #413, #127
  static Nivel13 + #414, #127
  static Nivel13 + #415, #127
  static Nivel13 + #416, #127
  static Nivel13 + #417, #127
  static Nivel13 + #418, #127
  static Nivel13 + #419, #127
  static Nivel13 + #420, #127
  static Nivel13 + #421, #127
  static Nivel13 + #422, #127
  static Nivel13 + #423, #127
  static Nivel13 + #424, #127
  static Nivel13 + #425, #127
  static Nivel13 + #426, #127
  static Nivel13 + #427, #127
  static Nivel13 + #428, #127
  static Nivel13 + #429, #127
  static Nivel13 + #430, #127
  static Nivel13 + #431, #127
  static Nivel13 + #432, #127
  static Nivel13 + #433, #127
  static Nivel13 + #434, #127
  static Nivel13 + #435, #127
  static Nivel13 + #436, #127
  static Nivel13 + #437, #127
  static Nivel13 + #438, #127
  static Nivel13 + #439, #127

  ;Linha 11
  static Nivel13 + #440, #127
  static Nivel13 + #441, #127
  static Nivel13 + #442, #127
  static Nivel13 + #443, #127
  static Nivel13 + #444, #127
  static Nivel13 + #445, #127
  static Nivel13 + #446, #127
  static Nivel13 + #447, #127
  static Nivel13 + #448, #127
  static Nivel13 + #449, #127
  static Nivel13 + #450, #127
  static Nivel13 + #451, #127
  static Nivel13 + #452, #127
  static Nivel13 + #453, #127
  static Nivel13 + #454, #127
  static Nivel13 + #455, #127
  static Nivel13 + #456, #127
  static Nivel13 + #457, #127
  static Nivel13 + #458, #127
  static Nivel13 + #459, #127
  static Nivel13 + #460, #127
  static Nivel13 + #461, #127
  static Nivel13 + #462, #127
  static Nivel13 + #463, #127
  static Nivel13 + #464, #127
  static Nivel13 + #465, #127
  static Nivel13 + #466, #127
  static Nivel13 + #467, #127
  static Nivel13 + #468, #127
  static Nivel13 + #469, #127
  static Nivel13 + #470, #127
  static Nivel13 + #471, #127
  static Nivel13 + #472, #127
  static Nivel13 + #473, #127
  static Nivel13 + #474, #127
  static Nivel13 + #475, #127
  static Nivel13 + #476, #127
  static Nivel13 + #477, #127
  static Nivel13 + #478, #127
  static Nivel13 + #479, #127

  ;Linha 12
  static Nivel13 + #480, #127
  static Nivel13 + #481, #127
  static Nivel13 + #482, #127
  static Nivel13 + #483, #127
  static Nivel13 + #484, #127
  static Nivel13 + #485, #127
  static Nivel13 + #486, #127
  static Nivel13 + #487, #127
  static Nivel13 + #488, #127
  static Nivel13 + #489, #127
  static Nivel13 + #490, #127
  static Nivel13 + #491, #127
  static Nivel13 + #492, #127
  static Nivel13 + #493, #127
  static Nivel13 + #494, #127
  static Nivel13 + #495, #127
  static Nivel13 + #496, #127
  static Nivel13 + #497, #127
  static Nivel13 + #498, #127
  static Nivel13 + #499, #127
  static Nivel13 + #500, #127
  static Nivel13 + #501, #127
  static Nivel13 + #502, #127
  static Nivel13 + #503, #127
  static Nivel13 + #504, #127
  static Nivel13 + #505, #127
  static Nivel13 + #506, #127
  static Nivel13 + #507, #127
  static Nivel13 + #508, #127
  static Nivel13 + #509, #127
  static Nivel13 + #510, #127
  static Nivel13 + #511, #127
  static Nivel13 + #512, #127
  static Nivel13 + #513, #127
  static Nivel13 + #514, #127
  static Nivel13 + #515, #127
  static Nivel13 + #516, #127
  static Nivel13 + #517, #127
  static Nivel13 + #518, #127
  static Nivel13 + #519, #127

  ;Linha 13
  static Nivel13 + #520, #127
  static Nivel13 + #521, #127
  static Nivel13 + #522, #127
  static Nivel13 + #523, #127
  static Nivel13 + #524, #127
  static Nivel13 + #525, #127
  static Nivel13 + #526, #127
  static Nivel13 + #527, #127
  static Nivel13 + #528, #127
  static Nivel13 + #529, #127
  static Nivel13 + #530, #127
  static Nivel13 + #531, #127
  static Nivel13 + #532, #127
  static Nivel13 + #533, #127
  static Nivel13 + #534, #127
  static Nivel13 + #535, #127
  static Nivel13 + #536, #127
  static Nivel13 + #537, #127
  static Nivel13 + #538, #127
  static Nivel13 + #539, #127
  static Nivel13 + #540, #127
  static Nivel13 + #541, #127
  static Nivel13 + #542, #257
  static Nivel13 + #543, #3967
  static Nivel13 + #544, #3967
  static Nivel13 + #545, #3967
  static Nivel13 + #546, #127
  static Nivel13 + #547, #127
  static Nivel13 + #548, #127
  static Nivel13 + #549, #127
  static Nivel13 + #550, #127
  static Nivel13 + #551, #127
  static Nivel13 + #552, #127
  static Nivel13 + #553, #127
  static Nivel13 + #554, #127
  static Nivel13 + #555, #127
  static Nivel13 + #556, #127
  static Nivel13 + #557, #127
  static Nivel13 + #558, #127
  static Nivel13 + #559, #127

  ;Linha 14
  static Nivel13 + #560, #127
  static Nivel13 + #561, #127
  static Nivel13 + #562, #127
  static Nivel13 + #563, #127
  static Nivel13 + #564, #127
  static Nivel13 + #565, #127
  static Nivel13 + #566, #127
  static Nivel13 + #567, #127
  static Nivel13 + #568, #127
  static Nivel13 + #569, #127
  static Nivel13 + #570, #127
  static Nivel13 + #571, #127
  static Nivel13 + #572, #127
  static Nivel13 + #573, #127
  static Nivel13 + #574, #127
  static Nivel13 + #575, #127
  static Nivel13 + #576, #127
  static Nivel13 + #577, #127
  static Nivel13 + #578, #127
  static Nivel13 + #579, #127
  static Nivel13 + #580, #127
  static Nivel13 + #581, #127
  static Nivel13 + #582, #127
  static Nivel13 + #583, #127
  static Nivel13 + #584, #127
  static Nivel13 + #585, #127
  static Nivel13 + #586, #127
  static Nivel13 + #587, #127
  static Nivel13 + #588, #127
  static Nivel13 + #589, #127
  static Nivel13 + #590, #127
  static Nivel13 + #591, #127
  static Nivel13 + #592, #127
  static Nivel13 + #593, #127
  static Nivel13 + #594, #127
  static Nivel13 + #595, #127
  static Nivel13 + #596, #127
  static Nivel13 + #597, #127
  static Nivel13 + #598, #127
  static Nivel13 + #599, #127

  ;Linha 15
  static Nivel13 + #600, #127
  static Nivel13 + #601, #127
  static Nivel13 + #602, #127
  static Nivel13 + #603, #127
  static Nivel13 + #604, #127
  static Nivel13 + #605, #127
  static Nivel13 + #606, #127
  static Nivel13 + #607, #127
  static Nivel13 + #608, #127
  static Nivel13 + #609, #127
  static Nivel13 + #610, #127
  static Nivel13 + #611, #127
  static Nivel13 + #612, #127
  static Nivel13 + #613, #127
  static Nivel13 + #614, #127
  static Nivel13 + #615, #127
  static Nivel13 + #616, #127
  static Nivel13 + #617, #127
  static Nivel13 + #618, #127
  static Nivel13 + #619, #127
  static Nivel13 + #620, #127
  static Nivel13 + #621, #127
  static Nivel13 + #622, #127
  static Nivel13 + #623, #127
  static Nivel13 + #624, #127
  static Nivel13 + #625, #127
  static Nivel13 + #626, #127
  static Nivel13 + #627, #127
  static Nivel13 + #628, #127
  static Nivel13 + #629, #127
  static Nivel13 + #630, #127
  static Nivel13 + #631, #127
  static Nivel13 + #632, #127
  static Nivel13 + #633, #127
  static Nivel13 + #634, #127
  static Nivel13 + #635, #127
  static Nivel13 + #636, #127
  static Nivel13 + #637, #127
  static Nivel13 + #638, #127
  static Nivel13 + #639, #127

  ;Linha 16
  static Nivel13 + #640, #127
  static Nivel13 + #641, #127
  static Nivel13 + #642, #127
  static Nivel13 + #643, #127
  static Nivel13 + #644, #127
  static Nivel13 + #645, #127
  static Nivel13 + #646, #127
  static Nivel13 + #647, #127
  static Nivel13 + #648, #127
  static Nivel13 + #649, #127
  static Nivel13 + #650, #127
  static Nivel13 + #651, #127
  static Nivel13 + #652, #127
  static Nivel13 + #653, #127
  static Nivel13 + #654, #127
  static Nivel13 + #655, #127
  static Nivel13 + #656, #127
  static Nivel13 + #657, #127
  static Nivel13 + #658, #257
  static Nivel13 + #659, #257
  static Nivel13 + #660, #3967
  static Nivel13 + #661, #3967
  static Nivel13 + #662, #127
  static Nivel13 + #663, #127
  static Nivel13 + #664, #127
  static Nivel13 + #665, #127
  static Nivel13 + #666, #127
  static Nivel13 + #667, #127
  static Nivel13 + #668, #127
  static Nivel13 + #669, #127
  static Nivel13 + #670, #127
  static Nivel13 + #671, #127
  static Nivel13 + #672, #127
  static Nivel13 + #673, #127
  static Nivel13 + #674, #127
  static Nivel13 + #675, #127
  static Nivel13 + #676, #127
  static Nivel13 + #677, #127
  static Nivel13 + #678, #127
  static Nivel13 + #679, #127

  ;Linha 17
  static Nivel13 + #680, #127
  static Nivel13 + #681, #127
  static Nivel13 + #682, #127
  static Nivel13 + #683, #127
  static Nivel13 + #684, #127
  static Nivel13 + #685, #127
  static Nivel13 + #686, #127
  static Nivel13 + #687, #127
  static Nivel13 + #688, #127
  static Nivel13 + #689, #127
  static Nivel13 + #690, #127
  static Nivel13 + #691, #127
  static Nivel13 + #692, #127
  static Nivel13 + #693, #127
  static Nivel13 + #694, #127
  static Nivel13 + #695, #127
  static Nivel13 + #696, #127
  static Nivel13 + #697, #127
  static Nivel13 + #698, #127
  static Nivel13 + #699, #127
  static Nivel13 + #700, #127
  static Nivel13 + #701, #127
  static Nivel13 + #702, #127
  static Nivel13 + #703, #127
  static Nivel13 + #704, #127
  static Nivel13 + #705, #127
  static Nivel13 + #706, #127
  static Nivel13 + #707, #127
  static Nivel13 + #708, #127
  static Nivel13 + #709, #127
  static Nivel13 + #710, #127
  static Nivel13 + #711, #127
  static Nivel13 + #712, #127
  static Nivel13 + #713, #127
  static Nivel13 + #714, #127
  static Nivel13 + #715, #127
  static Nivel13 + #716, #127
  static Nivel13 + #717, #127
  static Nivel13 + #718, #127
  static Nivel13 + #719, #127

  ;Linha 18
  static Nivel13 + #720, #127
  static Nivel13 + #721, #127
  static Nivel13 + #722, #127
  static Nivel13 + #723, #127
  static Nivel13 + #724, #127
  static Nivel13 + #725, #127
  static Nivel13 + #726, #127
  static Nivel13 + #727, #127
  static Nivel13 + #728, #127
  static Nivel13 + #729, #127
  static Nivel13 + #730, #127
  static Nivel13 + #731, #127
  static Nivel13 + #732, #127
  static Nivel13 + #733, #127
  static Nivel13 + #734, #127
  static Nivel13 + #735, #127
  static Nivel13 + #736, #127
  static Nivel13 + #737, #127
  static Nivel13 + #738, #127
  static Nivel13 + #739, #127
  static Nivel13 + #740, #127
  static Nivel13 + #741, #127
  static Nivel13 + #742, #127
  static Nivel13 + #743, #127
  static Nivel13 + #744, #127
  static Nivel13 + #745, #127
  static Nivel13 + #746, #127
  static Nivel13 + #747, #127
  static Nivel13 + #748, #127
  static Nivel13 + #749, #127
  static Nivel13 + #750, #127
  static Nivel13 + #751, #2571
  static Nivel13 + #752, #127
  static Nivel13 + #753, #127
  static Nivel13 + #754, #127
  static Nivel13 + #755, #127
  static Nivel13 + #756, #127
  static Nivel13 + #757, #127
  static Nivel13 + #758, #127
  static Nivel13 + #759, #127

  ;Linha 19
  static Nivel13 + #760, #127
  static Nivel13 + #761, #127
  static Nivel13 + #762, #127
  static Nivel13 + #763, #127
  static Nivel13 + #764, #127
  static Nivel13 + #765, #127
  static Nivel13 + #766, #127
  static Nivel13 + #767, #127
  static Nivel13 + #768, #127
  static Nivel13 + #769, #127
  static Nivel13 + #770, #3967
  static Nivel13 + #771, #127
  static Nivel13 + #772, #127
  static Nivel13 + #773, #127
  static Nivel13 + #774, #127
  static Nivel13 + #775, #127
  static Nivel13 + #776, #127
  static Nivel13 + #777, #127
  static Nivel13 + #778, #127
  static Nivel13 + #779, #127
  static Nivel13 + #780, #127
  static Nivel13 + #781, #127
  static Nivel13 + #782, #127
  static Nivel13 + #783, #127
  static Nivel13 + #784, #127
  static Nivel13 + #785, #127
  static Nivel13 + #786, #127
  static Nivel13 + #787, #127
  static Nivel13 + #788, #127
  static Nivel13 + #789, #127
  static Nivel13 + #790, #127
  static Nivel13 + #791, #3594
  static Nivel13 + #792, #127
  static Nivel13 + #793, #127
  static Nivel13 + #794, #127
  static Nivel13 + #795, #127
  static Nivel13 + #796, #127
  static Nivel13 + #797, #127
  static Nivel13 + #798, #127
  static Nivel13 + #799, #127

  ;Linha 20
  static Nivel13 + #800, #127
  static Nivel13 + #801, #127
  static Nivel13 + #802, #127
  static Nivel13 + #803, #127
  static Nivel13 + #804, #127
  static Nivel13 + #805, #3967
  static Nivel13 + #806, #3967
  static Nivel13 + #807, #3967
  static Nivel13 + #808, #3967
  static Nivel13 + #809, #3967
  static Nivel13 + #810, #3967
  static Nivel13 + #811, #3967
  static Nivel13 + #812, #3967
  static Nivel13 + #813, #257
  static Nivel13 + #814, #257
  static Nivel13 + #815, #257
  static Nivel13 + #816, #3967
  static Nivel13 + #817, #127
  static Nivel13 + #818, #127
  static Nivel13 + #819, #127
  static Nivel13 + #820, #127
  static Nivel13 + #821, #127
  static Nivel13 + #822, #127
  static Nivel13 + #823, #127
  static Nivel13 + #824, #127
  static Nivel13 + #825, #127
  static Nivel13 + #826, #127
  static Nivel13 + #827, #127
  static Nivel13 + #828, #127
  static Nivel13 + #829, #127
  static Nivel13 + #830, #127
  static Nivel13 + #831, #3593
  static Nivel13 + #832, #127
  static Nivel13 + #833, #127
  static Nivel13 + #834, #127
  static Nivel13 + #835, #127
  static Nivel13 + #836, #127
  static Nivel13 + #837, #127
  static Nivel13 + #838, #127
  static Nivel13 + #839, #127

  ;Linha 21
  static Nivel13 + #840, #127
  static Nivel13 + #841, #127
  static Nivel13 + #842, #127
  static Nivel13 + #843, #127
  static Nivel13 + #844, #3967
  static Nivel13 + #845, #3967
  static Nivel13 + #846, #127
  static Nivel13 + #847, #127
  static Nivel13 + #848, #3967
  static Nivel13 + #849, #127
  static Nivel13 + #850, #127
  static Nivel13 + #851, #127
  static Nivel13 + #852, #127
  static Nivel13 + #853, #127
  static Nivel13 + #854, #127
  static Nivel13 + #855, #127
  static Nivel13 + #856, #127
  static Nivel13 + #857, #127
  static Nivel13 + #858, #127
  static Nivel13 + #859, #127
  static Nivel13 + #860, #127
  static Nivel13 + #861, #127
  static Nivel13 + #862, #127
  static Nivel13 + #863, #127
  static Nivel13 + #864, #127
  static Nivel13 + #865, #127
  static Nivel13 + #866, #127
  static Nivel13 + #867, #127
  static Nivel13 + #868, #127
  static Nivel13 + #869, #127
  static Nivel13 + #870, #127
  static Nivel13 + #871, #3593
  static Nivel13 + #872, #127
  static Nivel13 + #873, #127
  static Nivel13 + #874, #127
  static Nivel13 + #875, #127
  static Nivel13 + #876, #127
  static Nivel13 + #877, #268
  static Nivel13 + #878, #268
  static Nivel13 + #879, #127

  ;Linha 22
  static Nivel13 + #880, #127
  static Nivel13 + #881, #127
  static Nivel13 + #882, #127
  static Nivel13 + #883, #127
  static Nivel13 + #884, #3967
  static Nivel13 + #885, #127
  static Nivel13 + #886, #127
  static Nivel13 + #887, #127
  static Nivel13 + #888, #127
  static Nivel13 + #889, #3967
  static Nivel13 + #890, #3967
  static Nivel13 + #891, #127
  static Nivel13 + #892, #127
  static Nivel13 + #893, #127
  static Nivel13 + #894, #127
  static Nivel13 + #895, #127
  static Nivel13 + #896, #127
  static Nivel13 + #897, #127
  static Nivel13 + #898, #127
  static Nivel13 + #899, #127
  static Nivel13 + #900, #127
  static Nivel13 + #901, #127
  static Nivel13 + #902, #127
  static Nivel13 + #903, #127
  static Nivel13 + #904, #127
  static Nivel13 + #905, #127
  static Nivel13 + #906, #127
  static Nivel13 + #907, #127
  static Nivel13 + #908, #127
  static Nivel13 + #909, #127
  static Nivel13 + #910, #127
  static Nivel13 + #911, #3593
  static Nivel13 + #912, #127
  static Nivel13 + #913, #127
  static Nivel13 + #914, #127
  static Nivel13 + #915, #127
  static Nivel13 + #916, #127
  static Nivel13 + #917, #257
  static Nivel13 + #918, #257
  static Nivel13 + #919, #127

  ;Linha 23
  static Nivel13 + #920, #127
  static Nivel13 + #921, #127
  static Nivel13 + #922, #127
  static Nivel13 + #923, #127
  static Nivel13 + #924, #3967
  static Nivel13 + #925, #127
  static Nivel13 + #926, #127
  static Nivel13 + #927, #127
  static Nivel13 + #928, #3967
  static Nivel13 + #929, #3967
  static Nivel13 + #930, #3967
  static Nivel13 + #931, #127
  static Nivel13 + #932, #127
  static Nivel13 + #933, #127
  static Nivel13 + #934, #127
  static Nivel13 + #935, #127
  static Nivel13 + #936, #127
  static Nivel13 + #937, #127
  static Nivel13 + #938, #127
  static Nivel13 + #939, #127
  static Nivel13 + #940, #127
  static Nivel13 + #941, #127
  static Nivel13 + #942, #127
  static Nivel13 + #943, #127
  static Nivel13 + #944, #127
  static Nivel13 + #945, #127
  static Nivel13 + #946, #127
  static Nivel13 + #947, #127
  static Nivel13 + #948, #127
  static Nivel13 + #949, #127
  static Nivel13 + #950, #127
  static Nivel13 + #951, #3593
  static Nivel13 + #952, #127
  static Nivel13 + #953, #127
  static Nivel13 + #954, #127
  static Nivel13 + #955, #127
  static Nivel13 + #956, #268
  static Nivel13 + #957, #269
  static Nivel13 + #958, #269
  static Nivel13 + #959, #268

  ;Linha 24
  static Nivel13 + #960, #127
  static Nivel13 + #961, #127
  static Nivel13 + #962, #127
  static Nivel13 + #963, #127
  static Nivel13 + #964, #3967
  static Nivel13 + #965, #257
  static Nivel13 + #966, #257
  static Nivel13 + #967, #257
  static Nivel13 + #968, #257
  static Nivel13 + #969, #2818
  static Nivel13 + #970, #257
  static Nivel13 + #971, #3967
  static Nivel13 + #972, #3967
  static Nivel13 + #973, #127
  static Nivel13 + #974, #127
  static Nivel13 + #975, #127
  static Nivel13 + #976, #127
  static Nivel13 + #977, #127
  static Nivel13 + #978, #3967
  static Nivel13 + #979, #257
  static Nivel13 + #980, #257
  static Nivel13 + #981, #257
  static Nivel13 + #982, #127
  static Nivel13 + #983, #127
  static Nivel13 + #984, #127
  static Nivel13 + #985, #127
  static Nivel13 + #986, #127
  static Nivel13 + #987, #127
  static Nivel13 + #988, #3967
  static Nivel13 + #989, #3967
  static Nivel13 + #990, #3967
  static Nivel13 + #991, #3593
  static Nivel13 + #992, #127
  static Nivel13 + #993, #127
  static Nivel13 + #994, #127
  static Nivel13 + #995, #127
  static Nivel13 + #996, #257
  static Nivel13 + #997, #257
  static Nivel13 + #998, #257
  static Nivel13 + #999, #257

  ;Linha 25
  static Nivel13 + #1000, #127
  static Nivel13 + #1001, #127
  static Nivel13 + #1002, #127
  static Nivel13 + #1003, #127
  static Nivel13 + #1004, #3967
  static Nivel13 + #1005, #127
  static Nivel13 + #1006, #127
  static Nivel13 + #1007, #127
  static Nivel13 + #1008, #127
  static Nivel13 + #1009, #127
  static Nivel13 + #1010, #127
  static Nivel13 + #1011, #127
  static Nivel13 + #1012, #127
  static Nivel13 + #1013, #127
  static Nivel13 + #1014, #127
  static Nivel13 + #1015, #3967
  static Nivel13 + #1016, #3967
  static Nivel13 + #1017, #3967
  static Nivel13 + #1018, #3967
  static Nivel13 + #1019, #127
  static Nivel13 + #1020, #127
  static Nivel13 + #1021, #127
  static Nivel13 + #1022, #127
  static Nivel13 + #1023, #127
  static Nivel13 + #1024, #127
  static Nivel13 + #1025, #127
  static Nivel13 + #1026, #127
  static Nivel13 + #1027, #127
  static Nivel13 + #1028, #3967
  static Nivel13 + #1029, #3967
  static Nivel13 + #1030, #3967
  static Nivel13 + #1031, #3593
  static Nivel13 + #1032, #127
  static Nivel13 + #1033, #127
  static Nivel13 + #1034, #127
  static Nivel13 + #1035, #127
  static Nivel13 + #1036, #257
  static Nivel13 + #1037, #3967
  static Nivel13 + #1038, #3967
  static Nivel13 + #1039, #257

  ;Linha 26
  static Nivel13 + #1040, #127
  static Nivel13 + #1041, #127
  static Nivel13 + #1042, #127
  static Nivel13 + #1043, #127
  static Nivel13 + #1044, #127
  static Nivel13 + #1045, #127
  static Nivel13 + #1046, #127
  static Nivel13 + #1047, #127
  static Nivel13 + #1048, #127
  static Nivel13 + #1049, #127
  static Nivel13 + #1050, #127
  static Nivel13 + #1051, #127
  static Nivel13 + #1052, #127
  static Nivel13 + #1053, #127
  static Nivel13 + #1054, #127
  static Nivel13 + #1055, #3967
  static Nivel13 + #1056, #3967
  static Nivel13 + #1057, #3967
  static Nivel13 + #1058, #3967
  static Nivel13 + #1059, #3967
  static Nivel13 + #1060, #127
  static Nivel13 + #1061, #127
  static Nivel13 + #1062, #127
  static Nivel13 + #1063, #127
  static Nivel13 + #1064, #127
  static Nivel13 + #1065, #127
  static Nivel13 + #1066, #127
  static Nivel13 + #1067, #127
  static Nivel13 + #1068, #127
  static Nivel13 + #1069, #3967
  static Nivel13 + #1070, #3967
  static Nivel13 + #1071, #3593
  static Nivel13 + #1072, #127
  static Nivel13 + #1073, #3967
  static Nivel13 + #1074, #3967
  static Nivel13 + #1075, #3967
  static Nivel13 + #1076, #257
  static Nivel13 + #1077, #257
  static Nivel13 + #1078, #257
  static Nivel13 + #1079, #257

  ;Linha 27
  static Nivel13 + #1080, #127
  static Nivel13 + #1081, #127
  static Nivel13 + #1082, #127
  static Nivel13 + #1083, #127
  static Nivel13 + #1084, #127
  static Nivel13 + #1085, #127
  static Nivel13 + #1086, #127
  static Nivel13 + #1087, #127
  static Nivel13 + #1088, #127
  static Nivel13 + #1089, #127
  static Nivel13 + #1090, #127
  static Nivel13 + #1091, #127
  static Nivel13 + #1092, #127
  static Nivel13 + #1093, #127
  static Nivel13 + #1094, #3967
  static Nivel13 + #1095, #3967
  static Nivel13 + #1096, #3967
  static Nivel13 + #1097, #3967
  static Nivel13 + #1098, #3967
  static Nivel13 + #1099, #3967
  static Nivel13 + #1100, #127
  static Nivel13 + #1101, #127
  static Nivel13 + #1102, #127
  static Nivel13 + #1103, #127
  static Nivel13 + #1104, #127
  static Nivel13 + #1105, #3967
  static Nivel13 + #1106, #127
  static Nivel13 + #1107, #127
  static Nivel13 + #1108, #3967
  static Nivel13 + #1109, #3967
  static Nivel13 + #1110, #3967
  static Nivel13 + #1111, #263
  static Nivel13 + #1112, #127
  static Nivel13 + #1113, #3967
  static Nivel13 + #1114, #3967
  static Nivel13 + #1115, #3967
  static Nivel13 + #1116, #257
  static Nivel13 + #1117, #257
  static Nivel13 + #1118, #257
  static Nivel13 + #1119, #257

  ;Linha 28
  static Nivel13 + #1120, #256
  static Nivel13 + #1121, #256
  static Nivel13 + #1122, #256
  static Nivel13 + #1123, #256
  static Nivel13 + #1124, #256
  static Nivel13 + #1125, #256
  static Nivel13 + #1126, #256
  static Nivel13 + #1127, #256
  static Nivel13 + #1128, #256
  static Nivel13 + #1129, #256
  static Nivel13 + #1130, #256
  static Nivel13 + #1131, #256
  static Nivel13 + #1132, #256
  static Nivel13 + #1133, #3967
  static Nivel13 + #1134, #3967
  static Nivel13 + #1135, #3967
  static Nivel13 + #1136, #3967
  static Nivel13 + #1137, #3967
  static Nivel13 + #1138, #3967
  static Nivel13 + #1139, #3967
  static Nivel13 + #1140, #3967
  static Nivel13 + #1141, #3967
  static Nivel13 + #1142, #3967
  static Nivel13 + #1143, #3967
  static Nivel13 + #1144, #3967
  static Nivel13 + #1145, #3967
  static Nivel13 + #1146, #3967
  static Nivel13 + #1147, #3967
  static Nivel13 + #1148, #256
  static Nivel13 + #1149, #256
  static Nivel13 + #1150, #256
  static Nivel13 + #1151, #256
  static Nivel13 + #1152, #256
  static Nivel13 + #1153, #256
  static Nivel13 + #1154, #256
  static Nivel13 + #1155, #256
  static Nivel13 + #1156, #256
  static Nivel13 + #1157, #256
  static Nivel13 + #1158, #256
  static Nivel13 + #1159, #256

  ;Linha 29
  static Nivel13 + #1160, #256
  static Nivel13 + #1161, #256
  static Nivel13 + #1162, #256
  static Nivel13 + #1163, #256
  static Nivel13 + #1164, #256
  static Nivel13 + #1165, #256
  static Nivel13 + #1166, #256
  static Nivel13 + #1167, #256
  static Nivel13 + #1168, #256
  static Nivel13 + #1169, #256
  static Nivel13 + #1170, #256
  static Nivel13 + #1171, #256
  static Nivel13 + #1172, #256
  static Nivel13 + #1173, #3967
  static Nivel13 + #1174, #3967
  static Nivel13 + #1175, #3967
  static Nivel13 + #1176, #3967
  static Nivel13 + #1177, #3967
  static Nivel13 + #1178, #3967
  static Nivel13 + #1179, #3967
  static Nivel13 + #1180, #3967
  static Nivel13 + #1181, #3967
  static Nivel13 + #1182, #3967
  static Nivel13 + #1183, #3967
  static Nivel13 + #1184, #3967
  static Nivel13 + #1185, #3967
  static Nivel13 + #1186, #3967
  static Nivel13 + #1187, #3967
  static Nivel13 + #1188, #256
  static Nivel13 + #1189, #256
  static Nivel13 + #1190, #256
  static Nivel13 + #1191, #256
  static Nivel13 + #1192, #256
  static Nivel13 + #1193, #256
  static Nivel13 + #1194, #256
  static Nivel13 + #1195, #256
  static Nivel13 + #1196, #256
  static Nivel13 + #1197, #256
  static Nivel13 + #1198, #256
  static Nivel13 + #1199, #256

printNivel13Screen:
  push R0
  push R1
  push R2
  push R3

  loadn R0, #Nivel13
  loadn R1, #0
  loadn R2, #1200

  printNivel13ScreenLoop:

    add R3,R0,R1
    loadi R3, R3
    outchar R3, R1
    inc R1
    cmp R1, R2

    jne printNivel13ScreenLoop

  pop R3
  pop R2
  pop R1
  pop R0
  rts

NivelFinal1 : var #1200
  ;Linha 0
  static NivelFinal1 + #0, #3967
  static NivelFinal1 + #1, #3967
  static NivelFinal1 + #2, #3967
  static NivelFinal1 + #3, #3967
  static NivelFinal1 + #4, #3967
  static NivelFinal1 + #5, #3967
  static NivelFinal1 + #6, #3967
  static NivelFinal1 + #7, #3967
  static NivelFinal1 + #8, #3967
  static NivelFinal1 + #9, #3967
  static NivelFinal1 + #10, #3967
  static NivelFinal1 + #11, #3967
  static NivelFinal1 + #12, #3967
  static NivelFinal1 + #13, #3967
  static NivelFinal1 + #14, #3967
  static NivelFinal1 + #15, #3967
  static NivelFinal1 + #16, #3967
  static NivelFinal1 + #17, #3967
  static NivelFinal1 + #18, #3967
  static NivelFinal1 + #19, #3967
  static NivelFinal1 + #20, #3967
  static NivelFinal1 + #21, #3967
  static NivelFinal1 + #22, #3967
  static NivelFinal1 + #23, #3967
  static NivelFinal1 + #24, #3967
  static NivelFinal1 + #25, #3967
  static NivelFinal1 + #26, #3967
  static NivelFinal1 + #27, #3967
  static NivelFinal1 + #28, #3967
  static NivelFinal1 + #29, #3967
  static NivelFinal1 + #30, #3967
  static NivelFinal1 + #31, #3967
  static NivelFinal1 + #32, #3967
  static NivelFinal1 + #33, #3967
  static NivelFinal1 + #34, #3967
  static NivelFinal1 + #35, #3967
  static NivelFinal1 + #36, #3967
  static NivelFinal1 + #37, #3967
  static NivelFinal1 + #38, #3967
  static NivelFinal1 + #39, #3967

  ;Linha 1
  static NivelFinal1 + #40, #3967
  static NivelFinal1 + #41, #3967
  static NivelFinal1 + #42, #3967
  static NivelFinal1 + #43, #3967
  static NivelFinal1 + #44, #3967
  static NivelFinal1 + #45, #3967
  static NivelFinal1 + #46, #3967
  static NivelFinal1 + #47, #3967
  static NivelFinal1 + #48, #3967
  static NivelFinal1 + #49, #3967
  static NivelFinal1 + #50, #3967
  static NivelFinal1 + #51, #3967
  static NivelFinal1 + #52, #3967
  static NivelFinal1 + #53, #3967
  static NivelFinal1 + #54, #3967
  static NivelFinal1 + #55, #3967
  static NivelFinal1 + #56, #3967
  static NivelFinal1 + #57, #3967
  static NivelFinal1 + #58, #3967
  static NivelFinal1 + #59, #3967
  static NivelFinal1 + #60, #3967
  static NivelFinal1 + #61, #3967
  static NivelFinal1 + #62, #3967
  static NivelFinal1 + #63, #3967
  static NivelFinal1 + #64, #3967
  static NivelFinal1 + #65, #3967
  static NivelFinal1 + #66, #3967
  static NivelFinal1 + #67, #3967
  static NivelFinal1 + #68, #3967
  static NivelFinal1 + #69, #3967
  static NivelFinal1 + #70, #3967
  static NivelFinal1 + #71, #3967
  static NivelFinal1 + #72, #3967
  static NivelFinal1 + #73, #3967
  static NivelFinal1 + #74, #3967
  static NivelFinal1 + #75, #3967
  static NivelFinal1 + #76, #3967
  static NivelFinal1 + #77, #3967
  static NivelFinal1 + #78, #3967
  static NivelFinal1 + #79, #3967

  ;Linha 2
  static NivelFinal1 + #80, #3967
  static NivelFinal1 + #81, #3967
  static NivelFinal1 + #82, #3967
  static NivelFinal1 + #83, #3967
  static NivelFinal1 + #84, #3967
  static NivelFinal1 + #85, #3967
  static NivelFinal1 + #86, #3967
  static NivelFinal1 + #87, #3967
  static NivelFinal1 + #88, #3967
  static NivelFinal1 + #89, #3967
  static NivelFinal1 + #90, #3967
  static NivelFinal1 + #91, #3967
  static NivelFinal1 + #92, #3967
  static NivelFinal1 + #93, #3967
  static NivelFinal1 + #94, #3967
  static NivelFinal1 + #95, #3967
  static NivelFinal1 + #96, #3967
  static NivelFinal1 + #97, #3967
  static NivelFinal1 + #98, #3967
  static NivelFinal1 + #99, #3967
  static NivelFinal1 + #100, #3967
  static NivelFinal1 + #101, #3967
  static NivelFinal1 + #102, #3967
  static NivelFinal1 + #103, #3967
  static NivelFinal1 + #104, #3967
  static NivelFinal1 + #105, #3967
  static NivelFinal1 + #106, #3967
  static NivelFinal1 + #107, #3967
  static NivelFinal1 + #108, #3967
  static NivelFinal1 + #109, #3967
  static NivelFinal1 + #110, #3967
  static NivelFinal1 + #111, #3967
  static NivelFinal1 + #112, #3967
  static NivelFinal1 + #113, #3967
  static NivelFinal1 + #114, #3967
  static NivelFinal1 + #115, #3967
  static NivelFinal1 + #116, #3967
  static NivelFinal1 + #117, #3967
  static NivelFinal1 + #118, #3967
  static NivelFinal1 + #119, #3967

  ;Linha 3
  static NivelFinal1 + #120, #127
  static NivelFinal1 + #121, #3967
  static NivelFinal1 + #122, #3967
  static NivelFinal1 + #123, #3967
  static NivelFinal1 + #124, #127
  static NivelFinal1 + #125, #127
  static NivelFinal1 + #126, #127
  static NivelFinal1 + #127, #127
  static NivelFinal1 + #128, #127
  static NivelFinal1 + #129, #127
  static NivelFinal1 + #130, #3967
  static NivelFinal1 + #131, #3967
  static NivelFinal1 + #132, #3967
  static NivelFinal1 + #133, #3967
  static NivelFinal1 + #134, #127
  static NivelFinal1 + #135, #3967
  static NivelFinal1 + #136, #3967
  static NivelFinal1 + #137, #3967
  static NivelFinal1 + #138, #3967
  static NivelFinal1 + #139, #3967
  static NivelFinal1 + #140, #3967
  static NivelFinal1 + #141, #3967
  static NivelFinal1 + #142, #3967
  static NivelFinal1 + #143, #3967
  static NivelFinal1 + #144, #3967
  static NivelFinal1 + #145, #3967
  static NivelFinal1 + #146, #3967
  static NivelFinal1 + #147, #3967
  static NivelFinal1 + #148, #3967
  static NivelFinal1 + #149, #3967
  static NivelFinal1 + #150, #3967
  static NivelFinal1 + #151, #3967
  static NivelFinal1 + #152, #3967
  static NivelFinal1 + #153, #3967
  static NivelFinal1 + #154, #3967
  static NivelFinal1 + #155, #3967
  static NivelFinal1 + #156, #3967
  static NivelFinal1 + #157, #3967
  static NivelFinal1 + #158, #3967
  static NivelFinal1 + #159, #3967

  ;Linha 4
  static NivelFinal1 + #160, #127
  static NivelFinal1 + #161, #127
  static NivelFinal1 + #162, #127
  static NivelFinal1 + #163, #127
  static NivelFinal1 + #164, #127
  static NivelFinal1 + #165, #127
  static NivelFinal1 + #166, #127
  static NivelFinal1 + #167, #127
  static NivelFinal1 + #168, #127
  static NivelFinal1 + #169, #127
  static NivelFinal1 + #170, #127
  static NivelFinal1 + #171, #127
  static NivelFinal1 + #172, #127
  static NivelFinal1 + #173, #127
  static NivelFinal1 + #174, #3967
  static NivelFinal1 + #175, #3967
  static NivelFinal1 + #176, #3967
  static NivelFinal1 + #177, #127
  static NivelFinal1 + #178, #3967
  static NivelFinal1 + #179, #3967
  static NivelFinal1 + #180, #3967
  static NivelFinal1 + #181, #3967
  static NivelFinal1 + #182, #3967
  static NivelFinal1 + #183, #3967
  static NivelFinal1 + #184, #3967
  static NivelFinal1 + #185, #3967
  static NivelFinal1 + #186, #127
  static NivelFinal1 + #187, #3967
  static NivelFinal1 + #188, #3967
  static NivelFinal1 + #189, #3967
  static NivelFinal1 + #190, #3967
  static NivelFinal1 + #191, #3967
  static NivelFinal1 + #192, #3967
  static NivelFinal1 + #193, #3967
  static NivelFinal1 + #194, #3967
  static NivelFinal1 + #195, #3967
  static NivelFinal1 + #196, #3967
  static NivelFinal1 + #197, #3967
  static NivelFinal1 + #198, #3967
  static NivelFinal1 + #199, #3967

  ;Linha 5
  static NivelFinal1 + #200, #127
  static NivelFinal1 + #201, #127
  static NivelFinal1 + #202, #127
  static NivelFinal1 + #203, #127
  static NivelFinal1 + #204, #127
  static NivelFinal1 + #205, #127
  static NivelFinal1 + #206, #127
  static NivelFinal1 + #207, #127
  static NivelFinal1 + #208, #127
  static NivelFinal1 + #209, #127
  static NivelFinal1 + #210, #127
  static NivelFinal1 + #211, #127
  static NivelFinal1 + #212, #127
  static NivelFinal1 + #213, #127
  static NivelFinal1 + #214, #127
  static NivelFinal1 + #215, #127
  static NivelFinal1 + #216, #127
  static NivelFinal1 + #217, #127
  static NivelFinal1 + #218, #3967
  static NivelFinal1 + #219, #3967
  static NivelFinal1 + #220, #3967
  static NivelFinal1 + #221, #3967
  static NivelFinal1 + #222, #3967
  static NivelFinal1 + #223, #3967
  static NivelFinal1 + #224, #3967
  static NivelFinal1 + #225, #3967
  static NivelFinal1 + #226, #127
  static NivelFinal1 + #227, #127
  static NivelFinal1 + #228, #127
  static NivelFinal1 + #229, #127
  static NivelFinal1 + #230, #127
  static NivelFinal1 + #231, #3967
  static NivelFinal1 + #232, #3967
  static NivelFinal1 + #233, #3967
  static NivelFinal1 + #234, #3967
  static NivelFinal1 + #235, #3967
  static NivelFinal1 + #236, #3967
  static NivelFinal1 + #237, #3967
  static NivelFinal1 + #238, #3967
  static NivelFinal1 + #239, #3967

  ;Linha 6
  static NivelFinal1 + #240, #127
  static NivelFinal1 + #241, #127
  static NivelFinal1 + #242, #127
  static NivelFinal1 + #243, #127
  static NivelFinal1 + #244, #127
  static NivelFinal1 + #245, #127
  static NivelFinal1 + #246, #127
  static NivelFinal1 + #247, #127
  static NivelFinal1 + #248, #127
  static NivelFinal1 + #249, #127
  static NivelFinal1 + #250, #127
  static NivelFinal1 + #251, #127
  static NivelFinal1 + #252, #127
  static NivelFinal1 + #253, #127
  static NivelFinal1 + #254, #127
  static NivelFinal1 + #255, #127
  static NivelFinal1 + #256, #127
  static NivelFinal1 + #257, #127
  static NivelFinal1 + #258, #127
  static NivelFinal1 + #259, #127
  static NivelFinal1 + #260, #127
  static NivelFinal1 + #261, #127
  static NivelFinal1 + #262, #127
  static NivelFinal1 + #263, #127
  static NivelFinal1 + #264, #3967
  static NivelFinal1 + #265, #3967
  static NivelFinal1 + #266, #127
  static NivelFinal1 + #267, #127
  static NivelFinal1 + #268, #127
  static NivelFinal1 + #269, #127
  static NivelFinal1 + #270, #127
  static NivelFinal1 + #271, #127
  static NivelFinal1 + #272, #127
  static NivelFinal1 + #273, #3967
  static NivelFinal1 + #274, #3967
  static NivelFinal1 + #275, #3967
  static NivelFinal1 + #276, #3967
  static NivelFinal1 + #277, #3967
  static NivelFinal1 + #278, #3967
  static NivelFinal1 + #279, #127

  ;Linha 7
  static NivelFinal1 + #280, #127
  static NivelFinal1 + #281, #127
  static NivelFinal1 + #282, #127
  static NivelFinal1 + #283, #127
  static NivelFinal1 + #284, #127
  static NivelFinal1 + #285, #127
  static NivelFinal1 + #286, #127
  static NivelFinal1 + #287, #127
  static NivelFinal1 + #288, #127
  static NivelFinal1 + #289, #127
  static NivelFinal1 + #290, #127
  static NivelFinal1 + #291, #127
  static NivelFinal1 + #292, #127
  static NivelFinal1 + #293, #127
  static NivelFinal1 + #294, #127
  static NivelFinal1 + #295, #127
  static NivelFinal1 + #296, #127
  static NivelFinal1 + #297, #127
  static NivelFinal1 + #298, #127
  static NivelFinal1 + #299, #127
  static NivelFinal1 + #300, #127
  static NivelFinal1 + #301, #127
  static NivelFinal1 + #302, #127
  static NivelFinal1 + #303, #127
  static NivelFinal1 + #304, #127
  static NivelFinal1 + #305, #127
  static NivelFinal1 + #306, #127
  static NivelFinal1 + #307, #127
  static NivelFinal1 + #308, #127
  static NivelFinal1 + #309, #127
  static NivelFinal1 + #310, #127
  static NivelFinal1 + #311, #127
  static NivelFinal1 + #312, #127
  static NivelFinal1 + #313, #127
  static NivelFinal1 + #314, #127
  static NivelFinal1 + #315, #127
  static NivelFinal1 + #316, #3967
  static NivelFinal1 + #317, #3967
  static NivelFinal1 + #318, #3967
  static NivelFinal1 + #319, #127

  ;Linha 8
  static NivelFinal1 + #320, #127
  static NivelFinal1 + #321, #127
  static NivelFinal1 + #322, #127
  static NivelFinal1 + #323, #127
  static NivelFinal1 + #324, #127
  static NivelFinal1 + #325, #127
  static NivelFinal1 + #326, #127
  static NivelFinal1 + #327, #127
  static NivelFinal1 + #328, #127
  static NivelFinal1 + #329, #127
  static NivelFinal1 + #330, #127
  static NivelFinal1 + #331, #127
  static NivelFinal1 + #332, #127
  static NivelFinal1 + #333, #127
  static NivelFinal1 + #334, #127
  static NivelFinal1 + #335, #127
  static NivelFinal1 + #336, #127
  static NivelFinal1 + #337, #3967
  static NivelFinal1 + #338, #127
  static NivelFinal1 + #339, #127
  static NivelFinal1 + #340, #127
  static NivelFinal1 + #341, #127
  static NivelFinal1 + #342, #127
  static NivelFinal1 + #343, #127
  static NivelFinal1 + #344, #127
  static NivelFinal1 + #345, #127
  static NivelFinal1 + #346, #127
  static NivelFinal1 + #347, #127
  static NivelFinal1 + #348, #127
  static NivelFinal1 + #349, #127
  static NivelFinal1 + #350, #127
  static NivelFinal1 + #351, #127
  static NivelFinal1 + #352, #127
  static NivelFinal1 + #353, #127
  static NivelFinal1 + #354, #127
  static NivelFinal1 + #355, #127
  static NivelFinal1 + #356, #127
  static NivelFinal1 + #357, #127
  static NivelFinal1 + #358, #127
  static NivelFinal1 + #359, #127

  ;Linha 9
  static NivelFinal1 + #360, #127
  static NivelFinal1 + #361, #127
  static NivelFinal1 + #362, #127
  static NivelFinal1 + #363, #127
  static NivelFinal1 + #364, #127
  static NivelFinal1 + #365, #127
  static NivelFinal1 + #366, #127
  static NivelFinal1 + #367, #127
  static NivelFinal1 + #368, #127
  static NivelFinal1 + #369, #127
  static NivelFinal1 + #370, #127
  static NivelFinal1 + #371, #127
  static NivelFinal1 + #372, #127
  static NivelFinal1 + #373, #127
  static NivelFinal1 + #374, #3967
  static NivelFinal1 + #375, #3967
  static NivelFinal1 + #376, #3967
  static NivelFinal1 + #377, #3967
  static NivelFinal1 + #378, #127
  static NivelFinal1 + #379, #127
  static NivelFinal1 + #380, #127
  static NivelFinal1 + #381, #127
  static NivelFinal1 + #382, #127
  static NivelFinal1 + #383, #127
  static NivelFinal1 + #384, #127
  static NivelFinal1 + #385, #127
  static NivelFinal1 + #386, #127
  static NivelFinal1 + #387, #127
  static NivelFinal1 + #388, #127
  static NivelFinal1 + #389, #127
  static NivelFinal1 + #390, #127
  static NivelFinal1 + #391, #127
  static NivelFinal1 + #392, #127
  static NivelFinal1 + #393, #127
  static NivelFinal1 + #394, #127
  static NivelFinal1 + #395, #127
  static NivelFinal1 + #396, #127
  static NivelFinal1 + #397, #127
  static NivelFinal1 + #398, #127
  static NivelFinal1 + #399, #127

  ;Linha 10
  static NivelFinal1 + #400, #2062
  static NivelFinal1 + #401, #2062
  static NivelFinal1 + #402, #2062
  static NivelFinal1 + #403, #2062
  static NivelFinal1 + #404, #2062
  static NivelFinal1 + #405, #2062
  static NivelFinal1 + #406, #2062
  static NivelFinal1 + #407, #2062
  static NivelFinal1 + #408, #2062
  static NivelFinal1 + #409, #2062
  static NivelFinal1 + #410, #2062
  static NivelFinal1 + #411, #2062
  static NivelFinal1 + #412, #2062
  static NivelFinal1 + #413, #2062
  static NivelFinal1 + #414, #2062
  static NivelFinal1 + #415, #2062
  static NivelFinal1 + #416, #2062
  static NivelFinal1 + #417, #2062
  static NivelFinal1 + #418, #2062
  static NivelFinal1 + #419, #2062
  static NivelFinal1 + #420, #2062
  static NivelFinal1 + #421, #2062
  static NivelFinal1 + #422, #2062
  static NivelFinal1 + #423, #2062
  static NivelFinal1 + #424, #2062
  static NivelFinal1 + #425, #2062
  static NivelFinal1 + #426, #2062
  static NivelFinal1 + #427, #2062
  static NivelFinal1 + #428, #2062
  static NivelFinal1 + #429, #2062
  static NivelFinal1 + #430, #2062
  static NivelFinal1 + #431, #2062
  static NivelFinal1 + #432, #2062
  static NivelFinal1 + #433, #2062
  static NivelFinal1 + #434, #2062
  static NivelFinal1 + #435, #2062
  static NivelFinal1 + #436, #2062
  static NivelFinal1 + #437, #2062
  static NivelFinal1 + #438, #2062
  static NivelFinal1 + #439, #2062

  ;Linha 11
  static NivelFinal1 + #440, #2062
  static NivelFinal1 + #441, #2062
  static NivelFinal1 + #442, #2062
  static NivelFinal1 + #443, #2062
  static NivelFinal1 + #444, #2062
  static NivelFinal1 + #445, #2062
  static NivelFinal1 + #446, #2062
  static NivelFinal1 + #447, #2062
  static NivelFinal1 + #448, #2062
  static NivelFinal1 + #449, #2062
  static NivelFinal1 + #450, #2062
  static NivelFinal1 + #451, #2062
  static NivelFinal1 + #452, #2062
  static NivelFinal1 + #453, #2062
  static NivelFinal1 + #454, #2062
  static NivelFinal1 + #455, #2062
  static NivelFinal1 + #456, #2062
  static NivelFinal1 + #457, #2062
  static NivelFinal1 + #458, #2062
  static NivelFinal1 + #459, #2062
  static NivelFinal1 + #460, #2062
  static NivelFinal1 + #461, #2062
  static NivelFinal1 + #462, #2062
  static NivelFinal1 + #463, #2062
  static NivelFinal1 + #464, #2062
  static NivelFinal1 + #465, #2062
  static NivelFinal1 + #466, #2062
  static NivelFinal1 + #467, #2062
  static NivelFinal1 + #468, #2062
  static NivelFinal1 + #469, #2062
  static NivelFinal1 + #470, #2062
  static NivelFinal1 + #471, #2062
  static NivelFinal1 + #472, #2062
  static NivelFinal1 + #473, #2062
  static NivelFinal1 + #474, #2062
  static NivelFinal1 + #475, #2062
  static NivelFinal1 + #476, #2062
  static NivelFinal1 + #477, #2062
  static NivelFinal1 + #478, #2062
  static NivelFinal1 + #479, #2062

  ;Linha 12
  static NivelFinal1 + #480, #127
  static NivelFinal1 + #481, #127
  static NivelFinal1 + #482, #127
  static NivelFinal1 + #483, #127
  static NivelFinal1 + #484, #127
  static NivelFinal1 + #485, #127
  static NivelFinal1 + #486, #127
  static NivelFinal1 + #487, #127
  static NivelFinal1 + #488, #127
  static NivelFinal1 + #489, #127
  static NivelFinal1 + #490, #127
  static NivelFinal1 + #491, #127
  static NivelFinal1 + #492, #127
  static NivelFinal1 + #493, #127
  static NivelFinal1 + #494, #127
  static NivelFinal1 + #495, #127
  static NivelFinal1 + #496, #127
  static NivelFinal1 + #497, #127
  static NivelFinal1 + #498, #127
  static NivelFinal1 + #499, #127
  static NivelFinal1 + #500, #127
  static NivelFinal1 + #501, #127
  static NivelFinal1 + #502, #127
  static NivelFinal1 + #503, #127
  static NivelFinal1 + #504, #127
  static NivelFinal1 + #505, #127
  static NivelFinal1 + #506, #127
  static NivelFinal1 + #507, #127
  static NivelFinal1 + #508, #127
  static NivelFinal1 + #509, #127
  static NivelFinal1 + #510, #127
  static NivelFinal1 + #511, #127
  static NivelFinal1 + #512, #127
  static NivelFinal1 + #513, #127
  static NivelFinal1 + #514, #127
  static NivelFinal1 + #515, #127
  static NivelFinal1 + #516, #127
  static NivelFinal1 + #517, #127
  static NivelFinal1 + #518, #127
  static NivelFinal1 + #519, #127

  ;Linha 13
  static NivelFinal1 + #520, #127
  static NivelFinal1 + #521, #127
  static NivelFinal1 + #522, #127
  static NivelFinal1 + #523, #127
  static NivelFinal1 + #524, #127
  static NivelFinal1 + #525, #127
  static NivelFinal1 + #526, #127
  static NivelFinal1 + #527, #127
  static NivelFinal1 + #528, #127
  static NivelFinal1 + #529, #127
  static NivelFinal1 + #530, #127
  static NivelFinal1 + #531, #127
  static NivelFinal1 + #532, #127
  static NivelFinal1 + #533, #127
  static NivelFinal1 + #534, #127
  static NivelFinal1 + #535, #127
  static NivelFinal1 + #536, #127
  static NivelFinal1 + #537, #127
  static NivelFinal1 + #538, #127
  static NivelFinal1 + #539, #127
  static NivelFinal1 + #540, #127
  static NivelFinal1 + #541, #127
  static NivelFinal1 + #542, #127
  static NivelFinal1 + #543, #127
  static NivelFinal1 + #544, #127
  static NivelFinal1 + #545, #127
  static NivelFinal1 + #546, #127
  static NivelFinal1 + #547, #127
  static NivelFinal1 + #548, #127
  static NivelFinal1 + #549, #127
  static NivelFinal1 + #550, #127
  static NivelFinal1 + #551, #127
  static NivelFinal1 + #552, #127
  static NivelFinal1 + #553, #127
  static NivelFinal1 + #554, #127
  static NivelFinal1 + #555, #127
  static NivelFinal1 + #556, #127
  static NivelFinal1 + #557, #127
  static NivelFinal1 + #558, #127
  static NivelFinal1 + #559, #127

  ;Linha 14
  static NivelFinal1 + #560, #127
  static NivelFinal1 + #561, #127
  static NivelFinal1 + #562, #127
  static NivelFinal1 + #563, #127
  static NivelFinal1 + #564, #127
  static NivelFinal1 + #565, #127
  static NivelFinal1 + #566, #127
  static NivelFinal1 + #567, #127
  static NivelFinal1 + #568, #127
  static NivelFinal1 + #569, #127
  static NivelFinal1 + #570, #127
  static NivelFinal1 + #571, #127
  static NivelFinal1 + #572, #127
  static NivelFinal1 + #573, #127
  static NivelFinal1 + #574, #127
  static NivelFinal1 + #575, #127
  static NivelFinal1 + #576, #127
  static NivelFinal1 + #577, #127
  static NivelFinal1 + #578, #127
  static NivelFinal1 + #579, #127
  static NivelFinal1 + #580, #127
  static NivelFinal1 + #581, #127
  static NivelFinal1 + #582, #127
  static NivelFinal1 + #583, #127
  static NivelFinal1 + #584, #127
  static NivelFinal1 + #585, #127
  static NivelFinal1 + #586, #127
  static NivelFinal1 + #587, #127
  static NivelFinal1 + #588, #127
  static NivelFinal1 + #589, #127
  static NivelFinal1 + #590, #127
  static NivelFinal1 + #591, #127
  static NivelFinal1 + #592, #127
  static NivelFinal1 + #593, #127
  static NivelFinal1 + #594, #127
  static NivelFinal1 + #595, #127
  static NivelFinal1 + #596, #127
  static NivelFinal1 + #597, #127
  static NivelFinal1 + #598, #127
  static NivelFinal1 + #599, #127

  ;Linha 15
  static NivelFinal1 + #600, #127
  static NivelFinal1 + #601, #127
  static NivelFinal1 + #602, #127
  static NivelFinal1 + #603, #127
  static NivelFinal1 + #604, #127
  static NivelFinal1 + #605, #127
  static NivelFinal1 + #606, #127
  static NivelFinal1 + #607, #127
  static NivelFinal1 + #608, #127
  static NivelFinal1 + #609, #127
  static NivelFinal1 + #610, #127
  static NivelFinal1 + #611, #127
  static NivelFinal1 + #612, #127
  static NivelFinal1 + #613, #127
  static NivelFinal1 + #614, #127
  static NivelFinal1 + #615, #127
  static NivelFinal1 + #616, #127
  static NivelFinal1 + #617, #127
  static NivelFinal1 + #618, #127
  static NivelFinal1 + #619, #127
  static NivelFinal1 + #620, #127
  static NivelFinal1 + #621, #127
  static NivelFinal1 + #622, #127
  static NivelFinal1 + #623, #127
  static NivelFinal1 + #624, #127
  static NivelFinal1 + #625, #127
  static NivelFinal1 + #626, #127
  static NivelFinal1 + #627, #127
  static NivelFinal1 + #628, #127
  static NivelFinal1 + #629, #127
  static NivelFinal1 + #630, #127
  static NivelFinal1 + #631, #127
  static NivelFinal1 + #632, #127
  static NivelFinal1 + #633, #127
  static NivelFinal1 + #634, #127
  static NivelFinal1 + #635, #127
  static NivelFinal1 + #636, #127
  static NivelFinal1 + #637, #127
  static NivelFinal1 + #638, #127
  static NivelFinal1 + #639, #127

  ;Linha 16
  static NivelFinal1 + #640, #127
  static NivelFinal1 + #641, #127
  static NivelFinal1 + #642, #127
  static NivelFinal1 + #643, #127
  static NivelFinal1 + #644, #127
  static NivelFinal1 + #645, #127
  static NivelFinal1 + #646, #127
  static NivelFinal1 + #647, #127
  static NivelFinal1 + #648, #127
  static NivelFinal1 + #649, #127
  static NivelFinal1 + #650, #127
  static NivelFinal1 + #651, #127
  static NivelFinal1 + #652, #127
  static NivelFinal1 + #653, #127
  static NivelFinal1 + #654, #127
  static NivelFinal1 + #655, #127
  static NivelFinal1 + #656, #127
  static NivelFinal1 + #657, #127
  static NivelFinal1 + #658, #3967
  static NivelFinal1 + #659, #3967
  static NivelFinal1 + #660, #3967
  static NivelFinal1 + #661, #127
  static NivelFinal1 + #662, #127
  static NivelFinal1 + #663, #127
  static NivelFinal1 + #664, #127
  static NivelFinal1 + #665, #127
  static NivelFinal1 + #666, #127
  static NivelFinal1 + #667, #127
  static NivelFinal1 + #668, #127
  static NivelFinal1 + #669, #127
  static NivelFinal1 + #670, #127
  static NivelFinal1 + #671, #127
  static NivelFinal1 + #672, #127
  static NivelFinal1 + #673, #127
  static NivelFinal1 + #674, #127
  static NivelFinal1 + #675, #127
  static NivelFinal1 + #676, #127
  static NivelFinal1 + #677, #127
  static NivelFinal1 + #678, #127
  static NivelFinal1 + #679, #127

  ;Linha 17
  static NivelFinal1 + #680, #127
  static NivelFinal1 + #681, #127
  static NivelFinal1 + #682, #127
  static NivelFinal1 + #683, #127
  static NivelFinal1 + #684, #127
  static NivelFinal1 + #685, #127
  static NivelFinal1 + #686, #127
  static NivelFinal1 + #687, #127
  static NivelFinal1 + #688, #127
  static NivelFinal1 + #689, #127
  static NivelFinal1 + #690, #127
  static NivelFinal1 + #691, #127
  static NivelFinal1 + #692, #127
  static NivelFinal1 + #693, #127
  static NivelFinal1 + #694, #127
  static NivelFinal1 + #695, #127
  static NivelFinal1 + #696, #127
  static NivelFinal1 + #697, #127
  static NivelFinal1 + #698, #3967
  static NivelFinal1 + #699, #3967
  static NivelFinal1 + #700, #3967
  static NivelFinal1 + #701, #3967
  static NivelFinal1 + #702, #127
  static NivelFinal1 + #703, #127
  static NivelFinal1 + #704, #127
  static NivelFinal1 + #705, #127
  static NivelFinal1 + #706, #127
  static NivelFinal1 + #707, #127
  static NivelFinal1 + #708, #3967
  static NivelFinal1 + #709, #3967
  static NivelFinal1 + #710, #3967
  static NivelFinal1 + #711, #127
  static NivelFinal1 + #712, #127
  static NivelFinal1 + #713, #127
  static NivelFinal1 + #714, #127
  static NivelFinal1 + #715, #127
  static NivelFinal1 + #716, #127
  static NivelFinal1 + #717, #127
  static NivelFinal1 + #718, #127
  static NivelFinal1 + #719, #127

  ;Linha 18
  static NivelFinal1 + #720, #127
  static NivelFinal1 + #721, #127
  static NivelFinal1 + #722, #127
  static NivelFinal1 + #723, #127
  static NivelFinal1 + #724, #127
  static NivelFinal1 + #725, #127
  static NivelFinal1 + #726, #3967
  static NivelFinal1 + #727, #127
  static NivelFinal1 + #728, #127
  static NivelFinal1 + #729, #127
  static NivelFinal1 + #730, #127
  static NivelFinal1 + #731, #127
  static NivelFinal1 + #732, #127
  static NivelFinal1 + #733, #127
  static NivelFinal1 + #734, #127
  static NivelFinal1 + #735, #127
  static NivelFinal1 + #736, #127
  static NivelFinal1 + #737, #127
  static NivelFinal1 + #738, #127
  static NivelFinal1 + #739, #127
  static NivelFinal1 + #740, #127
  static NivelFinal1 + #741, #127
  static NivelFinal1 + #742, #127
  static NivelFinal1 + #743, #127
  static NivelFinal1 + #744, #127
  static NivelFinal1 + #745, #127
  static NivelFinal1 + #746, #4
  static NivelFinal1 + #747, #4
  static NivelFinal1 + #748, #127
  static NivelFinal1 + #749, #3967
  static NivelFinal1 + #750, #3967
  static NivelFinal1 + #751, #127
  static NivelFinal1 + #752, #127
  static NivelFinal1 + #753, #127
  static NivelFinal1 + #754, #127
  static NivelFinal1 + #755, #127
  static NivelFinal1 + #756, #127
  static NivelFinal1 + #757, #127
  static NivelFinal1 + #758, #127
  static NivelFinal1 + #759, #127

  ;Linha 19
  static NivelFinal1 + #760, #127
  static NivelFinal1 + #761, #127
  static NivelFinal1 + #762, #127
  static NivelFinal1 + #763, #127
  static NivelFinal1 + #764, #127
  static NivelFinal1 + #765, #3967
  static NivelFinal1 + #766, #3967
  static NivelFinal1 + #767, #3967
  static NivelFinal1 + #768, #127
  static NivelFinal1 + #769, #127
  static NivelFinal1 + #770, #3967
  static NivelFinal1 + #771, #127
  static NivelFinal1 + #772, #127
  static NivelFinal1 + #773, #127
  static NivelFinal1 + #774, #127
  static NivelFinal1 + #775, #3967
  static NivelFinal1 + #776, #3967
  static NivelFinal1 + #777, #3967
  static NivelFinal1 + #778, #3967
  static NivelFinal1 + #779, #3967
  static NivelFinal1 + #780, #3967
  static NivelFinal1 + #781, #3967
  static NivelFinal1 + #782, #3967
  static NivelFinal1 + #783, #3967
  static NivelFinal1 + #784, #3967
  static NivelFinal1 + #785, #3967
  static NivelFinal1 + #786, #1795
  static NivelFinal1 + #787, #1797
  static NivelFinal1 + #788, #127
  static NivelFinal1 + #789, #3967
  static NivelFinal1 + #790, #3967
  static NivelFinal1 + #791, #127
  static NivelFinal1 + #792, #127
  static NivelFinal1 + #793, #127
  static NivelFinal1 + #794, #127
  static NivelFinal1 + #795, #127
  static NivelFinal1 + #796, #127
  static NivelFinal1 + #797, #127
  static NivelFinal1 + #798, #127
  static NivelFinal1 + #799, #127

  ;Linha 20
  static NivelFinal1 + #800, #127
  static NivelFinal1 + #801, #127
  static NivelFinal1 + #802, #127
  static NivelFinal1 + #803, #127
  static NivelFinal1 + #804, #3967
  static NivelFinal1 + #805, #127
  static NivelFinal1 + #806, #3967
  static NivelFinal1 + #807, #3967
  static NivelFinal1 + #808, #3967
  static NivelFinal1 + #809, #3967
  static NivelFinal1 + #810, #3967
  static NivelFinal1 + #811, #3967
  static NivelFinal1 + #812, #3967
  static NivelFinal1 + #813, #3967
  static NivelFinal1 + #814, #3967
  static NivelFinal1 + #815, #3967
  static NivelFinal1 + #816, #3967
  static NivelFinal1 + #817, #127
  static NivelFinal1 + #818, #127
  static NivelFinal1 + #819, #127
  static NivelFinal1 + #820, #127
  static NivelFinal1 + #821, #127
  static NivelFinal1 + #822, #127
  static NivelFinal1 + #823, #127
  static NivelFinal1 + #824, #3967
  static NivelFinal1 + #825, #3967
  static NivelFinal1 + #826, #1795
  static NivelFinal1 + #827, #1797
  static NivelFinal1 + #828, #127
  static NivelFinal1 + #829, #127
  static NivelFinal1 + #830, #3967
  static NivelFinal1 + #831, #127
  static NivelFinal1 + #832, #127
  static NivelFinal1 + #833, #127
  static NivelFinal1 + #834, #127
  static NivelFinal1 + #835, #127
  static NivelFinal1 + #836, #127
  static NivelFinal1 + #837, #127
  static NivelFinal1 + #838, #127
  static NivelFinal1 + #839, #127

  ;Linha 21
  static NivelFinal1 + #840, #127
  static NivelFinal1 + #841, #127
  static NivelFinal1 + #842, #127
  static NivelFinal1 + #843, #3967
  static NivelFinal1 + #844, #3967
  static NivelFinal1 + #845, #127
  static NivelFinal1 + #846, #127
  static NivelFinal1 + #847, #3967
  static NivelFinal1 + #848, #3967
  static NivelFinal1 + #849, #127
  static NivelFinal1 + #850, #3967
  static NivelFinal1 + #851, #3967
  static NivelFinal1 + #852, #3967
  static NivelFinal1 + #853, #3967
  static NivelFinal1 + #854, #127
  static NivelFinal1 + #855, #127
  static NivelFinal1 + #856, #127
  static NivelFinal1 + #857, #127
  static NivelFinal1 + #858, #127
  static NivelFinal1 + #859, #127
  static NivelFinal1 + #860, #127
  static NivelFinal1 + #861, #127
  static NivelFinal1 + #862, #3967
  static NivelFinal1 + #863, #3967
  static NivelFinal1 + #864, #21
  static NivelFinal1 + #865, #127
  static NivelFinal1 + #866, #2062
  static NivelFinal1 + #867, #2062
  static NivelFinal1 + #868, #127
  static NivelFinal1 + #869, #127
  static NivelFinal1 + #870, #3967
  static NivelFinal1 + #871, #3967
  static NivelFinal1 + #872, #127
  static NivelFinal1 + #873, #127
  static NivelFinal1 + #874, #127
  static NivelFinal1 + #875, #127
  static NivelFinal1 + #876, #3967
  static NivelFinal1 + #877, #3967
  static NivelFinal1 + #878, #3967
  static NivelFinal1 + #879, #127

  ;Linha 22
  static NivelFinal1 + #880, #127
  static NivelFinal1 + #881, #127
  static NivelFinal1 + #882, #127
  static NivelFinal1 + #883, #3967
  static NivelFinal1 + #884, #127
  static NivelFinal1 + #885, #127
  static NivelFinal1 + #886, #127
  static NivelFinal1 + #887, #127
  static NivelFinal1 + #888, #127
  static NivelFinal1 + #889, #3967
  static NivelFinal1 + #890, #3967
  static NivelFinal1 + #891, #127
  static NivelFinal1 + #892, #127
  static NivelFinal1 + #893, #127
  static NivelFinal1 + #894, #127
  static NivelFinal1 + #895, #127
  static NivelFinal1 + #896, #127
  static NivelFinal1 + #897, #127
  static NivelFinal1 + #898, #127
  static NivelFinal1 + #899, #127
  static NivelFinal1 + #900, #127
  static NivelFinal1 + #901, #3967
  static NivelFinal1 + #902, #127
  static NivelFinal1 + #903, #127
  static NivelFinal1 + #904, #127
  static NivelFinal1 + #905, #127
  static NivelFinal1 + #906, #127
  static NivelFinal1 + #907, #127
  static NivelFinal1 + #908, #127
  static NivelFinal1 + #909, #127
  static NivelFinal1 + #910, #3967
  static NivelFinal1 + #911, #3967
  static NivelFinal1 + #912, #127
  static NivelFinal1 + #913, #127
  static NivelFinal1 + #914, #127
  static NivelFinal1 + #915, #127
  static NivelFinal1 + #916, #3967
  static NivelFinal1 + #917, #3967
  static NivelFinal1 + #918, #3967
  static NivelFinal1 + #919, #3967

  ;Linha 23
  static NivelFinal1 + #920, #127
  static NivelFinal1 + #921, #127
  static NivelFinal1 + #922, #127
  static NivelFinal1 + #923, #3967
  static NivelFinal1 + #924, #127
  static NivelFinal1 + #925, #127
  static NivelFinal1 + #926, #127
  static NivelFinal1 + #927, #127
  static NivelFinal1 + #928, #3967
  static NivelFinal1 + #929, #3967
  static NivelFinal1 + #930, #3967
  static NivelFinal1 + #931, #3967
  static NivelFinal1 + #932, #127
  static NivelFinal1 + #933, #127
  static NivelFinal1 + #934, #127
  static NivelFinal1 + #935, #127
  static NivelFinal1 + #936, #127
  static NivelFinal1 + #937, #127
  static NivelFinal1 + #938, #127
  static NivelFinal1 + #939, #127
  static NivelFinal1 + #940, #3967
  static NivelFinal1 + #941, #127
  static NivelFinal1 + #942, #3967
  static NivelFinal1 + #943, #127
  static NivelFinal1 + #944, #127
  static NivelFinal1 + #945, #127
  static NivelFinal1 + #946, #127
  static NivelFinal1 + #947, #127
  static NivelFinal1 + #948, #127
  static NivelFinal1 + #949, #127
  static NivelFinal1 + #950, #3967
  static NivelFinal1 + #951, #4
  static NivelFinal1 + #952, #4
  static NivelFinal1 + #953, #127
  static NivelFinal1 + #954, #127
  static NivelFinal1 + #955, #127
  static NivelFinal1 + #956, #3967
  static NivelFinal1 + #957, #3967
  static NivelFinal1 + #958, #3967
  static NivelFinal1 + #959, #3967

  ;Linha 24
  static NivelFinal1 + #960, #127
  static NivelFinal1 + #961, #127
  static NivelFinal1 + #962, #127
  static NivelFinal1 + #963, #3967
  static NivelFinal1 + #964, #3967
  static NivelFinal1 + #965, #3967
  static NivelFinal1 + #966, #3967
  static NivelFinal1 + #967, #3967
  static NivelFinal1 + #968, #3967
  static NivelFinal1 + #969, #3967
  static NivelFinal1 + #970, #3967
  static NivelFinal1 + #971, #3967
  static NivelFinal1 + #972, #3967
  static NivelFinal1 + #973, #3967
  static NivelFinal1 + #974, #3967
  static NivelFinal1 + #975, #3967
  static NivelFinal1 + #976, #127
  static NivelFinal1 + #977, #3967
  static NivelFinal1 + #978, #3967
  static NivelFinal1 + #979, #3967
  static NivelFinal1 + #980, #3967
  static NivelFinal1 + #981, #3967
  static NivelFinal1 + #982, #3967
  static NivelFinal1 + #983, #3967
  static NivelFinal1 + #984, #3967
  static NivelFinal1 + #985, #3967
  static NivelFinal1 + #986, #127
  static NivelFinal1 + #987, #127
  static NivelFinal1 + #988, #3967
  static NivelFinal1 + #989, #3967
  static NivelFinal1 + #990, #3967
  static NivelFinal1 + #991, #1795
  static NivelFinal1 + #992, #1797
  static NivelFinal1 + #993, #127
  static NivelFinal1 + #994, #127
  static NivelFinal1 + #995, #127
  static NivelFinal1 + #996, #3967
  static NivelFinal1 + #997, #3967
  static NivelFinal1 + #998, #3967
  static NivelFinal1 + #999, #3967

  ;Linha 25
  static NivelFinal1 + #1000, #2062
  static NivelFinal1 + #1001, #2062
  static NivelFinal1 + #1002, #2062
  static NivelFinal1 + #1003, #2062
  static NivelFinal1 + #1004, #2062
  static NivelFinal1 + #1005, #2062
  static NivelFinal1 + #1006, #127
  static NivelFinal1 + #1007, #3967
  static NivelFinal1 + #1008, #3967
  static NivelFinal1 + #1009, #127
  static NivelFinal1 + #1010, #3967
  static NivelFinal1 + #1011, #127
  static NivelFinal1 + #1012, #127
  static NivelFinal1 + #1013, #127
  static NivelFinal1 + #1014, #127
  static NivelFinal1 + #1015, #3967
  static NivelFinal1 + #1016, #3967
  static NivelFinal1 + #1017, #3967
  static NivelFinal1 + #1018, #3967
  static NivelFinal1 + #1019, #3967
  static NivelFinal1 + #1020, #2062
  static NivelFinal1 + #1021, #2062
  static NivelFinal1 + #1022, #2062
  static NivelFinal1 + #1023, #2062
  static NivelFinal1 + #1024, #2062
  static NivelFinal1 + #1025, #2062
  static NivelFinal1 + #1026, #2062
  static NivelFinal1 + #1027, #2062
  static NivelFinal1 + #1028, #2062
  static NivelFinal1 + #1029, #2062
  static NivelFinal1 + #1030, #2062
  static NivelFinal1 + #1031, #1795
  static NivelFinal1 + #1032, #1797
  static NivelFinal1 + #1033, #2062
  static NivelFinal1 + #1034, #2062
  static NivelFinal1 + #1035, #2062
  static NivelFinal1 + #1036, #2062
  static NivelFinal1 + #1037, #2062
  static NivelFinal1 + #1038, #2062
  static NivelFinal1 + #1039, #2062

  ;Linha 26
  static NivelFinal1 + #1040, #2062
  static NivelFinal1 + #1041, #2062
  static NivelFinal1 + #1042, #2062
  static NivelFinal1 + #1043, #2062
  static NivelFinal1 + #1044, #2062
  static NivelFinal1 + #1045, #2062
  static NivelFinal1 + #1046, #127
  static NivelFinal1 + #1047, #127
  static NivelFinal1 + #1048, #127
  static NivelFinal1 + #1049, #127
  static NivelFinal1 + #1050, #3967
  static NivelFinal1 + #1051, #3967
  static NivelFinal1 + #1052, #127
  static NivelFinal1 + #1053, #127
  static NivelFinal1 + #1054, #127
  static NivelFinal1 + #1055, #3967
  static NivelFinal1 + #1056, #3967
  static NivelFinal1 + #1057, #3967
  static NivelFinal1 + #1058, #3967
  static NivelFinal1 + #1059, #127
  static NivelFinal1 + #1060, #2062
  static NivelFinal1 + #1061, #2062
  static NivelFinal1 + #1062, #2062
  static NivelFinal1 + #1063, #2062
  static NivelFinal1 + #1064, #2062
  static NivelFinal1 + #1065, #2062
  static NivelFinal1 + #1066, #2062
  static NivelFinal1 + #1067, #2062
  static NivelFinal1 + #1068, #2062
  static NivelFinal1 + #1069, #2062
  static NivelFinal1 + #1070, #2062
  static NivelFinal1 + #1071, #1795
  static NivelFinal1 + #1072, #1797
  static NivelFinal1 + #1073, #2062
  static NivelFinal1 + #1074, #2062
  static NivelFinal1 + #1075, #2062
  static NivelFinal1 + #1076, #2062
  static NivelFinal1 + #1077, #2062
  static NivelFinal1 + #1078, #2062
  static NivelFinal1 + #1079, #2062

  ;Linha 27
  static NivelFinal1 + #1080, #2062
  static NivelFinal1 + #1081, #2062
  static NivelFinal1 + #1082, #2062
  static NivelFinal1 + #1083, #2062
  static NivelFinal1 + #1084, #2062
  static NivelFinal1 + #1085, #2062
  static NivelFinal1 + #1086, #3967
  static NivelFinal1 + #1087, #127
  static NivelFinal1 + #1088, #127
  static NivelFinal1 + #1089, #127
  static NivelFinal1 + #1090, #127
  static NivelFinal1 + #1091, #127
  static NivelFinal1 + #1092, #127
  static NivelFinal1 + #1093, #127
  static NivelFinal1 + #1094, #3967
  static NivelFinal1 + #1095, #3967
  static NivelFinal1 + #1096, #3967
  static NivelFinal1 + #1097, #3967
  static NivelFinal1 + #1098, #3967
  static NivelFinal1 + #1099, #3967
  static NivelFinal1 + #1100, #2062
  static NivelFinal1 + #1101, #2062
  static NivelFinal1 + #1102, #2062
  static NivelFinal1 + #1103, #2062
  static NivelFinal1 + #1104, #2062
  static NivelFinal1 + #1105, #2062
  static NivelFinal1 + #1106, #2062
  static NivelFinal1 + #1107, #2062
  static NivelFinal1 + #1108, #2062
  static NivelFinal1 + #1109, #2062
  static NivelFinal1 + #1110, #2062
  static NivelFinal1 + #1111, #1795
  static NivelFinal1 + #1112, #1797
  static NivelFinal1 + #1113, #2062
  static NivelFinal1 + #1114, #2062
  static NivelFinal1 + #1115, #2062
  static NivelFinal1 + #1116, #2062
  static NivelFinal1 + #1117, #2062
  static NivelFinal1 + #1118, #2062
  static NivelFinal1 + #1119, #2062

  ;Linha 28
  static NivelFinal1 + #1120, #2062
  static NivelFinal1 + #1121, #2062
  static NivelFinal1 + #1122, #2062
  static NivelFinal1 + #1123, #2062
  static NivelFinal1 + #1124, #2062
  static NivelFinal1 + #1125, #2062
  static NivelFinal1 + #1126, #2320
  static NivelFinal1 + #1127, #2320
  static NivelFinal1 + #1128, #2321
  static NivelFinal1 + #1129, #2321
  static NivelFinal1 + #1130, #2321
  static NivelFinal1 + #1131, #2320
  static NivelFinal1 + #1132, #2320
  static NivelFinal1 + #1133, #2320
  static NivelFinal1 + #1134, #2320
  static NivelFinal1 + #1135, #2320
  static NivelFinal1 + #1136, #2320
  static NivelFinal1 + #1137, #2320
  static NivelFinal1 + #1138, #2320
  static NivelFinal1 + #1139, #2320
  static NivelFinal1 + #1140, #2062
  static NivelFinal1 + #1141, #2062
  static NivelFinal1 + #1142, #2062
  static NivelFinal1 + #1143, #2062
  static NivelFinal1 + #1144, #2062
  static NivelFinal1 + #1145, #2062
  static NivelFinal1 + #1146, #2062
  static NivelFinal1 + #1147, #2062
  static NivelFinal1 + #1148, #2062
  static NivelFinal1 + #1149, #2062
  static NivelFinal1 + #1150, #2062
  static NivelFinal1 + #1151, #1795
  static NivelFinal1 + #1152, #1797
  static NivelFinal1 + #1153, #2062
  static NivelFinal1 + #1154, #2062
  static NivelFinal1 + #1155, #2062
  static NivelFinal1 + #1156, #2062
  static NivelFinal1 + #1157, #2062
  static NivelFinal1 + #1158, #2062
  static NivelFinal1 + #1159, #2062

  ;Linha 29
  static NivelFinal1 + #1160, #2062
  static NivelFinal1 + #1161, #2062
  static NivelFinal1 + #1162, #2062
  static NivelFinal1 + #1163, #2062
  static NivelFinal1 + #1164, #2062
  static NivelFinal1 + #1165, #2062
  static NivelFinal1 + #1166, #2319
  static NivelFinal1 + #1167, #2319
  static NivelFinal1 + #1168, #2319
  static NivelFinal1 + #1169, #2319
  static NivelFinal1 + #1170, #2319
  static NivelFinal1 + #1171, #2319
  static NivelFinal1 + #1172, #2319
  static NivelFinal1 + #1173, #2319
  static NivelFinal1 + #1174, #2319
  static NivelFinal1 + #1175, #2319
  static NivelFinal1 + #1176, #2319
  static NivelFinal1 + #1177, #2319
  static NivelFinal1 + #1178, #2319
  static NivelFinal1 + #1179, #2319
  static NivelFinal1 + #1180, #2062
  static NivelFinal1 + #1181, #2062
  static NivelFinal1 + #1182, #2062
  static NivelFinal1 + #1183, #2062
  static NivelFinal1 + #1184, #2062
  static NivelFinal1 + #1185, #2062
  static NivelFinal1 + #1186, #2062
  static NivelFinal1 + #1187, #2062
  static NivelFinal1 + #1188, #2062
  static NivelFinal1 + #1189, #2062
  static NivelFinal1 + #1190, #2062
  static NivelFinal1 + #1191, #1795
  static NivelFinal1 + #1192, #1797
  static NivelFinal1 + #1193, #2062
  static NivelFinal1 + #1194, #2062
  static NivelFinal1 + #1195, #2062
  static NivelFinal1 + #1196, #2062
  static NivelFinal1 + #1197, #2062
  static NivelFinal1 + #1198, #2062
  static NivelFinal1 + #1199, #2062

printNivelFinal1Screen:
  push R0
  push R1
  push R2
  push R3

  loadn R0, #NivelFinal1
  loadn R1, #0
  loadn R2, #1200

  printNivelFinal1ScreenLoop:

    add R3,R0,R1
    loadi R3, R3
    outchar R3, R1
    inc R1
    cmp R1, R2

    jne printNivelFinal1ScreenLoop

  pop R3
  pop R2
  pop R1
  pop R0
  rts

NivelFinal2 : var #1200
  ;Linha 0
  static NivelFinal2 + #0, #3967
  static NivelFinal2 + #1, #3967
  static NivelFinal2 + #2, #3967
  static NivelFinal2 + #3, #3967
  static NivelFinal2 + #4, #3967
  static NivelFinal2 + #5, #3967
  static NivelFinal2 + #6, #3967
  static NivelFinal2 + #7, #3967
  static NivelFinal2 + #8, #3967
  static NivelFinal2 + #9, #3967
  static NivelFinal2 + #10, #3967
  static NivelFinal2 + #11, #3967
  static NivelFinal2 + #12, #3967
  static NivelFinal2 + #13, #3967
  static NivelFinal2 + #14, #3967
  static NivelFinal2 + #15, #3967
  static NivelFinal2 + #16, #3967
  static NivelFinal2 + #17, #3967
  static NivelFinal2 + #18, #3967
  static NivelFinal2 + #19, #3967
  static NivelFinal2 + #20, #3967
  static NivelFinal2 + #21, #3967
  static NivelFinal2 + #22, #3967
  static NivelFinal2 + #23, #3967
  static NivelFinal2 + #24, #3967
  static NivelFinal2 + #25, #3967
  static NivelFinal2 + #26, #3967
  static NivelFinal2 + #27, #3967
  static NivelFinal2 + #28, #3967
  static NivelFinal2 + #29, #3967
  static NivelFinal2 + #30, #3967
  static NivelFinal2 + #31, #3967
  static NivelFinal2 + #32, #3967
  static NivelFinal2 + #33, #3967
  static NivelFinal2 + #34, #3967
  static NivelFinal2 + #35, #3967
  static NivelFinal2 + #36, #3967
  static NivelFinal2 + #37, #3967
  static NivelFinal2 + #38, #3967
  static NivelFinal2 + #39, #3967

  ;Linha 1
  static NivelFinal2 + #40, #3967
  static NivelFinal2 + #41, #3967
  static NivelFinal2 + #42, #3967
  static NivelFinal2 + #43, #3967
  static NivelFinal2 + #44, #3967
  static NivelFinal2 + #45, #3967
  static NivelFinal2 + #46, #3967
  static NivelFinal2 + #47, #3967
  static NivelFinal2 + #48, #3967
  static NivelFinal2 + #49, #3967
  static NivelFinal2 + #50, #3967
  static NivelFinal2 + #51, #3967
  static NivelFinal2 + #52, #3967
  static NivelFinal2 + #53, #3967
  static NivelFinal2 + #54, #3967
  static NivelFinal2 + #55, #3967
  static NivelFinal2 + #56, #3967
  static NivelFinal2 + #57, #3967
  static NivelFinal2 + #58, #3967
  static NivelFinal2 + #59, #3967
  static NivelFinal2 + #60, #3967
  static NivelFinal2 + #61, #3967
  static NivelFinal2 + #62, #3967
  static NivelFinal2 + #63, #3967
  static NivelFinal2 + #64, #3967
  static NivelFinal2 + #65, #3967
  static NivelFinal2 + #66, #3967
  static NivelFinal2 + #67, #3967
  static NivelFinal2 + #68, #3967
  static NivelFinal2 + #69, #3967
  static NivelFinal2 + #70, #3967
  static NivelFinal2 + #71, #3967
  static NivelFinal2 + #72, #3967
  static NivelFinal2 + #73, #3967
  static NivelFinal2 + #74, #3967
  static NivelFinal2 + #75, #3967
  static NivelFinal2 + #76, #3967
  static NivelFinal2 + #77, #3967
  static NivelFinal2 + #78, #3967
  static NivelFinal2 + #79, #3967

  ;Linha 2
  static NivelFinal2 + #80, #3967
  static NivelFinal2 + #81, #3967
  static NivelFinal2 + #82, #3967
  static NivelFinal2 + #83, #3967
  static NivelFinal2 + #84, #3967
  static NivelFinal2 + #85, #3967
  static NivelFinal2 + #86, #3967
  static NivelFinal2 + #87, #3967
  static NivelFinal2 + #88, #3967
  static NivelFinal2 + #89, #3967
  static NivelFinal2 + #90, #3967
  static NivelFinal2 + #91, #3967
  static NivelFinal2 + #92, #3967
  static NivelFinal2 + #93, #3967
  static NivelFinal2 + #94, #3967
  static NivelFinal2 + #95, #3967
  static NivelFinal2 + #96, #3967
  static NivelFinal2 + #97, #3967
  static NivelFinal2 + #98, #3967
  static NivelFinal2 + #99, #3967
  static NivelFinal2 + #100, #3967
  static NivelFinal2 + #101, #3967
  static NivelFinal2 + #102, #3967
  static NivelFinal2 + #103, #3967
  static NivelFinal2 + #104, #3967
  static NivelFinal2 + #105, #3967
  static NivelFinal2 + #106, #3967
  static NivelFinal2 + #107, #3967
  static NivelFinal2 + #108, #3967
  static NivelFinal2 + #109, #3967
  static NivelFinal2 + #110, #3967
  static NivelFinal2 + #111, #3967
  static NivelFinal2 + #112, #3967
  static NivelFinal2 + #113, #3967
  static NivelFinal2 + #114, #3967
  static NivelFinal2 + #115, #3967
  static NivelFinal2 + #116, #3967
  static NivelFinal2 + #117, #3967
  static NivelFinal2 + #118, #3967
  static NivelFinal2 + #119, #3967

  ;Linha 3
  static NivelFinal2 + #120, #127
  static NivelFinal2 + #121, #3967
  static NivelFinal2 + #122, #3967
  static NivelFinal2 + #123, #3967
  static NivelFinal2 + #124, #127
  static NivelFinal2 + #125, #127
  static NivelFinal2 + #126, #127
  static NivelFinal2 + #127, #127
  static NivelFinal2 + #128, #127
  static NivelFinal2 + #129, #127
  static NivelFinal2 + #130, #3967
  static NivelFinal2 + #131, #3967
  static NivelFinal2 + #132, #3967
  static NivelFinal2 + #133, #3967
  static NivelFinal2 + #134, #127
  static NivelFinal2 + #135, #3967
  static NivelFinal2 + #136, #3967
  static NivelFinal2 + #137, #3967
  static NivelFinal2 + #138, #3967
  static NivelFinal2 + #139, #3967
  static NivelFinal2 + #140, #3967
  static NivelFinal2 + #141, #3967
  static NivelFinal2 + #142, #3967
  static NivelFinal2 + #143, #3967
  static NivelFinal2 + #144, #3967
  static NivelFinal2 + #145, #3967
  static NivelFinal2 + #146, #3967
  static NivelFinal2 + #147, #3967
  static NivelFinal2 + #148, #3967
  static NivelFinal2 + #149, #3967
  static NivelFinal2 + #150, #3967
  static NivelFinal2 + #151, #3967
  static NivelFinal2 + #152, #3967
  static NivelFinal2 + #153, #3967
  static NivelFinal2 + #154, #3967
  static NivelFinal2 + #155, #3967
  static NivelFinal2 + #156, #3967
  static NivelFinal2 + #157, #3967
  static NivelFinal2 + #158, #3967
  static NivelFinal2 + #159, #3967

  ;Linha 4
  static NivelFinal2 + #160, #127
  static NivelFinal2 + #161, #127
  static NivelFinal2 + #162, #127
  static NivelFinal2 + #163, #127
  static NivelFinal2 + #164, #127
  static NivelFinal2 + #165, #127
  static NivelFinal2 + #166, #127
  static NivelFinal2 + #167, #127
  static NivelFinal2 + #168, #127
  static NivelFinal2 + #169, #127
  static NivelFinal2 + #170, #127
  static NivelFinal2 + #171, #127
  static NivelFinal2 + #172, #127
  static NivelFinal2 + #173, #127
  static NivelFinal2 + #174, #3967
  static NivelFinal2 + #175, #3967
  static NivelFinal2 + #176, #3967
  static NivelFinal2 + #177, #127
  static NivelFinal2 + #178, #3967
  static NivelFinal2 + #179, #3967
  static NivelFinal2 + #180, #3967
  static NivelFinal2 + #181, #3967
  static NivelFinal2 + #182, #3967
  static NivelFinal2 + #183, #3967
  static NivelFinal2 + #184, #3967
  static NivelFinal2 + #185, #3967
  static NivelFinal2 + #186, #127
  static NivelFinal2 + #187, #3967
  static NivelFinal2 + #188, #3967
  static NivelFinal2 + #189, #3967
  static NivelFinal2 + #190, #3967
  static NivelFinal2 + #191, #3967
  static NivelFinal2 + #192, #3967
  static NivelFinal2 + #193, #3967
  static NivelFinal2 + #194, #3967
  static NivelFinal2 + #195, #3967
  static NivelFinal2 + #196, #3967
  static NivelFinal2 + #197, #3967
  static NivelFinal2 + #198, #3967
  static NivelFinal2 + #199, #3967

  ;Linha 5
  static NivelFinal2 + #200, #127
  static NivelFinal2 + #201, #127
  static NivelFinal2 + #202, #127
  static NivelFinal2 + #203, #127
  static NivelFinal2 + #204, #127
  static NivelFinal2 + #205, #127
  static NivelFinal2 + #206, #127
  static NivelFinal2 + #207, #127
  static NivelFinal2 + #208, #127
  static NivelFinal2 + #209, #127
  static NivelFinal2 + #210, #127
  static NivelFinal2 + #211, #127
  static NivelFinal2 + #212, #127
  static NivelFinal2 + #213, #127
  static NivelFinal2 + #214, #127
  static NivelFinal2 + #215, #127
  static NivelFinal2 + #216, #127
  static NivelFinal2 + #217, #127
  static NivelFinal2 + #218, #3967
  static NivelFinal2 + #219, #3967
  static NivelFinal2 + #220, #3967
  static NivelFinal2 + #221, #3967
  static NivelFinal2 + #222, #3967
  static NivelFinal2 + #223, #3967
  static NivelFinal2 + #224, #3967
  static NivelFinal2 + #225, #3967
  static NivelFinal2 + #226, #127
  static NivelFinal2 + #227, #127
  static NivelFinal2 + #228, #127
  static NivelFinal2 + #229, #127
  static NivelFinal2 + #230, #127
  static NivelFinal2 + #231, #3967
  static NivelFinal2 + #232, #3967
  static NivelFinal2 + #233, #3967
  static NivelFinal2 + #234, #3967
  static NivelFinal2 + #235, #3967
  static NivelFinal2 + #236, #3967
  static NivelFinal2 + #237, #3967
  static NivelFinal2 + #238, #3967
  static NivelFinal2 + #239, #3967

  ;Linha 6
  static NivelFinal2 + #240, #127
  static NivelFinal2 + #241, #127
  static NivelFinal2 + #242, #127
  static NivelFinal2 + #243, #127
  static NivelFinal2 + #244, #127
  static NivelFinal2 + #245, #127
  static NivelFinal2 + #246, #127
  static NivelFinal2 + #247, #127
  static NivelFinal2 + #248, #127
  static NivelFinal2 + #249, #127
  static NivelFinal2 + #250, #127
  static NivelFinal2 + #251, #127
  static NivelFinal2 + #252, #127
  static NivelFinal2 + #253, #127
  static NivelFinal2 + #254, #127
  static NivelFinal2 + #255, #127
  static NivelFinal2 + #256, #127
  static NivelFinal2 + #257, #127
  static NivelFinal2 + #258, #127
  static NivelFinal2 + #259, #127
  static NivelFinal2 + #260, #127
  static NivelFinal2 + #261, #127
  static NivelFinal2 + #262, #127
  static NivelFinal2 + #263, #127
  static NivelFinal2 + #264, #3967
  static NivelFinal2 + #265, #3967
  static NivelFinal2 + #266, #127
  static NivelFinal2 + #267, #127
  static NivelFinal2 + #268, #127
  static NivelFinal2 + #269, #127
  static NivelFinal2 + #270, #127
  static NivelFinal2 + #271, #127
  static NivelFinal2 + #272, #127
  static NivelFinal2 + #273, #3967
  static NivelFinal2 + #274, #3967
  static NivelFinal2 + #275, #3967
  static NivelFinal2 + #276, #3967
  static NivelFinal2 + #277, #3967
  static NivelFinal2 + #278, #3967
  static NivelFinal2 + #279, #127

  ;Linha 7
  static NivelFinal2 + #280, #127
  static NivelFinal2 + #281, #127
  static NivelFinal2 + #282, #127
  static NivelFinal2 + #283, #127
  static NivelFinal2 + #284, #127
  static NivelFinal2 + #285, #127
  static NivelFinal2 + #286, #127
  static NivelFinal2 + #287, #127
  static NivelFinal2 + #288, #127
  static NivelFinal2 + #289, #127
  static NivelFinal2 + #290, #127
  static NivelFinal2 + #291, #127
  static NivelFinal2 + #292, #127
  static NivelFinal2 + #293, #127
  static NivelFinal2 + #294, #127
  static NivelFinal2 + #295, #127
  static NivelFinal2 + #296, #127
  static NivelFinal2 + #297, #127
  static NivelFinal2 + #298, #127
  static NivelFinal2 + #299, #127
  static NivelFinal2 + #300, #127
  static NivelFinal2 + #301, #127
  static NivelFinal2 + #302, #127
  static NivelFinal2 + #303, #127
  static NivelFinal2 + #304, #127
  static NivelFinal2 + #305, #127
  static NivelFinal2 + #306, #127
  static NivelFinal2 + #307, #127
  static NivelFinal2 + #308, #127
  static NivelFinal2 + #309, #127
  static NivelFinal2 + #310, #127
  static NivelFinal2 + #311, #127
  static NivelFinal2 + #312, #127
  static NivelFinal2 + #313, #127
  static NivelFinal2 + #314, #127
  static NivelFinal2 + #315, #127
  static NivelFinal2 + #316, #3967
  static NivelFinal2 + #317, #3967
  static NivelFinal2 + #318, #3967
  static NivelFinal2 + #319, #127

  ;Linha 8
  static NivelFinal2 + #320, #127
  static NivelFinal2 + #321, #127
  static NivelFinal2 + #322, #127
  static NivelFinal2 + #323, #127
  static NivelFinal2 + #324, #127
  static NivelFinal2 + #325, #127
  static NivelFinal2 + #326, #127
  static NivelFinal2 + #327, #127
  static NivelFinal2 + #328, #127
  static NivelFinal2 + #329, #127
  static NivelFinal2 + #330, #127
  static NivelFinal2 + #331, #127
  static NivelFinal2 + #332, #127
  static NivelFinal2 + #333, #127
  static NivelFinal2 + #334, #127
  static NivelFinal2 + #335, #127
  static NivelFinal2 + #336, #127
  static NivelFinal2 + #337, #3967
  static NivelFinal2 + #338, #127
  static NivelFinal2 + #339, #127
  static NivelFinal2 + #340, #127
  static NivelFinal2 + #341, #127
  static NivelFinal2 + #342, #127
  static NivelFinal2 + #343, #127
  static NivelFinal2 + #344, #127
  static NivelFinal2 + #345, #127
  static NivelFinal2 + #346, #127
  static NivelFinal2 + #347, #127
  static NivelFinal2 + #348, #127
  static NivelFinal2 + #349, #127
  static NivelFinal2 + #350, #127
  static NivelFinal2 + #351, #127
  static NivelFinal2 + #352, #127
  static NivelFinal2 + #353, #127
  static NivelFinal2 + #354, #127
  static NivelFinal2 + #355, #127
  static NivelFinal2 + #356, #127
  static NivelFinal2 + #357, #127
  static NivelFinal2 + #358, #127
  static NivelFinal2 + #359, #127

  ;Linha 9
  static NivelFinal2 + #360, #127
  static NivelFinal2 + #361, #127
  static NivelFinal2 + #362, #127
  static NivelFinal2 + #363, #127
  static NivelFinal2 + #364, #127
  static NivelFinal2 + #365, #127
  static NivelFinal2 + #366, #127
  static NivelFinal2 + #367, #127
  static NivelFinal2 + #368, #127
  static NivelFinal2 + #369, #127
  static NivelFinal2 + #370, #127
  static NivelFinal2 + #371, #127
  static NivelFinal2 + #372, #127
  static NivelFinal2 + #373, #127
  static NivelFinal2 + #374, #3967
  static NivelFinal2 + #375, #3967
  static NivelFinal2 + #376, #3967
  static NivelFinal2 + #377, #3967
  static NivelFinal2 + #378, #127
  static NivelFinal2 + #379, #127
  static NivelFinal2 + #380, #127
  static NivelFinal2 + #381, #127
  static NivelFinal2 + #382, #127
  static NivelFinal2 + #383, #127
  static NivelFinal2 + #384, #127
  static NivelFinal2 + #385, #127
  static NivelFinal2 + #386, #127
  static NivelFinal2 + #387, #127
  static NivelFinal2 + #388, #127
  static NivelFinal2 + #389, #127
  static NivelFinal2 + #390, #127
  static NivelFinal2 + #391, #127
  static NivelFinal2 + #392, #127
  static NivelFinal2 + #393, #127
  static NivelFinal2 + #394, #127
  static NivelFinal2 + #395, #127
  static NivelFinal2 + #396, #127
  static NivelFinal2 + #397, #127
  static NivelFinal2 + #398, #127
  static NivelFinal2 + #399, #127

  ;Linha 10
  static NivelFinal2 + #400, #2062
  static NivelFinal2 + #401, #2062
  static NivelFinal2 + #402, #2062
  static NivelFinal2 + #403, #2062
  static NivelFinal2 + #404, #2062
  static NivelFinal2 + #405, #2062
  static NivelFinal2 + #406, #2062
  static NivelFinal2 + #407, #2062
  static NivelFinal2 + #408, #2062
  static NivelFinal2 + #409, #2062
  static NivelFinal2 + #410, #2062
  static NivelFinal2 + #411, #2062
  static NivelFinal2 + #412, #2062
  static NivelFinal2 + #413, #2062
  static NivelFinal2 + #414, #2062
  static NivelFinal2 + #415, #2062
  static NivelFinal2 + #416, #2062
  static NivelFinal2 + #417, #2062
  static NivelFinal2 + #418, #2062
  static NivelFinal2 + #419, #2062
  static NivelFinal2 + #420, #2062
  static NivelFinal2 + #421, #2062
  static NivelFinal2 + #422, #2062
  static NivelFinal2 + #423, #2062
  static NivelFinal2 + #424, #2062
  static NivelFinal2 + #425, #2062
  static NivelFinal2 + #426, #2062
  static NivelFinal2 + #427, #2062
  static NivelFinal2 + #428, #2062
  static NivelFinal2 + #429, #2062
  static NivelFinal2 + #430, #2062
  static NivelFinal2 + #431, #2062
  static NivelFinal2 + #432, #2062
  static NivelFinal2 + #433, #2062
  static NivelFinal2 + #434, #2062
  static NivelFinal2 + #435, #2062
  static NivelFinal2 + #436, #2062
  static NivelFinal2 + #437, #2062
  static NivelFinal2 + #438, #2062
  static NivelFinal2 + #439, #2062

  ;Linha 11
  static NivelFinal2 + #440, #2062
  static NivelFinal2 + #441, #2062
  static NivelFinal2 + #442, #2062
  static NivelFinal2 + #443, #2062
  static NivelFinal2 + #444, #2062
  static NivelFinal2 + #445, #2062
  static NivelFinal2 + #446, #2062
  static NivelFinal2 + #447, #2062
  static NivelFinal2 + #448, #2062
  static NivelFinal2 + #449, #2062
  static NivelFinal2 + #450, #2062
  static NivelFinal2 + #451, #2062
  static NivelFinal2 + #452, #2062
  static NivelFinal2 + #453, #2062
  static NivelFinal2 + #454, #2062
  static NivelFinal2 + #455, #2062
  static NivelFinal2 + #456, #2062
  static NivelFinal2 + #457, #2062
  static NivelFinal2 + #458, #2062
  static NivelFinal2 + #459, #2062
  static NivelFinal2 + #460, #2062
  static NivelFinal2 + #461, #2062
  static NivelFinal2 + #462, #2062
  static NivelFinal2 + #463, #2062
  static NivelFinal2 + #464, #2062
  static NivelFinal2 + #465, #2062
  static NivelFinal2 + #466, #2062
  static NivelFinal2 + #467, #2062
  static NivelFinal2 + #468, #2062
  static NivelFinal2 + #469, #2062
  static NivelFinal2 + #470, #2062
  static NivelFinal2 + #471, #2062
  static NivelFinal2 + #472, #2062
  static NivelFinal2 + #473, #2062
  static NivelFinal2 + #474, #2062
  static NivelFinal2 + #475, #2062
  static NivelFinal2 + #476, #2062
  static NivelFinal2 + #477, #2062
  static NivelFinal2 + #478, #2062
  static NivelFinal2 + #479, #2062

  ;Linha 12
  static NivelFinal2 + #480, #127
  static NivelFinal2 + #481, #127
  static NivelFinal2 + #482, #127
  static NivelFinal2 + #483, #127
  static NivelFinal2 + #484, #127
  static NivelFinal2 + #485, #127
  static NivelFinal2 + #486, #127
  static NivelFinal2 + #487, #127
  static NivelFinal2 + #488, #127
  static NivelFinal2 + #489, #127
  static NivelFinal2 + #490, #127
  static NivelFinal2 + #491, #127
  static NivelFinal2 + #492, #127
  static NivelFinal2 + #493, #127
  static NivelFinal2 + #494, #127
  static NivelFinal2 + #495, #127
  static NivelFinal2 + #496, #127
  static NivelFinal2 + #497, #127
  static NivelFinal2 + #498, #127
  static NivelFinal2 + #499, #127
  static NivelFinal2 + #500, #127
  static NivelFinal2 + #501, #127
  static NivelFinal2 + #502, #127
  static NivelFinal2 + #503, #127
  static NivelFinal2 + #504, #127
  static NivelFinal2 + #505, #127
  static NivelFinal2 + #506, #127
  static NivelFinal2 + #507, #127
  static NivelFinal2 + #508, #127
  static NivelFinal2 + #509, #127
  static NivelFinal2 + #510, #127
  static NivelFinal2 + #511, #127
  static NivelFinal2 + #512, #127
  static NivelFinal2 + #513, #127
  static NivelFinal2 + #514, #127
  static NivelFinal2 + #515, #127
  static NivelFinal2 + #516, #127
  static NivelFinal2 + #517, #127
  static NivelFinal2 + #518, #127
  static NivelFinal2 + #519, #127

  ;Linha 13
  static NivelFinal2 + #520, #127
  static NivelFinal2 + #521, #127
  static NivelFinal2 + #522, #127
  static NivelFinal2 + #523, #127
  static NivelFinal2 + #524, #127
  static NivelFinal2 + #525, #127
  static NivelFinal2 + #526, #127
  static NivelFinal2 + #527, #127
  static NivelFinal2 + #528, #127
  static NivelFinal2 + #529, #127
  static NivelFinal2 + #530, #127
  static NivelFinal2 + #531, #127
  static NivelFinal2 + #532, #127
  static NivelFinal2 + #533, #127
  static NivelFinal2 + #534, #127
  static NivelFinal2 + #535, #127
  static NivelFinal2 + #536, #127
  static NivelFinal2 + #537, #127
  static NivelFinal2 + #538, #127
  static NivelFinal2 + #539, #127
  static NivelFinal2 + #540, #127
  static NivelFinal2 + #541, #127
  static NivelFinal2 + #542, #127
  static NivelFinal2 + #543, #127
  static NivelFinal2 + #544, #127
  static NivelFinal2 + #545, #127
  static NivelFinal2 + #546, #127
  static NivelFinal2 + #547, #127
  static NivelFinal2 + #548, #127
  static NivelFinal2 + #549, #127
  static NivelFinal2 + #550, #127
  static NivelFinal2 + #551, #127
  static NivelFinal2 + #552, #127
  static NivelFinal2 + #553, #127
  static NivelFinal2 + #554, #127
  static NivelFinal2 + #555, #127
  static NivelFinal2 + #556, #127
  static NivelFinal2 + #557, #127
  static NivelFinal2 + #558, #127
  static NivelFinal2 + #559, #127

  ;Linha 14
  static NivelFinal2 + #560, #127
  static NivelFinal2 + #561, #127
  static NivelFinal2 + #562, #127
  static NivelFinal2 + #563, #127
  static NivelFinal2 + #564, #127
  static NivelFinal2 + #565, #127
  static NivelFinal2 + #566, #127
  static NivelFinal2 + #567, #127
  static NivelFinal2 + #568, #127
  static NivelFinal2 + #569, #127
  static NivelFinal2 + #570, #127
  static NivelFinal2 + #571, #127
  static NivelFinal2 + #572, #127
  static NivelFinal2 + #573, #127
  static NivelFinal2 + #574, #127
  static NivelFinal2 + #575, #127
  static NivelFinal2 + #576, #127
  static NivelFinal2 + #577, #127
  static NivelFinal2 + #578, #127
  static NivelFinal2 + #579, #127
  static NivelFinal2 + #580, #127
  static NivelFinal2 + #581, #127
  static NivelFinal2 + #582, #127
  static NivelFinal2 + #583, #127
  static NivelFinal2 + #584, #127
  static NivelFinal2 + #585, #127
  static NivelFinal2 + #586, #127
  static NivelFinal2 + #587, #127
  static NivelFinal2 + #588, #127
  static NivelFinal2 + #589, #127
  static NivelFinal2 + #590, #127
  static NivelFinal2 + #591, #127
  static NivelFinal2 + #592, #127
  static NivelFinal2 + #593, #127
  static NivelFinal2 + #594, #127
  static NivelFinal2 + #595, #127
  static NivelFinal2 + #596, #127
  static NivelFinal2 + #597, #127
  static NivelFinal2 + #598, #127
  static NivelFinal2 + #599, #127

  ;Linha 15
  static NivelFinal2 + #600, #127
  static NivelFinal2 + #601, #127
  static NivelFinal2 + #602, #127
  static NivelFinal2 + #603, #127
  static NivelFinal2 + #604, #127
  static NivelFinal2 + #605, #127
  static NivelFinal2 + #606, #127
  static NivelFinal2 + #607, #127
  static NivelFinal2 + #608, #127
  static NivelFinal2 + #609, #127
  static NivelFinal2 + #610, #127
  static NivelFinal2 + #611, #127
  static NivelFinal2 + #612, #127
  static NivelFinal2 + #613, #127
  static NivelFinal2 + #614, #127
  static NivelFinal2 + #615, #127
  static NivelFinal2 + #616, #127
  static NivelFinal2 + #617, #127
  static NivelFinal2 + #618, #127
  static NivelFinal2 + #619, #127
  static NivelFinal2 + #620, #127
  static NivelFinal2 + #621, #127
  static NivelFinal2 + #622, #127
  static NivelFinal2 + #623, #127
  static NivelFinal2 + #624, #127
  static NivelFinal2 + #625, #127
  static NivelFinal2 + #626, #127
  static NivelFinal2 + #627, #127
  static NivelFinal2 + #628, #127
  static NivelFinal2 + #629, #127
  static NivelFinal2 + #630, #127
  static NivelFinal2 + #631, #127
  static NivelFinal2 + #632, #127
  static NivelFinal2 + #633, #127
  static NivelFinal2 + #634, #127
  static NivelFinal2 + #635, #127
  static NivelFinal2 + #636, #127
  static NivelFinal2 + #637, #127
  static NivelFinal2 + #638, #127
  static NivelFinal2 + #639, #127

  ;Linha 16
  static NivelFinal2 + #640, #127
  static NivelFinal2 + #641, #127
  static NivelFinal2 + #642, #127
  static NivelFinal2 + #643, #127
  static NivelFinal2 + #644, #127
  static NivelFinal2 + #645, #127
  static NivelFinal2 + #646, #127
  static NivelFinal2 + #647, #127
  static NivelFinal2 + #648, #127
  static NivelFinal2 + #649, #127
  static NivelFinal2 + #650, #127
  static NivelFinal2 + #651, #127
  static NivelFinal2 + #652, #127
  static NivelFinal2 + #653, #127
  static NivelFinal2 + #654, #127
  static NivelFinal2 + #655, #127
  static NivelFinal2 + #656, #127
  static NivelFinal2 + #657, #127
  static NivelFinal2 + #658, #3967
  static NivelFinal2 + #659, #3967
  static NivelFinal2 + #660, #3967
  static NivelFinal2 + #661, #127
  static NivelFinal2 + #662, #127
  static NivelFinal2 + #663, #127
  static NivelFinal2 + #664, #127
  static NivelFinal2 + #665, #127
  static NivelFinal2 + #666, #127
  static NivelFinal2 + #667, #127
  static NivelFinal2 + #668, #127
  static NivelFinal2 + #669, #127
  static NivelFinal2 + #670, #127
  static NivelFinal2 + #671, #127
  static NivelFinal2 + #672, #127
  static NivelFinal2 + #673, #127
  static NivelFinal2 + #674, #127
  static NivelFinal2 + #675, #127
  static NivelFinal2 + #676, #127
  static NivelFinal2 + #677, #127
  static NivelFinal2 + #678, #127
  static NivelFinal2 + #679, #127

  ;Linha 17
  static NivelFinal2 + #680, #127
  static NivelFinal2 + #681, #127
  static NivelFinal2 + #682, #127
  static NivelFinal2 + #683, #127
  static NivelFinal2 + #684, #127
  static NivelFinal2 + #685, #127
  static NivelFinal2 + #686, #127
  static NivelFinal2 + #687, #127
  static NivelFinal2 + #688, #127
  static NivelFinal2 + #689, #127
  static NivelFinal2 + #690, #127
  static NivelFinal2 + #691, #127
  static NivelFinal2 + #692, #127
  static NivelFinal2 + #693, #127
  static NivelFinal2 + #694, #127
  static NivelFinal2 + #695, #127
  static NivelFinal2 + #696, #127
  static NivelFinal2 + #697, #127
  static NivelFinal2 + #698, #3967
  static NivelFinal2 + #699, #3967
  static NivelFinal2 + #700, #3967
  static NivelFinal2 + #701, #3967
  static NivelFinal2 + #702, #127
  static NivelFinal2 + #703, #127
  static NivelFinal2 + #704, #127
  static NivelFinal2 + #705, #127
  static NivelFinal2 + #706, #127
  static NivelFinal2 + #707, #127
  static NivelFinal2 + #708, #3967
  static NivelFinal2 + #709, #3967
  static NivelFinal2 + #710, #3967
  static NivelFinal2 + #711, #127
  static NivelFinal2 + #712, #127
  static NivelFinal2 + #713, #127
  static NivelFinal2 + #714, #127
  static NivelFinal2 + #715, #127
  static NivelFinal2 + #716, #127
  static NivelFinal2 + #717, #127
  static NivelFinal2 + #718, #127
  static NivelFinal2 + #719, #127

  ;Linha 18
  static NivelFinal2 + #720, #127
  static NivelFinal2 + #721, #127
  static NivelFinal2 + #722, #127
  static NivelFinal2 + #723, #127
  static NivelFinal2 + #724, #127
  static NivelFinal2 + #725, #127
  static NivelFinal2 + #726, #3967
  static NivelFinal2 + #727, #127
  static NivelFinal2 + #728, #127
  static NivelFinal2 + #729, #127
  static NivelFinal2 + #730, #127
  static NivelFinal2 + #731, #127
  static NivelFinal2 + #732, #127
  static NivelFinal2 + #733, #127
  static NivelFinal2 + #734, #127
  static NivelFinal2 + #735, #127
  static NivelFinal2 + #736, #4
  static NivelFinal2 + #737, #4
  static NivelFinal2 + #738, #3967
  static NivelFinal2 + #739, #127
  static NivelFinal2 + #740, #127
  static NivelFinal2 + #741, #127
  static NivelFinal2 + #742, #127
  static NivelFinal2 + #743, #127
  static NivelFinal2 + #744, #127
  static NivelFinal2 + #745, #3967
  static NivelFinal2 + #746, #3967
  static NivelFinal2 + #747, #3967
  static NivelFinal2 + #748, #127
  static NivelFinal2 + #749, #3967
  static NivelFinal2 + #750, #3967
  static NivelFinal2 + #751, #127
  static NivelFinal2 + #752, #127
  static NivelFinal2 + #753, #127
  static NivelFinal2 + #754, #127
  static NivelFinal2 + #755, #127
  static NivelFinal2 + #756, #127
  static NivelFinal2 + #757, #127
  static NivelFinal2 + #758, #127
  static NivelFinal2 + #759, #127

  ;Linha 19
  static NivelFinal2 + #760, #127
  static NivelFinal2 + #761, #127
  static NivelFinal2 + #762, #127
  static NivelFinal2 + #763, #127
  static NivelFinal2 + #764, #127
  static NivelFinal2 + #765, #3967
  static NivelFinal2 + #766, #3967
  static NivelFinal2 + #767, #3967
  static NivelFinal2 + #768, #127
  static NivelFinal2 + #769, #127
  static NivelFinal2 + #770, #3967
  static NivelFinal2 + #771, #127
  static NivelFinal2 + #772, #127
  static NivelFinal2 + #773, #127
  static NivelFinal2 + #774, #127
  static NivelFinal2 + #775, #3967
  static NivelFinal2 + #776, #1795
  static NivelFinal2 + #777, #1797
  static NivelFinal2 + #778, #3967
  static NivelFinal2 + #779, #3967
  static NivelFinal2 + #780, #3967
  static NivelFinal2 + #781, #3967
  static NivelFinal2 + #782, #3967
  static NivelFinal2 + #783, #3967
  static NivelFinal2 + #784, #3967
  static NivelFinal2 + #785, #3967
  static NivelFinal2 + #786, #3967
  static NivelFinal2 + #787, #3967
  static NivelFinal2 + #788, #127
  static NivelFinal2 + #789, #3967
  static NivelFinal2 + #790, #3967
  static NivelFinal2 + #791, #127
  static NivelFinal2 + #792, #127
  static NivelFinal2 + #793, #127
  static NivelFinal2 + #794, #127
  static NivelFinal2 + #795, #127
  static NivelFinal2 + #796, #127
  static NivelFinal2 + #797, #127
  static NivelFinal2 + #798, #127
  static NivelFinal2 + #799, #127

  ;Linha 20
  static NivelFinal2 + #800, #127
  static NivelFinal2 + #801, #127
  static NivelFinal2 + #802, #127
  static NivelFinal2 + #803, #127
  static NivelFinal2 + #804, #3967
  static NivelFinal2 + #805, #127
  static NivelFinal2 + #806, #3967
  static NivelFinal2 + #807, #3967
  static NivelFinal2 + #808, #3967
  static NivelFinal2 + #809, #3967
  static NivelFinal2 + #810, #2062
  static NivelFinal2 + #811, #2062
  static NivelFinal2 + #812, #3967
  static NivelFinal2 + #813, #3967
  static NivelFinal2 + #814, #3967
  static NivelFinal2 + #815, #3967
  static NivelFinal2 + #816, #1795
  static NivelFinal2 + #817, #1797
  static NivelFinal2 + #818, #3967
  static NivelFinal2 + #819, #127
  static NivelFinal2 + #820, #127
  static NivelFinal2 + #821, #127
  static NivelFinal2 + #822, #127
  static NivelFinal2 + #823, #127
  static NivelFinal2 + #824, #3967
  static NivelFinal2 + #825, #3967
  static NivelFinal2 + #826, #3967
  static NivelFinal2 + #827, #3967
  static NivelFinal2 + #828, #127
  static NivelFinal2 + #829, #127
  static NivelFinal2 + #830, #3967
  static NivelFinal2 + #831, #127
  static NivelFinal2 + #832, #127
  static NivelFinal2 + #833, #127
  static NivelFinal2 + #834, #127
  static NivelFinal2 + #835, #127
  static NivelFinal2 + #836, #127
  static NivelFinal2 + #837, #127
  static NivelFinal2 + #838, #127
  static NivelFinal2 + #839, #127

  ;Linha 21
  static NivelFinal2 + #840, #127
  static NivelFinal2 + #841, #127
  static NivelFinal2 + #842, #127
  static NivelFinal2 + #843, #3967
  static NivelFinal2 + #844, #3967
  static NivelFinal2 + #845, #127
  static NivelFinal2 + #846, #127
  static NivelFinal2 + #847, #3967
  static NivelFinal2 + #848, #3967
  static NivelFinal2 + #849, #127
  static NivelFinal2 + #850, #3967
  static NivelFinal2 + #851, #3967
  static NivelFinal2 + #852, #3967
  static NivelFinal2 + #853, #3967
  static NivelFinal2 + #854, #127
  static NivelFinal2 + #855, #127
  static NivelFinal2 + #856, #1795
  static NivelFinal2 + #857, #1797
  static NivelFinal2 + #858, #3967
  static NivelFinal2 + #859, #127
  static NivelFinal2 + #860, #127
  static NivelFinal2 + #861, #127
  static NivelFinal2 + #862, #3967
  static NivelFinal2 + #863, #3967
  static NivelFinal2 + #864, #3967
  static NivelFinal2 + #865, #3967
  static NivelFinal2 + #866, #4
  static NivelFinal2 + #867, #4
  static NivelFinal2 + #868, #127
  static NivelFinal2 + #869, #127
  static NivelFinal2 + #870, #3967
  static NivelFinal2 + #871, #3967
  static NivelFinal2 + #872, #127
  static NivelFinal2 + #873, #127
  static NivelFinal2 + #874, #127
  static NivelFinal2 + #875, #127
  static NivelFinal2 + #876, #3967
  static NivelFinal2 + #877, #3967
  static NivelFinal2 + #878, #3967
  static NivelFinal2 + #879, #127

  ;Linha 22
  static NivelFinal2 + #880, #127
  static NivelFinal2 + #881, #127
  static NivelFinal2 + #882, #127
  static NivelFinal2 + #883, #3967
  static NivelFinal2 + #884, #127
  static NivelFinal2 + #885, #127
  static NivelFinal2 + #886, #127
  static NivelFinal2 + #887, #127
  static NivelFinal2 + #888, #127
  static NivelFinal2 + #889, #3967
  static NivelFinal2 + #890, #3967
  static NivelFinal2 + #891, #127
  static NivelFinal2 + #892, #127
  static NivelFinal2 + #893, #127
  static NivelFinal2 + #894, #127
  static NivelFinal2 + #895, #127
  static NivelFinal2 + #896, #1795
  static NivelFinal2 + #897, #1797
  static NivelFinal2 + #898, #127
  static NivelFinal2 + #899, #127
  static NivelFinal2 + #900, #127
  static NivelFinal2 + #901, #3967
  static NivelFinal2 + #902, #127
  static NivelFinal2 + #903, #127
  static NivelFinal2 + #904, #127
  static NivelFinal2 + #905, #127
  static NivelFinal2 + #906, #1795
  static NivelFinal2 + #907, #1797
  static NivelFinal2 + #908, #127
  static NivelFinal2 + #909, #127
  static NivelFinal2 + #910, #3967
  static NivelFinal2 + #911, #3967
  static NivelFinal2 + #912, #127
  static NivelFinal2 + #913, #127
  static NivelFinal2 + #914, #127
  static NivelFinal2 + #915, #127
  static NivelFinal2 + #916, #3967
  static NivelFinal2 + #917, #3967
  static NivelFinal2 + #918, #3967
  static NivelFinal2 + #919, #3967

  ;Linha 23
  static NivelFinal2 + #920, #127
  static NivelFinal2 + #921, #127
  static NivelFinal2 + #922, #127
  static NivelFinal2 + #923, #3967
  static NivelFinal2 + #924, #127
  static NivelFinal2 + #925, #4
  static NivelFinal2 + #926, #4
  static NivelFinal2 + #927, #127
  static NivelFinal2 + #928, #3967
  static NivelFinal2 + #929, #3967
  static NivelFinal2 + #930, #3967
  static NivelFinal2 + #931, #3967
  static NivelFinal2 + #932, #127
  static NivelFinal2 + #933, #127
  static NivelFinal2 + #934, #127
  static NivelFinal2 + #935, #127
  static NivelFinal2 + #936, #1795
  static NivelFinal2 + #937, #1797
  static NivelFinal2 + #938, #127
  static NivelFinal2 + #939, #127
  static NivelFinal2 + #940, #3967
  static NivelFinal2 + #941, #127
  static NivelFinal2 + #942, #3967
  static NivelFinal2 + #943, #127
  static NivelFinal2 + #944, #127
  static NivelFinal2 + #945, #127
  static NivelFinal2 + #946, #1795
  static NivelFinal2 + #947, #1797
  static NivelFinal2 + #948, #127
  static NivelFinal2 + #949, #127
  static NivelFinal2 + #950, #3967
  static NivelFinal2 + #951, #3967
  static NivelFinal2 + #952, #3967
  static NivelFinal2 + #953, #127
  static NivelFinal2 + #954, #127
  static NivelFinal2 + #955, #127
  static NivelFinal2 + #956, #3967
  static NivelFinal2 + #957, #3967
  static NivelFinal2 + #958, #3967
  static NivelFinal2 + #959, #3967

  ;Linha 24
  static NivelFinal2 + #960, #127
  static NivelFinal2 + #961, #127
  static NivelFinal2 + #962, #127
  static NivelFinal2 + #963, #3967
  static NivelFinal2 + #964, #3967
  static NivelFinal2 + #965, #1795
  static NivelFinal2 + #966, #1797
  static NivelFinal2 + #967, #3967
  static NivelFinal2 + #968, #3967
  static NivelFinal2 + #969, #3967
  static NivelFinal2 + #970, #3967
  static NivelFinal2 + #971, #3967
  static NivelFinal2 + #972, #3967
  static NivelFinal2 + #973, #3967
  static NivelFinal2 + #974, #3967
  static NivelFinal2 + #975, #3967
  static NivelFinal2 + #976, #1795
  static NivelFinal2 + #977, #1797
  static NivelFinal2 + #978, #3967
  static NivelFinal2 + #979, #3967
  static NivelFinal2 + #980, #3967
  static NivelFinal2 + #981, #3967
  static NivelFinal2 + #982, #3967
  static NivelFinal2 + #983, #3967
  static NivelFinal2 + #984, #3967
  static NivelFinal2 + #985, #3967
  static NivelFinal2 + #986, #1795
  static NivelFinal2 + #987, #1797
  static NivelFinal2 + #988, #3967
  static NivelFinal2 + #989, #3967
  static NivelFinal2 + #990, #3967
  static NivelFinal2 + #991, #3967
  static NivelFinal2 + #992, #3967
  static NivelFinal2 + #993, #127
  static NivelFinal2 + #994, #127
  static NivelFinal2 + #995, #127
  static NivelFinal2 + #996, #3967
  static NivelFinal2 + #997, #3967
  static NivelFinal2 + #998, #3967
  static NivelFinal2 + #999, #3967

  ;Linha 25
  static NivelFinal2 + #1000, #2062
  static NivelFinal2 + #1001, #2062
  static NivelFinal2 + #1002, #2062
  static NivelFinal2 + #1003, #2062
  static NivelFinal2 + #1004, #2062
  static NivelFinal2 + #1005, #1795
  static NivelFinal2 + #1006, #1797
  static NivelFinal2 + #1007, #2062
  static NivelFinal2 + #1008, #2062
  static NivelFinal2 + #1009, #2062
  static NivelFinal2 + #1010, #2062
  static NivelFinal2 + #1011, #2062
  static NivelFinal2 + #1012, #2062
  static NivelFinal2 + #1013, #2062
  static NivelFinal2 + #1014, #2062
  static NivelFinal2 + #1015, #2062
  static NivelFinal2 + #1016, #1795
  static NivelFinal2 + #1017, #1797
  static NivelFinal2 + #1018, #3967
  static NivelFinal2 + #1019, #3967
  static NivelFinal2 + #1020, #3967
  static NivelFinal2 + #1021, #3967
  static NivelFinal2 + #1022, #3967
  static NivelFinal2 + #1023, #3967
  static NivelFinal2 + #1024, #3967
  static NivelFinal2 + #1025, #3967
  static NivelFinal2 + #1026, #1795
  static NivelFinal2 + #1027, #1797
  static NivelFinal2 + #1028, #2062
  static NivelFinal2 + #1029, #2062
  static NivelFinal2 + #1030, #2062
  static NivelFinal2 + #1031, #2062
  static NivelFinal2 + #1032, #2062
  static NivelFinal2 + #1033, #2062
  static NivelFinal2 + #1034, #2062
  static NivelFinal2 + #1035, #2062
  static NivelFinal2 + #1036, #2062
  static NivelFinal2 + #1037, #2062
  static NivelFinal2 + #1038, #2062
  static NivelFinal2 + #1039, #2062

  ;Linha 26
  static NivelFinal2 + #1040, #2062
  static NivelFinal2 + #1041, #2062
  static NivelFinal2 + #1042, #2062
  static NivelFinal2 + #1043, #2062
  static NivelFinal2 + #1044, #2062
  static NivelFinal2 + #1045, #1795
  static NivelFinal2 + #1046, #1797
  static NivelFinal2 + #1047, #2062
  static NivelFinal2 + #1048, #2062
  static NivelFinal2 + #1049, #2062
  static NivelFinal2 + #1050, #2062
  static NivelFinal2 + #1051, #2062
  static NivelFinal2 + #1052, #2062
  static NivelFinal2 + #1053, #2062
  static NivelFinal2 + #1054, #2062
  static NivelFinal2 + #1055, #2062
  static NivelFinal2 + #1056, #1795
  static NivelFinal2 + #1057, #1797
  static NivelFinal2 + #1058, #3967
  static NivelFinal2 + #1059, #3967
  static NivelFinal2 + #1060, #3967
  static NivelFinal2 + #1061, #3967
  static NivelFinal2 + #1062, #3967
  static NivelFinal2 + #1063, #3967
  static NivelFinal2 + #1064, #3967
  static NivelFinal2 + #1065, #3967
  static NivelFinal2 + #1066, #1795
  static NivelFinal2 + #1067, #1797
  static NivelFinal2 + #1068, #2062
  static NivelFinal2 + #1069, #2062
  static NivelFinal2 + #1070, #2062
  static NivelFinal2 + #1071, #2062
  static NivelFinal2 + #1072, #2062
  static NivelFinal2 + #1073, #2062
  static NivelFinal2 + #1074, #2062
  static NivelFinal2 + #1075, #2062
  static NivelFinal2 + #1076, #2062
  static NivelFinal2 + #1077, #2062
  static NivelFinal2 + #1078, #2062
  static NivelFinal2 + #1079, #2062

  ;Linha 27
  static NivelFinal2 + #1080, #2062
  static NivelFinal2 + #1081, #2062
  static NivelFinal2 + #1082, #2062
  static NivelFinal2 + #1083, #2062
  static NivelFinal2 + #1084, #2062
  static NivelFinal2 + #1085, #1795
  static NivelFinal2 + #1086, #1797
  static NivelFinal2 + #1087, #2062
  static NivelFinal2 + #1088, #2062
  static NivelFinal2 + #1089, #2062
  static NivelFinal2 + #1090, #2062
  static NivelFinal2 + #1091, #2062
  static NivelFinal2 + #1092, #2062
  static NivelFinal2 + #1093, #2062
  static NivelFinal2 + #1094, #2062
  static NivelFinal2 + #1095, #2062
  static NivelFinal2 + #1096, #1795
  static NivelFinal2 + #1097, #1797
  static NivelFinal2 + #1098, #3967
  static NivelFinal2 + #1099, #3967
  static NivelFinal2 + #1100, #3967
  static NivelFinal2 + #1101, #3967
  static NivelFinal2 + #1102, #3967
  static NivelFinal2 + #1103, #3967
  static NivelFinal2 + #1104, #3967
  static NivelFinal2 + #1105, #3967
  static NivelFinal2 + #1106, #1795
  static NivelFinal2 + #1107, #1797
  static NivelFinal2 + #1108, #2062
  static NivelFinal2 + #1109, #2062
  static NivelFinal2 + #1110, #2062
  static NivelFinal2 + #1111, #2062
  static NivelFinal2 + #1112, #2062
  static NivelFinal2 + #1113, #2062
  static NivelFinal2 + #1114, #2062
  static NivelFinal2 + #1115, #2062
  static NivelFinal2 + #1116, #2062
  static NivelFinal2 + #1117, #2062
  static NivelFinal2 + #1118, #2062
  static NivelFinal2 + #1119, #2062

  ;Linha 28
  static NivelFinal2 + #1120, #2062
  static NivelFinal2 + #1121, #2062
  static NivelFinal2 + #1122, #2062
  static NivelFinal2 + #1123, #2062
  static NivelFinal2 + #1124, #2062
  static NivelFinal2 + #1125, #1795
  static NivelFinal2 + #1126, #1797
  static NivelFinal2 + #1127, #2062
  static NivelFinal2 + #1128, #2062
  static NivelFinal2 + #1129, #2062
  static NivelFinal2 + #1130, #2062
  static NivelFinal2 + #1131, #2062
  static NivelFinal2 + #1132, #2062
  static NivelFinal2 + #1133, #2062
  static NivelFinal2 + #1134, #2062
  static NivelFinal2 + #1135, #2062
  static NivelFinal2 + #1136, #1795
  static NivelFinal2 + #1137, #1797
  static NivelFinal2 + #1138, #2320
  static NivelFinal2 + #1139, #2320
  static NivelFinal2 + #1140, #2320
  static NivelFinal2 + #1141, #2320
  static NivelFinal2 + #1142, #2320
  static NivelFinal2 + #1143, #2320
  static NivelFinal2 + #1144, #2320
  static NivelFinal2 + #1145, #2320
  static NivelFinal2 + #1146, #1795
  static NivelFinal2 + #1147, #1797
  static NivelFinal2 + #1148, #2062
  static NivelFinal2 + #1149, #2062
  static NivelFinal2 + #1150, #2062
  static NivelFinal2 + #1151, #2062
  static NivelFinal2 + #1152, #2062
  static NivelFinal2 + #1153, #2062
  static NivelFinal2 + #1154, #2062
  static NivelFinal2 + #1155, #2062
  static NivelFinal2 + #1156, #2062
  static NivelFinal2 + #1157, #2062
  static NivelFinal2 + #1158, #2062
  static NivelFinal2 + #1159, #2062

  ;Linha 29
  static NivelFinal2 + #1160, #2062
  static NivelFinal2 + #1161, #2062
  static NivelFinal2 + #1162, #2062
  static NivelFinal2 + #1163, #2062
  static NivelFinal2 + #1164, #2062
  static NivelFinal2 + #1165, #1795
  static NivelFinal2 + #1166, #1797
  static NivelFinal2 + #1167, #2062
  static NivelFinal2 + #1168, #2062
  static NivelFinal2 + #1169, #2062
  static NivelFinal2 + #1170, #2062
  static NivelFinal2 + #1171, #2062
  static NivelFinal2 + #1172, #2062
  static NivelFinal2 + #1173, #2062
  static NivelFinal2 + #1174, #2062
  static NivelFinal2 + #1175, #2062
  static NivelFinal2 + #1176, #1795
  static NivelFinal2 + #1177, #1797
  static NivelFinal2 + #1178, #2319
  static NivelFinal2 + #1179, #2319
  static NivelFinal2 + #1180, #2319
  static NivelFinal2 + #1181, #2319
  static NivelFinal2 + #1182, #2319
  static NivelFinal2 + #1183, #2319
  static NivelFinal2 + #1184, #2319
  static NivelFinal2 + #1185, #2319
  static NivelFinal2 + #1186, #1795
  static NivelFinal2 + #1187, #1797
  static NivelFinal2 + #1188, #2062
  static NivelFinal2 + #1189, #2062
  static NivelFinal2 + #1190, #2062
  static NivelFinal2 + #1191, #2062
  static NivelFinal2 + #1192, #2062
  static NivelFinal2 + #1193, #2062
  static NivelFinal2 + #1194, #2062
  static NivelFinal2 + #1195, #2062
  static NivelFinal2 + #1196, #2062
  static NivelFinal2 + #1197, #2062
  static NivelFinal2 + #1198, #2062
  static NivelFinal2 + #1199, #2062

printNivelFinal2Screen:
  push R0
  push R1
  push R2
  push R3

  loadn R0, #NivelFinal2
  loadn R1, #0
  loadn R2, #1200

  printNivelFinal2ScreenLoop:

    add R3,R0,R1
    loadi R3, R3
    outchar R3, R1
    inc R1
    cmp R1, R2

    jne printNivelFinal2ScreenLoop

  pop R3
  pop R2
  pop R1
  pop R0
  rts

NivelFinal3 : var #1200
  ;Linha 0
  static NivelFinal3 + #0, #3967
  static NivelFinal3 + #1, #3967
  static NivelFinal3 + #2, #3967
  static NivelFinal3 + #3, #3967
  static NivelFinal3 + #4, #3967
  static NivelFinal3 + #5, #3967
  static NivelFinal3 + #6, #3967
  static NivelFinal3 + #7, #3967
  static NivelFinal3 + #8, #3967
  static NivelFinal3 + #9, #3967
  static NivelFinal3 + #10, #3967
  static NivelFinal3 + #11, #3967
  static NivelFinal3 + #12, #3967
  static NivelFinal3 + #13, #3967
  static NivelFinal3 + #14, #3967
  static NivelFinal3 + #15, #3967
  static NivelFinal3 + #16, #3967
  static NivelFinal3 + #17, #3967
  static NivelFinal3 + #18, #3967
  static NivelFinal3 + #19, #3967
  static NivelFinal3 + #20, #3967
  static NivelFinal3 + #21, #3967
  static NivelFinal3 + #22, #3967
  static NivelFinal3 + #23, #3967
  static NivelFinal3 + #24, #3967
  static NivelFinal3 + #25, #3967
  static NivelFinal3 + #26, #3967
  static NivelFinal3 + #27, #3967
  static NivelFinal3 + #28, #3967
  static NivelFinal3 + #29, #3967
  static NivelFinal3 + #30, #3967
  static NivelFinal3 + #31, #3967
  static NivelFinal3 + #32, #3967
  static NivelFinal3 + #33, #3967
  static NivelFinal3 + #34, #3967
  static NivelFinal3 + #35, #3967
  static NivelFinal3 + #36, #3967
  static NivelFinal3 + #37, #3967
  static NivelFinal3 + #38, #3967
  static NivelFinal3 + #39, #3967

  ;Linha 1
  static NivelFinal3 + #40, #3967
  static NivelFinal3 + #41, #3967
  static NivelFinal3 + #42, #3967
  static NivelFinal3 + #43, #3967
  static NivelFinal3 + #44, #3967
  static NivelFinal3 + #45, #3967
  static NivelFinal3 + #46, #3967
  static NivelFinal3 + #47, #3967
  static NivelFinal3 + #48, #3967
  static NivelFinal3 + #49, #3967
  static NivelFinal3 + #50, #3967
  static NivelFinal3 + #51, #3967
  static NivelFinal3 + #52, #3967
  static NivelFinal3 + #53, #3967
  static NivelFinal3 + #54, #3967
  static NivelFinal3 + #55, #3967
  static NivelFinal3 + #56, #3967
  static NivelFinal3 + #57, #3967
  static NivelFinal3 + #58, #3967
  static NivelFinal3 + #59, #3967
  static NivelFinal3 + #60, #3967
  static NivelFinal3 + #61, #3967
  static NivelFinal3 + #62, #3967
  static NivelFinal3 + #63, #3967
  static NivelFinal3 + #64, #3967
  static NivelFinal3 + #65, #3967
  static NivelFinal3 + #66, #3967
  static NivelFinal3 + #67, #3967
  static NivelFinal3 + #68, #3967
  static NivelFinal3 + #69, #3967
  static NivelFinal3 + #70, #3967
  static NivelFinal3 + #71, #3967
  static NivelFinal3 + #72, #3967
  static NivelFinal3 + #73, #3967
  static NivelFinal3 + #74, #3967
  static NivelFinal3 + #75, #3967
  static NivelFinal3 + #76, #3967
  static NivelFinal3 + #77, #3967
  static NivelFinal3 + #78, #3967
  static NivelFinal3 + #79, #3967

  ;Linha 2
  static NivelFinal3 + #80, #3967
  static NivelFinal3 + #81, #3967
  static NivelFinal3 + #82, #3967
  static NivelFinal3 + #83, #3967
  static NivelFinal3 + #84, #3967
  static NivelFinal3 + #85, #3967
  static NivelFinal3 + #86, #3967
  static NivelFinal3 + #87, #3967
  static NivelFinal3 + #88, #3967
  static NivelFinal3 + #89, #3967
  static NivelFinal3 + #90, #3967
  static NivelFinal3 + #91, #3967
  static NivelFinal3 + #92, #3967
  static NivelFinal3 + #93, #3967
  static NivelFinal3 + #94, #3967
  static NivelFinal3 + #95, #3967
  static NivelFinal3 + #96, #3967
  static NivelFinal3 + #97, #3967
  static NivelFinal3 + #98, #3967
  static NivelFinal3 + #99, #3967
  static NivelFinal3 + #100, #3967
  static NivelFinal3 + #101, #3967
  static NivelFinal3 + #102, #3967
  static NivelFinal3 + #103, #3967
  static NivelFinal3 + #104, #3967
  static NivelFinal3 + #105, #3967
  static NivelFinal3 + #106, #3967
  static NivelFinal3 + #107, #3967
  static NivelFinal3 + #108, #3967
  static NivelFinal3 + #109, #3967
  static NivelFinal3 + #110, #3967
  static NivelFinal3 + #111, #3967
  static NivelFinal3 + #112, #3967
  static NivelFinal3 + #113, #3967
  static NivelFinal3 + #114, #3967
  static NivelFinal3 + #115, #3967
  static NivelFinal3 + #116, #3967
  static NivelFinal3 + #117, #3967
  static NivelFinal3 + #118, #3967
  static NivelFinal3 + #119, #3967

  ;Linha 3
  static NivelFinal3 + #120, #127
  static NivelFinal3 + #121, #3967
  static NivelFinal3 + #122, #3967
  static NivelFinal3 + #123, #3967
  static NivelFinal3 + #124, #127
  static NivelFinal3 + #125, #127
  static NivelFinal3 + #126, #127
  static NivelFinal3 + #127, #127
  static NivelFinal3 + #128, #127
  static NivelFinal3 + #129, #127
  static NivelFinal3 + #130, #3967
  static NivelFinal3 + #131, #3967
  static NivelFinal3 + #132, #3967
  static NivelFinal3 + #133, #3967
  static NivelFinal3 + #134, #127
  static NivelFinal3 + #135, #3967
  static NivelFinal3 + #136, #3967
  static NivelFinal3 + #137, #3967
  static NivelFinal3 + #138, #3967
  static NivelFinal3 + #139, #3967
  static NivelFinal3 + #140, #3967
  static NivelFinal3 + #141, #3967
  static NivelFinal3 + #142, #3967
  static NivelFinal3 + #143, #3967
  static NivelFinal3 + #144, #3967
  static NivelFinal3 + #145, #3967
  static NivelFinal3 + #146, #3967
  static NivelFinal3 + #147, #3967
  static NivelFinal3 + #148, #3967
  static NivelFinal3 + #149, #3967
  static NivelFinal3 + #150, #3967
  static NivelFinal3 + #151, #3967
  static NivelFinal3 + #152, #3967
  static NivelFinal3 + #153, #3967
  static NivelFinal3 + #154, #3967
  static NivelFinal3 + #155, #3967
  static NivelFinal3 + #156, #3967
  static NivelFinal3 + #157, #3967
  static NivelFinal3 + #158, #3967
  static NivelFinal3 + #159, #3967

  ;Linha 4
  static NivelFinal3 + #160, #127
  static NivelFinal3 + #161, #127
  static NivelFinal3 + #162, #127
  static NivelFinal3 + #163, #127
  static NivelFinal3 + #164, #127
  static NivelFinal3 + #165, #127
  static NivelFinal3 + #166, #127
  static NivelFinal3 + #167, #127
  static NivelFinal3 + #168, #127
  static NivelFinal3 + #169, #127
  static NivelFinal3 + #170, #127
  static NivelFinal3 + #171, #127
  static NivelFinal3 + #172, #127
  static NivelFinal3 + #173, #127
  static NivelFinal3 + #174, #3967
  static NivelFinal3 + #175, #3967
  static NivelFinal3 + #176, #3967
  static NivelFinal3 + #177, #127
  static NivelFinal3 + #178, #3967
  static NivelFinal3 + #179, #3967
  static NivelFinal3 + #180, #3967
  static NivelFinal3 + #181, #3967
  static NivelFinal3 + #182, #3967
  static NivelFinal3 + #183, #3967
  static NivelFinal3 + #184, #3967
  static NivelFinal3 + #185, #3967
  static NivelFinal3 + #186, #127
  static NivelFinal3 + #187, #3967
  static NivelFinal3 + #188, #3967
  static NivelFinal3 + #189, #3967
  static NivelFinal3 + #190, #3967
  static NivelFinal3 + #191, #3967
  static NivelFinal3 + #192, #3967
  static NivelFinal3 + #193, #3967
  static NivelFinal3 + #194, #3967
  static NivelFinal3 + #195, #3967
  static NivelFinal3 + #196, #3967
  static NivelFinal3 + #197, #3967
  static NivelFinal3 + #198, #3967
  static NivelFinal3 + #199, #3967

  ;Linha 5
  static NivelFinal3 + #200, #127
  static NivelFinal3 + #201, #127
  static NivelFinal3 + #202, #127
  static NivelFinal3 + #203, #127
  static NivelFinal3 + #204, #127
  static NivelFinal3 + #205, #127
  static NivelFinal3 + #206, #127
  static NivelFinal3 + #207, #127
  static NivelFinal3 + #208, #127
  static NivelFinal3 + #209, #127
  static NivelFinal3 + #210, #127
  static NivelFinal3 + #211, #127
  static NivelFinal3 + #212, #127
  static NivelFinal3 + #213, #127
  static NivelFinal3 + #214, #127
  static NivelFinal3 + #215, #127
  static NivelFinal3 + #216, #127
  static NivelFinal3 + #217, #127
  static NivelFinal3 + #218, #3967
  static NivelFinal3 + #219, #3967
  static NivelFinal3 + #220, #3967
  static NivelFinal3 + #221, #3967
  static NivelFinal3 + #222, #3967
  static NivelFinal3 + #223, #3967
  static NivelFinal3 + #224, #3967
  static NivelFinal3 + #225, #3967
  static NivelFinal3 + #226, #127
  static NivelFinal3 + #227, #127
  static NivelFinal3 + #228, #127
  static NivelFinal3 + #229, #127
  static NivelFinal3 + #230, #127
  static NivelFinal3 + #231, #3967
  static NivelFinal3 + #232, #3967
  static NivelFinal3 + #233, #3967
  static NivelFinal3 + #234, #3967
  static NivelFinal3 + #235, #3967
  static NivelFinal3 + #236, #3967
  static NivelFinal3 + #237, #3967
  static NivelFinal3 + #238, #3967
  static NivelFinal3 + #239, #3967

  ;Linha 6
  static NivelFinal3 + #240, #127
  static NivelFinal3 + #241, #127
  static NivelFinal3 + #242, #127
  static NivelFinal3 + #243, #127
  static NivelFinal3 + #244, #127
  static NivelFinal3 + #245, #127
  static NivelFinal3 + #246, #127
  static NivelFinal3 + #247, #127
  static NivelFinal3 + #248, #127
  static NivelFinal3 + #249, #127
  static NivelFinal3 + #250, #127
  static NivelFinal3 + #251, #127
  static NivelFinal3 + #252, #127
  static NivelFinal3 + #253, #127
  static NivelFinal3 + #254, #127
  static NivelFinal3 + #255, #127
  static NivelFinal3 + #256, #127
  static NivelFinal3 + #257, #127
  static NivelFinal3 + #258, #127
  static NivelFinal3 + #259, #127
  static NivelFinal3 + #260, #127
  static NivelFinal3 + #261, #127
  static NivelFinal3 + #262, #127
  static NivelFinal3 + #263, #127
  static NivelFinal3 + #264, #3967
  static NivelFinal3 + #265, #3967
  static NivelFinal3 + #266, #127
  static NivelFinal3 + #267, #127
  static NivelFinal3 + #268, #127
  static NivelFinal3 + #269, #127
  static NivelFinal3 + #270, #127
  static NivelFinal3 + #271, #127
  static NivelFinal3 + #272, #127
  static NivelFinal3 + #273, #3967
  static NivelFinal3 + #274, #3967
  static NivelFinal3 + #275, #3967
  static NivelFinal3 + #276, #3967
  static NivelFinal3 + #277, #3967
  static NivelFinal3 + #278, #3967
  static NivelFinal3 + #279, #127

  ;Linha 7
  static NivelFinal3 + #280, #127
  static NivelFinal3 + #281, #127
  static NivelFinal3 + #282, #127
  static NivelFinal3 + #283, #127
  static NivelFinal3 + #284, #127
  static NivelFinal3 + #285, #127
  static NivelFinal3 + #286, #127
  static NivelFinal3 + #287, #127
  static NivelFinal3 + #288, #127
  static NivelFinal3 + #289, #127
  static NivelFinal3 + #290, #127
  static NivelFinal3 + #291, #127
  static NivelFinal3 + #292, #127
  static NivelFinal3 + #293, #127
  static NivelFinal3 + #294, #127
  static NivelFinal3 + #295, #127
  static NivelFinal3 + #296, #127
  static NivelFinal3 + #297, #127
  static NivelFinal3 + #298, #127
  static NivelFinal3 + #299, #127
  static NivelFinal3 + #300, #127
  static NivelFinal3 + #301, #127
  static NivelFinal3 + #302, #127
  static NivelFinal3 + #303, #127
  static NivelFinal3 + #304, #127
  static NivelFinal3 + #305, #127
  static NivelFinal3 + #306, #127
  static NivelFinal3 + #307, #127
  static NivelFinal3 + #308, #127
  static NivelFinal3 + #309, #127
  static NivelFinal3 + #310, #127
  static NivelFinal3 + #311, #127
  static NivelFinal3 + #312, #127
  static NivelFinal3 + #313, #127
  static NivelFinal3 + #314, #127
  static NivelFinal3 + #315, #127
  static NivelFinal3 + #316, #3967
  static NivelFinal3 + #317, #3967
  static NivelFinal3 + #318, #3967
  static NivelFinal3 + #319, #3967

  ;Linha 8
  static NivelFinal3 + #320, #127
  static NivelFinal3 + #321, #127
  static NivelFinal3 + #322, #127
  static NivelFinal3 + #323, #127
  static NivelFinal3 + #324, #127
  static NivelFinal3 + #325, #127
  static NivelFinal3 + #326, #127
  static NivelFinal3 + #327, #127
  static NivelFinal3 + #328, #127
  static NivelFinal3 + #329, #127
  static NivelFinal3 + #330, #127
  static NivelFinal3 + #331, #127
  static NivelFinal3 + #332, #127
  static NivelFinal3 + #333, #127
  static NivelFinal3 + #334, #127
  static NivelFinal3 + #335, #127
  static NivelFinal3 + #336, #127
  static NivelFinal3 + #337, #3967
  static NivelFinal3 + #338, #127
  static NivelFinal3 + #339, #127
  static NivelFinal3 + #340, #127
  static NivelFinal3 + #341, #127
  static NivelFinal3 + #342, #127
  static NivelFinal3 + #343, #127
  static NivelFinal3 + #344, #127
  static NivelFinal3 + #345, #127
  static NivelFinal3 + #346, #127
  static NivelFinal3 + #347, #127
  static NivelFinal3 + #348, #127
  static NivelFinal3 + #349, #127
  static NivelFinal3 + #350, #127
  static NivelFinal3 + #351, #127
  static NivelFinal3 + #352, #127
  static NivelFinal3 + #353, #127
  static NivelFinal3 + #354, #127
  static NivelFinal3 + #355, #127
  static NivelFinal3 + #356, #127
  static NivelFinal3 + #357, #127
  static NivelFinal3 + #358, #127
  static NivelFinal3 + #359, #127

  ;Linha 9
  static NivelFinal3 + #360, #127
  static NivelFinal3 + #361, #127
  static NivelFinal3 + #362, #127
  static NivelFinal3 + #363, #127
  static NivelFinal3 + #364, #127
  static NivelFinal3 + #365, #127
  static NivelFinal3 + #366, #127
  static NivelFinal3 + #367, #127
  static NivelFinal3 + #368, #127
  static NivelFinal3 + #369, #127
  static NivelFinal3 + #370, #127
  static NivelFinal3 + #371, #127
  static NivelFinal3 + #372, #127
  static NivelFinal3 + #373, #127
  static NivelFinal3 + #374, #3967
  static NivelFinal3 + #375, #3967
  static NivelFinal3 + #376, #3967
  static NivelFinal3 + #377, #3967
  static NivelFinal3 + #378, #127
  static NivelFinal3 + #379, #127
  static NivelFinal3 + #380, #127
  static NivelFinal3 + #381, #127
  static NivelFinal3 + #382, #127
  static NivelFinal3 + #383, #127
  static NivelFinal3 + #384, #127
  static NivelFinal3 + #385, #127
  static NivelFinal3 + #386, #127
  static NivelFinal3 + #387, #127
  static NivelFinal3 + #388, #127
  static NivelFinal3 + #389, #127
  static NivelFinal3 + #390, #127
  static NivelFinal3 + #391, #127
  static NivelFinal3 + #392, #127
  static NivelFinal3 + #393, #127
  static NivelFinal3 + #394, #127
  static NivelFinal3 + #395, #127
  static NivelFinal3 + #396, #127
  static NivelFinal3 + #397, #127
  static NivelFinal3 + #398, #127
  static NivelFinal3 + #399, #127

  ;Linha 10
  static NivelFinal3 + #400, #2062
  static NivelFinal3 + #401, #2062
  static NivelFinal3 + #402, #2062
  static NivelFinal3 + #403, #2062
  static NivelFinal3 + #404, #2062
  static NivelFinal3 + #405, #2062
  static NivelFinal3 + #406, #2062
  static NivelFinal3 + #407, #2062
  static NivelFinal3 + #408, #2062
  static NivelFinal3 + #409, #2062
  static NivelFinal3 + #410, #2062
  static NivelFinal3 + #411, #2062
  static NivelFinal3 + #412, #2062
  static NivelFinal3 + #413, #2062
  static NivelFinal3 + #414, #2062
  static NivelFinal3 + #415, #2062
  static NivelFinal3 + #416, #2062
  static NivelFinal3 + #417, #2062
  static NivelFinal3 + #418, #2062
  static NivelFinal3 + #419, #2062
  static NivelFinal3 + #420, #2062
  static NivelFinal3 + #421, #2062
  static NivelFinal3 + #422, #2062
  static NivelFinal3 + #423, #2062
  static NivelFinal3 + #424, #2062
  static NivelFinal3 + #425, #2062
  static NivelFinal3 + #426, #2062
  static NivelFinal3 + #427, #2062
  static NivelFinal3 + #428, #2062
  static NivelFinal3 + #429, #2062
  static NivelFinal3 + #430, #2062
  static NivelFinal3 + #431, #2062
  static NivelFinal3 + #432, #2062
  static NivelFinal3 + #433, #2062
  static NivelFinal3 + #434, #2062
  static NivelFinal3 + #435, #2062
  static NivelFinal3 + #436, #2062
  static NivelFinal3 + #437, #2062
  static NivelFinal3 + #438, #2062
  static NivelFinal3 + #439, #2062

  ;Linha 11
  static NivelFinal3 + #440, #2062
  static NivelFinal3 + #441, #2062
  static NivelFinal3 + #442, #2062
  static NivelFinal3 + #443, #2062
  static NivelFinal3 + #444, #2062
  static NivelFinal3 + #445, #2062
  static NivelFinal3 + #446, #2062
  static NivelFinal3 + #447, #2062
  static NivelFinal3 + #448, #2062
  static NivelFinal3 + #449, #2062
  static NivelFinal3 + #450, #2062
  static NivelFinal3 + #451, #2062
  static NivelFinal3 + #452, #2062
  static NivelFinal3 + #453, #2062
  static NivelFinal3 + #454, #2062
  static NivelFinal3 + #455, #2062
  static NivelFinal3 + #456, #2062
  static NivelFinal3 + #457, #2062
  static NivelFinal3 + #458, #2062
  static NivelFinal3 + #459, #2062
  static NivelFinal3 + #460, #2062
  static NivelFinal3 + #461, #2062
  static NivelFinal3 + #462, #2062
  static NivelFinal3 + #463, #2062
  static NivelFinal3 + #464, #2062
  static NivelFinal3 + #465, #2062
  static NivelFinal3 + #466, #2062
  static NivelFinal3 + #467, #2062
  static NivelFinal3 + #468, #2062
  static NivelFinal3 + #469, #2062
  static NivelFinal3 + #470, #2062
  static NivelFinal3 + #471, #2062
  static NivelFinal3 + #472, #2062
  static NivelFinal3 + #473, #2062
  static NivelFinal3 + #474, #2062
  static NivelFinal3 + #475, #2062
  static NivelFinal3 + #476, #2062
  static NivelFinal3 + #477, #2062
  static NivelFinal3 + #478, #2062
  static NivelFinal3 + #479, #2062

  ;Linha 12
  static NivelFinal3 + #480, #127
  static NivelFinal3 + #481, #127
  static NivelFinal3 + #482, #127
  static NivelFinal3 + #483, #127
  static NivelFinal3 + #484, #127
  static NivelFinal3 + #485, #127
  static NivelFinal3 + #486, #127
  static NivelFinal3 + #487, #127
  static NivelFinal3 + #488, #127
  static NivelFinal3 + #489, #127
  static NivelFinal3 + #490, #127
  static NivelFinal3 + #491, #127
  static NivelFinal3 + #492, #127
  static NivelFinal3 + #493, #127
  static NivelFinal3 + #494, #127
  static NivelFinal3 + #495, #127
  static NivelFinal3 + #496, #127
  static NivelFinal3 + #497, #127
  static NivelFinal3 + #498, #127
  static NivelFinal3 + #499, #2062
  static NivelFinal3 + #500, #2062
  static NivelFinal3 + #501, #2062
  static NivelFinal3 + #502, #3967
  static NivelFinal3 + #503, #3967
  static NivelFinal3 + #504, #127
  static NivelFinal3 + #505, #127
  static NivelFinal3 + #506, #127
  static NivelFinal3 + #507, #127
  static NivelFinal3 + #508, #127
  static NivelFinal3 + #509, #127
  static NivelFinal3 + #510, #127
  static NivelFinal3 + #511, #127
  static NivelFinal3 + #512, #127
  static NivelFinal3 + #513, #127
  static NivelFinal3 + #514, #3967
  static NivelFinal3 + #515, #2062
  static NivelFinal3 + #516, #2062
  static NivelFinal3 + #517, #127
  static NivelFinal3 + #518, #127
  static NivelFinal3 + #519, #127

  ;Linha 13
  static NivelFinal3 + #520, #127
  static NivelFinal3 + #521, #127
  static NivelFinal3 + #522, #127
  static NivelFinal3 + #523, #127
  static NivelFinal3 + #524, #127
  static NivelFinal3 + #525, #127
  static NivelFinal3 + #526, #127
  static NivelFinal3 + #527, #127
  static NivelFinal3 + #528, #127
  static NivelFinal3 + #529, #127
  static NivelFinal3 + #530, #127
  static NivelFinal3 + #531, #127
  static NivelFinal3 + #532, #127
  static NivelFinal3 + #533, #127
  static NivelFinal3 + #534, #127
  static NivelFinal3 + #535, #127
  static NivelFinal3 + #536, #127
  static NivelFinal3 + #537, #127
  static NivelFinal3 + #538, #127
  static NivelFinal3 + #539, #2062
  static NivelFinal3 + #540, #2062
  static NivelFinal3 + #541, #2062
  static NivelFinal3 + #542, #3967
  static NivelFinal3 + #543, #3967
  static NivelFinal3 + #544, #127
  static NivelFinal3 + #545, #127
  static NivelFinal3 + #546, #127
  static NivelFinal3 + #547, #127
  static NivelFinal3 + #548, #127
  static NivelFinal3 + #549, #127
  static NivelFinal3 + #550, #127
  static NivelFinal3 + #551, #127
  static NivelFinal3 + #552, #127
  static NivelFinal3 + #553, #3967
  static NivelFinal3 + #554, #3967
  static NivelFinal3 + #555, #2062
  static NivelFinal3 + #556, #2062
  static NivelFinal3 + #557, #127
  static NivelFinal3 + #558, #127
  static NivelFinal3 + #559, #127

  ;Linha 14
  static NivelFinal3 + #560, #127
  static NivelFinal3 + #561, #127
  static NivelFinal3 + #562, #127
  static NivelFinal3 + #563, #127
  static NivelFinal3 + #564, #127
  static NivelFinal3 + #565, #127
  static NivelFinal3 + #566, #127
  static NivelFinal3 + #567, #127
  static NivelFinal3 + #568, #127
  static NivelFinal3 + #569, #127
  static NivelFinal3 + #570, #127
  static NivelFinal3 + #571, #127
  static NivelFinal3 + #572, #127
  static NivelFinal3 + #573, #127
  static NivelFinal3 + #574, #127
  static NivelFinal3 + #575, #127
  static NivelFinal3 + #576, #127
  static NivelFinal3 + #577, #127
  static NivelFinal3 + #578, #127
  static NivelFinal3 + #579, #2062
  static NivelFinal3 + #580, #2062
  static NivelFinal3 + #581, #2062
  static NivelFinal3 + #582, #3967
  static NivelFinal3 + #583, #3967
  static NivelFinal3 + #584, #127
  static NivelFinal3 + #585, #127
  static NivelFinal3 + #586, #127
  static NivelFinal3 + #587, #127
  static NivelFinal3 + #588, #127
  static NivelFinal3 + #589, #127
  static NivelFinal3 + #590, #127
  static NivelFinal3 + #591, #127
  static NivelFinal3 + #592, #127
  static NivelFinal3 + #593, #127
  static NivelFinal3 + #594, #3967
  static NivelFinal3 + #595, #2062
  static NivelFinal3 + #596, #2062
  static NivelFinal3 + #597, #127
  static NivelFinal3 + #598, #127
  static NivelFinal3 + #599, #127

  ;Linha 15
  static NivelFinal3 + #600, #127
  static NivelFinal3 + #601, #127
  static NivelFinal3 + #602, #127
  static NivelFinal3 + #603, #127
  static NivelFinal3 + #604, #127
  static NivelFinal3 + #605, #127
  static NivelFinal3 + #606, #127
  static NivelFinal3 + #607, #127
  static NivelFinal3 + #608, #127
  static NivelFinal3 + #609, #127
  static NivelFinal3 + #610, #127
  static NivelFinal3 + #611, #127
  static NivelFinal3 + #612, #127
  static NivelFinal3 + #613, #127
  static NivelFinal3 + #614, #127
  static NivelFinal3 + #615, #127
  static NivelFinal3 + #616, #127
  static NivelFinal3 + #617, #127
  static NivelFinal3 + #618, #127
  static NivelFinal3 + #619, #2062
  static NivelFinal3 + #620, #2062
  static NivelFinal3 + #621, #2062
  static NivelFinal3 + #622, #3967
  static NivelFinal3 + #623, #3967
  static NivelFinal3 + #624, #127
  static NivelFinal3 + #625, #127
  static NivelFinal3 + #626, #127
  static NivelFinal3 + #627, #127
  static NivelFinal3 + #628, #127
  static NivelFinal3 + #629, #127
  static NivelFinal3 + #630, #127
  static NivelFinal3 + #631, #127
  static NivelFinal3 + #632, #127
  static NivelFinal3 + #633, #127
  static NivelFinal3 + #634, #3967
  static NivelFinal3 + #635, #2062
  static NivelFinal3 + #636, #2062
  static NivelFinal3 + #637, #127
  static NivelFinal3 + #638, #127
  static NivelFinal3 + #639, #127

  ;Linha 16
  static NivelFinal3 + #640, #127
  static NivelFinal3 + #641, #127
  static NivelFinal3 + #642, #127
  static NivelFinal3 + #643, #127
  static NivelFinal3 + #644, #127
  static NivelFinal3 + #645, #127
  static NivelFinal3 + #646, #127
  static NivelFinal3 + #647, #127
  static NivelFinal3 + #648, #127
  static NivelFinal3 + #649, #127
  static NivelFinal3 + #650, #127
  static NivelFinal3 + #651, #127
  static NivelFinal3 + #652, #127
  static NivelFinal3 + #653, #127
  static NivelFinal3 + #654, #127
  static NivelFinal3 + #655, #127
  static NivelFinal3 + #656, #127
  static NivelFinal3 + #657, #127
  static NivelFinal3 + #658, #3967
  static NivelFinal3 + #659, #3967
  static NivelFinal3 + #660, #3967
  static NivelFinal3 + #661, #127
  static NivelFinal3 + #662, #127
  static NivelFinal3 + #663, #127
  static NivelFinal3 + #664, #127
  static NivelFinal3 + #665, #127
  static NivelFinal3 + #666, #127
  static NivelFinal3 + #667, #127
  static NivelFinal3 + #668, #127
  static NivelFinal3 + #669, #127
  static NivelFinal3 + #670, #127
  static NivelFinal3 + #671, #127
  static NivelFinal3 + #672, #127
  static NivelFinal3 + #673, #127
  static NivelFinal3 + #674, #3967
  static NivelFinal3 + #675, #127
  static NivelFinal3 + #676, #127
  static NivelFinal3 + #677, #127
  static NivelFinal3 + #678, #127
  static NivelFinal3 + #679, #127

  ;Linha 17
  static NivelFinal3 + #680, #127
  static NivelFinal3 + #681, #127
  static NivelFinal3 + #682, #127
  static NivelFinal3 + #683, #3967
  static NivelFinal3 + #684, #3967
  static NivelFinal3 + #685, #3967
  static NivelFinal3 + #686, #127
  static NivelFinal3 + #687, #3967
  static NivelFinal3 + #688, #127
  static NivelFinal3 + #689, #3967
  static NivelFinal3 + #690, #127
  static NivelFinal3 + #691, #3967
  static NivelFinal3 + #692, #127
  static NivelFinal3 + #693, #3967
  static NivelFinal3 + #694, #127
  static NivelFinal3 + #695, #127
  static NivelFinal3 + #696, #127
  static NivelFinal3 + #697, #127
  static NivelFinal3 + #698, #3967
  static NivelFinal3 + #699, #3967
  static NivelFinal3 + #700, #3967
  static NivelFinal3 + #701, #3967
  static NivelFinal3 + #702, #127
  static NivelFinal3 + #703, #127
  static NivelFinal3 + #704, #127
  static NivelFinal3 + #705, #127
  static NivelFinal3 + #706, #127
  static NivelFinal3 + #707, #127
  static NivelFinal3 + #708, #3967
  static NivelFinal3 + #709, #3967
  static NivelFinal3 + #710, #3967
  static NivelFinal3 + #711, #127
  static NivelFinal3 + #712, #127
  static NivelFinal3 + #713, #127
  static NivelFinal3 + #714, #127
  static NivelFinal3 + #715, #127
  static NivelFinal3 + #716, #127
  static NivelFinal3 + #717, #127
  static NivelFinal3 + #718, #127
  static NivelFinal3 + #719, #127

  ;Linha 18
  static NivelFinal3 + #720, #127
  static NivelFinal3 + #721, #127
  static NivelFinal3 + #722, #127
  static NivelFinal3 + #723, #127
  static NivelFinal3 + #724, #127
  static NivelFinal3 + #725, #127
  static NivelFinal3 + #726, #3967
  static NivelFinal3 + #727, #127
  static NivelFinal3 + #728, #127
  static NivelFinal3 + #729, #127
  static NivelFinal3 + #730, #127
  static NivelFinal3 + #731, #127
  static NivelFinal3 + #732, #127
  static NivelFinal3 + #733, #127
  static NivelFinal3 + #734, #127
  static NivelFinal3 + #735, #127
  static NivelFinal3 + #736, #127
  static NivelFinal3 + #737, #127
  static NivelFinal3 + #738, #127
  static NivelFinal3 + #739, #127
  static NivelFinal3 + #740, #127
  static NivelFinal3 + #741, #127
  static NivelFinal3 + #742, #127
  static NivelFinal3 + #743, #127
  static NivelFinal3 + #744, #127
  static NivelFinal3 + #745, #3967
  static NivelFinal3 + #746, #3967
  static NivelFinal3 + #747, #3967
  static NivelFinal3 + #748, #3967
  static NivelFinal3 + #749, #3967
  static NivelFinal3 + #750, #3967
  static NivelFinal3 + #751, #127
  static NivelFinal3 + #752, #127
  static NivelFinal3 + #753, #127
  static NivelFinal3 + #754, #127
  static NivelFinal3 + #755, #127
  static NivelFinal3 + #756, #127
  static NivelFinal3 + #757, #127
  static NivelFinal3 + #758, #127
  static NivelFinal3 + #759, #127

  ;Linha 19
  static NivelFinal3 + #760, #127
  static NivelFinal3 + #761, #127
  static NivelFinal3 + #762, #127
  static NivelFinal3 + #763, #127
  static NivelFinal3 + #764, #127
  static NivelFinal3 + #765, #3967
  static NivelFinal3 + #766, #3967
  static NivelFinal3 + #767, #3967
  static NivelFinal3 + #768, #127
  static NivelFinal3 + #769, #127
  static NivelFinal3 + #770, #3967
  static NivelFinal3 + #771, #127
  static NivelFinal3 + #772, #127
  static NivelFinal3 + #773, #127
  static NivelFinal3 + #774, #127
  static NivelFinal3 + #775, #3967
  static NivelFinal3 + #776, #3967
  static NivelFinal3 + #777, #3967
  static NivelFinal3 + #778, #3967
  static NivelFinal3 + #779, #3967
  static NivelFinal3 + #780, #3967
  static NivelFinal3 + #781, #3967
  static NivelFinal3 + #782, #3967
  static NivelFinal3 + #783, #3967
  static NivelFinal3 + #784, #3967
  static NivelFinal3 + #785, #3967
  static NivelFinal3 + #786, #3967
  static NivelFinal3 + #787, #3967
  static NivelFinal3 + #788, #127
  static NivelFinal3 + #789, #3967
  static NivelFinal3 + #790, #3967
  static NivelFinal3 + #791, #127
  static NivelFinal3 + #792, #127
  static NivelFinal3 + #793, #127
  static NivelFinal3 + #794, #127
  static NivelFinal3 + #795, #127
  static NivelFinal3 + #796, #127
  static NivelFinal3 + #797, #127
  static NivelFinal3 + #798, #127
  static NivelFinal3 + #799, #127

  ;Linha 20
  static NivelFinal3 + #800, #127
  static NivelFinal3 + #801, #127
  static NivelFinal3 + #802, #127
  static NivelFinal3 + #803, #127
  static NivelFinal3 + #804, #3967
  static NivelFinal3 + #805, #127
  static NivelFinal3 + #806, #3967
  static NivelFinal3 + #807, #3967
  static NivelFinal3 + #808, #3967
  static NivelFinal3 + #809, #3967
  static NivelFinal3 + #810, #3967
  static NivelFinal3 + #811, #3967
  static NivelFinal3 + #812, #3967
  static NivelFinal3 + #813, #3967
  static NivelFinal3 + #814, #3967
  static NivelFinal3 + #815, #3967
  static NivelFinal3 + #816, #3967
  static NivelFinal3 + #817, #127
  static NivelFinal3 + #818, #127
  static NivelFinal3 + #819, #127
  static NivelFinal3 + #820, #127
  static NivelFinal3 + #821, #127
  static NivelFinal3 + #822, #127
  static NivelFinal3 + #823, #127
  static NivelFinal3 + #824, #3967
  static NivelFinal3 + #825, #3967
  static NivelFinal3 + #826, #3967
  static NivelFinal3 + #827, #3967
  static NivelFinal3 + #828, #127
  static NivelFinal3 + #829, #127
  static NivelFinal3 + #830, #3967
  static NivelFinal3 + #831, #127
  static NivelFinal3 + #832, #127
  static NivelFinal3 + #833, #127
  static NivelFinal3 + #834, #1555
  static NivelFinal3 + #835, #127
  static NivelFinal3 + #836, #127
  static NivelFinal3 + #837, #127
  static NivelFinal3 + #838, #127
  static NivelFinal3 + #839, #127

  ;Linha 21
  static NivelFinal3 + #840, #127
  static NivelFinal3 + #841, #127
  static NivelFinal3 + #842, #127
  static NivelFinal3 + #843, #3967
  static NivelFinal3 + #844, #3967
  static NivelFinal3 + #845, #127
  static NivelFinal3 + #846, #127
  static NivelFinal3 + #847, #3967
  static NivelFinal3 + #848, #3967
  static NivelFinal3 + #849, #127
  static NivelFinal3 + #850, #3967
  static NivelFinal3 + #851, #3967
  static NivelFinal3 + #852, #3967
  static NivelFinal3 + #853, #3967
  static NivelFinal3 + #854, #127
  static NivelFinal3 + #855, #127
  static NivelFinal3 + #856, #127
  static NivelFinal3 + #857, #127
  static NivelFinal3 + #858, #127
  static NivelFinal3 + #859, #127
  static NivelFinal3 + #860, #127
  static NivelFinal3 + #861, #127
  static NivelFinal3 + #862, #3967
  static NivelFinal3 + #863, #3967
  static NivelFinal3 + #864, #3967
  static NivelFinal3 + #865, #3967
  static NivelFinal3 + #866, #3967
  static NivelFinal3 + #867, #3967
  static NivelFinal3 + #868, #127
  static NivelFinal3 + #869, #127
  static NivelFinal3 + #870, #3967
  static NivelFinal3 + #871, #3967
  static NivelFinal3 + #872, #127
  static NivelFinal3 + #873, #2068
  static NivelFinal3 + #874, #2062
  static NivelFinal3 + #875, #2062
  static NivelFinal3 + #876, #2062
  static NivelFinal3 + #877, #2062
  static NivelFinal3 + #878, #2062
  static NivelFinal3 + #879, #2062

  ;Linha 22
  static NivelFinal3 + #880, #127
  static NivelFinal3 + #881, #127
  static NivelFinal3 + #882, #127
  static NivelFinal3 + #883, #3967
  static NivelFinal3 + #884, #127
  static NivelFinal3 + #885, #127
  static NivelFinal3 + #886, #127
  static NivelFinal3 + #887, #127
  static NivelFinal3 + #888, #127
  static NivelFinal3 + #889, #3967
  static NivelFinal3 + #890, #3967
  static NivelFinal3 + #891, #127
  static NivelFinal3 + #892, #127
  static NivelFinal3 + #893, #127
  static NivelFinal3 + #894, #127
  static NivelFinal3 + #895, #127
  static NivelFinal3 + #896, #3967
  static NivelFinal3 + #897, #127
  static NivelFinal3 + #898, #127
  static NivelFinal3 + #899, #2062
  static NivelFinal3 + #900, #2062
  static NivelFinal3 + #901, #2062
  static NivelFinal3 + #902, #274
  static NivelFinal3 + #903, #274
  static NivelFinal3 + #904, #274
  static NivelFinal3 + #905, #274
  static NivelFinal3 + #906, #274
  static NivelFinal3 + #907, #274
  static NivelFinal3 + #908, #274
  static NivelFinal3 + #909, #274
  static NivelFinal3 + #910, #274
  static NivelFinal3 + #911, #274
  static NivelFinal3 + #912, #274
  static NivelFinal3 + #913, #274
  static NivelFinal3 + #914, #2062
  static NivelFinal3 + #915, #2062
  static NivelFinal3 + #916, #2062
  static NivelFinal3 + #917, #2062
  static NivelFinal3 + #918, #2062
  static NivelFinal3 + #919, #2062

  ;Linha 23
  static NivelFinal3 + #920, #127
  static NivelFinal3 + #921, #127
  static NivelFinal3 + #922, #4
  static NivelFinal3 + #923, #4
  static NivelFinal3 + #924, #3967
  static NivelFinal3 + #925, #127
  static NivelFinal3 + #926, #127
  static NivelFinal3 + #927, #127
  static NivelFinal3 + #928, #3967
  static NivelFinal3 + #929, #3967
  static NivelFinal3 + #930, #3967
  static NivelFinal3 + #931, #3967
  static NivelFinal3 + #932, #127
  static NivelFinal3 + #933, #127
  static NivelFinal3 + #934, #127
  static NivelFinal3 + #935, #127
  static NivelFinal3 + #936, #127
  static NivelFinal3 + #937, #127
  static NivelFinal3 + #938, #127
  static NivelFinal3 + #939, #2062
  static NivelFinal3 + #940, #2062
  static NivelFinal3 + #941, #2062
  static NivelFinal3 + #942, #3967
  static NivelFinal3 + #943, #3967
  static NivelFinal3 + #944, #127
  static NivelFinal3 + #945, #3967
  static NivelFinal3 + #946, #3967
  static NivelFinal3 + #947, #127
  static NivelFinal3 + #948, #127
  static NivelFinal3 + #949, #127
  static NivelFinal3 + #950, #3967
  static NivelFinal3 + #951, #3967
  static NivelFinal3 + #952, #3967
  static NivelFinal3 + #953, #127
  static NivelFinal3 + #954, #2062
  static NivelFinal3 + #955, #2062
  static NivelFinal3 + #956, #2062
  static NivelFinal3 + #957, #2062
  static NivelFinal3 + #958, #2062
  static NivelFinal3 + #959, #2062

  ;Linha 24
  static NivelFinal3 + #960, #127
  static NivelFinal3 + #961, #127
  static NivelFinal3 + #962, #1795
  static NivelFinal3 + #963, #1797
  static NivelFinal3 + #964, #3967
  static NivelFinal3 + #965, #3967
  static NivelFinal3 + #966, #3967
  static NivelFinal3 + #967, #3967
  static NivelFinal3 + #968, #3967
  static NivelFinal3 + #969, #3967
  static NivelFinal3 + #970, #3967
  static NivelFinal3 + #971, #3967
  static NivelFinal3 + #972, #3967
  static NivelFinal3 + #973, #3967
  static NivelFinal3 + #974, #3967
  static NivelFinal3 + #975, #3967
  static NivelFinal3 + #976, #127
  static NivelFinal3 + #977, #3967
  static NivelFinal3 + #978, #3967
  static NivelFinal3 + #979, #2062
  static NivelFinal3 + #980, #2062
  static NivelFinal3 + #981, #2062
  static NivelFinal3 + #982, #3967
  static NivelFinal3 + #983, #3967
  static NivelFinal3 + #984, #3967
  static NivelFinal3 + #985, #3967
  static NivelFinal3 + #986, #127
  static NivelFinal3 + #987, #127
  static NivelFinal3 + #988, #3967
  static NivelFinal3 + #989, #3967
  static NivelFinal3 + #990, #3967
  static NivelFinal3 + #991, #3967
  static NivelFinal3 + #992, #3967
  static NivelFinal3 + #993, #127
  static NivelFinal3 + #994, #2062
  static NivelFinal3 + #995, #2062
  static NivelFinal3 + #996, #2062
  static NivelFinal3 + #997, #2062
  static NivelFinal3 + #998, #2062
  static NivelFinal3 + #999, #2062

  ;Linha 25
  static NivelFinal3 + #1000, #2062
  static NivelFinal3 + #1001, #2062
  static NivelFinal3 + #1002, #1795
  static NivelFinal3 + #1003, #1797
  static NivelFinal3 + #1004, #2062
  static NivelFinal3 + #1005, #2062
  static NivelFinal3 + #1006, #2062
  static NivelFinal3 + #1007, #2062
  static NivelFinal3 + #1008, #2062
  static NivelFinal3 + #1009, #2062
  static NivelFinal3 + #1010, #2062
  static NivelFinal3 + #1011, #2062
  static NivelFinal3 + #1012, #2062
  static NivelFinal3 + #1013, #2062
  static NivelFinal3 + #1014, #2320
  static NivelFinal3 + #1015, #2320
  static NivelFinal3 + #1016, #2320
  static NivelFinal3 + #1017, #2320
  static NivelFinal3 + #1018, #2320
  static NivelFinal3 + #1019, #2062
  static NivelFinal3 + #1020, #2062
  static NivelFinal3 + #1021, #2062
  static NivelFinal3 + #1022, #2320
  static NivelFinal3 + #1023, #2320
  static NivelFinal3 + #1024, #2320
  static NivelFinal3 + #1025, #2320
  static NivelFinal3 + #1026, #2320
  static NivelFinal3 + #1027, #2320
  static NivelFinal3 + #1028, #2320
  static NivelFinal3 + #1029, #2320
  static NivelFinal3 + #1030, #2320
  static NivelFinal3 + #1031, #2320
  static NivelFinal3 + #1032, #2320
  static NivelFinal3 + #1033, #2320
  static NivelFinal3 + #1034, #2062
  static NivelFinal3 + #1035, #2062
  static NivelFinal3 + #1036, #2062
  static NivelFinal3 + #1037, #2062
  static NivelFinal3 + #1038, #2062
  static NivelFinal3 + #1039, #2062

  ;Linha 26
  static NivelFinal3 + #1040, #2062
  static NivelFinal3 + #1041, #2062
  static NivelFinal3 + #1042, #1795
  static NivelFinal3 + #1043, #1797
  static NivelFinal3 + #1044, #2062
  static NivelFinal3 + #1045, #2062
  static NivelFinal3 + #1046, #2062
  static NivelFinal3 + #1047, #2062
  static NivelFinal3 + #1048, #2062
  static NivelFinal3 + #1049, #2062
  static NivelFinal3 + #1050, #2062
  static NivelFinal3 + #1051, #2062
  static NivelFinal3 + #1052, #2062
  static NivelFinal3 + #1053, #2062
  static NivelFinal3 + #1054, #2319
  static NivelFinal3 + #1055, #2319
  static NivelFinal3 + #1056, #2319
  static NivelFinal3 + #1057, #2319
  static NivelFinal3 + #1058, #2319
  static NivelFinal3 + #1059, #2062
  static NivelFinal3 + #1060, #2062
  static NivelFinal3 + #1061, #2062
  static NivelFinal3 + #1062, #2319
  static NivelFinal3 + #1063, #2319
  static NivelFinal3 + #1064, #2319
  static NivelFinal3 + #1065, #2319
  static NivelFinal3 + #1066, #2319
  static NivelFinal3 + #1067, #2319
  static NivelFinal3 + #1068, #2319
  static NivelFinal3 + #1069, #2319
  static NivelFinal3 + #1070, #2319
  static NivelFinal3 + #1071, #2319
  static NivelFinal3 + #1072, #2319
  static NivelFinal3 + #1073, #2319
  static NivelFinal3 + #1074, #2062
  static NivelFinal3 + #1075, #2062
  static NivelFinal3 + #1076, #2062
  static NivelFinal3 + #1077, #2062
  static NivelFinal3 + #1078, #2062
  static NivelFinal3 + #1079, #2062

  ;Linha 27
  static NivelFinal3 + #1080, #2062
  static NivelFinal3 + #1081, #2062
  static NivelFinal3 + #1082, #1795
  static NivelFinal3 + #1083, #1797
  static NivelFinal3 + #1084, #2062
  static NivelFinal3 + #1085, #2062
  static NivelFinal3 + #1086, #2062
  static NivelFinal3 + #1087, #2062
  static NivelFinal3 + #1088, #2062
  static NivelFinal3 + #1089, #2062
  static NivelFinal3 + #1090, #2062
  static NivelFinal3 + #1091, #2062
  static NivelFinal3 + #1092, #2062
  static NivelFinal3 + #1093, #2062
  static NivelFinal3 + #1094, #2319
  static NivelFinal3 + #1095, #2319
  static NivelFinal3 + #1096, #2319
  static NivelFinal3 + #1097, #2319
  static NivelFinal3 + #1098, #2319
  static NivelFinal3 + #1099, #2062
  static NivelFinal3 + #1100, #2062
  static NivelFinal3 + #1101, #2062
  static NivelFinal3 + #1102, #2319
  static NivelFinal3 + #1103, #2319
  static NivelFinal3 + #1104, #2319
  static NivelFinal3 + #1105, #2319
  static NivelFinal3 + #1106, #2319
  static NivelFinal3 + #1107, #2319
  static NivelFinal3 + #1108, #2319
  static NivelFinal3 + #1109, #2319
  static NivelFinal3 + #1110, #2319
  static NivelFinal3 + #1111, #2319
  static NivelFinal3 + #1112, #2319
  static NivelFinal3 + #1113, #2319
  static NivelFinal3 + #1114, #2062
  static NivelFinal3 + #1115, #2062
  static NivelFinal3 + #1116, #2062
  static NivelFinal3 + #1117, #2062
  static NivelFinal3 + #1118, #2062
  static NivelFinal3 + #1119, #2062

  ;Linha 28
  static NivelFinal3 + #1120, #2062
  static NivelFinal3 + #1121, #2062
  static NivelFinal3 + #1122, #1795
  static NivelFinal3 + #1123, #1797
  static NivelFinal3 + #1124, #2062
  static NivelFinal3 + #1125, #2062
  static NivelFinal3 + #1126, #2062
  static NivelFinal3 + #1127, #2062
  static NivelFinal3 + #1128, #2062
  static NivelFinal3 + #1129, #2062
  static NivelFinal3 + #1130, #2062
  static NivelFinal3 + #1131, #2062
  static NivelFinal3 + #1132, #2062
  static NivelFinal3 + #1133, #2062
  static NivelFinal3 + #1134, #2319
  static NivelFinal3 + #1135, #2319
  static NivelFinal3 + #1136, #2319
  static NivelFinal3 + #1137, #2319
  static NivelFinal3 + #1138, #2319
  static NivelFinal3 + #1139, #2062
  static NivelFinal3 + #1140, #2062
  static NivelFinal3 + #1141, #2062
  static NivelFinal3 + #1142, #2319
  static NivelFinal3 + #1143, #2319
  static NivelFinal3 + #1144, #2319
  static NivelFinal3 + #1145, #2319
  static NivelFinal3 + #1146, #2319
  static NivelFinal3 + #1147, #2319
  static NivelFinal3 + #1148, #2319
  static NivelFinal3 + #1149, #2319
  static NivelFinal3 + #1150, #2319
  static NivelFinal3 + #1151, #2319
  static NivelFinal3 + #1152, #2319
  static NivelFinal3 + #1153, #2319
  static NivelFinal3 + #1154, #2062
  static NivelFinal3 + #1155, #2062
  static NivelFinal3 + #1156, #2062
  static NivelFinal3 + #1157, #2062
  static NivelFinal3 + #1158, #2062
  static NivelFinal3 + #1159, #2062

  ;Linha 29
  static NivelFinal3 + #1160, #2062
  static NivelFinal3 + #1161, #2062
  static NivelFinal3 + #1162, #1795
  static NivelFinal3 + #1163, #1797
  static NivelFinal3 + #1164, #2062
  static NivelFinal3 + #1165, #2062
  static NivelFinal3 + #1166, #2062
  static NivelFinal3 + #1167, #2062
  static NivelFinal3 + #1168, #2062
  static NivelFinal3 + #1169, #2062
  static NivelFinal3 + #1170, #2062
  static NivelFinal3 + #1171, #2062
  static NivelFinal3 + #1172, #2062
  static NivelFinal3 + #1173, #2062
  static NivelFinal3 + #1174, #2319
  static NivelFinal3 + #1175, #2319
  static NivelFinal3 + #1176, #2319
  static NivelFinal3 + #1177, #2319
  static NivelFinal3 + #1178, #2319
  static NivelFinal3 + #1179, #2062
  static NivelFinal3 + #1180, #2062
  static NivelFinal3 + #1181, #2062
  static NivelFinal3 + #1182, #2319
  static NivelFinal3 + #1183, #2319
  static NivelFinal3 + #1184, #2319
  static NivelFinal3 + #1185, #2319
  static NivelFinal3 + #1186, #2319
  static NivelFinal3 + #1187, #2319
  static NivelFinal3 + #1188, #2319
  static NivelFinal3 + #1189, #2319
  static NivelFinal3 + #1190, #2319
  static NivelFinal3 + #1191, #2319
  static NivelFinal3 + #1192, #2319
  static NivelFinal3 + #1193, #2319
  static NivelFinal3 + #1194, #2062
  static NivelFinal3 + #1195, #2062
  static NivelFinal3 + #1196, #2062
  static NivelFinal3 + #1197, #2062
  static NivelFinal3 + #1198, #2062
  static NivelFinal3 + #1199, #2062

printNivelFinal3Screen:
  push R0
  push R1
  push R2
  push R3

  loadn R0, #NivelFinal3
  loadn R1, #0
  loadn R2, #1200

  printNivelFinal3ScreenLoop:

    add R3,R0,R1
    loadi R3, R3
    outchar R3, R1
    inc R1
    cmp R1, R2

    jne printNivelFinal3ScreenLoop

  pop R3
  pop R2
  pop R1
  pop R0
  rts
Characters : var #1200
  ;Linha 0
  static Characters + #0, #2327
  static Characters + #1, #3967
  static Characters + #2, #287
  static Characters + #3, #3967
  static Characters + #4, #2590
  static Characters + #5, #3967
  static Characters + #6, #2589
  static Characters + #7, #3967
  static Characters + #8, #2075
  static Characters + #9, #3967
  static Characters + #10, #794
  static Characters + #11, #3967
  static Characters + #12, #3967
  static Characters + #13, #3967
  static Characters + #14, #3967
  static Characters + #15, #3967
  static Characters + #16, #3967
  static Characters + #17, #3967
  static Characters + #18, #3967
  static Characters + #19, #3967
  static Characters + #20, #3967
  static Characters + #21, #3967
  static Characters + #22, #3967
  static Characters + #23, #3967
  static Characters + #24, #3967
  static Characters + #25, #3967
  static Characters + #26, #3967
  static Characters + #27, #3967
  static Characters + #28, #3967
  static Characters + #29, #3967
  static Characters + #30, #3967
  static Characters + #31, #3967
  static Characters + #32, #3967
  static Characters + #33, #3967
  static Characters + #34, #3967
  static Characters + #35, #3967
  static Characters + #36, #3967
  static Characters + #37, #3967
  static Characters + #38, #3967
  static Characters + #39, #3967

  ;Linha 1
  static Characters + #40, #3967
  static Characters + #41, #3967
  static Characters + #42, #3967
  static Characters + #43, #3967
  static Characters + #44, #3967
  static Characters + #45, #3967
  static Characters + #46, #3967
  static Characters + #47, #3967
  static Characters + #48, #3967
  static Characters + #49, #3967
  static Characters + #50, #3967
  static Characters + #51, #3967
  static Characters + #52, #3967
  static Characters + #53, #3967
  static Characters + #54, #3967
  static Characters + #55, #3967
  static Characters + #56, #3967
  static Characters + #57, #3967
  static Characters + #58, #3967
  static Characters + #59, #3967
  static Characters + #60, #3967
  static Characters + #61, #3967
  static Characters + #62, #3967
  static Characters + #63, #3967
  static Characters + #64, #3967
  static Characters + #65, #3967
  static Characters + #66, #3967
  static Characters + #67, #3967
  static Characters + #68, #3967
  static Characters + #69, #3967
  static Characters + #70, #3967
  static Characters + #71, #3967
  static Characters + #72, #3967
  static Characters + #73, #3967
  static Characters + #74, #3967
  static Characters + #75, #3967
  static Characters + #76, #3967
  static Characters + #77, #3967
  static Characters + #78, #3967
  static Characters + #79, #3967

  ;Linha 2
  static Characters + #80, #2332
  static Characters + #81, #3967
  static Characters + #82, #3967
  static Characters + #83, #3967
  static Characters + #84, #2585
  static Characters + #85, #3967
  static Characters + #86, #3967
  static Characters + #87, #3967
  static Characters + #88, #2072
  static Characters + #89, #3967
  static Characters + #90, #3967
  static Characters + #91, #3967
  static Characters + #92, #3967
  static Characters + #93, #3967
  static Characters + #94, #3967
  static Characters + #95, #3967
  static Characters + #96, #3967
  static Characters + #97, #3967
  static Characters + #98, #3967
  static Characters + #99, #3967
  static Characters + #100, #3967
  static Characters + #101, #3967
  static Characters + #102, #3967
  static Characters + #103, #3967
  static Characters + #104, #3967
  static Characters + #105, #3967
  static Characters + #106, #3967
  static Characters + #107, #3967
  static Characters + #108, #3967
  static Characters + #109, #3967
  static Characters + #110, #3967
  static Characters + #111, #3967
  static Characters + #112, #3967
  static Characters + #113, #3967
  static Characters + #114, #3967
  static Characters + #115, #3967
  static Characters + #116, #3967
  static Characters + #117, #3967
  static Characters + #118, #3967
  static Characters + #119, #3967

  ;Linha 3
  static Characters + #120, #127
  static Characters + #121, #3967
  static Characters + #122, #3967
  static Characters + #123, #3967
  static Characters + #124, #127
  static Characters + #125, #127
  static Characters + #126, #127
  static Characters + #127, #127
  static Characters + #128, #127
  static Characters + #129, #127
  static Characters + #130, #3967
  static Characters + #131, #3967
  static Characters + #132, #3967
  static Characters + #133, #3967
  static Characters + #134, #127
  static Characters + #135, #3967
  static Characters + #136, #3967
  static Characters + #137, #3967
  static Characters + #138, #3967
  static Characters + #139, #3967
  static Characters + #140, #3967
  static Characters + #141, #3967
  static Characters + #142, #3967
  static Characters + #143, #3967
  static Characters + #144, #3967
  static Characters + #145, #3967
  static Characters + #146, #3967
  static Characters + #147, #3967
  static Characters + #148, #3967
  static Characters + #149, #3967
  static Characters + #150, #3967
  static Characters + #151, #3967
  static Characters + #152, #3967
  static Characters + #153, #3967
  static Characters + #154, #3967
  static Characters + #155, #3967
  static Characters + #156, #3967
  static Characters + #157, #3967
  static Characters + #158, #3967
  static Characters + #159, #3967

  ;Linha 4
  static Characters + #160, #127
  static Characters + #161, #127
  static Characters + #162, #127
  static Characters + #163, #127
  static Characters + #164, #127
  static Characters + #165, #127
  static Characters + #166, #127
  static Characters + #167, #127
  static Characters + #168, #127
  static Characters + #169, #127
  static Characters + #170, #127
  static Characters + #171, #127
  static Characters + #172, #127
  static Characters + #173, #127
  static Characters + #174, #3967
  static Characters + #175, #3967
  static Characters + #176, #3967
  static Characters + #177, #127
  static Characters + #178, #3967
  static Characters + #179, #3967
  static Characters + #180, #3967
  static Characters + #181, #3967
  static Characters + #182, #3967
  static Characters + #183, #3967
  static Characters + #184, #3967
  static Characters + #185, #3967
  static Characters + #186, #127
  static Characters + #187, #3967
  static Characters + #188, #3967
  static Characters + #189, #3967
  static Characters + #190, #3967
  static Characters + #191, #3967
  static Characters + #192, #3967
  static Characters + #193, #3967
  static Characters + #194, #3967
  static Characters + #195, #3967
  static Characters + #196, #3967
  static Characters + #197, #3967
  static Characters + #198, #3967
  static Characters + #199, #3967

  ;Linha 5
  static Characters + #200, #127
  static Characters + #201, #127
  static Characters + #202, #127
  static Characters + #203, #127
  static Characters + #204, #127
  static Characters + #205, #127
  static Characters + #206, #127
  static Characters + #207, #127
  static Characters + #208, #127
  static Characters + #209, #127
  static Characters + #210, #127
  static Characters + #211, #127
  static Characters + #212, #127
  static Characters + #213, #127
  static Characters + #214, #127
  static Characters + #215, #127
  static Characters + #216, #127
  static Characters + #217, #127
  static Characters + #218, #3967
  static Characters + #219, #3967
  static Characters + #220, #3967
  static Characters + #221, #3967
  static Characters + #222, #3967
  static Characters + #223, #3967
  static Characters + #224, #3967
  static Characters + #225, #3967
  static Characters + #226, #127
  static Characters + #227, #127
  static Characters + #228, #127
  static Characters + #229, #127
  static Characters + #230, #127
  static Characters + #231, #3967
  static Characters + #232, #3967
  static Characters + #233, #3967
  static Characters + #234, #3967
  static Characters + #235, #3967
  static Characters + #236, #3967
  static Characters + #237, #3967
  static Characters + #238, #3967
  static Characters + #239, #3967

  ;Linha 6
  static Characters + #240, #127
  static Characters + #241, #127
  static Characters + #242, #127
  static Characters + #243, #127
  static Characters + #244, #127
  static Characters + #245, #127
  static Characters + #246, #127
  static Characters + #247, #127
  static Characters + #248, #127
  static Characters + #249, #127
  static Characters + #250, #127
  static Characters + #251, #127
  static Characters + #252, #127
  static Characters + #253, #127
  static Characters + #254, #127
  static Characters + #255, #127
  static Characters + #256, #127
  static Characters + #257, #127
  static Characters + #258, #127
  static Characters + #259, #127
  static Characters + #260, #127
  static Characters + #261, #127
  static Characters + #262, #127
  static Characters + #263, #127
  static Characters + #264, #3967
  static Characters + #265, #3967
  static Characters + #266, #127
  static Characters + #267, #127
  static Characters + #268, #127
  static Characters + #269, #127
  static Characters + #270, #127
  static Characters + #271, #127
  static Characters + #272, #127
  static Characters + #273, #3967
  static Characters + #274, #3967
  static Characters + #275, #3967
  static Characters + #276, #3967
  static Characters + #277, #3967
  static Characters + #278, #3967
  static Characters + #279, #127

  ;Linha 7
  static Characters + #280, #127
  static Characters + #281, #127
  static Characters + #282, #127
  static Characters + #283, #127
  static Characters + #284, #127
  static Characters + #285, #127
  static Characters + #286, #127
  static Characters + #287, #127
  static Characters + #288, #127
  static Characters + #289, #127
  static Characters + #290, #127
  static Characters + #291, #127
  static Characters + #292, #127
  static Characters + #293, #127
  static Characters + #294, #127
  static Characters + #295, #127
  static Characters + #296, #127
  static Characters + #297, #127
  static Characters + #298, #127
  static Characters + #299, #127
  static Characters + #300, #127
  static Characters + #301, #127
  static Characters + #302, #127
  static Characters + #303, #127
  static Characters + #304, #127
  static Characters + #305, #127
  static Characters + #306, #127
  static Characters + #307, #127
  static Characters + #308, #127
  static Characters + #309, #127
  static Characters + #310, #127
  static Characters + #311, #127
  static Characters + #312, #127
  static Characters + #313, #127
  static Characters + #314, #127
  static Characters + #315, #127
  static Characters + #316, #3967
  static Characters + #317, #3967
  static Characters + #318, #3967
  static Characters + #319, #3967

  ;Linha 8
  static Characters + #320, #127
  static Characters + #321, #127
  static Characters + #322, #127
  static Characters + #323, #127
  static Characters + #324, #127
  static Characters + #325, #127
  static Characters + #326, #127
  static Characters + #327, #127
  static Characters + #328, #127
  static Characters + #329, #127
  static Characters + #330, #127
  static Characters + #331, #127
  static Characters + #332, #127
  static Characters + #333, #127
  static Characters + #334, #127
  static Characters + #335, #127
  static Characters + #336, #127
  static Characters + #337, #3967
  static Characters + #338, #127
  static Characters + #339, #127
  static Characters + #340, #127
  static Characters + #341, #127
  static Characters + #342, #127
  static Characters + #343, #127
  static Characters + #344, #127
  static Characters + #345, #127
  static Characters + #346, #127
  static Characters + #347, #127
  static Characters + #348, #127
  static Characters + #349, #127
  static Characters + #350, #127
  static Characters + #351, #127
  static Characters + #352, #127
  static Characters + #353, #127
  static Characters + #354, #127
  static Characters + #355, #127
  static Characters + #356, #127
  static Characters + #357, #127
  static Characters + #358, #127
  static Characters + #359, #127

  ;Linha 9
  static Characters + #360, #127
  static Characters + #361, #127
  static Characters + #362, #127
  static Characters + #363, #127
  static Characters + #364, #3967
  static Characters + #365, #3967
  static Characters + #366, #127
  static Characters + #367, #127
  static Characters + #368, #127
  static Characters + #369, #127
  static Characters + #370, #127
  static Characters + #371, #127
  static Characters + #372, #127
  static Characters + #373, #127
  static Characters + #374, #3967
  static Characters + #375, #3967
  static Characters + #376, #3967
  static Characters + #377, #3967
  static Characters + #378, #3967
  static Characters + #379, #3967
  static Characters + #380, #3967
  static Characters + #381, #3967
  static Characters + #382, #3967
  static Characters + #383, #3967
  static Characters + #384, #3967
  static Characters + #385, #3967
  static Characters + #386, #3967
  static Characters + #387, #127
  static Characters + #388, #127
  static Characters + #389, #127
  static Characters + #390, #127
  static Characters + #391, #127
  static Characters + #392, #127
  static Characters + #393, #127
  static Characters + #394, #127
  static Characters + #395, #127
  static Characters + #396, #127
  static Characters + #397, #127
  static Characters + #398, #127
  static Characters + #399, #127

  ;Linha 10
  static Characters + #400, #3967
  static Characters + #401, #3967
  static Characters + #402, #3967
  static Characters + #403, #3967
  static Characters + #404, #3967
  static Characters + #405, #3967
  static Characters + #406, #3967
  static Characters + #407, #3967
  static Characters + #408, #3967
  static Characters + #409, #3967
  static Characters + #410, #3967
  static Characters + #411, #3967
  static Characters + #412, #3967
  static Characters + #413, #3967
  static Characters + #414, #3967
  static Characters + #415, #3967
  static Characters + #416, #3967
  static Characters + #417, #3967
  static Characters + #418, #3967
  static Characters + #419, #3967
  static Characters + #420, #3967
  static Characters + #421, #3967
  static Characters + #422, #3967
  static Characters + #423, #3967
  static Characters + #424, #3967
  static Characters + #425, #3967
  static Characters + #426, #3967
  static Characters + #427, #3967
  static Characters + #428, #3967
  static Characters + #429, #3967
  static Characters + #430, #3967
  static Characters + #431, #3967
  static Characters + #432, #3967
  static Characters + #433, #3967
  static Characters + #434, #3967
  static Characters + #435, #3967
  static Characters + #436, #3967
  static Characters + #437, #3967
  static Characters + #438, #3967
  static Characters + #439, #3967

  ;Linha 11
  static Characters + #440, #3967
  static Characters + #441, #3967
  static Characters + #442, #3967
  static Characters + #443, #3967
  static Characters + #444, #3967
  static Characters + #445, #3967
  static Characters + #446, #3967
  static Characters + #447, #3967
  static Characters + #448, #3967
  static Characters + #449, #3967
  static Characters + #450, #3967
  static Characters + #451, #3967
  static Characters + #452, #3967
  static Characters + #453, #3967
  static Characters + #454, #3967
  static Characters + #455, #3967
  static Characters + #456, #3967
  static Characters + #457, #3967
  static Characters + #458, #3967
  static Characters + #459, #3967
  static Characters + #460, #3967
  static Characters + #461, #3967
  static Characters + #462, #3967
  static Characters + #463, #3967
  static Characters + #464, #3967
  static Characters + #465, #3967
  static Characters + #466, #3967
  static Characters + #467, #3967
  static Characters + #468, #3967
  static Characters + #469, #3967
  static Characters + #470, #3967
  static Characters + #471, #3967
  static Characters + #472, #3967
  static Characters + #473, #3967
  static Characters + #474, #3967
  static Characters + #475, #3967
  static Characters + #476, #3967
  static Characters + #477, #3967
  static Characters + #478, #3967
  static Characters + #479, #3967

  ;Linha 12
  static Characters + #480, #127
  static Characters + #481, #3967
  static Characters + #482, #127
  static Characters + #483, #3967
  static Characters + #484, #127
  static Characters + #485, #127
  static Characters + #486, #3967
  static Characters + #487, #127
  static Characters + #488, #127
  static Characters + #489, #127
  static Characters + #490, #3967
  static Characters + #491, #3967
  static Characters + #492, #3967
  static Characters + #493, #127
  static Characters + #494, #127
  static Characters + #495, #127
  static Characters + #496, #127
  static Characters + #497, #127
  static Characters + #498, #3967
  static Characters + #499, #3967
  static Characters + #500, #3967
  static Characters + #501, #3967
  static Characters + #502, #3967
  static Characters + #503, #3967
  static Characters + #504, #3967
  static Characters + #505, #3967
  static Characters + #506, #3967
  static Characters + #507, #3967
  static Characters + #508, #3967
  static Characters + #509, #3967
  static Characters + #510, #3967
  static Characters + #511, #3967
  static Characters + #512, #127
  static Characters + #513, #127
  static Characters + #514, #3967
  static Characters + #515, #3967
  static Characters + #516, #3967
  static Characters + #517, #3967
  static Characters + #518, #127
  static Characters + #519, #127

  ;Linha 13
  static Characters + #520, #127
  static Characters + #521, #127
  static Characters + #522, #127
  static Characters + #523, #127
  static Characters + #524, #127
  static Characters + #525, #127
  static Characters + #526, #127
  static Characters + #527, #127
  static Characters + #528, #3967
  static Characters + #529, #3967
  static Characters + #530, #127
  static Characters + #531, #127
  static Characters + #532, #127
  static Characters + #533, #127
  static Characters + #534, #127
  static Characters + #535, #127
  static Characters + #536, #3967
  static Characters + #537, #3967
  static Characters + #538, #3967
  static Characters + #539, #3967
  static Characters + #540, #3967
  static Characters + #541, #3967
  static Characters + #542, #3967
  static Characters + #543, #3967
  static Characters + #544, #3967
  static Characters + #545, #127
  static Characters + #546, #127
  static Characters + #547, #127
  static Characters + #548, #127
  static Characters + #549, #127
  static Characters + #550, #127
  static Characters + #551, #127
  static Characters + #552, #127
  static Characters + #553, #3967
  static Characters + #554, #3967
  static Characters + #555, #3967
  static Characters + #556, #3967
  static Characters + #557, #3967
  static Characters + #558, #3967
  static Characters + #559, #3967

  ;Linha 14
  static Characters + #560, #127
  static Characters + #561, #127
  static Characters + #562, #127
  static Characters + #563, #127
  static Characters + #564, #127
  static Characters + #565, #127
  static Characters + #566, #127
  static Characters + #567, #127
  static Characters + #568, #127
  static Characters + #569, #127
  static Characters + #570, #127
  static Characters + #571, #127
  static Characters + #572, #127
  static Characters + #573, #127
  static Characters + #574, #127
  static Characters + #575, #127
  static Characters + #576, #3967
  static Characters + #577, #127
  static Characters + #578, #127
  static Characters + #579, #3967
  static Characters + #580, #3967
  static Characters + #581, #3967
  static Characters + #582, #3967
  static Characters + #583, #3967
  static Characters + #584, #127
  static Characters + #585, #127
  static Characters + #586, #127
  static Characters + #587, #127
  static Characters + #588, #127
  static Characters + #589, #127
  static Characters + #590, #127
  static Characters + #591, #127
  static Characters + #592, #127
  static Characters + #593, #127
  static Characters + #594, #3967
  static Characters + #595, #3967
  static Characters + #596, #3967
  static Characters + #597, #127
  static Characters + #598, #127
  static Characters + #599, #127

  ;Linha 15
  static Characters + #600, #127
  static Characters + #601, #127
  static Characters + #602, #127
  static Characters + #603, #127
  static Characters + #604, #127
  static Characters + #605, #127
  static Characters + #606, #127
  static Characters + #607, #127
  static Characters + #608, #127
  static Characters + #609, #127
  static Characters + #610, #127
  static Characters + #611, #127
  static Characters + #612, #127
  static Characters + #613, #127
  static Characters + #614, #127
  static Characters + #615, #127
  static Characters + #616, #127
  static Characters + #617, #3967
  static Characters + #618, #3967
  static Characters + #619, #3967
  static Characters + #620, #3967
  static Characters + #621, #3967
  static Characters + #622, #3967
  static Characters + #623, #3967
  static Characters + #624, #127
  static Characters + #625, #127
  static Characters + #626, #127
  static Characters + #627, #127
  static Characters + #628, #127
  static Characters + #629, #127
  static Characters + #630, #127
  static Characters + #631, #127
  static Characters + #632, #127
  static Characters + #633, #127
  static Characters + #634, #3967
  static Characters + #635, #3967
  static Characters + #636, #3967
  static Characters + #637, #127
  static Characters + #638, #127
  static Characters + #639, #127

  ;Linha 16
  static Characters + #640, #127
  static Characters + #641, #127
  static Characters + #642, #127
  static Characters + #643, #127
  static Characters + #644, #127
  static Characters + #645, #127
  static Characters + #646, #127
  static Characters + #647, #127
  static Characters + #648, #127
  static Characters + #649, #127
  static Characters + #650, #127
  static Characters + #651, #127
  static Characters + #652, #127
  static Characters + #653, #127
  static Characters + #654, #127
  static Characters + #655, #127
  static Characters + #656, #127
  static Characters + #657, #127
  static Characters + #658, #3967
  static Characters + #659, #3967
  static Characters + #660, #3967
  static Characters + #661, #127
  static Characters + #662, #3967
  static Characters + #663, #127
  static Characters + #664, #127
  static Characters + #665, #127
  static Characters + #666, #127
  static Characters + #667, #127
  static Characters + #668, #127
  static Characters + #669, #127
  static Characters + #670, #127
  static Characters + #671, #127
  static Characters + #672, #127
  static Characters + #673, #127
  static Characters + #674, #3967
  static Characters + #675, #127
  static Characters + #676, #127
  static Characters + #677, #127
  static Characters + #678, #127
  static Characters + #679, #127

  ;Linha 17
  static Characters + #680, #127
  static Characters + #681, #127
  static Characters + #682, #127
  static Characters + #683, #3967
  static Characters + #684, #3967
  static Characters + #685, #3967
  static Characters + #686, #127
  static Characters + #687, #3967
  static Characters + #688, #127
  static Characters + #689, #3967
  static Characters + #690, #127
  static Characters + #691, #3967
  static Characters + #692, #127
  static Characters + #693, #3967
  static Characters + #694, #127
  static Characters + #695, #127
  static Characters + #696, #127
  static Characters + #697, #127
  static Characters + #698, #3967
  static Characters + #699, #3967
  static Characters + #700, #3967
  static Characters + #701, #3967
  static Characters + #702, #3967
  static Characters + #703, #127
  static Characters + #704, #127
  static Characters + #705, #127
  static Characters + #706, #127
  static Characters + #707, #127
  static Characters + #708, #3967
  static Characters + #709, #3967
  static Characters + #710, #3967
  static Characters + #711, #127
  static Characters + #712, #127
  static Characters + #713, #127
  static Characters + #714, #127
  static Characters + #715, #3967
  static Characters + #716, #127
  static Characters + #717, #127
  static Characters + #718, #127
  static Characters + #719, #127

  ;Linha 18
  static Characters + #720, #127
  static Characters + #721, #127
  static Characters + #722, #127
  static Characters + #723, #127
  static Characters + #724, #127
  static Characters + #725, #127
  static Characters + #726, #3967
  static Characters + #727, #127
  static Characters + #728, #127
  static Characters + #729, #127
  static Characters + #730, #127
  static Characters + #731, #127
  static Characters + #732, #127
  static Characters + #733, #127
  static Characters + #734, #127
  static Characters + #735, #127
  static Characters + #736, #127
  static Characters + #737, #127
  static Characters + #738, #127
  static Characters + #739, #127
  static Characters + #740, #127
  static Characters + #741, #127
  static Characters + #742, #127
  static Characters + #743, #127
  static Characters + #744, #127
  static Characters + #745, #3967
  static Characters + #746, #3967
  static Characters + #747, #3967
  static Characters + #748, #3967
  static Characters + #749, #3967
  static Characters + #750, #3967
  static Characters + #751, #127
  static Characters + #752, #127
  static Characters + #753, #127
  static Characters + #754, #127
  static Characters + #755, #3967
  static Characters + #756, #127
  static Characters + #757, #127
  static Characters + #758, #127
  static Characters + #759, #127

  ;Linha 19
  static Characters + #760, #127
  static Characters + #761, #127
  static Characters + #762, #127
  static Characters + #763, #127
  static Characters + #764, #127
  static Characters + #765, #3967
  static Characters + #766, #3967
  static Characters + #767, #3967
  static Characters + #768, #127
  static Characters + #769, #127
  static Characters + #770, #3967
  static Characters + #771, #127
  static Characters + #772, #127
  static Characters + #773, #127
  static Characters + #774, #127
  static Characters + #775, #3967
  static Characters + #776, #3967
  static Characters + #777, #3967
  static Characters + #778, #3967
  static Characters + #779, #3967
  static Characters + #780, #3967
  static Characters + #781, #3967
  static Characters + #782, #3967
  static Characters + #783, #3967
  static Characters + #784, #3967
  static Characters + #785, #3967
  static Characters + #786, #3967
  static Characters + #787, #3967
  static Characters + #788, #127
  static Characters + #789, #3967
  static Characters + #790, #3967
  static Characters + #791, #127
  static Characters + #792, #127
  static Characters + #793, #127
  static Characters + #794, #127
  static Characters + #795, #127
  static Characters + #796, #127
  static Characters + #797, #127
  static Characters + #798, #127
  static Characters + #799, #127

  ;Linha 20
  static Characters + #800, #127
  static Characters + #801, #127
  static Characters + #802, #127
  static Characters + #803, #127
  static Characters + #804, #3967
  static Characters + #805, #127
  static Characters + #806, #3967
  static Characters + #807, #3967
  static Characters + #808, #3967
  static Characters + #809, #3967
  static Characters + #810, #3967
  static Characters + #811, #3967
  static Characters + #812, #3967
  static Characters + #813, #3967
  static Characters + #814, #3967
  static Characters + #815, #3967
  static Characters + #816, #3967
  static Characters + #817, #127
  static Characters + #818, #127
  static Characters + #819, #127
  static Characters + #820, #127
  static Characters + #821, #127
  static Characters + #822, #127
  static Characters + #823, #127
  static Characters + #824, #3967
  static Characters + #825, #3967
  static Characters + #826, #3967
  static Characters + #827, #3967
  static Characters + #828, #127
  static Characters + #829, #127
  static Characters + #830, #3967
  static Characters + #831, #127
  static Characters + #832, #3967
  static Characters + #833, #3967
  static Characters + #834, #3967
  static Characters + #835, #3967
  static Characters + #836, #127
  static Characters + #837, #127
  static Characters + #838, #127
  static Characters + #839, #3967

  ;Linha 21
  static Characters + #840, #127
  static Characters + #841, #127
  static Characters + #842, #127
  static Characters + #843, #3967
  static Characters + #844, #3967
  static Characters + #845, #127
  static Characters + #846, #127
  static Characters + #847, #3967
  static Characters + #848, #3967
  static Characters + #849, #127
  static Characters + #850, #3967
  static Characters + #851, #3967
  static Characters + #852, #3967
  static Characters + #853, #3967
  static Characters + #854, #127
  static Characters + #855, #127
  static Characters + #856, #127
  static Characters + #857, #127
  static Characters + #858, #127
  static Characters + #859, #3967
  static Characters + #860, #3967
  static Characters + #861, #3967
  static Characters + #862, #3967
  static Characters + #863, #3967
  static Characters + #864, #3967
  static Characters + #865, #3967
  static Characters + #866, #3967
  static Characters + #867, #3967
  static Characters + #868, #3967
  static Characters + #869, #3967
  static Characters + #870, #3967
  static Characters + #871, #3967
  static Characters + #872, #3967
  static Characters + #873, #3967
  static Characters + #874, #3967
  static Characters + #875, #3967
  static Characters + #876, #3967
  static Characters + #877, #3967
  static Characters + #878, #3967
  static Characters + #879, #3967

  ;Linha 22
  static Characters + #880, #127
  static Characters + #881, #127
  static Characters + #882, #3967
  static Characters + #883, #3967
  static Characters + #884, #127
  static Characters + #885, #127
  static Characters + #886, #127
  static Characters + #887, #127
  static Characters + #888, #127
  static Characters + #889, #3967
  static Characters + #890, #3967
  static Characters + #891, #127
  static Characters + #892, #127
  static Characters + #893, #127
  static Characters + #894, #127
  static Characters + #895, #127
  static Characters + #896, #3967
  static Characters + #897, #127
  static Characters + #898, #127
  static Characters + #899, #3967
  static Characters + #900, #3967
  static Characters + #901, #3967
  static Characters + #902, #3967
  static Characters + #903, #3967
  static Characters + #904, #3967
  static Characters + #905, #3967
  static Characters + #906, #3967
  static Characters + #907, #3967
  static Characters + #908, #3967
  static Characters + #909, #3967
  static Characters + #910, #3967
  static Characters + #911, #3967
  static Characters + #912, #3967
  static Characters + #913, #3967
  static Characters + #914, #3967
  static Characters + #915, #3967
  static Characters + #916, #3967
  static Characters + #917, #3967
  static Characters + #918, #3967
  static Characters + #919, #3967

  ;Linha 23
  static Characters + #920, #127
  static Characters + #921, #127
  static Characters + #922, #3967
  static Characters + #923, #3967
  static Characters + #924, #3967
  static Characters + #925, #127
  static Characters + #926, #127
  static Characters + #927, #127
  static Characters + #928, #3967
  static Characters + #929, #3967
  static Characters + #930, #3967
  static Characters + #931, #3967
  static Characters + #932, #127
  static Characters + #933, #127
  static Characters + #934, #127
  static Characters + #935, #127
  static Characters + #936, #127
  static Characters + #937, #127
  static Characters + #938, #127
  static Characters + #939, #3967
  static Characters + #940, #3967
  static Characters + #941, #3967
  static Characters + #942, #3967
  static Characters + #943, #3967
  static Characters + #944, #3967
  static Characters + #945, #3967
  static Characters + #946, #3967
  static Characters + #947, #127
  static Characters + #948, #127
  static Characters + #949, #127
  static Characters + #950, #3967
  static Characters + #951, #3967
  static Characters + #952, #3967
  static Characters + #953, #3967
  static Characters + #954, #3967
  static Characters + #955, #3967
  static Characters + #956, #3967
  static Characters + #957, #3967
  static Characters + #958, #3967
  static Characters + #959, #3967

  ;Linha 24
  static Characters + #960, #127
  static Characters + #961, #3967
  static Characters + #962, #3967
  static Characters + #963, #3967
  static Characters + #964, #3967
  static Characters + #965, #3967
  static Characters + #966, #3967
  static Characters + #967, #3967
  static Characters + #968, #3967
  static Characters + #969, #3967
  static Characters + #970, #3967
  static Characters + #971, #3967
  static Characters + #972, #3967
  static Characters + #973, #3967
  static Characters + #974, #3967
  static Characters + #975, #3967
  static Characters + #976, #127
  static Characters + #977, #3967
  static Characters + #978, #3967
  static Characters + #979, #3967
  static Characters + #980, #3967
  static Characters + #981, #3967
  static Characters + #982, #3967
  static Characters + #983, #3967
  static Characters + #984, #3967
  static Characters + #985, #3967
  static Characters + #986, #127
  static Characters + #987, #127
  static Characters + #988, #3967
  static Characters + #989, #3967
  static Characters + #990, #3967
  static Characters + #991, #3967
  static Characters + #992, #3967
  static Characters + #993, #127
  static Characters + #994, #3967
  static Characters + #995, #3967
  static Characters + #996, #3967
  static Characters + #997, #3967
  static Characters + #998, #3967
  static Characters + #999, #3967

  ;Linha 25
  static Characters + #1000, #3967
  static Characters + #1001, #3967
  static Characters + #1002, #3967
  static Characters + #1003, #3967
  static Characters + #1004, #3967
  static Characters + #1005, #3967
  static Characters + #1006, #3967
  static Characters + #1007, #3967
  static Characters + #1008, #3967
  static Characters + #1009, #3967
  static Characters + #1010, #3967
  static Characters + #1011, #3967
  static Characters + #1012, #3967
  static Characters + #1013, #3967
  static Characters + #1014, #3967
  static Characters + #1015, #3967
  static Characters + #1016, #3967
  static Characters + #1017, #3967
  static Characters + #1018, #3967
  static Characters + #1019, #3967
  static Characters + #1020, #3967
  static Characters + #1021, #3967
  static Characters + #1022, #3967
  static Characters + #1023, #3967
  static Characters + #1024, #3967
  static Characters + #1025, #3967
  static Characters + #1026, #3967
  static Characters + #1027, #3967
  static Characters + #1028, #3967
  static Characters + #1029, #3967
  static Characters + #1030, #3967
  static Characters + #1031, #3967
  static Characters + #1032, #3967
  static Characters + #1033, #3967
  static Characters + #1034, #3967
  static Characters + #1035, #3967
  static Characters + #1036, #3967
  static Characters + #1037, #3967
  static Characters + #1038, #3967
  static Characters + #1039, #3967

  ;Linha 26
  static Characters + #1040, #3967
  static Characters + #1041, #3967
  static Characters + #1042, #3967
  static Characters + #1043, #3967
  static Characters + #1044, #3967
  static Characters + #1045, #3967
  static Characters + #1046, #3967
  static Characters + #1047, #3967
  static Characters + #1048, #3967
  static Characters + #1049, #3967
  static Characters + #1050, #3967
  static Characters + #1051, #3967
  static Characters + #1052, #3967
  static Characters + #1053, #3967
  static Characters + #1054, #3967
  static Characters + #1055, #3967
  static Characters + #1056, #3967
  static Characters + #1057, #3967
  static Characters + #1058, #3967
  static Characters + #1059, #3967
  static Characters + #1060, #3967
  static Characters + #1061, #3967
  static Characters + #1062, #3967
  static Characters + #1063, #3967
  static Characters + #1064, #3967
  static Characters + #1065, #3967
  static Characters + #1066, #3967
  static Characters + #1067, #3967
  static Characters + #1068, #3967
  static Characters + #1069, #3967
  static Characters + #1070, #3967
  static Characters + #1071, #3967
  static Characters + #1072, #3967
  static Characters + #1073, #3967
  static Characters + #1074, #3967
  static Characters + #1075, #3967
  static Characters + #1076, #3967
  static Characters + #1077, #3967
  static Characters + #1078, #3967
  static Characters + #1079, #3967

  ;Linha 27
  static Characters + #1080, #3967
  static Characters + #1081, #3967
  static Characters + #1082, #3967
  static Characters + #1083, #3967
  static Characters + #1084, #3967
  static Characters + #1085, #3967
  static Characters + #1086, #3967
  static Characters + #1087, #3967
  static Characters + #1088, #3967
  static Characters + #1089, #3967
  static Characters + #1090, #3967
  static Characters + #1091, #3967
  static Characters + #1092, #3967
  static Characters + #1093, #3967
  static Characters + #1094, #3967
  static Characters + #1095, #3967
  static Characters + #1096, #3967
  static Characters + #1097, #3967
  static Characters + #1098, #3967
  static Characters + #1099, #3967
  static Characters + #1100, #3967
  static Characters + #1101, #3967
  static Characters + #1102, #3967
  static Characters + #1103, #3967
  static Characters + #1104, #3967
  static Characters + #1105, #3967
  static Characters + #1106, #3967
  static Characters + #1107, #3967
  static Characters + #1108, #3967
  static Characters + #1109, #3967
  static Characters + #1110, #3967
  static Characters + #1111, #3967
  static Characters + #1112, #3967
  static Characters + #1113, #3967
  static Characters + #1114, #3967
  static Characters + #1115, #3967
  static Characters + #1116, #3967
  static Characters + #1117, #3967
  static Characters + #1118, #3967
  static Characters + #1119, #3967

  ;Linha 28
  static Characters + #1120, #3967
  static Characters + #1121, #3967
  static Characters + #1122, #3967
  static Characters + #1123, #3967
  static Characters + #1124, #3967
  static Characters + #1125, #3967
  static Characters + #1126, #3967
  static Characters + #1127, #3967
  static Characters + #1128, #3967
  static Characters + #1129, #3967
  static Characters + #1130, #3967
  static Characters + #1131, #3967
  static Characters + #1132, #3967
  static Characters + #1133, #3967
  static Characters + #1134, #3967
  static Characters + #1135, #3967
  static Characters + #1136, #3967
  static Characters + #1137, #3967
  static Characters + #1138, #3967
  static Characters + #1139, #3967
  static Characters + #1140, #3967
  static Characters + #1141, #3967
  static Characters + #1142, #3967
  static Characters + #1143, #3967
  static Characters + #1144, #3967
  static Characters + #1145, #3967
  static Characters + #1146, #3967
  static Characters + #1147, #3967
  static Characters + #1148, #3967
  static Characters + #1149, #3967
  static Characters + #1150, #3967
  static Characters + #1151, #3967
  static Characters + #1152, #3967
  static Characters + #1153, #3967
  static Characters + #1154, #3967
  static Characters + #1155, #3967
  static Characters + #1156, #3967
  static Characters + #1157, #3967
  static Characters + #1158, #3967
  static Characters + #1159, #3967

  ;Linha 29
  static Characters + #1160, #3967
  static Characters + #1161, #3967
  static Characters + #1162, #3967
  static Characters + #1163, #3967
  static Characters + #1164, #3967
  static Characters + #1165, #3967
  static Characters + #1166, #3967
  static Characters + #1167, #3967
  static Characters + #1168, #3967
  static Characters + #1169, #3967
  static Characters + #1170, #3967
  static Characters + #1171, #3967
  static Characters + #1172, #3967
  static Characters + #1173, #3967
  static Characters + #1174, #3967
  static Characters + #1175, #3967
  static Characters + #1176, #3967
  static Characters + #1177, #3967
  static Characters + #1178, #3967
  static Characters + #1179, #3967
  static Characters + #1180, #3967
  static Characters + #1181, #3967
  static Characters + #1182, #3967
  static Characters + #1183, #3967
  static Characters + #1184, #3967
  static Characters + #1185, #3967
  static Characters + #1186, #3967
  static Characters + #1187, #3967
  static Characters + #1188, #3967
  static Characters + #1189, #3967
  static Characters + #1190, #3967
  static Characters + #1191, #3967
  static Characters + #1192, #3967
  static Characters + #1193, #3967
  static Characters + #1194, #3967
  static Characters + #1195, #3967
  static Characters + #1196, #3967
  static Characters + #1197, #3967
  static Characters + #1198, #3967
  static Characters + #1199, #3967

printCharactersScreen:
  push R0
  push R1
  push R2
  push R3

  loadn R0, #Characters
  loadn R1, #0
  loadn R2, #1200

  printCharactersScreenLoop:

    add R3,R0,R1
    loadi R3, R3
    outchar R3, R1
    inc R1
    cmp R1, R2

    jne printCharactersScreenLoop

  pop R3
  pop R2
  pop R1
  pop R0
  rts