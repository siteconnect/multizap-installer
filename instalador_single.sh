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
ip_atual=$(curl -s http://checkip.amazonaws.com)

# portas padrão
BACKEND_PORT_DEFAULT=4000
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
  printf "${YELLOW}";


printf ${YELLOW}"                        SISTEMA PARA MÚLTIPLOS ATENDIMENTOS \n" 
printf ${GREEN}" ███╗   ███╗ ██╗   ██╗  ██╗     ████████╗  ██╗   ██████████╗   █████╗    ██████╗  \n" 
printf ${GREEN}" ████╗ ████║ ██║   ██║  ██║     ╚══██╔══╝  ██║    ╚═══ ██╔╝   ██╔══██╗   ██╔══ ██╗ \n"
printf ${GREEN}" ██╔████╔██║ ██║   ██║  ██║        ██║     ██║      ██║       ████████   ███████╔╝   \n"
printf ${GREEN}" ██║╚██╔╝██║ ██║   ██║  ██║        ██║     ██║    ██║         ██╔══ ██║  ██ ╔═══╝   \n" 
printf ${GREEN}" ██║ ╚═╝ ██║ ╚██████╔╝  ███████╗   ██║     ██║   █████████    ██║   ██║  ██║       \n"
printf ${GREEN}" ╚═╝     ╚═╝ ╚═════╝    ╚══════╝   ╚═╝     ╚═╝  ╚   ═   ╝     ╚═╝   ╚═╝  ╚═╝     \n"  
printf "\n" 
                                                                                                                                                         
printf "            \033[1;33m        ";
printf "${NC}";

printf "\n"
}

# -------------------------- TRATA ERRO ----------------------------
trata_erro() {
  printf "${RED} ❌ Erro na etapa: $1. Encerrando.${NC}\n"
  exit 1
}

# ---------------------- PERGUNTAR VARIÁVEIS -----------------------
perguntas_iniciais() {
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

  banner
  printf "${WHITE} >> Digite o seu melhor email (usado no Certbot/SSL):\n${NC}"
  read -p "> " email_deploy

  banner
  printf "${WHITE} >> Nome da empresa/pasta (sem espaço, ex: empresa01):\n${NC}"
  read -p "> " empresa

  banner
  printf "${WHITE} >> Senha para usuário deploy / Redis / BD (sem caracteres especiais):\n${NC}"
  read -p "> " senha_deploy

  banner
  printf "${WHITE} >> Título da aplicação (aparece no navegador, pode ter espaço):\n${NC}"
  read -p "> " nome_titulo

  banner
  printf "${WHITE} >> Número de telefone para suporte (só números):\n${NC}"
  read -p "> " numero_suporte

  # Removido perguntas de GitHub Token e Repo URL conforme solicitado
  github_token=""
  repo_url=""

  # portas (fixas)
  backend_port=${BACKEND_PORT_DEFAULT}
  frontend_port=${FRONTEND_PORT_DEFAULT}
  apioficial_port=${APIOFICIAL_PORT_DEFAULT}

  # gerar JWTs
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
  printf "   Senha deploy/Redis/BD:${YELLOW}%s${NC}\n" "$senha_deploy"
  printf "   Título App:            ${YELLOW}%s${NC}\n" "$nome_titulo"
  printf "   Telefone Suporte:     ${YELLOW}%s${NC}\n" "$numero_suporte"
  printf "   Porta Backend:        ${YELLOW}%s${NC}\n" "$backend_port"
  printf "   Porta Frontend:       ${YELLOW}%s${NC}\n" "$frontend_port"
  printf "   Porta APIOficial:     ${YELLOW}%s${NC}\n\n" "$apioficial_port"

  printf "${WHITE} >> Os dados estão corretos? (S/N): ${NC}"
  read -p "" confirmacao
  confirmacao=$(echo "$confirmacao" | tr '[:lower:]' '[:upper:]')

  if [ "$confirmacao" != "S" ]; then
    printf "\n${YELLOW} >> Operação cancelada pelo usuário.${NC}\n"
    exit 0
  fi

  # salvar variáveis
  cat > "$ARQUIVO_VARIAVEIS" <<EOF
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
EOF
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

  local invalids=""

  for domain in "$subdominio_frontend" "$subdominio_backend" "$subdominio_oficial"; do
    resolved_ip=$(dig +short "$domain" @8.8.8.8 | head -n1)
    if [ -z "$resolved_ip" ] || [ "$resolved_ip" != "$ip_atual" ]; then
      invalids="$invalids $domain"
      echo " - ${domain} -> ${resolved_ip:-N/A} (IP da VPS: ${ip_atual})"
    fi
  done

  if [ -n "$invalids" ]; then
    echo
    printf "${YELLOW} >> Alguns domínios não parecem apontar para o IP desta VPS.${NC}\n"
    printf "${WHITE} >> Deseja continuar MESMO ASSIM? (S/N): ${NC}"
    read -p "" cont
    cont=$(echo "$cont" | tr '[:lower:]' '[:upper:]')
    if [ "$cont" != "S" ]; then
      printf "${RED} >> Instalação cancelada por DNS incorreto.${NC}\n"
      exit 1
    fi
  else
    printf "${GREEN} >> DNS OK para todos os domínios.${NC}\n"
  fi
  sleep 2
}

