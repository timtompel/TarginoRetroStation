# Revisão do fonte 1.5.1 — 21/10/2026

Escopo: leitura dos fontes locais de instalação, atualização, biblioteca, arte e detalhes; análise sintática dos 25 scripts PowerShell; execução dos testes existentes Update.Tests.ps1 e Migration.Tests.ps1. Nenhum fonte de execução ou instalação do usuário foi alterado. Não é certificação de ausência de bugs nem teste de todos os cores/jogos.

## Bootstrapper: ainda não implementado

O Setup atual é offline: Build.ps1 incorpora o ZIP completo como recurso `hydra.payload.zip`, e Setup.cs extrai esse recurso. A atualização online funciona, mas baixa novamente o Setup completo. Isso não é instalação por bootstrapper nem atualização diferencial.

O instalador publicado tem 5.045.760 bytes. O atualizador verifica release estável, produto/repositório, assinatura RSA-SHA256, tamanho e SHA256 e exige confirmação. Esse mecanismo de verificação deve ser reaproveitado no futuro instalador web. O limite atual é de 64 MiB (FrontendUpdate.ps1:41 e RetroStationUpdateWorker.ps1:28); crescer além disso exige uma versão anterior capaz de aceitar o novo tamanho ou a migração para outro pacote.

## Achados em ordem de prioridade

1. **P2 — recuperação incompleta se a escrita falhar no meio.** Setup.cs:202 faz backup; :203 trunca/grava diretamente o destino; :204 só então adiciona o caminho à lista `written`. Se CopyTo falhar (disco cheio ou erro de I/O), o caminho afetado ainda não estará na lista percorrida pelo rollback. Um arquivo existente pode ficar parcial mesmo com backup disponível. Recomenda-se gravar em temporário, validar e substituir, incluindo o destino no controle de restauração antes de qualquer truncamento. Achado por inspeção; falha de disco não foi reproduzida.

2. **P2 — dependência de ambiente de desenvolvimento no fallback de metadados.** HydraDetailsWorker.ps1:29–34 tenta Python instalado e depois um caminho `.cache/codex-runtimes/...` do perfil do usuário. Esse caminho não é uma dependência distribuída nem garantida. Quando WebClient falha e Python não existe, os detalhes/capturas falham. Recomenda-se compartilhar os transportes nativos já usados por HydraArtwork (WebClient, WinHTTP e curl), sem desativar validação TLS. O helper hydra-media-transport.py ainda é chamado aqui: não é seguro removê-lo isoladamente antes de substituir o fallback.

3. **Código legado de atualização, inativo mas ainda presente.** Launcher.ps1:5067–5233 contém UpdateWinPort (`UpdRun`, download por URL configurável, extração e substituição). A inicialização atual força UpdOn=false e limpa UpdUrl/UpdPass (:6678–6679), e o teste confirma que fica desabilitado. Ainda há campos na tela dev (:5669–5670) e ramo de inicialização (:6643) sem utilidade atual. Remover em conjunto código, campos, estado e chamadas; manter apenas o canal assinado RetroStation. Não confundir esse código inativo com o atualizador que está funcionando.

4. **Herança de launcher de recompilados.** Existem filtros Instalados/Não instalados (:2261, :4095), adição em massa da pasta Jogos (:4970 em diante), compactados, download de jogos por links e dependências VC++/DirectX de jogos (:6197 em diante). Vários ainda possuem chamadas em menus e compartilham verificações/índices com a biblioteca. São candidatos à separação ou remoção do produto Hydra, não funções comprovadamente mortas que possam ser apagadas em bloco. Remover primeiro as opções de interface redundantes, migrando filtros antigos para `all`; preservar os cálculos de biblioteca até os testes demonstrarem independência.

5. **Sobras pequenas comprovadas por busca no projeto.** HydraArtwork.ps1 inicializa `pythonProcess`/`usePython`, mas não inicia Python; o finally ainda tenta encerrar esse processo sempre nulo. FrontendUpdate.ps1 define `Read-FrontendStatus` sem chamadas no projeto. Setup.cs mantém condicionais para ASPECT_TEST, LIVE_TEST, LOCAL_FIRST, VISUAL_TEST, RELEASE_CANDIDATE e PS2_TEST, embora Build.ps1 compile somente STABLE_RELEASE. User-Agents de arte/detalhes ainda anunciam 1.4.2/1.3. Limpar e centralizar versão facilita manutenção, mas não reduz significativamente o instalador.

6. **Acúmulo local, separado do produto distribuído.** Na inspeção, build/ tinha 44 diretórios e 724 arquivos (~180 MiB), incluindo fixtures, estágios e cópias antigas. Está excluído por .gitignore e pelo empacotamento de fontes. Não foi apagado: contém evidências, backups e a cópia usada no teste online. No programa instalado, cada verificação cria Cache/Update/<GUID>; a rotina atual não define retenção para essas pastas. Cada reinstalação também guarda backup dos arquivos sobrescritos, mesmo quando iguais. Recomenda-se retenção explícita e nunca remover instalador em execução, dados pessoais, artes, saves ou a única cópia recuperável.

## Validação executada

- 25 arquivos PowerShell analisados: zero erros de sintaxe; 407 definições de função encontradas (não equivale a 407 funções únicas ou necessariamente usadas).
- Update.Tests.ps1 passou: estáveis, ausência de downgrade, rejeição de produto/repositório incorretos, adulteração e bloqueio durante jogo/inicialização.
- Migration.Tests.ps1 passou: reaproveitamento de mídia/música/avatar, caminhos externos preservados, rollback de migração e rejeição de launcher não relacionado.
- Não houve nova publicação, remoção de arquivos, alteração em D:\Games\hydra nem implantação nesta revisão.

## Sequência recomendada

Corrigir recuperação de escrita; substituir fallback dependente de Python/Codex; retirar UpdateWinPort e opções herdadas com testes de configurações antigas; implementar bootstrapper pequeno com validação assinada, download temporário, nova tentativa e confirmação; testar instalação limpa e atualização separadamente. Publicar a próxima versão como nova release estável, sem substituir os arquivos da 1.5.1 já publicada.
