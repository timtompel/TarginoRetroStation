# Targino RetroStation 1.5.10 - escolha de renderizacao do Nintendo 64 e abertura mais rapida (teste)

VERSAO DE TESTE. Nao publicar como release ate passar no checklist.

## Nintendo 64: como quer rodar?
Ao abrir um jogo de N64, o launcher pergunta (como no PS2) qual renderizacao usar:
- Vulkan (ParaLLEl) - padrao do Hydra.
- OpenGL (GLideN64) - para PCs sem Vulkan ou com driver de video antigo.
- Software (Angrylion) - mais lento, funciona sem depender da placa de video.
A escolha vale so para aquela abertura e fica marcada como padrao da proxima vez. Nenhum arquivo do Hydra, core, ROM ou configuracao e alterado em disco: o ajuste e aplicado somente ao processo que o launcher abre. Se o adaptador nao reconhecer o Hydra instalado, o N64 abre como antes, sem pergunta.

## Abertura (1.5.7 a 1.5.9)
Tela "Iniciando..." imediata, listagem das ROMs mais rapida, indice de artes consultado por tabela de consulta direta (antes cada busca percorria ~1700 campos), e erro "converter nulo para IntPtr" ao fechar o Hydra corrigido. O log mostra "Marcos" por etapa.

## Inalterado
Capas, favoritos, ROMs, BIOS, saves, atualizador e menus continuam como na 1.5.5.

Esta versao pertence somente a base. O build local nao equivale a publicacao do atualizador online.
