; >>> INICIO DO ARQUIVO: data/98_mario_ram.asm
;========================================================================

;════════════════════════════════════════════════════════════
; MARIO RAM (Variáveis Globais)
; 
; Estas variáveis mudam durante a execução do jogo
; Devem ser incluídas ANTES do main, mas DEPOIS de todas
; as funções que as usam
;════════════════════════════════════════════════════════════

;════════════════════════════════════════════════════════════
; ESTADO DO JOGO
;════════════════════════════════════════════════════════════

game_active:        var #1          ; 1 = jogando, 0 = parado
game_paused:        var #1          ; 1 = pausado, 0 = rodando
game_level:         var #1          ; Nível atual (1, 2, 3...)
current_screen:     var #1          ; Tela atual (menu, playing, game_over)

;════════════════════════════════════════════════════════════
; MARIO - POSIÇÃO E MOVIMENTO
;════════════════════════════════════════════════════════════

player_x:           var #1          ; Posição X no mundo (0-map_width-1)
player_y:           var #1          ; Posição Y (0-29)
player_vel_x:       var #1          ; Velocidade X (-1, 0, +1, +2)
player_vel_y:       var #1          ; compatibilidade: velocidade Y
player_vel_x_dir:   var #1          ; 0=esquerda, 1=direita
player_vel_x_mag:   var #1          ; magnitude horizontal
player_vel_y_dir:   var #1          ; 0=baixo, 1=cima
player_vel_y_mag:   var #1          ; magnitude vertical
player_on_ground:   var #1          ; 1 = no chão, 0 = no ar
player_facing:      var #1          ; 0 = left, 1 = right
player_run_active:  var #1          ; 0 = corrida off, 1 = corrida on (toggle)
player_alive:       var #1          ; 1 = vivo, 0 = morto

;════════════════════════════════════════════════════════════
; MARIO - ANIMAÇÃO
;════════════════════════════════════════════════════════════

player_anim_frame:  var #1          ; Frame da animação (0-3)
player_anim_timer:  var #1          ; Contador de frames para animação

;════════════════════════════════════════════════════════════
; INIMIGOS - Posição e Movimento
;════════════════════════════════════════════════════════════

enemy_x:            var #1          ; Posição X
enemy_y:            var #1          ; Posição Y
enemy_vel_x:        var #1          ; Velocidade X (compatibilidade)
enemy_vel_y:        var #1          ; Velocidade Y (compatibilidade)
enemy_vel_x_dir:    var #1          ; 0=esquerda, 1=direita
enemy_vel_x_mag:    var #1          ; magnitude horizontal
enemy_vel_y_dir:    var #1          ; 0=baixo, 1=cima
enemy_vel_y_mag:    var #1          ; magnitude vertical
enemy_dir:          var #1          ; Direção (0=left, 1=right)
enemy_alive:        var #1          ; 1 = vivo, 0 = morto
enemy_type:         var #1          ; Tipo (0=goomba, 1=koopa, etc)

;════════════════════════════════════════════════════════════
; CÂMERA
;════════════════════════════════════════════════════════════

camera_x:           var #1          ; Posição X da câmera (scroll horizontal)
camera_y:           var #1          ; Posição Y da câmera (scroll vertical, geralmente 0)
camera_target_x:    var #1          ; Alvo de câmera (smooth follow)

;════════════════════════════════════════════════════════════
; MAPA
;════════════════════════════════════════════════════════════

map_ptr:            var #1          ; Ponteiro para dados do mapa atual
map_width:          var #1          ; Largura do mapa em tiles (N)
map_height:         var #1          ; Altura do mapa em tiles (30)
map_stride:         var #1          ; N+1: caracteres por linha incluindo terminador

;════════════════════════════════════════════════════════════
; PLACAR E VIDAS
;════════════════════════════════════════════════════════════

score:              var #1          ; Placar total
lives:              var #1          ; Vidas restantes (0-9)
coins_collected:    var #1          ; Moedas coletadas neste nível

;════════════════════════════════════════════════════════════
; FLAGS E CONTADORES
;════════════════════════════════════════════════════════════

invincibility_timer: var #1         ; Contador de invencibilidade após hit
jump_timer:         var #1          ; Contador para duração do pulo (não usado agora)
input_cooldown:     var #1          ; Debounce de input (evitar repetição rápida)
frame_count:        var #1          ; Contador global de frames

;════════════════════════════════════════════════════════════
; CACHE DE VALORES (para otimização)
;════════════════════════════════════════════════════════════

last_key:           var #1          ; Última tecla pressionada
is_solid_cache:     var #1          ; Cache de último tile verificado
render_row_ptr:     var #1          ; Ponteiro da linha corrente do mapa durante render

;════════════════════════════════════════════════════════════
; FIM DO ARQUIVO RAM
;════════════════════════════════════════════════════════════

;========================================================================