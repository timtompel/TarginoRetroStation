# Targino RetroStation 1.5.5 - limpeza e robustez do atualizador

VERSAO DE TESTE. Nao publicar como release ate passar no checklist (docs/CHECKLIST-TESTE-1.5.5.md).

## Atualizador
Cada redirecionamento do download e validado antes de conectar (HTTPS, hosts do GitHub, no maximo 5 saltos). A atualizacao agora mostra uma janela com o progresso do download e botao Cancelar; cancelar encerra sem mensagem de erro. Assinatura RSA, hash e tamanho continuam obrigatorios.

## Capas
Aliases embutidos sao montados uma unica vez. Novo arquivo opcional Dados\hydra-capas-aliases.json permite informar o nome Libretro de jogos sem capa (sem recompilar); ao mudar esse arquivo, apenas os jogos sem capa sao consultados de novo. Capas ja baixadas, favoritos, ROMs, BIOS e saves nao sao tocados. Ferramenta tools/Gerar-Relatorio-Capas.ps1 sugere nomes parecidos para os jogos sem capa.

## Remocao de codigo herdado
Removido o bloco de download pelo Telegram (inativo no RetroStation): janela Conectar ao Telegram, leitura de login, tdl e campos TdlPath/TelegramPath. O programa nao le nem grava dados do Telegram. Se voce conectou uma conta em algum teste antigo, apague TarginoRetroStation\Cache\Telegram e encerre a sessao no app do Telegram.

## Interno
Helper unico de SHA-256 para texto. Launcher.ps1 passou de 6305 para 5909 linhas.

Esta versao pertence somente a base. O build local nao equivale a publicacao do atualizador online.
