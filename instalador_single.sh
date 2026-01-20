#!/bin/bash

# ----------------------------- CORES ------------------------------
GREEN='\033[1;32m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ------------------------- VARIÁVEIS BASE -------------------------
ARCH=$(uname -m)
UBUNTU_VERSION=$(lsb_release -sr)
ARQUIVO_VARIAVEIS="VARIAVEIS_INSTALACAO"
ARQUIVO_ETAPA="ETAPA_INSTALACAO"
ip_atual=$(curl -s http://checkip.amazonaws.com)

# portas padrão
BACKEND_PORT_DEFAULT=8080
FRONTEND_PORT_DEFAULT=3000
APIOFICIAL_PORT_DEFAULT=6000

# ------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo
  printf "${WHITE} >> Este script precisa ser executado como root ${RED}ou com privilégios de superusuário${WHITE}.\n"
  echo
  sleep 2
  exit 1
fi

# ------------------------------ BANNER -----------------------------
banner() {
  clear
  printf "${YELLOW}"
  printf "                        SISTEMA PARA MÚLTIPLOS ATENDIMENTOS \n" 
  printf "${GREEN} ███╗   ███╗ ██╗   ██╗  ██╗     ████████╗  ██╗   ██████████╗   █████╗    ██████╗  \n" 
  printf "${GREEN} ████╗ ████║ ██║   ██║  ██║     ╚══██╔══╝  ██║    ╚═══ ██╔╝   ██╔══██╗   ██╔══ ██╗ \n"
  printf "${GREEN} ██╔████╔██║ ██║   ██║  ██║        ██║     ██║      ██║       ████████   ███████╔╝   \n"
  printf "${GREEN} ██║╚██╔╝██║ ██║   ██║  ██║        ██║     ██║    ██║         ██╔══ ██║  ██ ╔═══╝   \n" 
  printf "${GREEN} ██║ ╚═╝ ██║ ╚██████╔╝  ███████╗   ██║     ██║   █████████    ██║   ██║  ██║       \n"
  printf "${GREEN} ╚═╝     ╚═╝ ╚═════╝    ╚══════╝   ╚═╝     ╚═╝  ╚   ═   ╝     ╚═╝   ╚═╝  ╚═╝     \n"  
  printf "\n" 
  printf "${NC}"
}

# -------------------------- TRATA ERRO ----------------------------
trata_erro() {
  printf "${RED} ❌ Erro na etapa: $1. Encerrando.${NC}\n"
  exit 1
}

# ----------------- CARREGAR / SALVAR VARIÁVEIS --------------------
carregar_variaveis() {
  if [ -f "$ARQUIVO_VARIAVEIS" ]; then
    source "$ARQUIVO_VARIAVEIS"
  fi
}

salvar_variaveis() {
  cat >$ARQUIVO_VARIAVEIS <<EOF
subdominio_backend=${subdominio_backend}
subdominio_frontend=${subdominio_frontend}
subdominio_oficial=${subdominio_oficial}
email_deploy=${email_deploy}
empresa=${empresa}
senha_deploy=${senha_deploy}
nome_titulo=${nome_titulo}
numero_suporte=${numero_suporte}
backend_port=${backend_port}
frontend_port=${frontend_port}
apioficial_port=${apioficial_port}
proxy=${proxy}
repo_url=${repo_url}
EOF
}

carregar_etapa() {
  if [ -f "$ARQUIVO_ETAPA" ]; then
    etapa=$(cat "$ARQUIVO_ETAPA")
  else
    etapa=0
  fi
}

salvar_etapa() {
  echo "$1" >"$ARQUIVO_ETAPA"
}

# ---------------------- PERGUNTAR VARIÁVEIS -----------------------
questoes_dns_base() {
  banner
  printf "${WHITE} >> Insira a URL do FRONTEND (ex: app.seusistema.com.br):\n${NC}"
  read -p "> " subdominio_frontend_raw
  subdominio_frontend=$(echo "${subdominio_frontend_raw}" | sed 's|https://||; s|http://||' | cut -d'/' -f1)

  banner
  printf "${WHITE} >> Insira a URL do BACKEND (ex: api.seusistema.com.br):\n${NC}"
  read -p "> " subdominio_backend_raw
  subdominio_backend=$(echo "${subdominio_backend_raw}" | sed 's|https://||; s|http://||' | cut -d'/' -f1)

  banner
  printf "${WHITE} >> Insira a URL da API OFICIAL (ex: oficial.seusistema.com.br):\n${NC}"
  read -p "> " subdominio_oficial_raw
  subdominio_oficial=$(echo "${subdominio_oficial_raw}" | sed 's|https://||; s|http://||' | cut -d'/' -f1)
}

questoes_variaveis_base() {
  banner
  # EMAIL padrão
  email_deploy="suporte@multiflow.app"

  # NOME DA INSTÂNCIA
  printf "${WHITE} >> Digite o nome da instância (letras minúsculas e sem espaço, ex: empresa01): \n"
  read -p "> " empresa

  # SENHAS E TÍTULO PADRÃO
  senha_deploy="12243648"
  nome_titulo="MultiFlow"
  numero_suporte=""
  
  # GitHub e Repo fixos
  github_token=""
  repo_url="https://github.com/siteconnect/oficialflow-100.1.git"
}

define_proxy_base() {
  proxy="nginx"
}

define_portas_base() {
  backend_port=${BACKEND_PORT_DEFAULT}
  frontend_port=${FRONTEND_PORT_DEFAULT}
  apioficial_port=${APIOFICIAL_PORT_DEFAULT}
  
  jwt_secret=$(openssl rand -base64 32)
  jwt_refresh_secret=$(openssl rand -base64 32)
}

# --------------------- MOSTRA RESUMO E CONFIRMA -------------------
confirmar_dados() {
  banner
  printf "${WHITE} >> Confira os dados da instalação:\n\n"
  printf "   Subdomínio FRONTEND:  ${YELLOW}%s${NC}\n" "$subdominio_frontend"
  printf "   Subdomínio BACKEND:   ${YELLOW}%s${NC}\n" "$subdominio_backend"
  printf "   Subdomínio API OFICIAL: ${YELLOW}%s${NC}\n" "$subdominio_oficial"
  printf "   Email Certbot:        ${YELLOW}%s${NC}\n" "$email_deploy"
  printf "   Empresa/Pasta:        ${YELLOW}%s${NC}\n" "$empresa"
  printf "   Senha Deploy/BD:      ${YELLOW}%s${NC}\n" "$senha_deploy"
  printf "   Título App:           ${YELLOW}%s${NC}\n" "$nome_titulo"
  printf "   Proxy:                ${YELLOW}%s${NC}\n" "$proxy"
  printf "   URL Repositório:      ${YELLOW}%s${NC}\n\n" "$repo_url"

  printf "${GREEN} >> Continuando a Instalação automaticamente... ${NC}\n"
  sleep 3
}

# ------------------------ VERIFICA DNS ----------------------------
verificar_dns() {
  banner
  printf "${WHITE} >> Verificando apontamento DNS dos domínios...\n${NC}"
  sleep 2

  if ! command -v dig &>/dev/null; then
    apt-get update -y >/dev/null 2>&1
    apt-get install -y dnsutils >/dev/null 2>&1
  fi

  local domains=("$subdominio_frontend" "$subdominio_backend" "$subdominio_oficial")
  for domain in "${domains[@]}"; do
    resolved_ip=$(dig +short "$domain" | tail -n1)
    if [ "$resolved_ip" != "$ip_atual" ]; then
      printf "${RED} >> Erro: O domínio ${domain} não aponta para o IP ${ip_atual}.${NC}\n"
      exit 1
    fi
  done
  printf "${GREEN} >> DNS OK para todos os domínios.${NC}\n"
}

# ----------------- ATUALIZA VPS + PACOTES BASE --------------------
atualiza_vps() {
  banner
  printf "${WHITE} >> Atualizando sistema e pacotes base...\n${NC}"
  DEBIAN_FRONTEND=noninteractive apt-get update -y || trata_erro "apt update"
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || trata_erro "apt upgrade"
  DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential curl wget git ufw snapd ca-certificates gnupg software-properties-common lsof htop || trata_erro "pacotes base"
}

# --------------------------- USUÁRIO DEPLOY -----------------------
cria_usuario_deploy() {
  banner
  printf "${WHITE} >> Criando usuário 'deploy'...\n${NC}"
  if id "deploy" &>/dev/null; then
    printf "${YELLOW} >> Usuário deploy já existe.${NC}\n"
  else
    useradd -m -p "$(openssl passwd -1 "${senha_deploy}")" -s /bin/bash -G sudo deploy || trata_erro "cria deploy"
  fi
  usermod -aG sudo deploy || true
}

# --------------------------- TIMEZONE -----------------------------
config_timezone() {
  timedatectl set-timezone America/Sao_Paulo || trata_erro "timezone"
}

# ---------------------------- FIREWALL ----------------------------
config_firewall() {
  if command -v ufw &>/dev/null; then
    ufw allow 22/tcp || true
    ufw allow 80/tcp || true
    ufw allow 443/tcp || true
    ufw --force enable || true
  fi
}

# --------------------------- POSTGRES -----------------------------
instala_postgres() {
  banner
  printf "${WHITE} >> Instalando PostgreSQL 17...\n${NC}"
  sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
  wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - >/dev/null 2>&1
  apt-get update -y >/dev/null 2>&1
  apt-get install -y postgresql-17 || trata_erro "instala_postgres"

  sudo -u postgres psql <<EOF
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${empresa}') THEN
      CREATE ROLE ${empresa} LOGIN PASSWORD '${senha_deploy}';
   END IF;
END \$\$;
CREATE DATABASE ${empresa} OWNER ${empresa};
EOF
}

# ---------------------------- REDIS -------------------------------
instala_redis() {
  banner
  printf "${WHITE} >> Instalando Redis...\n${NC}"
  apt-get install -y redis-server || trata_erro "redis install"
  sed -i "s/^# requirepass .*/requirepass ${senha_deploy}/" /etc/redis/redis.conf
  systemctl restart redis-server
}

# ----------------------------- NODEJS -----------------------------
instala_node() {
  banner
  printf "${WHITE} >> Instalando Node.js 22.x...\n${NC}"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs || trata_erro "nodejs"
}

# ------------------------------ PM2 -------------------------------
instala_pm2() {
  npm install -g pm2 || trata_erro "pm2 install"
  su - deploy -c "pm2 startup systemd -u deploy --hp /home/deploy" || true
}

# ------------------------------ NGINX -----------------------------
instala_nginx() {
  apt-get install -y nginx || trata_erro "nginx"
  rm -f /etc/nginx/sites-enabled/default
  snap install --classic certbot || true
  ln -sf /snap/bin/certbot /usr/bin/certbot || true
}

# ---------------------------- CLONE REPO --------------------------
clona_codigo() {
  banner
  printf "${WHITE} >> Clonando código do repositório privado...\n${NC}"
  
  dest_dir="/home/deploy/${empresa}"
  mkdir -p "${dest_dir}"
  
  if [ -z "$(ls -A "${dest_dir}" 2>/dev/null)" ]; then
    git clone "${repo_url}" "${dest_dir}" || trata_erro "git clone"
  fi

  chown -R deploy:deploy "${dest_dir}"
  chmod -R 775 "${dest_dir}"
}

# ------------------------- GERA .ENV ------------------------------
gera_envs() {
  banner
  printf "${WHITE} >> Gerando arquivos .env...\n${NC}"
  
  # Exemplo Backend
  cat > "/home/deploy/${empresa}/backend/.env" <<EOF
NODE_ENV=production
BACKEND_URL=https://${subdominio_backend}
FRONTEND_URL=https://${subdominio_frontend}
DB_HOST=localhost
DB_USER=${empresa}
DB_PASS=${senha_deploy}
DB_NAME=${empresa}
JWT_SECRET=${jwt_secret}
JWT_REFRESH_SECRET=${jwt_refresh_secret}
EOF
  chown deploy:deploy "/home/deploy/${empresa}/backend/.env"
}

# ------------------------- NGINX CONFIG ---------------------------
config_nginx() {
  banner
  printf "${WHITE} >> Configurando Nginx e SSL...\n${NC}"
  
  cat > /etc/nginx/sites-available/${empresa} <<EOF
server {
    server_name ${subdominio_frontend};
    location / {
        proxy_pass http://127.0.0.1:${frontend_port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/${empresa} /etc/nginx/sites-enabled/
  systemctl reload nginx
  
  certbot --nginx -m "${email_deploy}" --agree-tos -n -d "${subdominio_frontend}" -d "${subdominio_backend}" -d "${subdominio_oficial}"
}

# --------------------------- FINALIZAÇÃO --------------------------
finaliza() {
  banner
  printf "${GREEN} ✅ Instalação concluída com sucesso!\n\n${NC}"
  printf "${WHITE}Frontend: https://${subdominio_frontend}\n"
  printf "Backend:  https://${subdominio_backend}\n"
}

# ==================================================================
#                            EXECUÇÃO
# ==================================================================
carregar_etapa
if [ "$etapa" == "0" ]; then
  questoes_dns_base
  verificar_dns
  questoes_variaveis_base
  define_proxy_base
  define_portas_base
  confirmar_dados
  salvar_variaveis
  salvar_etapa 1
fi

atualiza_vps
cria_usuario_deploy
config_timezone
config_firewall
instala_postgres
instala_redis
instala_node
instala_pm2
instala_nginx
clona_codigo
gera_envs
config_nginx
finaliza
