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
    loadn r0, #500
    call scoreAdd
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
