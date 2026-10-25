; módulo de pontuação: os outros módulos alteram o score só por estas rotinas
; entrada: r0 = pontos; nenhum registrador é alterado

; soma r0 ao score, parando em 65535 (maior valor de 16 bits)
scoreAdd:
    push r1
    push r2
    load r1, score
    loadn r2, #65535
    sub r2, r2, r1
    ; comparamos com o espaço que falta em vez de somar direto, para não depender do carry
    cmp r0, r2
    jgr scoreAddSaturate
    add r1, r1, r0
    store score, r1
    jmp scoreAddDone
scoreAddSaturate:
    loadn r1, #65535
    store score, r1
scoreAddDone:
    pop r2
    pop r1
    rts

; subtrai r0 do score, parando em 0
scoreSub:
    push r1
    load r1, score
    cmp r0, r1
    jgr scoreSubZero
    sub r1, r1, r0
    store score, r1
    jmp scoreSubDone
scoreSubZero:
    loadn r1, #0
    store score, r1
scoreSubDone:
    pop r1
    rts
