# Targino RetroStation

![Targino Social Media](assets/banner.png)

Frontend independente para **Hydra Frontend**, com biblioteca por sistemas, capas, busca, favoritos, controle, música e modo Big Picture. Não é o Hydra Launcher comercial. Versão 1.5.4: evolução do complemento TarginoLauncher 1.4.2 para Hydra; não confundir com o projeto de recompilados do Central Arquivista.

## Instalar

Escolha **WebSetup.exe** (instalador pequeno que baixa e verifica a última versão publicada) ou **Setup.exe** (pacote completo para instalação offline). O build local 1.5.4 só entra no atualizador online quando sua release for publicada. No instalador web, Baixar instalador → aguardar validação → Instalar. Não há download de jogos/BIOS/Hydra nem atualização diferencial. Correções de correspondência e artes neutras por plataforma: [1.5.4](docs/NOTAS-1.5.4.md). Histórico: [1.5.3](docs/NOTAS-1.5.3.md), [1.5.2](docs/NOTAS-1.5.2.md).

1. Instale e prepare o [Hydra oficial](https://hydrafrontend.com/) em uma pasta gravável.
2. Baixe o instalador em [Releases](https://github.com/timtompel/TarginoRetroStation/releases/latest).
3. Selecione a pasta que contém `hydra.exe`. Abra pelo atalho **Targino RetroStation**.
4. Forneça seus próprios jogos e BIOS. Somente sistemas com jogos reconhecidos aparecem.

**Não distribuímos Hydra, cores, jogos, BIOS, músicas ou saves.** O usuário é responsável pelos arquivos e pelas permissões aplicáveis. Não desative antivírus para instalar o frontend. O instalador atual não possui certificado Authenticode.

## Manual

Consulte o [manual completo](docs/Manual.html), também disponível offline no menu Filtros do programa. Explica instalação, BIOS, arquivos CUE/BIN, controles, personalização, música, saves, janela para OBS, artes e diagnóstico.

## Atualizações

Canal exclusivo `timtompel/TarginoRetroStation`. Apenas releases estáveis `vX.Y.Z`, com manifesto RSA-SHA256 e hash/tamanho do instalador verificados. Pré-visualizações e versões de teste não são instaladas. A verificação ocorre em segundo plano uma vez ao dia; a instalação exige confirmação e o fechamento do jogo. Verificação manual em **Filtros → Verificar atualizações do RetroStation…**.

Uma assinatura de manifesto não é um certificado Authenticode. Nenhum token GitHub ou chave privada acompanha o programa. Não use o repositório do Arquivista para este produto.

## Migrar do complemento antigo

Na primeira atualização, mantenha marcada a opção de reaproveitar e consolidar o antigo `TarginoLauncher`, dentro da mesma raiz Hydra. A origem precisa ser identificada como complemento Hydra; uma instalação do Arquivista não será migrada. Se só existir a pasta antiga, ela será renomeada sem duplicar a mídia. Se ambas existirem, os dados atuais do RetroStation prevalecem: arquivos antigos ausentes são transferidos, cópias idênticas são retiradas e versões diferentes são guardadas em um backup ZIP verificado. Os caminhos internos são ajustados, incluindo músicas e imagens pessoais. ROMs, BIOS e saves não são movidos. Arquivos desconhecidos da raiz e instaladores baixados não são apagados. A pasta antiga só é retirada quando vazia; arquivos bloqueados não são forçados. O backup fica em `TarginoRetroStation/Backups/Migracao-1.4.2`. Use o novo atalho após migrar.

## Compilar / publicar

Windows x64, Windows PowerShell 5.1 e compilador C# do .NET Framework 4.x. Execute `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File installer/Build.ps1`. Recursos de marca já estão incluídos; não é preciso Python para compilar. A versão atual é 1.5.2. A chave pública vem em `src/UpdatePublicKey.xml`; a privada do publicador é protegida por DPAPI e nunca faz parte deste projeto ou das releases. Não substitua a chave pública em futuras versões.

Os testes usam instalações sintéticas, sem ROMs ou BIOS reais. A aprovação desses testes não comprova compatibilidade de todos os jogos, placas ou cores. Não foram corrigidas as limitações conhecidas do modo Software do PS2 neste computador.

## Créditos

Projeto por **Targino Social Media**. [YouTube @targino.socialmedia](https://www.youtube.com/@targino.socialmedia). Avatar e banner fornecidos pelo autor. Hydra e os cores pertencem aos respectivos autores. Capas e logos são consultados no Libretro e mantêm os direitos de seus titulares; não vêm pré-baixados no instalador. TheGamesDB é opcional e exige chave do próprio usuário.

Esta versão continua utilizando código visual derivado do launcher PowerShell fornecido como referência pelo usuário (Central Arquivista). Os créditos devem ser mantidos. Não foi estabelecida licença geral de redistribuição do código de terceiros: a publicação pública do código derivado depende da confirmação dos direitos correspondentes. Não presumir que a ausência de licença autoriza reutilização.
