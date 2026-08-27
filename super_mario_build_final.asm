;========================================================================
; >>> INICIO DO ARQUIVO: src/00_mario_main.asm
;========================================================================

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

;========================================================================
; >>> INICIO DO ARQUIVO: src/01_mario_physics.asm
;========================================================================

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
; A grade do jogo e discreta (1 tile por coordenada). Portanto a magnitude
; NAO e usada como "numero de tiles a saltar de uma vez". Cada frame desloca
; no maximo 1 tile em cada eixo; a magnitude controla o estado da velocidade.
; Isso impede atravessar plataformas e torna a colisao deterministica.
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
    jle physics_gravity_store_down
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
    jle physics_gravity_apex

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
;   - cada frame pode mover no maximo 1 tile;
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
    jmp physics_vertical_done

physics_vertical_store_air_down:
    ; Ainda no ar. Consome apenas um passo da magnitude.
    loadn r5, #1
    cmp r3, r5
    jle physics_down_zero_velocity
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
    jle physics_hit_ceiling

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
    jle physics_up_zero_velocity
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
    load r1, player_x
    load r3, player_vel_x_mag
    load r4, player_vel_x_dir

    loadn r5, #0
    cmp r3, r5
    jeq physics_horizontal_done

    ; Nesta grade discreta, um frame move no maximo 1 tile.
    loadn r5, #1
    cmp r4, r5
    jeq physics_horizontal_right

; -------------------------------- LEFT ----------------------------------
physics_horizontal_left:
    loadn r5, #0
    cmp r1, r5
    jeq physics_horizontal_blocked

    mov r4, r1
    dec r4
    mov r0, r4
    load r5, player_y
    mov r2, r5
    ; physics_check_collision_tile usa r0=x, r1=y.
    mov r1, r2
    call physics_check_collision_tile

    loadn r5, #1
    cmp r2, r5
    jeq physics_horizontal_blocked

    mov r1, r4
    jmp physics_horizontal_store

; -------------------------------- RIGHT ---------------------------------
physics_horizontal_right:
    load r5, map_width
    dec r5
    cmp r1, r5
    jeg physics_horizontal_blocked

    mov r4, r1
    inc r4
    mov r0, r4
    load r5, player_y
    mov r2, r5
    mov r1, r2
    call physics_check_collision_tile

    loadn r5, #1
    cmp r2, r5
    jeq physics_horizontal_blocked

    mov r1, r4
    jmp physics_horizontal_store

physics_horizontal_blocked:
    ; IMPORTANTE: nao altera r1. Colisao mantem a coordenada original.
    loadn r0, #player_vel_x_mag
    loadn r5, #0
    storei r0, r5
    jmp physics_horizontal_store_position

physics_horizontal_store:
physics_horizontal_store_position:
    loadn r0, #player_x
    storei r0, r1

    ; O input e reaplicado pelo modulo player no proximo frame.
    loadn r0, #player_vel_x_mag
    loadn r5, #0
    storei r0, r5

    ; Compatibilidade: player_vel_x acompanha o estado final.
    loadn r0, #player_vel_x
    storei r0, r5

physics_horizontal_done:
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

    ; Coordenadas 0 sao validas. Como o player nunca gera X/Y negativo,
    ; nao existe tratamento adicional de sinal aqui.
    load r3, map_ptr
    load r4, map_stride
    mul r4, r1, r4
    add r4, r4, r0
    add r3, r3, r4
    loadi r5, r3

    ; '#' e '=' sao solidos.
    loadn r4, #'#'
    cmp r5, r4
    jeq physics_collision_solid

    loadn r4, #'='
    cmp r5, r4
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

;========================================================================
; >>> INICIO DO ARQUIVO: src/02_mario_render.asm
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
; - Cada linha do mapa possui map_width caracteres + terminador.
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

    ; Tile valido: escreve diretamente no endereco da ROM.
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
    ; nao interfira no stride real N+1 do mapa.
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
    loadn r0, #'@'
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
    loadn r0, #'x'
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
    loadn r2, #'0'
    add r0, r0, r2
    outchar r0, r1

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
    loadn r2, #'0'
    add r0, r0, r2
    loadn r1, #21
    outchar r0, r1

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

;========================================================================
; >>> INICIO DO ARQUIVO: src/03_mario_player.asm
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

    ; Cada frame começa sem deslocamento horizontal residual.
    loadn r0, #0
    loadn r1, #player_vel_x
    storei r1, r0
    loadn r1, #player_vel_x_mag
    storei r1, r0

    inchar r0

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

    loadn r1, #'s'
    cmp r0, r1
    jeq player_input_toggle_run

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