# ----------------- ATUALIZA VPS + PACOTES BASE --------------------
atualiza_vps() {
  banner
  printf "${WHITE} >> Atualizando sistema e pacotes base...\n${NC}"
  DEBIAN_FRONTEND=noninteractive apt-get update -y || trata_erro "apt update"
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || trata_erro "apt upgrade"
  DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential curl wget git ufw snapd ca-certificates || trata_erro "pacotes base"
}

# --------------------------- USUÁRIO DEPLOY -----------------------
cria_usuario_deploy() {
  banner
  printf "${WHITE} >> Criando usuário 'deploy'...\n${NC}"

  if id "deploy" &>/dev/null; then
    printf "${YELLOW} >> Usuário deploy já existe. Pulando criação.${NC}\n"
  else
    useradd -m -p "$(openssl passwd -1 "${senha_deploy}")" -s /bin/bash -G sudo deploy || trata_erro "cria deploy"
  fi

  usermod -aG sudo deploy || true
  sleep 1
}

# --------------------------- TIMEZONE -----------------------------
config_timezone() {
  banner
  printf "${WHITE} >> Configurando timezone America/Sao_Paulo...\n${NC}"
  timedatectl set-timezone America/Sao_Paulo || trata_erro "timezone"
}

# ---------------------------- FIREWALL ----------------------------
config_firewall() {
  banner
  printf "${WHITE} >> Abrindo portas 22, 80 e 443 no firewall...\n${NC}"

  if command -v ufw &>/dev/null; then
    ufw allow 22/tcp || true
    ufw allow 80/tcp || true
    ufw allow 443/tcp || true
  fi
  sleep 1
}

# --------------------------- POSTGRES -----------------------------
instala_postgres() {
  banner
  printf "${WHITE} >> Instalando PostgreSQL 17...\n${NC}"

  apt-get install -y gnupg >/dev/null 2>&1
  sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
  wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - >/dev/null 2>&1
  apt-get update -y >/dev/null 2>&1
  apt-get install -y postgresql-17 || trata_erro "instala_postgres"

  sudo -u postgres psql <<EOF
DO
\$do\$
BEGIN
   IF NOT EXISTS (
      SELECT
      FROM   pg_catalog.pg_roles
      WHERE  rolname = '${empresa}') THEN

      CREATE ROLE ${empresa} LOGIN PASSWORD '${senha_deploy}';
   END IF;
END
\$do\$;

CREATE DATABASE ${empresa} OWNER ${empresa};
EOF
}

# ---------------------------- REDIS -------------------------------
instala_redis() {
  banner
  printf "${WHITE} >> Instalando Redis...\n${NC}"

  apt-get install -y redis-server || trata_erro "redis install"
  sed -i "s/^# requirepass .*/requirepass ${senha_deploy}/" /etc/redis/redis.conf
  sed -i "s/^appendonly no/appendonly yes/" /etc/redis/redis.conf
  systemctl enable redis-server
  systemctl restart redis-server
}

