# Targino RetroStation 1.5.3 — correção das artes

- Busca de capas trata diferenças de espaços, hífens e região, sem usar rótulos da interface como parte do título.
- Removida a escolha por prefixo que poderia confundir um jogo com sua continuação. A busca permanece restrita ao sistema correto.
- Resultados antigos sem correspondência são pesquisados novamente uma vez na migração e, depois, a cada 24 horas. Índices de capas também são renovados; downloads já válidos são preservados.
- Corrigida a diferença de versão de transporte entre a interface e o processo de download, respeitando a espera de 30 minutos em falhas.
- Contadores consideram apenas os itens do catálogo atual, sem somar jogos removidos ou duplicados antigos.
- PacMan de 3DO recebe uma imagem alternativa de gameplay publicada pelo Archive3DO quando não há capa na Libretro. A origem é registrada como captura, não como capa oficial: https://archive3do.com/software-preservation-center/

Atualização exclusiva da edição base. Não inclui recursos de download de jogos da Premium. Não acompanha Hydra, cores, ROMs, BIOS, saves ou credenciais. Configurações, favoritos e mídias locais permanecem preservados.

Instaladores sem certificado Authenticode. O atualizador continua validando manifesto assinado RSA-SHA256, tamanho e SHA256 do pacote e solicita confirmação antes de instalar.
