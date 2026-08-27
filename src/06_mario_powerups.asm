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
