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