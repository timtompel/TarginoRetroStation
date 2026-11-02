# Targino RetroStation 1.5.7 - abertura mais rapida (teste)

VERSAO DE TESTE. Nao publicar como release ate passar no checklist. A 1.5.6 interna tinha um erro ao abrir e nao deve ser usada.

## Abertura
Uma tela "Iniciando..." aparece em cerca de 1 segundo (medido: 238 ms), antes do carregamento pesado. Ela e trocada pela tela "Carregando jogos" no mesmo lugar, sem piscar, e nunca fica aberta por engano (fecha sozinha em 90 s no pior caso). Antes, nada aparecia por 13 a 20 segundos.
A listagem das ROMs do Hydra ficou mais direta: so cria objetos de arquivo para as extensoes do sistema e o caminho relativo de cada ROM nao usa mais objetos Uri. Se qualquer coisa nessa listagem falhar, o metodo antigo e usado automaticamente. Arquivos ocultos e de sistema continuam ignorados, como antes.
O log mostra quanto tempo leva ler os manifestos do Hydra e listar os jogos (e quanto disso e so leitura das pastas), para localizar o que ainda for lento.

## Inalterado
Capas, favoritos, ROMs, BIOS, saves, atualizador e menus continuam como na 1.5.5.

Esta versao pertence somente a base. O build local nao equivale a publicacao do atualizador online.
