; >>> INICIO DO ARQUIVO: data/99_mario_rom.asm
;========================================================================

;════════════════════════════════════════════════════════════
; ARQUIVO: 99_mario_rom.asm
; MODULO: ROM (Read-Only Memory)
; FUNÇÃO: Constantes estáticas, Strings, Mapas
; ATENÇÃO: DEVE SER O ÚLTIMO ARQUIVO A SER INCLUÍDO/COMPILADO
;════════════════════════════════════════════════════════════

;════════════════════════════════════════════════════════════
; MAPA DO JOGO (Level 1)
; Dimensões atuais: 40 colunas x 30 linhas; formato preparado para N x 30
;
; Estrutura preparada para mapas N x 30. Cada linha deve ter N caracteres
; visíveis + 1 caractere invisível de terminador (\0).
;
; Legenda para o motor de colisão e renderização:
;   ' ' = Ar (Vazio)
;   '#' = Parede / Chão Sólido
;   '=' = Plataforma Sólida
;   '$' = Moeda (Score)
;   '*' = Power-up (Especial)
;════════════════════════════════════════════════════════════

;========================================================================
; 99_mario_rom_camera_test.asm
; MODULO: ROM
; TESTE: CAMERA / SCROLL HORIZONTAL
; MAPA: 120 x 30 tiles
;
; A tela possui 40 colunas. Portanto, neste mapa a camera pode percorrer
; camera_x = 0..80. O player permanece em coordenadas do MUNDO.
;
; Cada linha possui exatamente 120 caracteres visiveis. A diretiva `string`
; acrescenta o terminador utilizado pelo stride do mapa.
;
; Legenda:
;   ' ' = ar
;   '#' = solido
;   '=' = plataforma
;   '$' = moeda
;   '*' = power-up
;========================================================================

map_data:
    string "                                                                                                                        " ; Linha 00
    string "                                                                                                                        " ; Linha 01
    string "                                                                                                                        " ; Linha 02
    string "                                                                                                                        " ; Linha 03
    string "                                                                                                                        " ; Linha 04
    string "                                                                                                                        " ; Linha 05
    string "                                                                                                                        " ; Linha 06
    string "                                                                                                                        " ; Linha 07
    string "                                                                                                                        " ; Linha 08
    string "                                                                                                                        " ; Linha 09
    string "                                                                                                                        " ; Linha 10
    string "                                                                                                $                       " ; Linha 11
    string "                                                                                              =====                     " ; Linha 12
    string "                                                                         $                      *                       " ; Linha 13
    string "                                                                        ====                                            " ; Linha 14
    string "                                                  $                                                                     " ; Linha 15
    string "                                                =====                                                             $     " ; Linha 16
    string "             $                $                     *                                $                           ====   " ; Linha 17
    string "            ===             ====                                                    ===                                 " ; Linha 18
    string "                                                                                                                        " ; Linha 19
    string "                                                              #######                                    #######        " ; Linha 20
    string "                                                                                                                        " ; Linha 21
    string "                                                                                                                        " ; Linha 22
    string "                                                                                                            ###         " ; Linha 23
    string "                  $                        $                        ##      $                      ##$                  " ; Linha 24
    string "                                                                    ##                             ##                   " ; Linha 25
    string "######################    ##############################      ##########################    ############################" ; Linha 26
    string "######################    ##############################      ##########################    ############################" ; Linha 27
    string "######################    ##############################      ##########################    ############################" ; Linha 28
    string "######################    ##############################      ##########################    ############################" ; Linha 29