# Targino RetroStation 1.5.6 - abertura mais rapida (teste)

VERSAO DE TESTE. Nao publicar como release ate passar no checklist.

## Abertura
Uma tela "Iniciando..." aparece em cerca de 1 segundo, antes do carregamento pesado. Ela e trocada pela tela "Carregando jogos" no mesmo lugar, sem piscar, e nunca fica aberta por engano (fecha sozinha em 90 s no pior caso). Antes, nada aparecia por 13 a 20 segundos.
A leitura da biblioteca do Hydra ficou mais leve: o calculo do caminho relativo de cada ROM nao cria mais objetos Uri (feito 3 vezes por jogo) e a lista de jogos nao e mais recopiada a cada ROM. O resultado e igual ao anterior; se algum caminho for diferente do esperado, o metodo antigo e usado.
O log agora mostra quanto tempo leva ler os manifestos do Hydra e listar os jogos, para localizar o que ainda for lento.

## Inalterado
Capas, favoritos, ROMs, BIOS, saves, atualizador e menus continuam como na 1.5.5.

Esta versao pertence somente a base. O build local nao equivale a publicacao do atualizador online.
