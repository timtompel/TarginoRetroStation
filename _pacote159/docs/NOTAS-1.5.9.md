# Targino RetroStation 1.5.9 - abertura: fim das buscas lentas no indice de artes (teste)

VERSAO DE TESTE. Nao publicar como release ate passar no checklist.

## Abertura
O log da 1.5.8 mostrou que dois trechos gastavam cerca de 5,8 ms por jogo cada um: a preparacao da biblioteca Hydra (4,9 s) e a verificacao das artes (4,9 s), somando ~9,7 s dos 18,4 s de abertura. Os dois procuravam uma chave dentro do indice de artes (um objeto com ~1700 campos) com PSObject.Properties[...], que percorre a lista inteira a cada busca. Agora o indice vira uma tabela de consulta direta, montada uma vez, e cada busca e instantanea. O resultado das buscas e identico.
Tambem desde a 1.5.7: tela "Iniciando..." imediata, listagem de ROMs mais rapida e correcao do erro "converter nulo para IntPtr" ao fechar o Hydra (1.5.8). O log continua mostrando "Marcos" por etapa.

## Inalterado
Capas, favoritos, ROMs, BIOS, saves, atualizador e menus continuam como na 1.5.5.

Esta versao pertence somente a base. O build local nao equivale a publicacao do atualizador online.