# ----------------------------- NODEJS -----------------------------
instala_node() {
  banner
  printf "${WHITE} >> Instalando Node.js 22.x (NodeSource)...\n${NC}"

  # Remove entradas antigas do NodeSource, se existirem
  rm -f /etc/apt/sources.list.d/nodesource.list 2>/dev/null

  # Adiciona repositório do Node 22.x
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - || trata_erro "nodesource"

  apt-get update -y >/dev/null 2>&1
  apt-get install -y nodejs build-essential gcc g++ make || trata_erro "nodejs"

  printf "${WHITE} >> Versões instaladas:\n"
  printf "     node: ${YELLOW}$(node -v 2>/dev/null)${WHITE}\n"
  printf "     npm:  ${YELLOW}$(npm -v 2>/dev/null)${NC}\n"
}

# ------------------------------ PM2 -------------------------------
instala_pm2() {
  banner
  printf "${WHITE} >> Instalando PM2...\n${NC}"

  npm install -g pm2 || trata_erro "pm2 install"
  pm2 --version || trata_erro "pm2 check"

  if id "deploy" &>/dev/null; then
    su - deploy -c "pm2 startup systemd -u deploy --hp /home/deploy" || true
  fi
}

# ------------------------------ NGINX -----------------------------
instala_nginx() {
  banner
  printf "${WHITE} >> Instalando Nginx + Certbot...\n${NC}"

  apt-get install -y nginx || trata_erro "nginx"
  rm -f /etc/nginx/sites-enabled/default

  apt-get install -y snapd >/dev/null 2>&1 || true
  snap install core >/dev/null 2>&1 || true
  snap refresh core >/dev/null 2>&1 || true

  apt-get remove -y certbot >/dev/null 2>&1 || true
  snap install --classic certbot >/dev/null 2>&1 || true
  ln -sf /snap/bin/certbot /usr/bin/certbot || true

  systemctl enable nginx
  systemctl restart nginx
}

# ------------------------------ GIT -------------------------------
instala_git() {
  banner
  printf "${WHITE} >> Garantindo Git instalado...\n${NC}"
  apt-get install -y git || trata_erro "git"
}

# ---------------------------- CLONE REPO --------------------------
clona_codigo() {
  banner
  printf "${WHITE} >> Clonando código do repositório privado...\n${NC}"

  BASE_DIR="/home/deploy/${empresa}"
  REPO_DIR="${BASE_DIR}/repo"

  # Nota: Se github_token estiver vazio, a clonagem falhará para repos privados.
  # Adicione o token no início do script se não for perguntar.
  REPO_URL_AUTH=$(echo "$repo_url" | sed "s|https://|https://${github_token}@|")

  mkdir -p "$BASE_DIR"
  chown -R deploy:deploy "$BASE_DIR"

  su - deploy <<EOF
set -e
mkdir -p "${REPO_DIR}"
cd "${BASE_DIR}"

if [ -d "${REPO_DIR}/.git" ]; then
  echo ">> Repositório já existe, executando git pull..."
  cd "${REPO_DIR}"
  git pull
else
  echo ">> Clonando repositório..."
  # Se repo_url estiver vazio, isso dará erro.
  if [ -z "${repo_url}" ]; then
     echo "ERRO: URL do repositório não definida."
     exit 1
  fi
  git clone "${REPO_URL_AUTH}" repo
fi
EOF

  # mover backend/frontend/api_oficial
  if [ ! -d "${REPO_DIR}/backend" ] || [ ! -d "${REPO_DIR}/frontend" ]; then
    printf "${RED} >> ERRO: Repo não contém pastas backend/ e frontend/ esperadas.${NC}\n"
    exit 1
  fi

  mv "${REPO_DIR}/backend" "${BASE_DIR}/backend"
  mv "${REPO_DIR}/frontend" "${BASE_DIR}/frontend"

  if [ -d "${REPO_DIR}/api_oficial" ]; then
    mv "${REPO_DIR}/api_oficial" "${BASE_DIR}/api_oficial"
  fi

  chown -R deploy:deploy "${BASE_DIR}"
}

