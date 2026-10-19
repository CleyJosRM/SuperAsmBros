
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
