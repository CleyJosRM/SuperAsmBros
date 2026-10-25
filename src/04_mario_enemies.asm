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
    loadn r0, #500
    call scoreAdd
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