# ------------------------ CRIA BANCO APIOFICIAL -------------------
cria_banco_apioficial() {
  banner
  printf "${WHITE} >> Criando banco 'oficialseparado' para API Oficial...\n${NC}"

  sudo -u postgres psql <<EOF
DO
\$do\$
BEGIN
   IF NOT EXISTS (
      SELECT
      FROM   pg_database
      WHERE  datname = 'oficialseparado') THEN
      CREATE DATABASE oficialseparado OWNER ${empresa};
   END IF;
END
\$do\$;
EOF
}

# ------------------------- GERA .ENV BACKEND ----------------------
gera_env_backend() {
  banner
  printf "${WHITE} >> Gerando .env do backend...\n${NC}"

  BACKEND_DIR="/home/deploy/${empresa}/backend"

  cat > "${BACKEND_DIR}/.env" <<EOF
NODE_ENV=production
BACKEND_URL=https://${subdominio_backend}
FRONTEND_URL=https://${subdominio_frontend}

DB_DIALECT=postgres
DB_HOST=localhost
DB_USER=${empresa}
DB_PASS=${senha_deploy}
DB_NAME=${empresa}
DB_PORT=5432

REDIS_URI=redis://:${senha_deploy}@127.0.0.1:6379
JWT_SECRET=${jwt_secret}
JWT_REFRESH_SECRET=${jwt_refresh_secret}

USE_WHATSAPP_OFICIAL=true
URL_API_OFICIAL=https://${subdominio_oficial}

MASTER_SECRET=${senha_deploy}
MASTER_AUTH=${senha_deploy}
MASTER_NAME=${nome_titulo}
MASTER_SUPORTE=${numero_suporte}
EOF

  chown deploy:deploy "${BACKEND_DIR}/.env"
}

# ----------------------- GERA .ENV FRONTEND -----------------------
gera_env_frontend() {
  banner
  printf "${WHITE} >> Gerando .env do frontend...\n${NC}"

  FRONTEND_DIR="/home/deploy/${empresa}/frontend"

  cat > "${FRONTEND_DIR}/.env" <<EOF
REACT_APP_BACKEND_URL=https://${subdominio_backend}
REACT_APP_FRONTEND_URL=https://${subdominio_frontend}
REACT_APP_TITLE=${nome_titulo}
EOF

  chown deploy:deploy "${FRONTEND_DIR}/.env"
}

# ----------------------- GERA .ENV API OFICIAL --------------------
gera_env_apioficial() {
  API_DIR="/home/deploy/${empresa}/api_oficial"
  [ -d "${API_DIR}" ] || return 0

  banner
  printf "${WHITE} >> Gerando .env da API Oficial...\n${NC}"

  cat > "${API_DIR}/.env" <<EOF
DATABASE_LINK=postgresql://${empresa}:${senha_deploy}@localhost:5432/oficialseparado?schema=public
DATABASE_URL=localhost
DATABASE_PORT=5432
DATABASE_USER=${empresa}
DATABASE_PASSWORD=${senha_deploy}
DATABASE_NAME=oficialseparado

TOKEN_ADMIN=adminpro
URL_BACKEND_MULT100=https://${subdominio_backend}
JWT_REFRESH_SECRET=${jwt_refresh_secret}

REDIS_URI=redis://:${senha_deploy}@127.0.0.1:6379
PORT=${apioficial_port}
URL_API_OFICIAL=${subdominio_oficial}

NAME_ADMIN=SetupAutomatizado
EMAIL_ADMIN=admin@multi100.com.br
PASSWORD_ADMIN=adminpro
EOF

  chown deploy:deploy "${API_DIR}/.env"
}

# --------------------------- BACKEND NPM --------------------------
instala_backend() {
  banner
  printf "${WHITE} >> Instalando dependências e build do backend...\n${NC}"

  BACKEND_DIR="/home/deploy/${empresa}/backend"

  su - deploy <<EOF
set -e
cd "${BACKEND_DIR}"
npm install --force
npm run db:migrate || npm run db:migrate:prod || true
npm run build
pm2 start dist/server.js --name=${empresa}-backend || pm2 start dist/main.js --name=${empresa}-backend
pm2 save
EOF
}

