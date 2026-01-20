#!/bin/bash

GREEN='\033[1;32m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

# Variaveis Padrão
ARCH=$(uname -m)
UBUNTU_VERSION=$(lsb_release -sr)
ARQUIVO_VARIAVEIS="VARIAVEIS_INSTALACAO"
ip_atual=$(curl -s http://checkip.amazonaws.com)
default_apioficial_port=6000

if [ "$EUID" -ne 0 ]; then
  echo
  printf "${WHITE} >> Este script precisa ser executado como root ${RED}ou com privilégios de superusuário${WHITE}.\n"
  echo
  sleep 2
  exit 1
fi

# Função para manipular erros e encerrar o script
trata_erro() {
  printf "${RED}Erro encontrado na etapa $1. Encerrando o script.${WHITE}\n"
  exit 1
}

# Banner
banner() {
  clear
  printf "${BLUE}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                    INSTALADOR API OFICIAL                    ║"
  echo "║                                                              ║"
  echo "║                    MultiFlow System                          ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  printf "${WHITE}"
  echo
}

# Função de Reparo Crítico do Nginx (Limpa a linha include quebrada e links órfãos)
reparo_nginx_critico() {
  banner
  printf "${YELLOW} >> Executando Reparo Crítico de Configuração do Nginx...${WHITE}\n"
  
  # 1. Limpa links e arquivos órfãos (como o -oficial)
  printf "${WHITE} >> Removendo links simbólicos quebrados (e.g., -oficial)...${WHITE}\n"
  sudo rm -f /etc/nginx/sites-enabled/-oficial
  printf "${WHITE} >> Removendo arquivos de configuração órfãos (e.g., -oficial) em sites-available...${WHITE}\n"
  sudo rm -f /etc/nginx/sites-available/-oficial

  # 2. Remove a linha "include /etc/nginx/sites-enabled/-oficial;" do nginx.conf
  printf "${WHITE} >> Removendo a linha de inclusão quebrada do /etc/nginx/nginx.conf...${WHITE}\n"
  sudo sed -i '/include \/etc\/nginx\/sites-enabled\/-oficial;/d' /etc/nginx/nginx.conf
  
  printf "${GREEN} >> Reparo concluído. Testando a configuração do Nginx...${WHITE}\n"
  sudo nginx -t
  if [ $? -ne 0 ]; then
    printf "${RED} >> ERRO: O Nginx ainda não passou no teste de configuração após o reparo. Interrompendo a instalação.${WHITE}\n"
    printf "${YELLOW} >> Se este erro persistir, verifique a permissão do diretório /etc/nginx/sites-enabled.${WHITE}\n"
    exit 1
  fi
  printf "${GREEN} >> Nginx pronto. Continuando...${WHITE}\n"
  sleep 2
}

# Carregar variáveis
carregar_variaveis() {
  if [ -f "$ARQUIVO_VARIAVEIS" ]; then
    source "$ARQUIVO_VARIAVEIS"
  else
    empresa="multiflow"
    nome_titulo="MultiFlow"
    printf "${RED} >> ERRO: Arquivo VARIAVEIS_INSTALACAO não encontrado. Este script deve ser executado pelo instalador principal.${WHITE}\n"
    exit 1
  fi
}

# Função auxiliar para garantir subdominio_backend está carregado
carregar_subdominio_backend() {
  if [ -z "${subdominio_backend}" ]; then
    local backend_env_path="/home/deploy/${empresa}/backend/.env"
    if [ -f "${backend_env_path}" ]; then
      local subdominio_backend_full=$(grep "^BACKEND_URL=" "${backend_env_path}" 2>/dev/null | cut -d '=' -f2-)
      subdominio_backend=$(echo "${subdominio_backend_full}" | sed 's|https://||g' | sed 's|http://||g' | cut -d'/' -f1)
      # Salva para futuras execuções se carregado
      echo "subdominio_backend=${subdominio_backend}" >>$ARQUIVO_VARIAVEIS
    else
      printf "${RED} >> ERRO: Não foi possível encontrar o .env do backend para carregar o subdomínio principal.${WHITE}\n"
      exit 1
    fi
  fi
}

# Solicitar dados do subdomínio da API Oficial
solicitar_dados_apioficial() {
  local temp_subdominio_oficial
  banner
  printf "${WHITE} >> Insira o subdomínio da API Oficial (Ex: api.seusistema.com.br): \n"
  echo
  read -p "> " temp_subdominio_oficial
  echo

  # Limpar e salvar subdomínio (sem protocolo)
  subdominio_oficial=$(echo "${temp_subdominio_oficial}" | sed 's|https://||g' | sed 's|http://||g' | cut -d'/' -f1)

  printf "   ${WHITE}Subdominio API Oficial: ---->> ${YELLOW}${subdominio_oficial}\n"
  # Salvar a nova variável no arquivo de variáveis principal
  echo "subdominio_oficial=${subdominio_oficial}" >>$ARQUIVO_VARIAVEIS
}

# Validação de DNS
verificar_dns_apioficial() {
  banner
  printf "${WHITE} >> Verificando o DNS do subdomínio da API Oficial...\n"
  echo
  sleep 2

  if ! command -v dig &> /dev/null; then
    sudo apt-get update >/dev/null 2>&1
    sudo apt-get install dnsutils -y >/dev/null 2>&1
  fi

  local domain=${subdominio_oficial}
  local resolved_ip

  if [ -z "${domain}" ]; then
    printf "${RED} >> ERRO: Subdomínio da API Oficial está vazio. Revise o passo anterior.${WHITE}\n"
    exit 1
  fi

  # Consulta DNS (A record)
  resolved_ip=$(dig +short ${domain} @8.8.8.8)

  if [[ "${resolved_ip}" != "${ip_atual}"* ]] || [ -z "${resolved_ip}" ]; then
    echo "O domínio ${domain} (resolvido para ${resolved_ip}) não está apontando para o IP público atual (${ip_atual})."
    echo
    printf "${RED} >> ERRO: Verifique o apontamento de DNS do subdomínio: ${subdominio_oficial}${WHITE}\n"
    sleep 5
    exit 1
  else
    echo "Subdomínio ${domain} está apontando corretamente para o IP público da VPS."
    sleep 2
  fi
  echo
  printf "${WHITE} >> Continuando...\n"
  sleep 2
  echo
}

# Configurar Nginx para API Oficial
configurar_nginx_apioficial() {
  banner
  printf "${WHITE} >> Configurando Nginx para API Oficial...\n"
  echo

  local sites_available_path="/etc/nginx/sites-available/${empresa}-oficial"
  local sites_enabled_link="/etc/nginx/sites-enabled/${empresa}-oficial"

  # 1. Remove link simbólico anterior
  if [ -L "${sites_enabled_link}" ]; then
    printf "${YELLOW} >> Removendo link simbólico antigo em ${sites_enabled_link}...${WHITE}\n"
    sudo rm -f "${sites_enabled_link}"
  fi

  # 2. Remove o arquivo de configuração anterior
  if [ -f "${sites_available_path}" ]; then
    printf "${YELLOW} >> Removendo arquivo de configuração antigo em ${sites_available_path}...${WHITE}\n"
    sudo rm -f "${sites_available_path}"
  fi

  {
    local oficial_hostname=${subdominio_oficial}

    sudo su - root <<EOF
cat > ${sites_available_path} <<END
upstream oficial {
    server 127.0.0.1:${default_apioficial_port};
    keepalive 32;
}
server {
    server_name ${oficial_hostname};
    location / {
        proxy_pass http://oficial;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
        proxy_buffering on;
    }
}
END
ln -sf ${sites_available_path} ${sites_enabled_link}
EOF

    sleep 2
    # Recarrega Nginx antes de emitir o Certbot para que a nova config seja lida
    sudo systemctl reload nginx 

    banner
    printf "${WHITE} >> Emitindo SSL do https://${subdominio_oficial}...\n"
    echo
    local oficial_domain=${subdominio_oficial}
    
    if [ -z "${email_deploy}" ]; then
      printf "${RED} >> ERRO: O email para o Certbot (email_deploy) não foi encontrado.${WHITE}\n"
      exit 1
    fi

    printf "${WHITE} >> Executando: certbot -m ${email_deploy} --nginx --agree-tos -n -d ${oficial_domain}\n"
    sudo certbot -m "${email_deploy}" \
                 --nginx \
                 --agree-tos \
                 -n \
                 -d "${oficial_domain}"
    
    if [ $? -ne 0 ]; then
      printf "${RED} >> ERRO: Falha ao emitir o certificado SSL/TLS com Certbot para ${oficial_domain}.${WHITE}\n"
      printf "${YELLOW} >> Verifique se o DNS está totalmente propagado, se o email é válido e se o Nginx está funcionando corretamente.${WHITE}\n"
      exit 1
    fi

    sleep 2
  } || trata_erro "configurar_nginx_apioficial"
}

# Criar banco de dados para API Oficial
criar_banco_apioficial() {
  banner
  printf "${WHITE} >> Criando banco de dados 'oficialseparado' para API Oficial...\n"
  echo
  {
    if [ -z "${empresa}" ] || [ -z "${senha_deploy}" ]; then
      printf "${RED} >> ERRO: Variáveis 'empresa' ou 'senha_deploy' não estão definidas! Necessária para o banco de dados.${WHITE}\n"
      exit 1
    fi
    
    sudo -u postgres psql <<EOF
CREATE DATABASE oficialseparado WITH OWNER ${empresa};
\q
EOF
    printf "${GREEN} >> Banco de dados 'oficialseparado' criado e associado ao usuário '${empresa}' com sucesso!${WHITE}\n"
    sleep 2
  } || trata_erro "criar_banco_apioficial"
}

# Configurar arquivo .env da API Oficial
configurar_env_apioficial() {
  banner
  printf "${WHITE} >> Configurando arquivo .env da API Oficial...\n"
  echo
  {
    local backend_env_path="/home/deploy/${empresa}/backend/.env"
    local jwt_refresh_secret_backend=$(grep "^JWT_REFRESH_SECRET=" "${backend_env_path}" 2>/dev/null | cut -d '=' -f2-)
    local backend_url_full=$(grep "^BACKEND_URL=" "${backend_env_path}" 2>/dev/null | cut -d '=' -f2-)
    
    if [ -z "${jwt_refresh_secret_backend}" ] || [ -z "${backend_url_full}" ]; then
      printf "${RED} >> ERRO: Não foi possível obter JWT_REFRESH_SECRET ou BACKEND_URL do backend principal.${WHITE}\n"
      exit 1
    fi

    local api_oficial_dir="/home/deploy/${empresa}/api_oficial"
    
    mkdir -p "${api_oficial_dir}"
    chown -R deploy:deploy "${api_oficial_dir}"
    
    sudo -u deploy cat > "${api_oficial_dir}/.env" <<EOF
# Configurações de acesso ao Banco de Dados (Postgres)
DATABASE_LINK=postgresql://${empresa}:${senha_deploy}@localhost:5432/oficialseparado?schema=public
DATABASE_URL=localhost
DATABASE_PORT=5432
DATABASE_USER=${empresa}
DATABASE_PASSWORD=${senha_deploy}
DATABASE_NAME=oficialseparado

# Configurações do MultiFlow Backend (URL Completa com https://)
TOKEN_ADMIN=adminpro
URL_BACKEND_MULT100=${backend_url_full}
JWT_REFRESH_SECRET=${jwt_refresh_secret_backend}

# Configurações da API Oficial
REDIS_URI=redis://:${senha_deploy}@127.0.0.1:6379
PORT=${default_apioficial_port}
# URL_API_OFICIAL deve ser a URL limpa (sem https://)
URL_API_OFICIAL=${subdominio_oficial}

# Configurações de Usuário Inicial
NAME_ADMIN=SetupAutomatizado
EMAIL_ADMIN=admin@multi100.com.br
PASSWORD_ADMIN=adminpro
EOF

    printf "${GREEN} >> Arquivo .env da API Oficial configurado com sucesso!${WHITE}\n"
    sleep 2
  } || trata_erro "configurar_env_apioficial"
}

# Instalar e configurar API Oficial
instalar_apioficial() {
  banner
  printf "${WHITE} >> Instalando e configurando API Oficial...\n"
  echo
  {
    local api_oficial_dir="/home/deploy/${empresa}/api_oficial"
    
    # Assumimos que o código-fonte já foi clonado
    chown -R deploy:deploy "${api_oficial_dir}"

    sudo su - deploy <<INSTALL_API
export PATH=/usr/bin:/usr/local/bin:\$PATH

cd ${api_oficial_dir}

printf "${WHITE} >> Instalando dependências (npm install)...\n"
npm install --force

printf "${WHITE} >> Gerando Prisma (npx prisma generate)...\n"
npx prisma generate

printf "${WHITE} >> Buildando aplicação (npm run build)...\n"
npm run build

printf "${WHITE} >> Executando migrações (npx prisma migrate deploy)...\n"
npx prisma migrate deploy

printf "${WHITE} >> Gerando cliente Prisma (npx prisma generate client)...\n"
npx prisma generate client

printf "${WHITE} >> Iniciando aplicação com PM2...\n"
pm2 start dist/main.js --name=api_oficial
pm2 save

printf "${GREEN} >> API Oficial instalada e configurada com sucesso!${WHITE}\n"
sleep 2
INSTALL_API
  } || trata_erro "instalar_apioficial"
}

# Atualizar .env do backend com URL da API Oficial
atualizar_env_backend() {
  banner
  printf "${WHITE} >> Atualizando .env do backend com URL da API Oficial...\n"
  echo
  {
    local backend_env_path="/home/deploy/${empresa}/backend/.env"
    
    local new_url="URL_API_OFICIAL=https://${subdominio_oficial}"
    
    # 1. Ativa USE_WHATSAPP_OFICIAL
    if ! grep -q "^USE_WHATSAPP_OFICIAL=true" "${backend_env_path}"; then
      sudo sed -i 's|^USE_WHATSAPP_OFICIAL=.*|USE_WHATSAPP_OFICIAL=true|' "${backend_env_path}" || echo "USE_WHATSAPP_OFICIAL=true" | sudo tee -a "${backend_env_path}" >/dev/null
    fi

    # 2. Substitui ou adiciona URL_API_OFICIAL
    if grep -q "^URL_API_OFICIAL=" "${backend_env_path}"; then
      sudo sed -i "s|^URL_API_OFICIAL=.*|${new_url}|" "${backend_env_path}"
    else
      echo "${new_url}" | sudo tee -a "${backend_env_path}" >/dev/null
    fi
    
    # 3. Reiniciar o Backend para carregar a nova variável
    sudo su - deploy <<RESTART_BACKEND
export PATH=/usr/bin:/usr/local/bin:\$PATH
pm2 reload ${empresa}-backend
RESTART_BACKEND

    printf "${GREEN} >> .env do backend atualizado e backend reiniciado com sucesso!${WHITE}\n"
    sleep 2
  } || trata_erro "atualizar_env_backend"
}

# Reiniciar serviços de Proxy
reiniciar_servicos() {
  banner
  printf "${WHITE} >> Reiniciando serviços de Proxy (Nginx/Traefik)...\n"
  echo
  {
    sudo su - root <<EOF
if systemctl is-active --quiet nginx; then
  sudo systemctl restart nginx
  printf "${GREEN}Nginx reiniciado.${WHITE}\n"
elif systemctl is-active --quiet traefik; then
  sudo systemctl restart traefik.service
  printf "${GREEN}Traefik reiniciado.${WHITE}\n"
else
  printf "${YELLOW}Nenhum serviço de proxy (Nginx ou Traefik) está em execução.${WHITE}\n"
fi
EOF
    printf "${GREEN} >> Serviços de Proxy concluído.${WHITE}\n"
    sleep 2
  } || trata_erro "reiniciar_servicos"
}

# Função principal
main() {
  # 1. Reparo Crítico no Nginx (Remove links e includes quebrados)
  reparo_nginx_critico
    
  # 2. Carregar variáveis do instalador principal (inclui empresa, email_deploy, senha_deploy)
  carregar_variaveis
  # 3. Garante que o subdomínio principal está carregado para configurar o .env da API Oficial
  carregar_subdominio_backend
    
  # 4. Coletar dados da nova API
  solicitar_dados_apioficial
    
  # 5. Verificar DNS
  verificar_dns_apioficial
    
  # 6. Configurar Proxy e SSL
  configurar_nginx_apioficial 
    
  # 7. Criar banco de dados
  criar_banco_apioficial
    
  # 8. Configurar variáveis de ambiente da API Oficial
  configurar_env_apioficial
    
  # 9. Instalar dependências e iniciar 
  instalar_apioficial
    
  # 10. Atualizar o backend principal para usar a nova API
  atualizar_env_backend
    
  # 11. Reiniciar serviços
  reiniciar_servicos
    
  banner
  printf "${GREEN} >> Instalação da API Oficial concluída com sucesso!${WHITE}\n"
  echo
  printf "${WHITE} >> API Oficial disponível em: ${YELLOW}https://${subdominio_oficial}${WHITE}\n"
  printf "${WHITE} >> Porta da API Oficial: ${YELLOW}${default_apioficial_port}${WHITE}\n"
  echo
  sleep 5
}

# Executar função principal
main