player_input_toggle_run:
    load r0, player_run_active
    loadn r1, #0
    cmp r0, r1
    jeq player_run_enable

    ; Já ativo -> desativa.
    loadn r0, #0
    loadn r1, #player_run_active
    storei r1, r0
    jmp input_done

player_run_enable:
    loadn r0, #1
    loadn r1, #player_run_active
    storei r1, r0
    jmp input_done

input_done:
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

    load r0, player_run_active
    loadn r1, #1
    cmp r0, r1
    jeq player_left_run

player_left_normal:
    loadn r0, #1
    jmp player_left_store_mag

player_left_run:
    loadn r0, #2

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

    load r0, player_run_active
    loadn r1, #1
    cmp r0, r1
    jeq player_right_run

player_right_normal:
    loadn r0, #1
    jmp player_right_store_mag

player_right_run:
    loadn r0, #2

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
    loadn r0, #12
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
    call physics_check_collision_tile

    loadn r0, #player_on_ground
    storei r0, r2

    pop r2
    pop r1
    pop r0
    rts

;========================================================================

;========================================================================
; >>> INICIO DO ARQUIVO: src/04_mario_enemies.asm
;========================================================================

; >>> INICIO DO ARQUIVO: src/04_mario_enemies.asm
;========================================================================

;════════════════════════════════════════════════════════════
; MODULE: Mario Enemies
;════════════════════════════════════════════════════════════

enemy_update:
    push r0
    push r1
    
    load r0, enemy_alive
    loadn r1, #1
    cmp r0, r1
    jne enemy_update_skip
    
    call enemy_apply_gravity
    call enemy_update_position
    call enemy_patrol
    call enemy_check_ground
    
enemy_update_skip:
    pop r1
    pop r0
    rts

enemy_apply_gravity:
    push r0
    push r1
    push r2

    load r0, enemy_vel_y_dir
    load r1, enemy_vel_y_mag
    loadn r2, #1
    cmp r0, r2
    jeq enemy_gravity_up

    loadn r2, #2
    add r1, r1, r2
    loadn r2, #10
    cmp r1, r2
    jle enemy_gravity_store
    mov r1, r2

enemy_gravity_store:
    loadn r0, #enemy_vel_y_mag
    storei r0, r1
    loadn r0, #enemy_vel_y
    storei r0, r1
    jmp enemy_gravity_done

enemy_gravity_up:
    loadn r2, #2
    cmp r1, r2
    jle enemy_gravity_apex
    sub r1, r1, r2
    loadn r0, #enemy_vel_y_mag
    storei r0, r1
    jmp enemy_gravity_done

enemy_gravity_apex:
    loadn r1, #0
    loadn r0, #enemy_vel_y_dir
    storei r0, r1
    loadn r0, #enemy_vel_y_mag
    storei r0, r1
    loadn r0, #enemy_vel_y
    storei r0, r1

enemy_gravity_done:
    pop r2
    pop r1
    pop r0
    rts

enemy_update_position:
    push r0
    push r1
    push r2
    push r3
    push r4
    push r5

    load r1, enemy_y
    load r3, enemy_vel_y_mag
    loadn r5, #0
    cmp r3, r5
    jeg enemy_vertical_done

enemy_move_down_loop:
    loadn r5, #29
    cmp r1, r5
    jeg enemy_land_floor
    mov r4, r1
    inc r4
    load r0, enemy_x
    mov r5, r4
    mov r1, r5
    call physics_check_collision_tile
    loadn r5, #1
    cmp r2, r5
    jeq enemy_land
    mov r1, r4
    dec r3
    loadn r5, #0
    cmp r3, r5
    jgr enemy_move_down_loop
    jmp enemy_vertical_air

enemy_land:
enemy_land_floor:
    loadn r0, #enemy_vel_y_mag
    loadn r5, #0
    storei r0, r5
    loadn r0, #enemy_vel_y
    storei r0, r5
    jmp enemy_vertical_done

enemy_vertical_air:
    loadn r0, #enemy_vel_y_mag
    storei r0, r3

