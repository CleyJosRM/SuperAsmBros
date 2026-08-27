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