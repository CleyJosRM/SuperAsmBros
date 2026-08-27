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