# Targino RetroStation 1.5.1

- Corrigido o conflito de foco que fazia o menu lateral aparecer e sumir. Alternar para o visual clássico agora restaura busca/filtros e mantém o menu Big Picture oculto.

- Migração única do complemento Hydra 1.4.2: se apenas a pasta TarginoLauncher existir, ela é renomeada e reaproveitada, sem copiar todas as artes novamente.
- Se as duas pastas existirem, a configuração atual do RetroStation é preservada e os arquivos antigos ausentes são transferidos. Arquivos idênticos são deduplicados; versões diferentes são preservadas em backup ZIP verificado antes de retirar a cópia antiga.
- Caminhos internos de capas, fundos, avatares e músicas são ajustados. Arquivos externos não são renomeados. Imagens pessoais já existentes não são substituídas pelo visual padrão.
- O comando antigo Abrir-TarginoLauncher.cmd só é retirado se identificado como apontando para a instalação antiga e após backup. Instaladores baixados pelo usuário e arquivos desconhecidos da raiz não são apagados.
- Aviso de versão estável com novidades e escolha explícita entre Atualizar agora e Agora não. Adiar não baixa nem instala nada. Jogos abertos ou iniciando impedem a atualização.

A migração é exclusiva do complemento Hydra: o Arquivista não é migrado. ROMs, BIOS, saves, Hydra e cores ficam fora da atualização. O pacote não fornece esses arquivos nem credenciais padrão de desenvolvedor.

Faça backup dos seus dados e feche os jogos antes de atualizar. O instalador não possui certificado Authenticode; o canal online usa manifesto RSA-SHA256 e verifica tamanho e SHA256.
