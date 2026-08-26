# ICMC Assembly Architecture - Game Development Reference Guide

**Documento de Referência Completo para Desenvolvimento de Jogos em Assembly ICMC**

Uma plataforma educacional para aprender arquitetura e organização de computadores através do desenvolvimento de jogos em linguagem montadora (Assembly).

---

## 📋 Índice
1. [Introdução](#introdução)
2. [Arquitetura ICMC](#arquitetura-icmc)
3. [Registradores](#registradores)
4. [Conjunto de Instruções](#conjunto-de-instruções)
5. [Padrões e Convenções](#padrões-e-convenções)
6. [Estrutura Base do Jogo](#estrutura-base-do-jogo)
7. [Funções Principais de Programação](#funções-principais-de-programação)
8. [Implementação de Exemplos](#implementação-de-exemplos)
9. [Dicas e Otimizações](#dicas-e-otimizações)

---

## Introdução

A arquitetura ICMC é uma arquitetura simplificada, projetada especificamente para fins educacionais. Ela foi desenvolvida no Instituto de Ciências Matemáticas e de Computação (ICMC) da Universidade de São Paulo para ensinar conceitos fundamentais de:

- **Organização de computadores**: registradores, memória, ALU
- **Programação em assembly**: linguagem de máquina de baixo nível
- **Design de arquitetura**: componentes básicos de um processador
- **Desenvolvimento prático**: criação de aplicações (como jogos) em assembly

### Características principais:
- Linguagem assembly mais simples que x86, ARM ou MIPS
- Sem convenções esquisitas de arquiteturas modernas
- Sistema de tela e entrada de teclado integrado
- Ambiente de desenvolvimento (IDE) disponível na web
- Emulador de arquitetura aberto e bem documentado

---

## Arquitetura ICMC

### Componentes Principais

```
┌─────────────────────────────────────┐
│         CPU (Processador)           │
│  ┌──────────┐    ┌──────────────┐  │
│  │Registr.  │    │ Unidade      │  │
│  │(8 + 4)   │◄──►│ Lógica e     │  │
│  └──────────┘    │ Aritmética   │  │
└────────────┬─────┴──────────┬───────┘
             │                │
    ┌────────▼────────┐   ┌───▼──────────┐
    │    MEMÓRIA      │   │  PERIFÉRICOS │
    │  (Program +     │   │  (Teclado,   │
    │   Data)         │   │   Vídeo)     │
    └─────────────────┘   └──────────────┘
```

### Memória

- **Tipo**: Memória linear endereçável
- **Tamanho**: Variável (dependente da implementação)
- **Organização**: Endereçamento por byte
- **Acesso**: Instruções de load/store

### Tela

- **Resolução**: 40 colunas × 30 linhas = 1200 tiles
- **Sistema de cores**: 16 cores (RGB 5-5-5 bits)
- **Origem**: Canto superior esquerdo (0,0)
- **Eixo X**: Aumenta para direita
- **Eixo Y**: Aumenta para baixo
- **Indexação**: Contínua (posição 0-1199)

**Mapeamento de coordenadas:**
```
Posição na tela (X, Y) = Índice linear
Índice linear = Y * 40 + X
X = Índice % 40
Y = Índice / 40
```

---

## Registradores

### Registradores de Propósito Geral

| Registrador | Uso | Descrição |
|-------------|-----|-----------|
| **R0** | Parâmetro/Retorno | Entrada e saída de funções |
| **R1** | Parâmetro/Retorno | Entrada e saída de funções |
| **R2** | Parâmetro/Retorno | Entrada e saída de funções |
| **R3** | Parâmetro/Retorno | Entrada e saída de funções |
| **R4** | Temporário | Cálculos intermediários |
| **R5** | Temporário | Cálculos intermediários |
| **R6** | Temporário | Cálculos intermediários |
| **R7** | Especial | Posição do personagem (em jogos) |

### Registradores Especiais

| Registrador | Nome | Uso |
|-------------|------|-----|
| **PC** | Program Counter | Endereço da próxima instrução a executar |
| **SP** | Stack Pointer | Apontador para o topo da pilha |
| **FR** | Flag Register | Flags de operação (Zero, Carry, Overflow, etc.) |
| **IR** | Instruction Register | Instrução atual sendo executada |
| **KB** | Keyboard Register | Código ASCII da tecla pressionada |
| **WC** | Write Count | Contador de escritas em memória de vídeo |

### Flags (FR - Flag Register)

| Flag | Descrição |
|------|-----------|
| **Z** (Zero) | Resultado anterior foi zero |
| **N** (Negative) | Resultado anterior foi negativo |
| **C** (Carry) | Houve carry/borrow |
| **OV** (Overflow) | Houve overflow em operação aritmética |
| **DZ** (Divide by Zero) | Divisão por zero |
| **EQ/GT/LT** | Resultado da comparação (Equal/Greater/Less) |

### Stack (Pilha)

A pilha é gerenciada pelo **SP (Stack Pointer)**:
- **LIFO**: Last In, First Out
- **Crescimento**: Depende da implementação
- **Uso**: Variáveis locais, endereços de retorno

---

## Conjunto de Instruções

### 1. Instruções de Movimento

#### LOAD / LOADI / LOADN
```assembly
load rx, addr          ; Carrega valor do endereço addr em rx
loadi rx, ry           ; Carrega valor do endereço em ry para rx
loadn rx, #n           ; Carrega constante n em rx

; Exemplos:
load r0, pos           ; r0 = mem[pos]
loadi r1, r2           ; r1 = mem[mem[r2]]
loadn r3, #42          ; r3 = 42
```

#### STORE / STOREI
```assembly
store addr, ry         ; Armazena ry no endereço addr
storei rx, ry          ; Armazena ry no endereço em rx

; Exemplos:
store position, r0     ; mem[position] = r0
storei r1, r2          ; mem[mem[r1]] = r2
```

#### MOV
```assembly
mov rx, ry             ; Copia valor de ry para rx

; Exemplo:
mov r0, r1             ; r0 = r1
```

### 2. Instruções Aritméticas

```assembly
add rx, ry, rz         ; rx = ry + rz
addc rx, ry, rz        ; rx = ry + rz + carry
sub rx, ry, rz         ; rx = ry - rz
subc rx, ry, rz        ; rx = ry - rz + carry
mul rx, ry, rz         ; rx = ry * rz
mulc rx, ry, rz        ; rx = ry * rz + carry
div rx, ry, rz         ; rx = ry / rz
divc rx, ry, rz        ; rx = ry / rz + carry
mod rx, ry, rz         ; rx = ry % rz (módulo)
inc rx                 ; rx++ (incrementa)
dec rx                 ; rx-- (decrementa)
```

### 3. Instruções Lógicas e de Bit

```assembly
and rx, ry, rz         ; rx = ry & rz (AND lógico)
or rx, ry, rz          ; rx = ry | rz (OR lógico)
xor rx, ry, rz         ; rx = ry ^ rz (XOR lógico)
not rx, ry             ; rx = ~ry (NOT lógico)
rotl rx, #bits         ; Rotação esquerda
rotr rx, #bits         ; Rotação direita
shiftl0 rx, #bits      ; Deslocamento esquerda com 0
shiftl1 rx, #bits      ; Deslocamento esquerda com 1
shiftr0 rx, #bits      ; Deslocamento direita com 0
shiftr1 rx, #bits      ; Deslocamento direita com 1
cmp rx, ry             ; Compara rx e ry (seta flags)
```

### 4. Instruções de Pulo (Jump)

```assembly
jmp addr               ; Pula incondicional para addr
jeq addr               ; Pula se Equal (flag Z = 1)
jne addr               ; Pula se Not Equal
jgr addr               ; Pula se Greater
jle addr               ; Pula se Less or Equal
jn addr                ; Pula se Negative
jz addr                ; Pula se Zero
jc addr                ; Pula se Carry
jov addr               ; Pula se Overflow
```

**Variações com flags:**
- `ceq`: Condicional Equal
- `cne`: Condicional Not Equal
- `cgr`: Condicional Greater
- `cle`: Condicional Less or Equal

### 5. Instruções de Chamada de Função

```assembly
call addr              ; Chama função em addr (empilha PC)
rts                    ; Retorna de função (desempilha PC)

; Variações condicionais:
ceq_call addr          ; call se Equal
cne_call addr          ; call se Not Equal
; ... etc
```

### 6. Instruções de Stack

```assembly
push rx                ; Empilha rx (SP -= 1)
pop rx                 ; Desempilha para rx (SP += 1)
```

### 7. Instruções de Controle

```assembly
setc                   ; Define flag Carry = 1
clearc                 ; Define flag Carry = 0
halt                   ; Para a execução
nop                    ; Operação nula (faz nada)
breakp                 ; Breakpoint para debug
```

### 8. Instruções de Input/Output

```assembly
inchar rx              ; Lê caractere do teclado para rx
outchar rx, ry         ; Escreve caractere rx na posição ry

; Exemplo:
inchar r0              ; r0 recebe código ASCII do teclado
outchar r0, r1         ; Desenha caractere (r0) na posição r1
```

---

## Padrões e Convenções

### 1. Convenção de Registradores

**Convenção de Registradores:**

```assembly
;r0-r3 -> entrada e saída de funções
;r4-r6 -> temporários
;r7    -> posição do personagem
```

Esta convenção garante que:
- Funções usam R0-R3 para parâmetros e retorno
- R4-R6 são "descartáveis" dentro de funções
- R7 mantém estado crítico do jogo

### 2. Convenção de Stack

Ao chamar funções, salvar registradores usados:

```assembly
function_name:
    push r0            ; Salva registradores que serão usados
    push r1
    push r4
    
    ; ... código da função ...
    
    pop r4             ; Restaura na ordem inversa
    pop r1
    pop r0
    rts                ; Retorna
```

### 3. Comentários

```assembly
; Comentários de linha única começam com ;
```

### 4. Labels (Etiquetas)

```assembly
main:                  ; Define rótulo "main"
    jmp main_loop      ; Pula para "main_loop"
    
main_loop:
    ; código
    jmp main_loop
```

### 5. Variáveis (Storage)

```assembly
; Declaração de variáveis
player_x: var #1       ; Uma célula (1 byte)
position: var #2       ; Duas células (2 bytes)

; Uso:
loadn r0, #player_x    ; Carrega endereço da variável
loadi r1, r0           ; Carrega valor armazenado
storei r0, r1          ; Armazena valor
```

### 6. Strings

```assembly
message: string "Hello World"
score: string "Score: 0"

; Uso:
loadn r0, message      ; Carrega endereço da string
; ... depois processar caractere por caractere
```

---

## Estrutura Base do Jogo

### Ciclo Principal

```assembly
main:
    ; Inicialização
    call init_game
    
game_loop:
    ; 1. Atualizar física
    call tick_physics
    
    ; 2. Renderizar
    call render_graphics
    
    ; 3. Processar entrada
    call handle_input
    
    ; 4. Lógica de jogo
    call update_game_logic
    
    ; 5. Verificar condição de término
    loadn r0, #game_active
    loadi r1, r0
    loadn r2, #1
    cmp r1, r2
    jeq game_loop       ; Continua se jogo está ativo
    
    ; Fim de jogo
    call show_end_screen
    halt
```

### Inicialização do Jogo

```assembly
init_game:
    push r0
    push r1
    
    ; Limpar tela
    call clear_screen
    
    ; Carregar dados
    call load_level
    
    ; Inicializar variáveis
    loadn r0, #player_position
    loadn r1, #spawn_position
    storei r0, r1
    
    ; Desenhar elementos iniciais
    call draw_map
    call draw_player
    
    pop r1
    pop r0
    rts
```

---

## Funções Principais de Programação

### 1. Funções de Renderização (Drawing)

#### draw_map - Desenha o mapa completo

```assembly
;Parâmetros: Nenhum (usa variáveis globais)
;Saída: Nenhuma (modifica tela)

draw_map:
    push r0-r6         ; Salva todos os registradores usados
    
    loadn r0, #map_ptr ; r0 = ponteiro para dados do mapa
    loadi r0, r0
    loadn r1, #0       ; r1 = posição na tela (0-1199)
    loadn r2, #1200    ; r2 = total de tiles (40x30)
    
draw_map_loop:
    cmp r1, r2         ; Verificar se terminou
    jeq draw_map_end
    
    loadi r6, r0       ; Ler caractere do mapa
    ; ... processar cada tipo de tile ...
    
    inc r0
    inc r1
    jmp draw_map_loop
    
draw_map_end:
    pop r6-r0
    rts
```

#### draw_player - Desenha o jogador

```assembly
;Parâmetros: r7 = posição do jogador
;Saída: Nenhuma

draw_player:
    push r0
    
    loadn r0, #'@'     ; r0 = caractere do jogador
    outchar r0, r7     ; Desenha na posição r7
    
    pop r0
    rts
```

#### erase_player - Apaga o jogador

```assembly
erase_player:
    push r0
    
    loadn r0, #' '     ; r0 = espaço em branco
    outchar r0, r7     ; Sobrescreve posição anterior
    
    pop r0
    rts
```

### 2. Funções de Física

#### tick_physics - Atualiza física do jogo

```assembly
; Processa:
; - Gravidade
; - Velocidade e aceleração
; - Colisões
; - Fricção

tick_physics:
    push r0-r6
    
    ; Aplicar gravidade
    call apply_gravity
    
    ; Aplicar fricção
    call apply_friction
    
    ; Atualizar posição
    call update_position
    
    ; Verificar colisões
    call check_collisions
    
    pop r6-r0
    rts
```

#### apply_gravity - Aplica força gravitacional

```assembly
apply_gravity:
    push r0-r6
    
    ; Verificar se está no chão
    loadn r4, #120         ; Offset para tile abaixo
    add r6, r7, r4
    
    ; Calcular posição em memória
    loadn r4, #40
    div r2, r6, r4
    mod r3, r6, r4
    loadn r4, #41
    mul r2, r2, r4
    add r2, r2, r3
    
    ; Carregar tile abaixo
    loadn r0, #map_ptr
    loadi r0, r0
    add r0, r0, r2
    loadi r1, r0
    
    ; Se não há tile abaixo, aplicar gravidade
    loadn r4, #'0'
    cmp r1, r4
    ceq apply_gravity_force
    
apply_gravity_force:
    ; Aumentar velocidade vertical
    loadn r0, #vel_y_mag
    loadi r1, r0
    inc r1
    storei r0, r1
    
    pop r6-r0
    rts
```

#### apply_friction - Aplica fricção no movimento horizontal

```assembly
apply_friction:
    push r0-r6
    
    ; Similar a apply_gravity, mas para vel_x_mag
    ; Verificar se está no chão
    
    ; Se está no chão, reduzir vel_x_mag
    loadn r0, #vel_x_mag
    loadi r1, r0
    
    loadn r4, #10
    cmp r1, r4
    jle set_zero_speed
    
    ; Dividir velocidade por 2
    loadn r4, #2
    div r1, r1, r4
    storei r0, r1
    jmp friction_end
    
set_zero_speed:
    loadn r1, #0
    storei r0, r1
    
friction_end:
    pop r6-r0
    rts
```

#### update_position - Atualiza posição do personagem

```assembly
update_position:
    push r0-r6
    
    ; Carregar velocidades
    loadn r0, #vel_x_dir
    loadi r2, r0           ; r2 = direção X (0=direita, 1=esquerda)
    
    loadn r0, #vel_x_mag
    loadi r3, r0           ; r3 = magnitude X
    
    ; Aplicar velocidade X
    cmp r2, #0
    ceq move_right
    cmp r2, #1
    ceq move_left
    
move_right:
    add r7, r7, r3         ; r7 += vel_x_mag
    jmp check_velocity_y
    
move_left:
    sub r7, r7, r3         ; r7 -= vel_x_mag
    
check_velocity_y:
    ; Similar para Y (mas com offset de 40 para vertical)
    
    pop r6-r0
    rts
```

### 3. Funções de Input (Entrada)

#### handle_input - Processa entrada do teclado

```assembly
handle_input:
    push r0-r2
    
    ; Ler entrada
    inchar r0              ; r0 = código ASCII da tecla
    
    ; Comparar com teclas
    loadn r1, #'w'
    cmp r0, r1
    ceq player_jump        ; W = pular
    
    loadn r1, #'a'
    cmp r0, r1
    ceq accel_left         ; A = acelerar esquerda
    
    loadn r1, #'d'
    cmp r0, r1
    ceq accel_right        ; D = acelerar direita
    
    loadn r1, #'s'
    cmp r0, r1
    ceq player_crouch      ; S = agachar
    
    pop r2-r0
    rts
```

#### inchar_with_timeout - Lê entrada com timeout

```assembly
; Para evitar travamento esperando por entrada
; Implementar contador de ticks
```

### 4. Funções de Colisão

#### check_collisions - Verifica colisões

```assembly
check_collisions:
    push r0-r6
    
    ; Carregar posição do jogador
    mov r6, r7
    
    ; Adicionar offset para tile abaixo
    loadn r4, #120
    add r6, r6, r4
    
    ; Calcular coordenadas
    loadn r4, #40
    div r2, r6, r4
    mod r3, r6, r4
    
    ; Carregar tile
    loadn r4, #41
    mul r2, r2, r4
    add r2, r2, r3
    
    loadn r0, #map_ptr
    loadi r0, r0
    add r0, r0, r2
    loadi r1, r0
    
    ; Verificar tipo de tile
    loadn r4, #'#'         ; Parede
    cmp r1, r4
    ceq collision_found
    
    loadn r4, #'6'         ; Pico de morte
    cmp r1, r4
    ceq player_dies
    
    jmp collision_end
    
collision_found:
    ; Desfazer movimento
    call undo_movement
    
collision_end:
    pop r6-r0
    rts
```

### 5. Funções de Matemática Assinada

#### signed_add - Soma dois números assinados (direção + magnitude)

```assembly
; Entrada:
; r0 = direção A (0 ou 1)
; r1 = magnitude A
; r2 = direção B (0 ou 1)
; r3 = magnitude B
; Saída:
; r0 = direção resultado
; r1 = magnitude resultado

signed_add:
    push r4
    
    cmp r0, r2             ; Direções são iguais?
    jeq sa_same_dir
    
    ; Direções opostas: resultado = |maior| - |menor|
    cmp r1, r3
    jeq sa_cancel
    jgr sa_a_bigger
    
    ; mag_b > mag_a
    mov r4, r1
    sub r1, r3, r4
    mov r0, r2
    jmp sa_end
    
sa_a_bigger:
    sub r1, r1, r3
    jmp sa_end
    
sa_cancel:
    loadn r1, #0
    jmp sa_end
    
sa_same_dir:
    add r1, r1, r3         ; Mesma direção: somar magnitudes
    
sa_end:
    pop r4
    rts
```

### 6. Funções Auxiliares

#### print_string - Imprime string na tela

```assembly
; Entrada:
; r0 = endereço da string
; r1 = posição inicial na tela
; r2 = cor (se aplicável)

print_string:
    push r0-r2
    
    mov r4, r0             ; r4 = ponteiro string
    mov r5, r1             ; r5 = posição tela
    
print_loop:
    loadi r3, r4           ; r3 = caractere
    
    loadn r6, #'\0'
    cmp r3, r6
    jeq print_end          ; Fim da string
    
    outchar r3, r5         ; Desenha caractere
    
    inc r4
    inc r5
    jmp print_loop
    
print_end:
    pop r2-r0
    rts
```

#### clear_screen - Limpa a tela

```assembly
clear_screen:
    push r0-r2
    
    loadn r0, #' '         ; r0 = espaço
    loadn r1, #0           ; r1 = posição
    loadn r2, #1200        ; r2 = total de tiles
    
clear_loop:
    cmp r1, r2
    jeq clear_end
    
    outchar r0, r1
    inc r1
    jmp clear_loop
    
clear_end:
    pop r2-r0
    rts
```

---

## Implementação de Exemplos

### Exemplo 1: Jogo Simples de Movimento

```assembly
; Variáveis globais
player_pos: var #2
map_data:
    string "########"
    string "#......#"
    string "#...@..#"
    string "########"

main:
    ; Inicializar posição do player (linha 2, coluna 4)
    loadn r0, #player_pos
    loadn r1, #84          ; (2 * 40) + 4
    storei r0, r1
    mov r7, r1             ; r7 = posição do player
    
    call draw_map
    call draw_player
    
game_loop:
    inchar r0              ; Ler tecla
    
    loadn r1, #'a'         ; A = esquerda
    cmp r0, r1
    ceq move_left
    
    loadn r1, #'d'         ; D = direita
    cmp r0, r1
    ceq move_right
    
    jmp game_loop
    
move_left:
    call erase_player
    dec r7
    call draw_player
    jmp game_loop
    
move_right:
    call erase_player
    inc r7
    call draw_player
    jmp game_loop

; ... funções draw_map, draw_player, erase_player ...
```

### Exemplo 2: Sistema de Pontos

```assembly
; Contador de pontos
score: var #2

init_score:
    loadn r0, #score
    loadn r1, #0
    storei r0, r1
    rts

add_score:
    ; r0 contém pontos a adicionar
    push r0
    push r1
    
    loadn r1, #score
    loadi r2, r1           ; r2 = score atual
    add r2, r2, r0         ; r2 = score + pontos
    storei r1, r2          ; Armazenar novo score
    
    ; Mostrar score na tela
    loadn r0, #score_display
    call print_number
    
    pop r1
    pop r0
    rts
```

### Exemplo 3: Sistema de Vidas

```assembly
; Vidas do player
lives: var #1

init_lives:
    loadn r0, #lives
    loadn r1, #3
    storei r0, r1
    rts

lose_life:
    push r0
    push r1
    
    loadn r0, #lives
    loadi r1, r0
    dec r1
    storei r0, r1
    
    cmp r1, #0
    jeq game_over
    
    ; Respawnar player
    call respawn_player
    
    pop r1
    pop r0
    rts

game_over:
    call show_game_over
    halt
```

---

## Dicas e Otimizações

### 1. Evitar Operações Caras

```assembly
; ❌ Lento: múltiplas divisões
loadn r1, #40
div r2, r6, r1
mod r3, r6, r1
loadn r1, #41
mul r2, r2, r1

; ✅ Melhor: salvar resultado intermediário
loadn r1, #40
div r2, r6, r1
mov r4, r2             ; Reutilizar resultado
mod r3, r6, r1
loadn r1, #41
mul r2, r4, r1
```

### 2. Dirty Bit para Renderização

```assembly
; Usar flag para só redesenhar quando necessário
dirty_flag: var #1

mark_dirty:
    loadn r0, #dirty_flag
    loadn r1, #1
    storei r0, r1
    rts

should_redraw:
    loadn r0, #dirty_flag
    loadi r1, r0
    cmp r1, #0
    jeq skip_draw
    ; ... desenhar ...
    loadn r1, #0
    storei r0, r1
skip_draw:
    rts
```

### 3. Cooldowns para Input

```assembly
; Prevenir ações repetidas muito rápido
action_cooldown: var #2

is_action_available:
    loadn r0, #action_cooldown
    loadi r1, r0
    cmp r1, #0
    jeq action_available
    dec r1
    storei r0, r1
    jne action_not_available
    
action_available:
    loadn r0, #1
    rts
    
action_not_available:
    loadn r0, #0
    rts
```

### 4. Reutilizar Código

```assembly
; Usar loops para operações repetitivas
; Evitar copiar código similar

clear_region:
    ; r0 = posição inicial
    ; r1 = número de tiles
    push r0
    push r1
    push r2
    
    loadn r2, #' '
    
clear_region_loop:
    cmp r1, #0
    jeq clear_region_end
    
    outchar r2, r0
    inc r0
    dec r1
    jmp clear_region_loop
    
clear_region_end:
    pop r2
    pop r1
    pop r0
    rts
```

### 5. Manutenção de Stack

```assembly
; Sempre balancear push/pop
function:
    push r0
    push r1
    push r2            ; 3 pushes
    
    ; ... código ...
    
    pop r2             ; 3 pops na ordem inversa
    pop r1
    pop r0
    rts                ; Seguro!
```

### 6. Comentários Úteis

```assembly
; Comentar lógica complexa
; Especialmente conversões de coordenadas

; Converter índice linear para coordenadas 2D
; Entrada: r6 = índice linear (0-1199)
; Saída: r2 = Y, r3 = X
loadn r1, #40          ; Largura da tela
div r2, r6, r1         ; Y = índice / 40
mod r3, r6, r1         ; X = índice % 40

; Converter coordenadas 2D para índice linear
; Entrada: r2 = Y, r3 = X
; Saída: r4 = índice
loadn r1, #40
mul r4, r2, r1         ; r4 = Y * 40
add r4, r4, r3         ; r4 += X
```

### 7. Memória de Offset (Stride)

```assembly
; Importante para linhas com null terminator
; Em ICMC, cada linha tem 40 chars + '\0' = 41 bytes

; Para acessar posição (X, Y) no mapa:
; offset = Y * 41 + X

loadn r0, #map_ptr
loadi r0, r0           ; r0 = endereço base do mapa
loadn r1, #41          ; Stride (40 + null terminator)
mul r4, r2, r1         ; r4 = Y * 41
add r4, r4, r3         ; r4 += X
add r0, r0, r4         ; r0 = endereço final
loadi r5, r0           ; r5 = caractere naquela posição
```

---

## Tabela de Cores

### Cores para Simulador
| Cor | Valor | Descrição |
|-----|-------|-----------|
| Branco | 0 | Fundo |
| Azul | 64512 | 100% azul |
| Verde | 58112 | 100% verde |
| Vermelho | 7936 | 100% vermelho |
| Gray Tile | 46592 | Parede cinza |
| Rosa Choque | 7168 | - |
| Almost White | 8192 | - |

---

## Referência Rápida de Instruções

### Movimento
- `load rx, addr` - Carregar de endereço
- `loadi rx, ry` - Carregar indireto
- `loadn rx, #n` - Carregar constante
- `store addr, ry` - Armazenar em endereço
- `storei rx, ry` - Armazenar indireto
- `mov rx, ry` - Copiar

### Aritmética
- `add / sub / mul / div / mod`
- `inc / dec`
- `addc / subc / mulc / divc` (com carry)

### Lógica
- `and / or / xor / not`
- `rotl / rotr` - Rotação
- `shiftl0/1 / shiftr0/1` - Deslocamento
- `cmp rx, ry` - Comparar

### Pulos
- `jmp` - Incondicional
- `jeq / jne / jgr / jle / jn / jz / jc / jov`

### Funções
- `call addr` - Chamar função
- `rts` - Retornar
- `push / pop` - Stack

### I/O
- `inchar rx` - Ler do teclado
- `outchar rx, ry` - Escrever na tela

---

## Referências

- **ICMC-IDE Web**: proc.giroto.dev
- **Processador ICMC**: github.com/simoesusp/Processador-ICMC
- **ICMC USP**: icmc.usp.br
