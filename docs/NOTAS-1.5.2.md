# Targino RetroStation 1.5.2

- Instalador web (bootstrapper) de aproximadamente 200 KiB: consulta somente a última release estável, baixa o Setup, verifica assinatura RSA-SHA256, tamanho e SHA256 e oferece Instalar. Há cancelamento e nova tentativa; instalação offline continua disponível. Não é atualização diferencial.
- Gravação dos arquivos do instalador em temporários validados antes da substituição; falhas de cópia e hash preservam o original. Reinstalação não cria backups de arquivos idênticos. Backups anteriores não são apagados.
- Artes e capturas compartilham alternativas HTTPS nativas, sem Python nem caminhos de desenvolvimento Codex. O helper antigo conhecido é retirado da pasta ativa para backup; versões modificadas pelo usuário são preservadas.
- Retirados UpdateWinPort, seus campos na tela de desenvolvimento, adição em massa de recompilados e instalação de runtimes de jogos. Recursos compartilhados de biblioteca e compatibilidade de configurações permanecem; não se trata de uma reescrita completa da base visual.
- Filtros Instalados/Não instalados removidos; seleções antigas voltam para Todos os jogos. O menu de contexto do Hydra não oferece downloads, extração ou exclusão de jogos.
- Cache de atualização conserva as três sessões mais recentes. Só sessões concluídas há mais de 30 dias, sem processo ativo, links ou arquivos desconhecidos, são retiradas. Backups, artes e dados pessoais ficam fora dessa limpeza.
- Limite de pacote aumentado para 512 MiB nos novos clientes; versões 1.5.0/1.5.1 ainda precisam receber uma atualização menor que 64 MiB antes de pacotes maiores.

Preservados retorno à biblioteca, músicas, janela para OBS, Big Picture, configurações pessoais e migração da 1.4.2. Hydra, ROMs, BIOS, cores e saves não acompanham o instalador e não são atualizados. O instalador não tem certificado Authenticode.