enemy_vertical_done:
    loadn r0, #enemy_y
    storei r0, r1

    ; -------------------------- horizontal ----------------------------
    load r1, enemy_x
    load r3, enemy_vel_x_mag
    load r4, enemy_vel_x_dir
    loadn r5, #0
    cmp r3, r5
    jeg enemy_x_done

    loadn r5, #1
    cmp r4, r5
    jeq enemy_go_right

enemy_go_left:
    loadn r5, #0
    cmp r1, r5
    jeq enemy_x_done
    mov r4, r1
    dec r4
    mov r0, r4
    load r1, enemy_y
    call physics_check_collision_tile
    loadn r5, #1
    cmp r2, r5
    jeq enemy_left_blocked
    mov r1, r4
    dec r3
    loadn r5, #0
    cmp r3, r5
    jgr enemy_go_left
    jmp enemy_x_store

enemy_go_right:
    load r5, map_width
    dec r5
    cmp r1, r5
    jeg enemy_x_done
    mov r4, r1
    inc r4
    mov r0, r4
    load r1, enemy_y
    call physics_check_collision_tile
    loadn r5, #1
    cmp r2, r5
    jeq enemy_right_blocked
    mov r1, r4
    dec r3
    loadn r5, #0
    cmp r3, r5
    jgr enemy_go_right
    jmp enemy_x_store

enemy_left_blocked:
    inc r1
    jmp enemy_x_done

enemy_right_blocked:
    dec r1
    jmp enemy_x_done

enemy_x_store:
    loadn r0, #enemy_x
    storei r0, r1

enemy_x_done:
    loadn r0, #enemy_x
    storei r0, r1
    loadn r0, #enemy_vel_x_mag
    loadn r5, #0
    storei r0, r5
    loadn r0, #enemy_vel_x
    storei r0, r5

    pop r5
    pop r4
    pop r3
    pop r2
    pop r1
    pop r0
    rts

enemy_patrol:
    push r0
    push r1
    push r2
    push r3

    load r0, enemy_x
    load r1, enemy_dir

    loadn r3, #0
    cmp r1, r3
    jne patrol_check_right

    loadn r2, #20
    cmp r0, r2
    jeg patrol_apply_dir
    loadn r1, #1
    loadn r2, #enemy_dir
    storei r2, r1
    jmp patrol_apply_dir

patrol_check_right:
    ; Limite dinamico: width - 2, com piso minimo para evitar underflow.
    load r2, map_width
    loadn r3, #2
    cmp r2, r3
    jle patrol_apply_dir
    sub r2, r2, r3
    cmp r0, r2
    jle patrol_apply_dir
    loadn r1, #0
    loadn r2, #enemy_dir
    storei r2, r1

patrol_apply_dir:
    load r1, enemy_dir
    loadn r3, #0
    cmp r1, r3
    jne patrol_go_right

    loadn r0, #0
    loadn r1, #enemy_vel_x_dir
    storei r1, r0
    loadn r0, #1
    loadn r1, #enemy_vel_x_mag
    storei r1, r0
    loadn r1, #enemy_vel_x
    loadn r0, #0
    loadn r2, #1
    sub r0, r0, r2
    storei r1, r0
    jmp patrol_done

patrol_go_right:
    loadn r0, #1
    loadn r1, #enemy_vel_x_dir
    storei r1, r0
    loadn r0, #1
    loadn r1, #enemy_vel_x_mag
    storei r1, r0
    loadn r1, #enemy_vel_x
    storei r1, r0

patrol_done:
    pop r3
    pop r2
    pop r1
    pop r0
    rts

enemy_check_ground:
    ; Grounded é resolvido pelo solver vertical.
    rts

check_player_enemy_collision:
    push r0
    push r1
    push r2
    push r3
    push r4

    load r0, player_x
    load r1, player_y
    load r2, enemy_x
    load r3, enemy_y
    
    sub r0, r0, r2              
    
    loadn r4, #1
    cmp r0, r4
    jgr no_collision            

    loadn r4, #0
    sub r4, r4, r0             ; -r0
    cmp r4, r0
    jgr no_collision            

    sub r1, r1, r3              
    
    loadn r4, #1
    cmp r1, r4
    jgr no_collision            

    loadn r4, #0
    sub r4, r4, r1             ; -r1
    cmp r4, r1
    jgr no_collision            
    
    load r0, player_y
    load r1, enemy_y
    
    cmp r0, r1                  
    jgr player_enemy_kill_player 
    
    loadn r0, #0
    loadn r1, #enemy_alive
    storei r1, r0               
    
    loadn r0, #0
    loadn r2, #6
    sub r0, r0, r2             ; -6
    loadn r1, #player_vel_y
    storei r1, r0
    
    loadn r0, #score             ; r0 = endereço (usado no storei abaixo)
    load r1, score
    loadn r2, #500
    add r1, r1, r2
    storei r0, r1
    
    jmp enemy_collision_done
    
