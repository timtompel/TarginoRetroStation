# Targino RetroStation 1.5.8 - abertura: medicao por etapa e correcoes (teste)

VERSAO DE TESTE. Nao publicar como release ate passar no checklist.

## Abertura
A tela "Iniciando..." aparece em ~0,2 s e a listagem das ROMs do Hydra caiu para ~1,2 s (1.5.7). Esta versao continua o trabalho:
- A leitura do indice de artes (hydra-midia-indice.json) agora e feita uma vez so na abertura, e nao duas.
- O log ganhou "Marcos" com o tempo de cada etapa (biblioteca Hydra, componentes C#, montagem da janela, janela mostrada, verificacao das artes), para mostrar exatamente onde ainda ha demora.

## Correcao
Depois que o Hydra fechava, o log registrava o erro "converter nulo para IntPtr" (TarginoLive.ps1). Corrigido: a observacao da janela do Hydra e ignorada quando a janela ja nao existe.

## Inalterado
Capas, favoritos, ROMs, BIOS, saves, atualizador e menus continuam como na 1.5.5.

Esta versao pertence somente a base. O build local nao equivale a publicacao do atualizador online.