# -------------------------- FRONTEND NPM --------------------------
instala_frontend() {
  banner
  printf "${WHITE} >> Instalando dependências e build do frontend...\n${NC}"

  FRONTEND_DIR="/home/deploy/${empresa}/frontend"

  su - deploy <<EOF
set -e
cd "${FRONTEND_DIR}"
npm install --force
npm run build
EOF
}

# ------------------------ API OFICIAL NPM -------------------------
instala_api_oficial() {
  API_DIR="/home/deploy/${empresa}/api_oficial"
  [ -d "${API_DIR}" ] || return 0

  banner
  printf "${WHITE} >> Instalando dependências e subindo API Oficial...\n${NC}"

  su - deploy <<EOF
set -e
cd "${API_DIR}"
npm install --force
npx prisma generate || true
npm run build
npx prisma migrate deploy || true
pm2 start dist/main.js --name=${empresa}-apioficial
pm2 save
EOF
}

# ------------------------- NGINX CONFIG ---------------------------
config_nginx() {
  banner
  printf "${WHITE} >> Configurando Nginx para frontend, backend e API Oficial...\n${NC}"

  FRONTEND_ROOT="/home/deploy/${empresa}/frontend/build"

  # FRONTEND
  cat > /etc/nginx/sites-available/${empresa}-frontend <<EOF
server {
    server_name ${subdominio_frontend};

    root ${FRONTEND_ROOT};
    index index.html;

    location / {
        try_files \$uri /index.html;
    }

    location /api {
        proxy_pass http://127.0.0.1:${backend_port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

  # BACKEND puro
  cat > /etc/nginx/sites-available/${empresa}-backend <<EOF
upstream ${empresa}_backend {
    server 127.0.0.1:${backend_port};
    keepalive 32;
}

server {
    server_name ${subdominio_backend};

    location / {
        proxy_pass http://${empresa}_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

  # API OFICIAL
  cat > /etc/nginx/sites-available/${empresa}-apioficial <<EOF
upstream ${empresa}_apioficial {
    server 127.0.0.1:${apioficial_port};
    keepalive 32;
}

server {
    server_name ${subdominio_oficial};

    location / {
        proxy_pass http://${empresa}_apioficial;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

  ln -sf /etc/nginx/sites-available/${empresa}-frontend /etc/nginx/sites-enabled/${empresa}-frontend
  ln -sf /etc/nginx/sites-available/${empresa}-backend /etc/nginx/sites-enabled/${empresa}-backend
  ln -sf /etc/nginx/sites-available/${empresa}-apioficial /etc/nginx/sites-enabled/${empresa}-apioficial

  nginx -t || trata_erro "nginx -t"
  systemctl reload nginx

  # SSL
  printf "${WHITE} >> Emitindo certificados SSL via Certbot...\n${NC}"
  certbot --nginx -m "${email_deploy}" --agree-tos -n \
    -d "${subdominio_frontend}" \
    -d "${subdominio_backend}" \
    -d "${subdominio_oficial}" || trata_erro "certbot"

  systemctl reload nginx
}

# --------------------------- FINALIZAÇÃO --------------------------
finaliza() {
  banner
  printf "${GREEN} ✅ Instalação concluída!\n\n${NC}"
  printf "${WHITE}Acesse:\n"
  printf " - Painel FRONTEND:  https://${subdominio_frontend}\n"
  printf " - BACKEND direto:    https://${subdominio_backend}\n"
  printf " - API OFICIAL:      https://${subdominio_oficial}\n\n"
  printf "PM2:\n"
  printf " - pm2 ls\n"
  printf " - pm2 logs ${empresa}-backend\n"
  printf " - pm2 logs ${empresa}-apioficial\n\n"
}

# ==================================================================
#                           EXECUÇÃO
# ==================================================================
perguntas_iniciais
confirmar_dados
verificar_dns
atualiza_vps
cria_usuario_deploy
config_timezone
config_firewall
instala_postgres
instala_redis
instala_node
instala_pm2
instala_nginx
instala_git
clona_codigo
cria_banco_apioficial
gera_env_backend
gera_env_frontend
gera_env_apioficial
instala_backend
instala_frontend
instala_api_oficial
config_nginx
finaliza
