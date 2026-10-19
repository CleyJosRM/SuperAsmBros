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
