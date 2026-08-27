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