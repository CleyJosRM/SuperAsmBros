#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    // 1. Definimos a ordem estrita de compilação dos módulos
    const char *arquivos[] = {
        "src/00_mario_main.asm",
        "src/01_mario_physics.asm",
        "src/02_mario_render.asm",
        "src/03_mario_player.asm",
        "src/04_mario_enemies.asm",
        "src/05_mario_blocks.asm",
        "src/06_mario_powerups.asm",
        "data/98_mario_ram.asm",
        "data/99_mario_rom.asm"
    };
    
    int num_arquivos = sizeof(arquivos) / sizeof(arquivos[0]);
    const char *arquivo_saida = "super_mario_build_final.asm";

    // 2. Abre o arquivo final para escrita
    FILE *out_file = fopen(arquivo_saida, "w");
    if (out_file == NULL) {
        printf("ERRO: Nao foi possivel criar o arquivo de saida: %s\n", arquivo_saida);
        return 1;
    }

    printf("Iniciando o empacotamento dos modulos ASM...\n");
    printf("--------------------------------------------\n");

    // 3. Itera sobre todos os arquivos na ordem correta
    for (int i = 0; i < num_arquivos; i++) {
        FILE *in_file = fopen(arquivos[i], "r");
        if (in_file == NULL) {
            printf("[AVISO] Arquivo nao encontrado: %s (Ignorando...)\n", arquivos[i]);
            continue;
        }

        printf("[OK] Processando: %s\n", arquivos[i]);

        // Insere um cabeçalho visual no arquivo final para facilitar o debug
        fprintf(out_file, ";========================================================================\n");
        fprintf(out_file, "; >>> INICIO DO ARQUIVO: %s\n", arquivos[i]);
        fprintf(out_file, ";========================================================================\n\n");

        char linha[1024];
        while (fgets(linha, sizeof(linha), in_file) != NULL) {
            fputs(linha, out_file);
        }

        fprintf(out_file, "\n\n");
        fclose(in_file);
    }

    fclose(out_file);
    
    printf("--------------------------------------------\n");
    printf("SUCESSO! Jogo compilado no arquivo: %s\n", arquivo_saida);
    printf("Voce ja pode copiar o conteudo dele para o simulador web do ICMC.\n");

    return 0;
}