player_enemy_kill_player:
    call player_die
    
enemy_collision_done:
    jmp collision_end
    
no_collision:
    jmp collision_end
    
collision_end:
    pop r4
    pop r3
    pop r2
    pop r1
    pop r0
    rts

;========================================================================

;========================================================================
; >>> INICIO DO ARQUIVO: src/05_mario_blocks.asm
;========================================================================

; >>> INICIO DO ARQUIVO: src/05_mario_blocks.asm
;========================================================================

;════════════════════════════════════════════════════════════
; MODULE: Mario Blocks
; Interação com blocos, moedas, power-ups
;════════════════════════════════════════════════════════════

;────────────────────────────────────────────────────────────
; check_player_coin_collision
;────────────────────────────────────────────────────────────
check_player_coin_collision:
    push r0
    push r1
    push r2
    push r3
    push r4
    
    load r0, player_x
    load r1, player_y
    
    ; Calcular índice linear = (y*41) + x
    load r2, map_stride
    mul r2, r1, r2
    add r2, r2, r0
    
    load r3, map_ptr
    
    add r3, r3, r2
    loadi r3, r3
    
    loadn r4, #'$'
    cmp r3, r4
    jne coin_no_collision
    
    loadn r0, #coins_collected
    load r1, coins_collected
    inc r1
    storei r0, r1
    
    loadn r0, #score
    load r1, score
    loadn r2, #100
    add r1, r1, r2
    storei r0, r1
    
coin_no_collision:
    pop r4
    pop r3
    pop r2
    pop r1
    pop r0
    rts

;────────────────────────────────────────────────────────────
; check_player_block_collision
;────────────────────────────────────────────────────────────
check_player_block_collision:
    push r0
    push r1
    push r2
    push r3
    push r4
    
    load r0, player_x
    load r1, player_y
    
    load r2, map_stride
    mul r2, r1, r2
    add r2, r2, r0
    
    load r3, map_ptr
    
    add r3, r3, r2
    loadi r3, r3
    
    loadn r4, #'#'
    cmp r3, r4
    jeq block_solid
    
    loadn r4, #'='
    cmp r3, r4
    jeq block_solid
    
    jmp block_no_collision
    
block_solid:
    loadn r0, #player_vel_x
    loadn r1, #0
    storei r0, r1
    
block_no_collision:
    pop r4
    pop r3
    pop r2
    pop r1
    pop r0
    rts

;════════════════════════════════════════════════════════════
; FIM DO MODULE BLOCKS
;════════════════════════════════════════════════════════════

;========================================================================

;========================================================================
; >>> INICIO DO ARQUIVO: src/06_mario_powerups.asm
;========================================================================

; >>> INICIO DO ARQUIVO: src/06_mario_powerups.asm
;========================================================================

;════════════════════════════════════════════════════════════
; MODULE: Mario Power-ups
; Geração, colisão e efeitos de power-ups
;════════════════════════════════════════════════════════════

;────────────────────────────────────────────────────────────
; check_player_powerup_collision
;────────────────────────────────────────────────────────────
check_player_powerup_collision:
    push r0
    push r1
    push r2
    push r3
    push r4
    
    loadn r0, #player_x
    loadi r0, r0
    
    loadn r1, #player_y
    loadi r1, r1
    
    load r2, map_stride
    mul r2, r1, r2
    add r2, r2, r0
    
    loadn r3, #map_ptr
    loadi r3, r3
    
    add r3, r3, r2
    loadi r3, r3
    
    loadn r4, #'*'
    cmp r3, r4
    jne powerup_no_collision
    
    ; POWER-UP COLETADO!
    loadn r0, #score
    loadi r1, r0
    loadn r2, #500              
    add r1, r1, r2
    storei r0, r1
    
powerup_no_collision:
    pop r4
    pop r3
    pop r2
    pop r1
    pop r0
    rts

;────────────────────────────────────────────────────────────
; powerup_give_extra_life
;────────────────────────────────────────────────────────────
powerup_give_extra_life:
    push r0
    push r1
    
    loadn r0, #lives
    loadi r1, r0
    inc r1
    storei r0, r1
    
    pop r1
    pop r0
    rts

