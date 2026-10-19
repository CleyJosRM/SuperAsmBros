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
