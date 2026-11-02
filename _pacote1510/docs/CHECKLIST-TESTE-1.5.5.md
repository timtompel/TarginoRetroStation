# Checklist de teste - 1.5.5 (marque cada item)

Antes: faca copia de TarginoRetroStation\Dados (favoritos, indices). Teste numa pasta Hydra de teste, se possivel.

## A. Inicio e versao
- [ ] Abre pelo atalho sem janela de erro.
- [ ] Logs\launcher.log comeca com "Launcher iniciado - v1.5.5" e nao tem linhas ERRO novas.
- [ ] Modo desenvolvedor: titulo mostra v1.5.5.

## B. Remocao do Telegram
- [ ] Menu do botao direito num jogo: Jogar/Fechar jogo, Favoritar, Personalizar launcher.
- [ ] Menu de um sistema (tela Sistemas) abre e entra no sistema.
- [ ] Personalizar > aba Compactados: so aparecem UnRAR e pastas; NAO aparecem tdl/Telegram.
- [ ] Personalizar > textos: abre sem erro (itens "baixando"/"cancelar download" sumiram).
- [ ] Jogar um jogo e fechar o launcher com o jogo aberto: sem erro no log.

## C. Capas
- [ ] Abre a biblioteca: capas existentes continuam; nenhuma capa baixada some.
- [ ] Rode tools\Gerar-Relatorio-Capas.ps1 -Root "<pasta hydra>": gera o .md e o modelo .json.
- [ ] Preencha 1 alias de teste, salve como Dados\hydra-capas-aliases.json, reabra: o jogo ganha capa (ou mantem arte do sistema se o nome nao existir).
- [ ] Alias com JSON invalido (apague uma aspa): o programa abre normalmente e usa so os aliases embutidos.
- [ ] Apague o aliases.json: jogos continuam como antes.

## D. Atualizador (sem instalar nada!)
- [ ] Filtros > Verificar atualizacoes: com 1.5.5 local e release 1.5.4 publicada, mostra "ja esta na versao estavel mais recente".
- [ ] Teste da janela de progresso e do Cancelar (nao instala):
      mkdir %TEMP%\rs-job
      powershell -STA -NoProfile -ExecutionPolicy Bypass -File "<pasta>\TarginoRetroStation\RetroStationUpdateWorker.ps1" -Root "<pasta hydra>" -Installed 1.5.3 -Job "%TEMP%\rs-job" -LauncherPid 0
      Na janela "Nova versao" clique "Atualizar agora": deve aparecer o progresso em MB. CLIQUE EM CANCELAR antes de terminar (se terminar, o Setup 1.5.4 sera aberto: feche-o sem instalar).
- [ ] Apos Cancelar: nenhuma mensagem de erro; %TEMP%\rs-job\error.txt NAO existe.
- [ ] Sem internet: mensagem "Nao foi possivel verificar/baixar... Nada foi instalado".

## E. Instalador
- [ ] Build.ps1 conclui sem erro; Setup.exe e WebSetup.exe gerados.
- [ ] Instala por cima da 1.5.4 mantendo favoritos, capas, musicas, saves.
- [ ] Antivirus nao bloqueia (anote o nome da deteccao se bloquear).

## Antes de publicar
- [ ] Todos os itens acima OK.
- [ ] Gerar update.json assinado SOMENTE depois de assinar/gerar o instalador final (hash do arquivo definitivo).
- [ ] Atualizar README: versao 1.5.5 e remover/ajustar "A versao atual e 1.5.2".

## F. Abertura (1.5.9)
- [ ] Ao abrir, a janelinha "Iniciando..." aparece em ~1-2 s (nao fica tela vazia).
- [ ] Ela vira "Carregando jogos" sem sumir/piscar e depois o launcher aparece.
- [ ] Nenhuma janelinha fica "sobrando" na tela depois que o launcher abre.
- [ ] Com a opcao "Tela Carregando jogos ao abrir" DESLIGADA, a janelinha "Iniciando..." tambem some quando o launcher abre.
- [ ] Capas, jogos e favoritos iguais aos da 1.5.5 (mesma quantidade de jogos).
- [ ] No Logs\launcher.log, procure as linhas "Hydra: ... lidos em ... ms" e "Hydra: ... listados em ... ms (so a leitura das pastas: ... ms)" e "Janela pronta em ... ms". Envie o log para comparar com os 19-20 s de antes.
- [ ] No log, envie as linhas com "Marco:", "Biblioteca Hydra:" e "Artes: verificacao".
- [ ] Jogue e feche um jogo: o erro "converter nulo para IntPtr" nao aparece mais no log.
- [ ] Compare: "Biblioteca Hydra: ... preparados em X ms" e "Artes: verificacao em Y ms" (na 1.5.8 eram ~4857 e ~4861 ms). "Janela pronta" era ~18,4 s.
- [ ] As capas dos jogos continuam as mesmas (nenhum jogo ficou sem capa que tinha antes; nomes dos jogos iguais).

## G. Nintendo 64 (1.5.10)
Importante: o Build precisa recompilar o HydraDirectBridge.dll a partir do HydraDirectBridge.cs. Se o dialogo do N64 NAO aparecer e o log trouxer "Escolha de renderizacao do N64 indisponivel", envie a linha do log.
- [ ] Abrir um jogo de N64 mostra o dialogo "Nintendo 64 - Como quer rodar?" com 3 opcoes.
- [ ] OpenGL (GLideN64): o jogo abre? (anote: abre / fecha logo / imagem incorreta)
- [ ] Software (Angrylion): o jogo abre? (pode ser lento)
- [ ] Vulkan (ParaLLEl): o jogo abre? (esperado falhar com driver NVIDIA antigo)
- [ ] A ultima escolha vem marcada na proxima vez.
- [ ] PS2 e Neo Geo continuam abrindo com o dialogo de sempre.
- [ ] Outros sistemas (SNES, PSX etc.) abrem direto, sem dialogo.
- [ ] Log: linha "Abertura direta 'n64' / '<escolha>'" e o resultado do jogo.
