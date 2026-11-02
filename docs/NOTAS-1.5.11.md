# Targino RetroStation 1.5.12 - diagnostico do fechamento + N64 (teste)

VERSAO DE TESTE. Nao publicar como release ate passar no checklist.

## Correcao em investigacao: launcher fechando depois da apresentacao
Na 1.5.10, ao clicar em "Ir para biblioteca" na janela de apresentacao, o launcher encerrava. A causa ainda nao esta confirmada. A unica mudanca recente que mexe no ciclo de vida das janelas e a janelinha "Iniciando..." (1.5.7 a 1.5.10), e os logs mostram a janela principal sendo recriada (a linha "Barra de tarefas" aparece duas vezes) a partir da 1.5.7. Para eliminar essa hipotese, a janelinha imediata foi DESLIGADA nesta versao.
Para o caso de continuar fechando, o log agora registra "Apresentacao aberta/fechada" e "Janela principal fechando (motivo ... | pilha ...)", que mostram quem mandou fechar.

## Nintendo 64: como quer rodar? (1.5.10)
Ao abrir um jogo de N64, o launcher pergunta qual renderizacao usar: Vulkan (ParaLLEl, padrao do Hydra), OpenGL (GLideN64) ou Software (Angrylion). Nada do Hydra, core, ROM ou configuracao e alterado em disco. Se o adaptador nao reconhecer o Hydra instalado, o N64 abre como antes.

## Abertura (1.5.7 a 1.5.9)
Listagem das ROMs mais rapida e indice de artes por tabela de consulta direta (medido: Janela pronta de 18,4 s para ~12,9 s). Erro "converter nulo para IntPtr" ao fechar o Hydra corrigido.

## Inalterado
Capas, favoritos, ROMs, BIOS, saves, atualizador e menus continuam como na 1.5.5.

Esta versao pertence somente a base. O build local nao equivale a publicacao do atualizador online.