;════════════════════════════════════════════════════════════
; FIM DO MODULE POWER-UPS
;════════════════════════════════════════════════════════════

;========================================================================


;========================================================================
; >>> INICIO DO ARQUIVO: data/98_mario_ram.asm
;========================================================================

; >>> INICIO DO ARQUIVO: data/98_mario_ram.asm
;========================================================================

;════════════════════════════════════════════════════════════
; MARIO RAM (Variáveis Globais)
; 
; Estas variáveis mudam durante a execução do jogo
; Devem ser incluídas ANTES do main, mas DEPOIS de todas
; as funções que as usam
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
player_run_active:  var #1          ; 0 = corrida off, 1 = corrida on (toggle)
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
map_stride:         var #1          ; N+1: caracteres por linha incluindo terminador

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

;========================================================================
; >>> INICIO DO ARQUIVO: data/99_mario_rom.asm
;========================================================================

; >>> INICIO DO ARQUIVO: data/99_mario_rom.asm
;========================================================================

;════════════════════════════════════════════════════════════
; ARQUIVO: 99_mario_rom.asm
; MODULO: ROM (Read-Only Memory)
; FUNÇÃO: Constantes estáticas, Strings, Mapas
; ATENÇÃO: DEVE SER O ÚLTIMO ARQUIVO A SER INCLUÍDO/COMPILADO
;════════════════════════════════════════════════════════════

;════════════════════════════════════════════════════════════
; MAPA DO JOGO (Level 1)
; Dimensões atuais: 40 colunas x 30 linhas; formato preparado para N x 30
;
; Estrutura preparada para mapas N x 30. Cada linha deve ter N caracteres
; visíveis + 1 caractere invisível de terminador (\0).
;
; Legenda para o motor de colisão e renderização:
;   ' ' = Ar (Vazio)
;   '#' = Parede / Chão Sólido
;   '=' = Plataforma Sólida
;   '$' = Moeda (Score)
;   '*' = Power-up (Especial)
;════════════════════════════════════════════════════════════

;========================================================================
; 99_mario_rom_camera_test.asm
; MODULO: ROM
; TESTE: CAMERA / SCROLL HORIZONTAL
; MAPA: 120 x 30 tiles
;
; A tela possui 40 colunas. Portanto, neste mapa a camera pode percorrer
; camera_x = 0..80. O player permanece em coordenadas do MUNDO.
;
; Cada linha possui exatamente 120 caracteres visiveis. A diretiva `string`
; acrescenta o terminador utilizado pelo stride do mapa.
;
; Legenda:
;   ' ' = ar
;   '#' = solido
;   '=' = plataforma
;   '$' = moeda
;   '*' = power-up
;========================================================================

map_data:
    string "                                                                                                                        " ; Linha 00
    string "                                                                                                                        " ; Linha 01
    string "                                                                                                                        " ; Linha 02
    string "                                                                                                                        " ; Linha 03
    string "                                                                                                                        " ; Linha 04
    string "                                                                                                                        " ; Linha 05
    string "                                                                                                                        " ; Linha 06
    string "                                                                                                                        " ; Linha 07
    string "                                                                                                                        " ; Linha 08
    string "                                                                                                                        " ; Linha 09
    string "                                                                                                                        " ; Linha 10
    string "                                                                                                $                       " ; Linha 11
    string "                                                                                              =====                     " ; Linha 12
    string "                                                                         $                      *                       " ; Linha 13
    string "                                                                        ====                                            " ; Linha 14
    string "                                                  $                                                                     " ; Linha 15
    string "                                                =====                                                             $     " ; Linha 16
    string "             $                $                     *                                $                           ====   " ; Linha 17
    string "            ===             ====                                                    ===                                 " ; Linha 18
    string "                                                                                                                        " ; Linha 19
    string "                                                              #######                                    #######        " ; Linha 20
    string "                                                                                                                        " ; Linha 21
    string "                                                                                                                        " ; Linha 22
    string "                                                                                                            ###         " ; Linha 23
    string "                  $                        $                        ##      $                      ##$                  " ; Linha 24
    string "                                                                    ##                             ##                   " ; Linha 25
    string "######################    ##############################      ##########################    ############################" ; Linha 26
    string "######################    ##############################      ##########################    ############################" ; Linha 27
    string "######################    ##############################      ##########################    ############################" ; Linha 28
    string "######################    ##############################      ##########################    ############################" ; Linha 29

