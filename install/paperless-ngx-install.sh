#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://docs.paperless-ngx.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies (Patience)"
$STD apt-get install -y \
  redis \
  postgresql \
  build-essential \
  imagemagick \
  fonts-liberation \
  optipng \
  gnupg \
  libpq-dev \
  libmagic-dev \
  mime-support \
  libzbar0 \
  poppler-utils \
  default-libmysqlclient-dev \
  automake \
  libtool \
  pkg-config \
  git \
  libtiff-dev \
  libpng-dev \
  libleptonica-dev
msg_ok "Installed Dependencies"

msg_info "Setup Python3"
$STD apt-get install -y \
  python3 \
  python3-pip \
  python3-dev \
  python3-setuptools \
  python3-wheel
msg_ok "Setup Python3"

msg_info "Installing OCR Dependencies (Patience)"
$STD apt-get install -y \
  unpaper \
  icc-profiles-free \
  qpdf \
  liblept5 \
  libxml2 \
  pngquant \
  zlib1g \
  tesseract-ocr \
  tesseract-ocr-eng

cd /tmp || exit
curl -fsSL "https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs10040/ghostscript-10.04.0.tar.gz" -o $(basename "https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs10040/ghostscript-10.04.0.tar.gz")
$STD tar -xzf ghostscript-10.04.0.tar.gz
cd ghostscript-10.04.0 || exit
$STD ./configure
$STD make
$STD sudo make install
msg_ok "Installed OCR Dependencies"

msg_info "Installing JBIG2"
$STD git clone https://github.com/ie13/jbig2enc /opt/jbig2enc
cd /opt/jbig2enc || exit
$STD bash ./autogen.sh
$STD bash ./configure
$STD make
$STD make install
rm -rf /opt/jbig2enc
msg_ok "Installed JBIG2"

msg_info "Installing Paperless-ngx (Patience)"
Paperlessngx=$(curl -fsSL "https://github.com/paperless-ngx/paperless-ngx/releases/latest" | grep "title>Release" | cut -d " " -f 5)
cd /opt || exit
$STD curl -fsSL "https://github.com/paperless-ngx/paperless-ngx/releases/download/$Paperlessngx/paperless-ngx-$Paperlessngx.tar.xz" -o "paperless-ngx-$Paperlessngx.tar.xz"
$STD tar -xf "paperless-ngx-$Paperlessngx.tar.xz" -C /opt/
mv paperless-ngx paperless
rm "paperless-ngx-$Paperlessngx.tar.xz"
cd /opt/paperless || exit
$STD pip install --upgrade pip
$STD pip install -r requirements.txt
curl -fsSL "https://raw.githubusercontent.com/paperless-ngx/paperless-ngx/main/paperless.conf.example" -o /opt/paperless/paperless.conf
mkdir -p {consume,data,media,static}
sed -i -e 's|#PAPERLESS_REDIS=redis://localhost:6379|PAPERLESS_REDIS=redis://localhost:6379|' /opt/paperless/paperless.conf
sed -i -e "s|#PAPERLESS_CONSUMPTION_DIR=../consume|PAPERLESS_CONSUMPTION_DIR=/opt/paperless/consume|" /opt/paperless/paperless.conf
sed -i -e "s|#PAPERLESS_DATA_DIR=../data|PAPERLESS_DATA_DIR=/opt/paperless/data|" /opt/paperless/paperless.conf
sed -i -e "s|#PAPERLESS_MEDIA_ROOT=../media|PAPERLESS_MEDIA_ROOT=/opt/paperless/media|" /opt/paperless/paperless.conf
sed -i -e "s|#PAPERLESS_STATICDIR=../static|PAPERLESS_STATICDIR=/opt/paperless/static|" /opt/paperless/paperless.conf
echo "${Paperlessngx}" >/opt/"${APPLICATION}"_version.txt
msg_ok "Installed Paperless-ngx"

msg_info "Installing Natural Language Toolkit (Patience)"
$STD python3 -m nltk.downloader -d /usr/share/nltk_data all
msg_ok "Installed Natural Language Toolkit"

msg_info "You can use the default database or connect to an external server"
read -r -p "Would you like use the default (local) PostgreSQL install? <y/N> " db_prompt

# Common variables for both paths
DB_NAME=paperlessdb
DB_USER=paperless
DB_PASS="$(openssl rand -base64 18 | cut -c1-13)"
SECRET_KEY="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)"

if [[ "${db_prompt,,}" =~ ^(y|yes)$ ]]; then

  msg_info "Setting up PostgreSQL database"
  # Use local PostgreSQL server
  DB_HOST="localhost"
  DB_PORT="5432"

  # Create database objects
  $STD sudo -u postgres psql <<EOF
CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';
CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;
ALTER ROLE $DB_USER SET client_encoding TO 'utf8';
ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';
ALTER ROLE $DB_USER SET timezone TO 'UTC';
EOF

  msg_ok "Set up PostgreSQL database"
else
  msg_info "Please supply the information to connect to your PostgreSQL server. This script will create the database there."

  read -r -p "Postgres host [default: localhost]: " DB_HOST
  DB_HOST=${DB_HOST:-localhost}

  read -r -p "Postgres host port [default: 5432]: " DB_PORT
  DB_PORT=${DB_PORT:-5432}

  read -r -p "User name: " PG_USER
  read -r -s -p "Password: " PG_PASS
  echo ""

  msg_info "Creating external database"

  # Create database objects on external server
  if ! PGPASSWORD="$PG_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$PG_USER" <<EOF; then
CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';
CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;
ALTER ROLE $DB_USER SET client_encoding TO 'utf8';
ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';
ALTER ROLE $DB_USER SET timezone TO 'UTC';
EOF
    msg_info "Failed to set up database. Exiting."
    exit 1
  fi

  msg_ok "Created external PostgreSQL database"
  $STD apt-get remove -y postgresql
fi

# Common configuration for both paths
{
  echo ""
  echo -e "Paperless-ngx DB Host: \e[32m$DB_HOST\e[0m"
  echo -e "Paperless-ngx User: \e[32m$DB_USER\e[0m"
  echo -e "Paperless-ngx Password: \e[32m$DB_PASS\e[0m"
  echo -e "Paperless-ngx Name: \e[32m$DB_NAME\e[0m"
} >>~/paperless.creds

# Configure Paperless with the database connection
sed -i -e "s|#PAPERLESS_DBHOST=localhost|PAPERLESS_DBHOST=$DB_HOST|" \
  -e "s|#PAPERLESS_DBPORT=5432|PAPERLESS_DBPORT=$DB_PORT|" \
  -e "s|#PAPERLESS_DBNAME=paperless|PAPERLESS_DBNAME=$DB_NAME|" \
  -e "s|#PAPERLESS_DBUSER=paperless|PAPERLESS_DBUSER=$DB_USER|" \
  -e "s|#PAPERLESS_DBPASS=paperless|PAPERLESS_DBPASS=$DB_PASS|" \
  -e "s|#PAPERLESS_SECRET_KEY=change-me|PAPERLESS_SECRET_KEY=$SECRET_KEY|" \
  /opt/paperless/paperless.conf

# Apply database migrations
cd /opt/paperless/src || exit
$STD python3 manage.py migrate
msg_info "Paperless-ngx database configuration complete"

read -r -p "Would you like to add Adminer? <y/N> " prompt
if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
  msg_info "Installing Adminer"
  $STD apt install -y adminer
  $STD a2enconf adminer
  systemctl reload apache2
  IP=$(hostname -I | awk '{print $1}')
  echo "" >>~/paperless.creds
  echo -e "Adminer Interface: \e[32m$IP/adminer/\e[0m" >>~/paperless.creds
  echo -e "Adminer System: \e[32mPostgreSQL\e[0m" >>~/paperless.creds
  echo -e "Adminer Server: \e[32mlocalhost:5432\e[0m" >>~/paperless.creds
  echo -e "Adminer Username: \e[32m$DB_USER\e[0m" >>~/paperless.creds
  echo -e "Adminer Password: \e[32m$DB_PASS\e[0m" >>~/paperless.creds
  echo -e "Adminer Database: \e[32m$DB_NAME\e[0m" >>~/paperless.creds
  msg_ok "Installed Adminer"
fi

msg_info "Setting up admin Paperless-ngx User & Password"
## From https://github.com/linuxserver/docker-paperless-ngx/blob/main/root/etc/cont-init.d/99-migrations
cat <<EOF | python3 /opt/paperless/src/manage.py shell
from django.contrib.auth import get_user_model
UserModel = get_user_model()
user = UserModel.objects.create_user('admin', password='$DB_PASS')
user.is_superuser = True
user.is_staff = True
user.save()
EOF
echo "" >>~/paperless.creds
echo -e "Paperless-ngx WebUI User: \e[32madmin\e[0m" >>~/paperless.creds
echo -e "Paperless-ngx WebUI Password: \e[32m$DB_PASS\e[0m" >>~/paperless.creds
echo "" >>~/paperless.creds
msg_ok "Set up admin Paperless-ngx User & Password"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/paperless-scheduler.service
[Unit]
Description=Paperless Celery beat
Requires=redis.service

[Service]
WorkingDirectory=/opt/paperless/src
ExecStart=celery --app paperless beat --loglevel INFO

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/paperless-task-queue.service
[Unit]
Description=Paperless Celery Workers
Requires=redis.service
After=postgresql.service

[Service]
WorkingDirectory=/opt/paperless/src
ExecStart=celery --app paperless worker --loglevel INFO

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/paperless-consumer.service
[Unit]
Description=Paperless consumer
Requires=redis.service

[Service]
WorkingDirectory=/opt/paperless/src
ExecStartPre=/bin/sleep 2
ExecStart=python3 manage.py document_consumer

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/paperless-webserver.service
[Unit]
Description=Paperless webserver
After=network.target
Wants=network.target
Requires=redis.service

[Service]
WorkingDirectory=/opt/paperless/src
ExecStart=granian --interface asginl --ws "paperless.asgi:application"
Environment=GRANIAN_HOST=::
Environment=GRANIAN_PORT=8000
Environment=GRANIAN_WORKERS=1

[Install]
WantedBy=multi-user.target
EOF

sed -i -e 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/' /etc/ImageMagick-6/policy.xml

systemctl daemon-reload
$STD systemctl enable -q --now paperless-webserver paperless-scheduler paperless-task-queue paperless-consumer
msg_ok "Created Services"

motd_ssh
customize

msg_info "Cleaning up"
rm -rf /opt/paperless/docker
rm -rf /tmp/ghostscript*
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
