# ICMC Assembly - Código Pronto para Usar

**Biblioteca de snippets de código prontos para copiar e adaptar em seus jogos**

---

## 📚 Índice
1. [Setup Básico](#setup-básico)
2. [Estrutura de Variáveis](#estrutura-de-variáveis)
3. [Funções de Tela](#funções-de-tela)
4. [Funções de Input](#funções-de-input)
5. [Funções de Física](#funções-de-física)
6. [Funções Matemáticas](#funções-matemáticas)
7. [Funções de Colisão](#funções-de-colisão)
8. [Padrões Comuns](#padrões-comuns)

---

## Setup Básico

### Estrutura Mínima de um Jogo

```assembly
;────────────────────────────────────────
; ICMC Game Boilerplate
;────────────────────────────────────────

; Convenção de registradores
;r0-r3 -> entrada e saída de funções
;r4-r6 -> temporários
;r7    -> posição do personagem

main:
    call init_game
    
game_loop:
    call update
    call render
    call input
    
    ; Verificar se jogo continua
    loadn r0, #game_active
    loadi r1, r0
    loadn r2, #1
    cmp r1, r2
    jeq game_loop
    
    call cleanup
    halt

init_game:
    push r0
    push r1
    
    ; Inicializar variáveis
    loadn r0, #0
    loadn r1, #game_time
    storei r1, r0
    
    loadn r1, #game_active
    storei r1, r0
    loadn r0, #1
    storei r1, r0
    
    ; Desenhar tela inicial
    call clear_screen
    call draw_map
    
    pop r1
    pop r0
    rts

update:
    push r0
    
    ; Atualizar lógica do jogo
    ; Aqui entra física, IA, etc.
    
    pop r0
    rts

render:
    push r0
    
    ; Redesenhar tela
    ; Usar dirty bits para otimizar
    
    pop r0
    rts

input:
    push r0
    
    inchar r0
    
    ; Processar entrada
    loadn r1, #'q'
    cmp r0, r1
    ceq quit_game
    
    pop r0
    rts

quit_game:
    loadn r0, #game_active
    loadn r1, #0
    storei r0, r1
    rts

cleanup:
    rts
```

---

## Estrutura de Variáveis

### Layout Típico

```assembly
;───── GAME STATE ─────
game_active: var #1
game_time: var #2
current_level: var #1

;───── PLAYER ─────
player_x: var #1
player_y: var #1
player_pos: var #2         ; Posição combinada
player_hp: var #1
player_score: var #2

;───── PHYSICS ─────
vel_x_dir: var #1          ; 0=direita, 1=esquerda
vel_x_mag: var #1
vel_y_dir: var #1          ; 0=baixo, 1=cima
vel_y_mag: var #1

;───── INPUT ─────
last_key: var #1
key_pressed: var #1
action_cooldown: var #1

;───── DATA ─────
map_ptr: var #1
map_data:
    string "########"
    string "#......#"
    string "#......#"
    string "########"
```

---

## Funções de Tela

### 1. Clear Screen (Limpar Tela)

```assembly
;─── Limpa completamente a tela com espaços
clear_screen:
    push r0
    push r1
    push r2
    
    loadn r0, #' '         ; Espaço
    loadn r1, #0           ; Posição inicial
    loadn r2, #1200        ; Total de tiles (40x30)
    
clear_screen_loop:
    cmp r1, r2
    jeq clear_screen_end
    
    outchar r0, r1
    inc r1
    jmp clear_screen_loop
    
clear_screen_end:
    pop r2
    pop r1
    pop r0
    rts
```

### 2. Draw Rectangle (Desenhar Retângulo)

```assembly
;─── Desenha retângulo cheio
; Entrada: r0=char, r1=x, r2=y, r3=width, r4=height
draw_rectangle:
    push r0
    push r1
    push r2
    push r3
    push r4
    push r5
    push r6
    
    mov r5, r2             ; r5 = Y inicial
    
draw_rect_y_loop:
    cmp r2, r4
    jeq draw_rect_end
    
    ; Calcular posição no início desta linha
    loadn r6, #40
    mul r7, r2, r6
    add r6, r1
    
    ; Desenhar linha
    mov r7, r3             ; r7 = contador de largura
    
draw_rect_x_loop:
    cmp r7, #0
    jeq draw_rect_next_y
    
    outchar r0, r6
    inc r6
    dec r7
    jmp draw_rect_x_loop
    
draw_rect_next_y:
    inc r2
    jmp draw_rect_y_loop
    
draw_rect_end:
    pop r6
    pop r5
    pop r4
    pop r3
    pop r2
    pop r1
    pop r0
    rts
```

### 3. Print String (Imprimir String)

```assembly
;─── Imprime string na posição especificada
; Entrada: r0=endereço_string, r1=posição_tela
print_string:
    push r0
    push r1
    push r2
    push r3
    
print_string_loop:
    loadi r2, r0           ; Ler caractere
    
    loadn r3, #'\0'
    cmp r2, r3
    jeq print_string_end
    
    outchar r2, r1         ; Desenhar
    
    inc r0                 ; Próximo char
    inc r1                 ; Próxima posição
    jmp print_string_loop
    
print_string_end:
    pop r3
    pop r2
    pop r1
    pop r0
    rts
```

### 4. Print Number (Imprimir Número)

```assembly
;─── Imprime número até 999
; Entrada: r0=número, r1=posição_tela
print_number:
    push r0
    push r1
    push r2
    push r3
    push r4
    
    ; Centenas
    mov r2, r0
    loadn r3, #100
    div r4, r2, r3
    loadn r0, #'0'
    add r0, r0, r4
    outchar r0, r1
    inc r1
    
    ; Dezenas
    mod r2, r2, r3
    loadn r3, #10
    div r4, r2, r3
    loadn r0, #'0'
    add r0, r0, r4
    outchar r0, r1
    inc r1
    
    ; Unidades
    mod r2, r2, r3
    loadn r0, #'0'
    add r0, r0, r2
    outchar r0, r1
    
    pop r4
    pop r3
    pop r2
    pop r1
    pop r0
    rts
```

### 5. Draw Sprite (Desenhar Sprite Simples)

```assembly
;─── Desenha sprite de múltiplos caracteres
; Entrada: r0=endereço_sprite, r1=posição_tela, r2=largura
draw_sprite:
    push r0
    push r1
    push r2
    push r3
    
    mov r3, r2             ; r3 = contador
    
draw_sprite_loop:
    cmp r3, #0
    jeq draw_sprite_end
    
    loadi r4, r0           ; Ler caractere do sprite
    outchar r4, r1         ; Desenhar
    
    inc r0
    inc r1
    dec r3
    jmp draw_sprite_loop
    
draw_sprite_end:
    pop r3
    pop r2
    pop r1
    pop r0
    rts
```

---

## Funções de Input

### 1. Read Key Once (Ler Tecla Uma Vez)

```assembly
;─── Lê uma tecla apenas quando pressionada
; Entrada: nenhuma
; Saída: r0 = código da tecla (ou 255 se nenhuma)
read_key_once:
    push r1
    push r2
    
    inchar r0
    
    loadn r1, #last_key
    loadi r2, r1
    
    cmp r0, r2             ; Mesma tecla de antes?
    jeq key_not_pressed
    
    storei r1, r0          ; Atualizar last_key
    jmp read_key_once_end
    
key_not_pressed:
    loadn r0, #255         ; Nenhuma tecla nova
    
read_key_once_end:
    pop r2
    pop r1
    rts
```

### 2. Is Key Pressed (Verificar Tecla Específica)

```assembly
;─── Verifica se uma tecla específica está pressionada
; Entrada: r0 = código da tecla a verificar
; Saída: r0 = 1 se pressionada, 0 caso contrário
is_key_pressed:
    push r1
    
    inchar r1
    
    cmp r1, r0
    ceq key_is_pressed
    
    loadn r0, #0
    jmp is_key_pressed_end
    
key_is_pressed:
    loadn r0, #1
    
is_key_pressed_end:
    pop r1
    rts
```

### 3. Handle WASD Input (Processar WASD)

```assembly
;─── Processa input WASD padrão
handle_wasd:
    push r0
    push r1
    
    inchar r0
    
    ; W = pular
    loadn r1, #'w'
    cmp r0, r1
    ceq do_jump
    
    ; A = esquerda
    loadn r1, #'a'
    cmp r0, r1
    ceq move_player_left
    
    ; D = direita
    loadn r1, #'d'
    cmp r0, r1
    ceq move_player_right
    
    ; S = agachar/ação
    loadn r1, #'s'
    cmp r0, r1
    ceq do_action
    
    jmp handle_wasd_end
    
do_jump:
    call player_jump
    jmp handle_wasd_end
    
move_player_left:
    call player_move_left
    jmp handle_wasd_end
    
move_player_right:
    call player_move_right
    jmp handle_wasd_end
    
do_action:
    call player_action
    
handle_wasd_end:
    pop r1
    pop r0
    rts
```

### 4. Cooldown Manager (Gerenciar Cooldown)

```assembly
;─── Gerencia cooldown de ações
; Entrada: r0 = endereço da variável de cooldown, r1 = duração em ticks
set_cooldown:
    push r0
    push r1
    
    storei r0, r1
    
    pop r1
    pop r0
    rts

;─── Atualiza todos os cooldowns
tick_cooldowns:
    push r0
    push r1
    
    ; Cooldown de ataque
    loadn r0, #attack_cooldown
    loadi r1, r0
    loadn r2, #0
    cmp r1, r2
    jeq skip_attack_cooldown
    
    dec r1
    storei r0, r1
    
skip_attack_cooldown:
    ; Cooldown de ação especial
    loadn r0, #special_cooldown
    loadi r1, r0
    cmp r1, r2
    jeq skip_special_cooldown
    
    dec r1
    storei r0, r1
    
skip_special_cooldown:
    pop r1
    pop r0
    rts

;─── Verifica se ação está disponível
can_act:
    push r0
    push r1
    
    loadn r0, #attack_cooldown
    loadi r1, r0
    
    loadn r0, #0
    cmp r1, r0
    jeq can_act_true
    
    loadn r0, #0
    rts
    
can_act_true:
    loadn r0, #1
    rts
```

---

## Funções de Física

### 1. Simple Gravity (Gravidade Simples)

```assembly
;─── Aplica gravidade ao personagem
apply_gravity:
    push r0
    push r1
    push r2
    push r3
    push r4
    push r5
    push r6
    
    ; Verificar se está no chão
    ; Calcular posição do tile abaixo
    loadn r4, #120         ; Offset vertical (3 linhas)
    add r6, r7, r4
    
    ; Converter para coordenadas de memória
    loadn r4, #40
    div r2, r6, r4
    mod r3, r6, r4
    loadn r4, #41          ; Stride (40 + null terminator)
    mul r2, r2, r4
    add r2, r2, r3
    
    ; Carregar tile abaixo
    loadn r0, #map_ptr
    loadi r0, r0
    add r0, r0, r2
    loadi r1, r0
    
    ; Se é ar, aplicar gravidade
    loadn r4, #'0'
    cmp r1, r4
    ceq apply_gravity_force
    
    ; Se não há chão, não aplicar mais gravidade
    jmp apply_gravity_end
    
apply_gravity_force:
    ; Aumentar velocidade vertical
    loadn r0, #vel_y_mag
    loadi r1, r0
    
    loadn r2, #100         ; Velocidade máxima
    cmp r1, r2
    jgr apply_gravity_end  ; Já atingiu máximo
    
    loadn r3, #5           ; Incremento de gravidade
    add r1, r1, r3
    storei r0, r1
    
apply_gravity_end:
    pop r6
    pop r5
    pop r4
    pop r3
    pop r2
    pop r1
    pop r0
    rts
```

### 2. Friction (Fricção)

```assembly
;─── Aplica fricção ao movimento horizontal
apply_friction:
    push r0
    push r1
    push r2
    push r3
    push r4
    
    ; Verificar se está no chão (mesmo código que gravity)
    loadn r4, #120
    add r6, r7, r4
    
    loadn r4, #40
    div r2, r6, r4
    mod r3, r6, r4
    loadn r4, #41
    mul r2, r2, r4
    add r2, r2, r3
    
    loadn r0, #map_ptr
    loadi r0, r0
    add r0, r0, r2
    loadi r1, r0
    
    ; Se não está no chão, sem fricção
    loadn r4, #'0'
    cmp r1, r4
    jeq apply_friction_end
    
    ; Está no chão: aplicar fricção
    loadn r0, #vel_x_mag
    loadi r1, r0
    
    ; Se velocidade é pequena, zerar
    loadn r2, #10
    cmp r1, r2
    jle set_zero_x_vel
    
    ; Senão, reduzir por 2
    loadn r2, #2
    div r1, r1, r2
    storei r0, r1
    jmp apply_friction_end
    
set_zero_x_vel:
    loadn r1, #0
    storei r0, r1
    
apply_friction_end:
    pop r4
    pop r3
    pop r2
    pop r1
    pop r0
    rts
```

### 3. Update Position (Atualizar Posição)

```assembly
;─── Atualiza posição do personagem baseado em velocidade
update_position:
    push r0
    push r1
    push r2
    push r3
    push r4
    
    ; Salvar posição anterior para colisão
    loadn r0, #prev_player_pos
    storei r0, r7
    
    ; Aplicar velocidade X
    loadn r0, #vel_x_dir
    loadi r2, r0           ; Direção X
    
    loadn r0, #vel_x_mag
    loadi r3, r0           ; Magnitude X
    
    cmp r2, #0
    ceq apply_vel_x_right
    cmp r2, #1
    ceq apply_vel_x_left
    
    jmp apply_vel_y
    
apply_vel_x_right:
    add r7, r7, r3
    jmp apply_vel_y
    
apply_vel_x_left:
    sub r7, r7, r3
    
apply_vel_y:
    ; Aplicar velocidade Y (com offset de 40 por linha)
    loadn r0, #vel_y_dir
    loadi r2, r0           ; Direção Y
    
    loadn r0, #vel_y_mag
    loadi r3, r0           ; Magnitude Y
    
    loadn r4, #40
    mul r3, r3, r4         ; Converter para índice de tela
    
    cmp r2, #0
    ceq apply_vel_y_down
    cmp r2, #1
    ceq apply_vel_y_up
    
    jmp update_position_end
    
apply_vel_y_down:
    add r7, r7, r3
    jmp update_position_end
    
apply_vel_y_up:
    sub r7, r7, r3
    
update_position_end:
    pop r4
    pop r3
    pop r2
    pop r1
    pop r0
    rts
```

---

## Funções Matemáticas

### 1. Signed Addition (Soma Assinada)

```assembly
;─── Soma dois números em formato direção+magnitude
; Entrada: r0=dir_a, r1=mag_a, r2=dir_b, r3=mag_b
; Saída: r0=dir_result, r1=mag_result
signed_add:
    push r4
    
    cmp r0, r2             ; Direções iguais?
    jeq sa_same_direction
    
    ; Direções opostas
    cmp r1, r3             ; Comparar magnitudes
    jeq sa_cancel          ; Iguais = cancela
    jgr sa_a_is_bigger     ; A é maior
    
    ; B é maior
    mov r4, r1
    sub r1, r3, r4
    mov r0, r2
    jmp sa_done
    
sa_a_is_bigger:
    sub r1, r1, r3
    jmp sa_done
    
sa_cancel:
    loadn r1, #0
    jmp sa_done
    
sa_same_direction:
    add r1, r1, r3         ; Somar magnitudes
    
sa_done:
    pop r4
    rts
```

### 2. Clamp Value (Limitar Valor)

```assembly
;─── Limita valor entre 0 e máximo
; Entrada/Saída: r0 = valor, r1 = máximo
clamp:
    push r2
    
    cmp r0, r1
    jle clamp_end
    
    mov r0, r1             ; Se maior que máx, setar para máx
    
clamp_end:
    pop r2
    rts
```

### 3. Absolute Value (Valor Absoluto)

```assembly
;─── Converte para valor absoluto
; Entrada/Saída: r0 = valor
abs:
    push r1
    
    loadn r1, #0
    cmp r0, r1
    jgr abs_end            ; Se positivo, já é absoluto
    
    ; Negativo: inverter sinal (aqui seria diferente se tivéssemos negativos)
    
abs_end:
    pop r1
    rts
```

### 4. Distance (Distância Entre Dois Pontos)

```assembly
;─── Calcula distância Manhattan entre dois pontos
; Entrada: r0=x1, r1=y1, r2=x2, r3=y2
; Saída: r0 = distância
distance_manhattan:
    push r1
    push r2
    push r3
    push r4
    
    ; |x1 - x2|
    cmp r0, r2
    jle dist_calc_y
    
    sub r4, r0, r2
    jmp dist_calc_y
    
dist_calc_y:
    sub r4, r2, r0
    
    ; |y1 - y2|
    cmp r1, r3
    jle dist_add
    
    sub r5, r1, r3
    jmp dist_add
    
dist_add:
    sub r5, r3, r1
    
    ; Somar distâncias
    add r0, r4, r5
    
    pop r4
    pop r3
    pop r2
    pop r1
    rts
```

---

## Funções de Colisão

### 1. Check Tile Collision (Verificar Colisão com Tile)

```assembly
;─── Verifica se há colisão em uma posição
; Entrada: r0 = índice na tela
; Saída: r0 = 1 se colidiu, 0 caso contrário
check_collision:
    push r1
    push r2
    push r3
    push r4
    
    ; Converter índice para coordenadas de memória
    loadn r1, #40
    div r2, r0, r1
    mod r3, r0, r1
    loadn r1, #41
    mul r2, r2, r1
    add r2, r2, r3
    
    ; Carregar tile
    loadn r0, #map_ptr
    loadi r0, r0
    add r0, r0, r2
    loadi r1, r0
    
    ; Verificar tipo de tile
    ; Parede
    loadn r4, #'#'
    cmp r1, r4
    ceq collision_found
    
    ; Pico morte
    loadn r4, #'6'
    cmp r1, r4
    ceq collision_found
    
    ; Nenhuma colisão
    loadn r0, #0
    jmp collision_check_end
    
collision_found:
    loadn r0, #1
    
collision_check_end:
    pop r4
    pop r3
    pop r2
    pop r1
    rts
```

### 2. Collision Response (Resposta a Colisão)

```assembly
;─── Reverte movimento se houve colisão
undo_movement:
    push r0
    
    loadn r0, #prev_player_pos
    loadi r0, r0
    mov r7, r0             ; Volta para posição anterior
    
    pop r0
    rts
```

### 3. Rectangle Collision (Colisão de Retângulo)

```assembly
;─── Verifica colisão entre dois retângulos
; Entrada: r0-r3=rect1(x,y,w,h), r4-r7=rect2(x,y,w,h)
; Saída: r0 = 1 se colidiu, 0 caso contrário
rect_collision:
    push r1
    push r2
    
    ; rect1.right > rect2.left && rect1.left < rect2.right
    add r1, r0, r2         ; r1 = x1 + w1 (direita de rect1)
    cmp r1, r4             ; Comparar com esquerda de rect2
    jle no_collision
    
    add r2, r4, r6         ; r2 = x2 + w2 (direita de rect2)
    cmp r0, r2
    jge no_collision
    
    ; Verificar Y também
    add r1, r1, r3         ; r1 = y1 + h1
    cmp r1, r5
    jle no_collision
    
    add r2, r5, r7
    cmp r1, r2
    jge no_collision
    
    ; Colidiu
    loadn r0, #1
    jmp rect_collision_end
    
no_collision:
    loadn r0, #0
    
rect_collision_end:
    pop r2
    pop r1
    rts
```

---

## Padrões Comuns

### 1. Dirty Bit Pattern (Redesenho Otimizado)

```assembly
;───── SETUP
dirty_flag: var #1

;───── INICIALIZAR
clear_dirty:
    loadn r0, #dirty_flag
    loadn r1, #0
    storei r0, r1
    rts

;───── MARCAR SUJO
mark_dirty:
    loadn r0, #dirty_flag
    loadi r1, r0
    
    ; Se já está marcado, pular erase
    loadn r2, #1
    cmp r1, r2
    jeq mark_dirty_end
    
    ; Eraser o personagem primeiro
    call erase_player
    
    ; Marcar como dirty
    storei r0, r2
    
mark_dirty_end:
    rts

;───── RENDERIZAR
render_with_dirty:
    loadn r0, #dirty_flag
    loadi r1, r0
    loadn r2, #0
    cmp r1, r2
    jeq skip_render
    
    call draw_player
    
    ; Limpar flag
    storei r0, r2
    
skip_render:
    rts
```

### 2. State Machine Pattern (Máquina de Estados)

```assembly
;───── ESTADOS
STATE_IDLE: equ #0
STATE_WALKING: equ #1
STATE_JUMPING: equ #2
STATE_FALLING: equ #3

;───── VARIÁVEL
player_state: var #1

;───── PROCESSAR ESTADO
update_state:
    push r0
    push r1
    
    loadn r0, #player_state
    loadi r1, r0           ; r1 = estado atual
    
    cmp r1, #0             ; IDLE?
    ceq state_idle
    
    cmp r1, #1             ; WALKING?
    ceq state_walking
    
    cmp r1, #2             ; JUMPING?
    ceq state_jumping
    
    cmp r1, #3             ; FALLING?
    ceq state_falling
    
    jmp update_state_end
    
state_idle:
    ; Lógica de idle
    jmp update_state_end
    
state_walking:
    ; Lógica de walking
    jmp update_state_end
    
state_jumping:
    ; Lógica de jumping
    jmp update_state_end
    
state_falling:
    ; Lógica de falling
    
update_state_end:
    pop r1
    pop r0
    rts
```

### 3. Event System Pattern (Sistema de Eventos)

```assembly
;───── FLAGS DE EVENTOS
event_player_move: var #1
event_player_attack: var #1
event_enemy_died: var #1

;───── TRIGGER EVENT
trigger_event:
    ; r0 = tipo de evento
    ; r1 = endereço da flag
    push r0
    push r1
    
    loadn r1, #1
    storei r0, r1
    
    pop r1
    pop r0
    rts

;───── PROCESSAR EVENTOS
process_events:
    push r0
    push r1
    
    ; Checar movimento
    loadn r0, #event_player_move
    loadi r1, r0
    cmp r1, #1
    ceq handle_move_event
    
    ; Checar ataque
    loadn r0, #event_player_attack
    loadi r1, r0
    cmp r1, #1
    ceq handle_attack_event
    
    ; Etc...
    
    jmp process_events_end
    
handle_move_event:
    call player_move
    ; Limpar flag
    loadn r1, #0
    storei r0, r1
    jmp process_events_end
    
handle_attack_event:
    call player_attack
    ; Limpar flag
    loadn r1, #0
    storei r0, r1
    
process_events_end:
    pop r1
    pop r0
    rts
```

### 4. Animation Loop Pattern (Loop de Animação)

```assembly
;───── VARIÁVEIS
anim_frame: var #1
anim_timer: var #1
anim_speed: var #1

frames: 
    string "@"
    string "#"
    string "O"
    string "*"

;───── INICIALIZAR ANIMAÇÃO
init_animation:
    push r0
    push r1
    
    loadn r0, #anim_frame
    loadn r1, #0
    storei r0, r1
    
    loadn r0, #anim_timer
    loadn r1, #0
    storei r0, r1
    
    loadn r0, #anim_speed
    loadn r1, #5           ; Muda a cada 5 ticks
    storei r0, r1
    
    pop r1
    pop r0
    rts

;───── ATUALIZAR ANIMAÇÃO
update_animation:
    push r0
    push r1
    push r2
    
    loadn r0, #anim_timer
    loadi r1, r0
    inc r1
    storei r0, r1
    
    loadn r0, #anim_speed
    loadi r2, r0
    cmp r1, r2
    jle update_anim_end
    
    ; Incrementar frame
    loadn r0, #anim_frame
    loadi r1, r0
    inc r1
    
    ; Limitar a 4 frames
    loadn r2, #4
    cmp r1, r2
    jne update_anim_store
    
    loadn r1, #0
    
update_anim_store:
    storei r0, r1
    
    ; Resetar timer
    loadn r0, #anim_timer
    loadn r1, #0
    storei r0, r1
    
update_anim_end:
    pop r2
    pop r1
    pop r0
    rts

;───── DESENHAR FRAME ATUAL
draw_animation:
    push r0
    push r1
    push r2
    push r3
    
    loadn r0, #anim_frame
    loadi r1, r0           ; r1 = frame atual (0-3)
    
    ; Calcular endereço do frame
    loadn r2, #frames
    add r2, r2, r1
    
    loadi r3, r2           ; r3 = caractere do frame
    
    ; Desenhar na posição r7
    outchar r3, r7
    
    pop r3
    pop r2
    pop r1
    pop r0
    rts
```

---

## Dicas de Debug

```assembly
;───── IMPRIMIR VALOR EM r0
debug_print_r0:
    push r1
    
    loadn r1, #0           ; Posição na tela (canto superior)
    call print_number      ; Assumindo que print_number está definido
    
    pop r1
    rts

;───── BREAKPOINT
debug_breakpoint:
    breakp                 ; Para debugger
    rts

;───── VERIFICAR POSIÇÃO DO PLAYER
debug_player_pos:
    push r0
    push r1
    
    ; Desenhar posição de r7 no canto superior direito
    loadn r0, #35
    mov r1, r7
    call print_number      ; Printa r7 na posição r0
    
    pop r1
    pop r0
    rts
```

---

## Referência Rápida

### Operações Comuns

```assembly
; Carregar endereço de variável
loadn r0, #variable_name

; Carregar valor de variável
loadn r0, #variable_name
loadi r1, r0

; Armazenar valor em variável
loadn r0, #variable_name
loadn r1, #value
storei r0, r1

; Loop de 0 a n
loadn r0, #n           ; Contador
my_loop:
    ; ... código ...
    dec r0
    jne my_loop

; Condicional simples
loadn r0, #valor1
loadn r1, #valor2
cmp r0, r1
jeq if_equal
jne if_not_equal
```