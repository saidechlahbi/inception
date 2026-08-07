*This project has been created as part of the 42 curriculum by sechlahb.*

# Developer Documentation

This document describes how to set up, build, and work on the Inception project from a developer's perspective. It covers the mandatory part only (NGINX, WordPress + php-fpm, MariaDB) — no bonus services are included in this submission.

## 1. Setting up the environment from scratch

### Prerequisites
- A Linux virtual machine (the project subject requires this to be done in a VM, not directly on the host).
- `docker` and the `docker compose` plugin installed and working (`docker compose version` should succeed).
- `make`.
- sudo/root access, needed for editing `/etc/hosts` and for `make fclean` to remove the host data directory.

### Repository layout
```
.
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── secrets/                      # local credential notes, git-ignored, not read by docker compose
│   ├── credentials.txt
│   ├── db_password.txt
│   └── db_root_password.txt
└── srcs
    ├── docker-compose.yml
    ├── .env                     # environment variables (git-ignored)
    └── requirements
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/
        │   └── tools/
        │       └── entrypoint.sh
        ├── nginx/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/
        │   │   └── nginx.conf
        │   └── tools/
        ├── wordpress/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/
        │   └── tools/
        │       └── wordpress.sh
        ├── tools/                # shared helper scripts, if any
        └── bonus/                # unused in this submission (bonus part not implemented)
```

The `secrets/` folder at the repository root holds the raw credential values for personal reference during development; it is git-ignored and is **not** wired into `docker-compose.yml` via Docker's `secrets:` mechanism — all containers actually receive their configuration through `env_file: - .env`, as described below. The `bonus/` directory exists but is empty/unused, since this submission covers the mandatory part only.

Each service directory under `requirements/` contains its own `Dockerfile` and any configuration files / entrypoint scripts it needs, following the "one Dockerfile per service, no pre-built images" rule of the subject.

### Configuration files and secrets

All configuration lives in `srcs/.env`, loaded by every service via `env_file: - .env` in `docker-compose.yml`. It defines:

- `MARIA_DB`, `USER`, `USER_PASSWORD`, `ROOT_PASSWORD` — MariaDB configuration: database name, application DB user/password, and root password.
- `DOMAIN_NAME` — the domain the site is served under (`sechlahb.42.fr`).
- `WP_ADMIN_USER`, `WP_ADMIN_EMAIL`, `WP_ADMIN_PASSWORD` — WordPress administrator account. The username must not contain "admin" or "administrator" in any casing.
- `WP_USER`, `WP_USER_EMAIL`, `WP_USER_PASSWORD` — a secondary, non-admin WordPress user.

Note: the MariaDB hostname is not read from an env var — `wordpress.sh` connects directly to the `mariadb` service by its Docker Compose service name (resolved via the `inception` network's internal DNS), so there is no `WORDPRESS_DB_HOST` variable in this project.

`.env` must never be committed — it is git-ignored. No credential is hardcoded in any Dockerfile; every Dockerfile/entrypoint reads its secrets from the environment at container start.

Before your first run, add the domain to your local DNS resolution:
```bash
echo "127.0.0.1   sechlahb.42.fr" | sudo tee -a /etc/hosts
```

## 2. Building and launching the project

The `Makefile` at the repository root wraps `docker compose`, always pointing at `srcs/docker-compose.yml` and `srcs/.env`:

```make
COMPOSE = docker compose \
        -f srcs/docker-compose.yml \
        --env-file srcs/.env
```

**Build and start every service** (creates the host data directories first, then builds and starts all containers in detached mode):
```bash
make
```
This runs, in effect:
```bash
mkdir -p /home/sechlahb/data/mariadb
mkdir -p /home/sechlahb/data/wordpress
docker compose -f srcs/docker-compose.yml --env-file srcs/.env up -d --build
```

**Stop containers, keep data:**
```bash
make down
```

**Stop containers and delete volumes:**
```bash
make clean
```

**Full teardown** (containers, volumes, all local images, and the host data directory):
```bash
make fclean
```
This runs `docker compose down -v`, then `docker system prune -af` (removes **all** unused Docker images/containers/build cache on the machine, not just this project's — be aware of this if you have other Docker projects on the same VM), and finally `sudo rm -rf /home/sechlahb/data`.

**Rebuild from scratch:**
```bash
make re
```

When iterating on a single service's Dockerfile, you can rebuild and restart just that service without tearing down everything else:
```bash
docker compose -f srcs/docker-compose.yml --env-file srcs/.env up -d --build <service_name>
```

## 3. Managing containers and volumes

**Useful Docker Compose commands** (run from the repo root, or `cd srcs` first):
```bash
docker compose -f srcs/docker-compose.yml ps            # list running services
docker compose -f srcs/docker-compose.yml logs -f nginx # follow logs for one service
docker compose -f srcs/docker-compose.yml exec wordpress sh   # shell into a running container
docker compose -f srcs/docker-compose.yml restart mariadb     # restart a single service
```

**Useful raw Docker commands:**
```bash
docker ps -a                 # all containers, including stopped ones
docker images                # list built images
docker volume ls             # list volumes (mariadb, wordpress)
docker network ls            # confirm the inception network exists
docker system df             # disk usage summary
```

All services are configured with `restart: always`, so a crashed container will be restarted automatically by the Docker daemon; you generally don't need to restart them by hand.

## 4. Where project data is stored and how it persists

Two named volumes are declared in `docker-compose.yml`:

```yaml
volumes:
  mariadb:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/sechlahb/data/mariadb
  wordpress:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/sechlahb/data/wordpress
```

- `mariadb` is mounted into the `mariadb` container at `/var/lib/mysql` — this is where all database files (WordPress tables, users, posts, etc.) live.
- `wordpress` is mounted at `/var/www/html` in both the `wordpress` and `nginx` containers — this is the WordPress installation and uploaded media, shared between the app server (for writing/serving PHP) and NGINX (for serving static assets).

Even though these are declared as Docker **named volumes** (not raw bind mounts) in the Compose syntax — which the subject requires — their storage backend is pinned to specific paths on the host (`/home/sechlahb/data/mariadb` and `/home/sechlahb/data/wordpress`) via `driver_opts`. This means:
- Data survives `docker compose down` and container recreation.
- Data is only removed by `docker compose down -v` (or `make clean` / `make fclean`, which use `-v`), or by manually deleting the host directory.
- You can inspect the raw files directly on the host in `/home/sechlahb/data/` while the stack is stopped (or even while running, though writes should go through the containers to avoid permission/lock issues).

To reset the project to a completely fresh state (empty database, fresh WordPress install), run `make clean` (or `make fclean` for a full image/data wipe) followed by `make`.

## 5. Service internals

This section walks through what each Dockerfile and entrypoint script actually does, and how `docker-compose.yml` wires the three services together. It's meant to let a developer (or an evaluator) understand the stack without having to reverse-engineer it during the defense.

### 5.1 docker-compose.yml

```yaml
services:
  mariadb:
    build: ./requirements/mariadb/
    image: mariadb:ince
    container_name: mariadb
    restart: always
    volumes:
      - mariadb:/var/lib/mysql
    networks:
      - inception
    env_file:
      - .env
```

- `build:` points at the service's own directory, so `docker compose up --build` builds each image from its local `Dockerfile` — nothing is pulled from Docker Hub except the base `debian:bookworm` image.
- `image: mariadb:ince` gives the built image the same name as the service (`mariadb`), which the subject requires.
- `container_name:` fixes a predictable name (`mariadb`, `wordpress`, `nginx`) so `docker compose exec <name>` / `docker logs <name>` are easy to use, and so the containers can resolve each other by name over the `inception` network (e.g. WordPress connects to the database at host `mariadb`).
- `restart: always` makes the Docker daemon restart the container automatically if it crashes, satisfying the "containers must restart on crash" requirement.
- `volumes:` mounts the named volume declared at the bottom of the file into the container's data path (`/var/lib/mysql` for MariaDB, `/var/www/html` for WordPress and NGINX — the last one shared so NGINX can serve the PHP files that WordPress writes).
- `networks: - inception` attaches every service to the single custom bridge network, which is what makes `mariadb` and `wordpress` resolvable by name and keeps `network: host`/`links:` (both forbidden) out of the picture.
- `env_file: - .env` injects the credentials and configuration (`MARIA_DB`, `USER`, `USER_PASSWORD`, `ROOT_PASSWORD`, `DOMAIN_NAME`, `WP_ADMIN_*`, `WP_USER_*`) as environment variables inside each container, so nothing is hardcoded in the Dockerfiles.
- `depends_on:` on `wordpress` (waits for `mariadb`) and on `nginx` (waits for `wordpress`) only controls **container start order**, not readiness — that's why `wordpress.sh` and `entrypoint.sh` also poll the database with `mariadb-admin ping` before doing anything, instead of assuming it's ready.
- Only the `nginx` service publishes a port: `ports: - 443:443`. `mariadb` and `wordpress` have no `ports:` entry at all, so they're reachable only from inside the `inception` network — NGINX is the sole entry point into the infrastructure, as required.
- The `volumes:` and `networks:` top-level blocks declare the named volumes (`mariadb`, `wordpress`) pinned to `/home/sechlahb/data/...` via `driver_opts`, and the `inception` bridge network with no extra configuration needed.

### 5.2 MariaDB — `Dockerfile` and `entrypoint.sh`

**Dockerfile:**
```dockerfile
FROM debian:bookworm

RUN apt-get update && \
    apt-get install -y mariadb-server && \
    rm -rf /var/lib/apt/lists/* && rm -rf /var/lib/mysql/*

COPY ./tools/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf

RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3306

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```

- `FROM debian:bookworm` — same penultimate-stable base as the other two services, no `latest` tag.
- `RUN apt-get install -y mariadb-server` installs the database server itself; `rm -rf /var/lib/apt/lists/*` clears the package index to keep the image smaller. `rm -rf /var/lib/mysql/*` wipes whatever default/system data files the package installs into that directory at build time — this matters because at runtime `/var/lib/mysql` is actually the named volume mounted over it, so this line just guarantees the image itself doesn't ship stale data underneath the mount point.
- `COPY ./tools/entrypoint.sh ...` copies the entrypoint script into the image.
- The `sed` command rewrites MariaDB's default config so it binds to `0.0.0.0` instead of `127.0.0.1` (localhost-only). By default MariaDB refuses connections from outside the container; without this change, WordPress (running in a separate container) could never reach it over the `inception` network — this is what makes `mariadb:3306` reachable from the `wordpress` service.
- `chmod +x` makes the script executable, `EXPOSE 3306` documents MariaDB's standard port, and `ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]` runs the script directly as PID 1.

**entrypoint.sh:**
```bash
#!/bin/bash
set -e

mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld

if [ ! -d /var/lib/mysql/mysql ]; then
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql
    service mariadb start
    until mariadb-admin ping; do sleep 1; done

    mariadb -u root -e "CREATE DATABASE IF NOT EXISTS \`${MARIA_DB}\`;"
    mariadb -u root -e "CREATE USER IF NOT EXISTS '${USER}'@'%' IDENTIFIED BY '${USER_PASSWORD}';"
    mariadb -u root -e "GRANT ALL PRIVILEGES ON \`${MARIA_DB}\`.* TO '${USER}'@'%';"
    mariadb -u root -e "FLUSH PRIVILEGES;"
    mariadb -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${ROOT_PASSWORD}';"
    mariadb-admin -u root -p"${ROOT_PASSWORD}" shutdown
fi
exec mariadbd --user=mysql
```

Step by step:
1. `set -e` stops the script immediately if any command fails, instead of continuing in a broken state.
2. `mkdir -p /run/mysqld` + `chown` creates the runtime directory MariaDB needs for its socket/PID file and makes sure the unprivileged `mysql` user can write to it.
3. The `if [ ! -d /var/lib/mysql/mysql ]` check is what makes the initialization **idempotent**: `/var/lib/mysql` lives on the named volume, so on the very first run the `mysql` system schema doesn't exist yet and this block runs; on every later restart (volume already populated) it's skipped entirely and the container just starts the daemon.
4. `mariadb-install-db` creates the initial system tables in the (empty) data directory.
5. `service mariadb start` + `until mariadb-admin ping; do sleep 1; done` starts the server temporarily and waits, polling, until it actually accepts connections — this avoids running SQL against a daemon that isn't ready yet (this is a short poll loop for startup synchronization, not an infinite loop / background daemon hack — it always exits once the ping succeeds).
6. The four `mariadb -u root -e "..."` calls create the WordPress database, create the application DB user with a password from `.env`, grant it privileges on that database only, and reload the grant tables.
7. `ALTER USER 'root'@'localhost' ...` sets the root password from `${ROOT_PASSWORD}` (also from `.env`) instead of leaving root passwordless.
8. `mariadb-admin ... shutdown` cleanly stops the temporary server used for setup.
9. `exec mariadbd --user=mysql` finally replaces the shell process with the real MariaDB daemon running in the foreground as PID 1 — this is what keeps the container alive without any `tail -f`/`sleep infinity` hack, and lets Docker signal the process directly (e.g. on `docker stop`).

### 5.3 WordPress — `Dockerfile` and `wordpress.sh`

**Dockerfile:**
```dockerfile
FROM debian:bookworm

RUN apt-get update && \
    apt-get install -y mariadb-client php8.2-fpm php8.2-mysql curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN curl -Os https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
    chmod +x wp-cli.phar && \
    mv wp-cli.phar /usr/local/bin/wp

COPY ./tools/wordpress.sh /usr/local/bin/

RUN sed -i 's/^listen.*/listen = 0.0.0.0:9000/' /etc/php/8.2/fpm/pool.d/www.conf

RUN chmod +x /usr/local/bin/wordpress.sh

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/wordpress.sh"]
```

- `FROM debian:bookworm` — the penultimate stable Debian release, as required (no `latest` tag).
- The first `RUN apt-get` installs `mariadb-client` (needed for `mariadb-admin ping` in the entrypoint), `php8.2-fpm`/`php8.2-mysql` (the actual WordPress runtime), and `curl` (to fetch WP-CLI); `apt-get clean` + removing `/var/lib/apt/lists/*` keeps the image smaller.
- The second `RUN curl ...` downloads WP-CLI (`wp-cli.phar`), makes it executable, and installs it as `/usr/local/bin/wp` — this is the tool `wordpress.sh` uses to install and configure WordPress non-interactively.
- `COPY ./tools/wordpress.sh /usr/local/bin/` copies the entrypoint script into the image.
- The `sed` command rewrites php-fpm's pool config so it listens on `0.0.0.0:9000` (a TCP socket reachable from other containers) instead of the default Unix socket, which only works within the same container — this is what lets NGINX reach PHP-FPM over the network via `fastcgi_pass wordpress:9000`.
- `chmod +x` makes the script executable, `EXPOSE 9000` documents the FastCGI port, and `ENTRYPOINT ["/usr/local/bin/wordpress.sh"]` runs the script directly as PID 1 (no shell wrapper, no background process).

**wordpress.sh:**
```bash
#!/bin/bash
until mariadb-admin ping -h mariadb -u $USER -p$USER_PASSWORD --silent; do
    sleep 1
done

mkdir -p /run/php
cd /var/www/html

if ! wp core is-installed --path=/var/www/html --allow-root; then
    wp core download --path=/var/www/html --allow-root
    wp config create --dbname="$MARIA_DB" --dbuser="$USER" --dbpass="$USER_PASSWORD" \
        --dbhost="mariadb" --path=/var/www/html --allow-root

    wp core install --path=/var/www/html --url="$DOMAIN_NAME" --title="Inception" \
        --admin_user="${WP_ADMIN_USER}" --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" --skip-email --allow-root

    wp user create "${WP_USER}" "${WP_USER_EMAIL}" --role=author \
        --user_pass="${WP_USER_PASSWORD}" --path=/var/www/html --allow-root

    chown -R www-data:www-data /var/www/html
fi

exec /usr/sbin/php-fpm8.2 -F
```

Step by step:
1. `until mariadb-admin ping -h mariadb ...; do sleep 1; done` waits for the MariaDB container to actually accept connections before touching the database — this is why `depends_on: - mariadb` in the compose file is enough for start order, since readiness is handled here.
2. `mkdir -p /run/php` creates php-fpm's runtime directory; `cd /var/www/html` moves into the shared volume where WordPress lives.
3. `wp core is-installed` checks whether WordPress is already set up on the volume. Because `/var/www/html` is a named volume, this makes the whole block idempotent: on the first `make`, the volume is empty and the block runs; on every later restart it's skipped and existing data (posts, users, settings) is preserved.
4. `wp core download` fetches WordPress core files into the volume.
5. `wp config create` writes `wp-config.php` with the DB name/user/password/host taken from `.env`, and pointed at the `mariadb` service by name (resolved via Docker's internal DNS on the `inception` network).
6. `wp core install` runs the actual WordPress installation non-interactively: it sets the site title/URL and creates the **administrator** account from `${WP_ADMIN_USER}`/`${WP_ADMIN_PASSWORD}`/`${WP_ADMIN_EMAIL}` — this is what guarantees you never see the WordPress "Installation" page when visiting the site, and this is where the "admin username must not contain admin/administrator" rule needs to be respected via the `.env` value.
7. `wp user create` adds the second, non-admin WordPress user (`WP_USER`, role `author`) required by the subject.
8. `chown -R www-data:www-data /var/www/html` gives the web server user ownership of the installed files so PHP-FPM (running as `www-data`) can write to them (uploads, cache, etc.).
9. `exec /usr/sbin/php-fpm8.2 -F` replaces the shell with php-fpm running **in the foreground** (`-F`) as PID 1 — again, no daemonizing/backgrounding, so Docker can track and signal the process correctly.

### 5.4 NGINX — `Dockerfile` and `nginx.conf`

**Dockerfile:**
```dockerfile
FROM debian:bookworm

RUN apt-get update && apt-get install -y nginx openssl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/nginx/ssl

RUN openssl req -x509 -nodes -out /etc/nginx/ssl/inception.crt -keyout /etc/nginx/ssl/inception.key -subj "/CN=sechlahb.42.fr"

COPY conf/nginx.conf /etc/nginx/conf.d/nginx.conf

EXPOSE 443

ENTRYPOINT [ "nginx" , "-g", "daemon off;" ]
```

- `FROM debian:bookworm` — same penultimate-stable base as the other two services.
- `RUN apt-get install -y nginx openssl` installs NGINX itself and OpenSSL, which is used at build time to generate the TLS certificate.
- `mkdir -p /etc/nginx/ssl` creates the directory that will hold the certificate and key (matching the paths referenced in `nginx.conf`).
- `openssl req -x509 -nodes -out /etc/nginx/ssl/inception.crt -keyout /etc/nginx/ssl/inception.key -subj "/CN=sechlahb.42.fr"` generates the self-signed certificate:
  - `-x509` outputs a self-signed certificate directly instead of a certificate signing request.
  - `-nodes` ("no DES") stores the private key **unencrypted**, so NGINX can start without being prompted for a passphrase.
  - `-out` / `-keyout` write the certificate and its matching private key to the two files `nginx.conf` later points at (`ssl_certificate` / `ssl_certificate_key`).
  - `-subj "/CN=sechlahb.42.fr"` sets the certificate's Common Name to the project's domain non-interactively (otherwise `openssl req` would prompt for country/org/etc. at build time and the build would hang).
  - This is why the browser shows a self-signed-certificate warning on first visit — it's expected and explicitly allowed by the subject.
  - Note: since no `-days` flag is passed, OpenSSL falls back to its default validity period; if you ever see the certificate rejected as expired, regenerate the image (`docker compose build --no-cache nginx`) to reissue a fresh one.
- `COPY conf/nginx.conf /etc/nginx/conf.d/nginx.conf` copies the server block into NGINX's config include directory (`/etc/nginx/conf.d/`), where NGINX automatically loads it.
- `EXPOSE 443` documents the HTTPS port. Combined with `docker-compose.yml`'s `ports: - 443:443`, this is the only port published to the host.
- `ENTRYPOINT [ "nginx", "-g", "daemon off;" ]` — `-g "daemon off;"` overrides NGINX's config directive that would otherwise make it fork into the background and exit immediately. Running it in the foreground is what makes NGINX PID 1 inside the container, so Docker can track it and restart it correctly on crash, with no `tail -f`-style hack needed.

**nginx.conf:**

```nginx
server {
    listen 443 ssl;
    server_name sechlahb.42.fr;

    root /var/www/html;
    index index.html index.php;

    ssl_certificate /etc/nginx/ssl/inception.crt;
    ssl_certificate_key /etc/nginx/ssl/inception.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php {
        include fastcgi_params;
        fastcgi_pass wordpress:9000;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
}
```

- `listen 443 ssl;` — NGINX only listens on 443, and only with SSL/TLS enabled; there's no `listen 80` block, which is why the site is unreachable over plain HTTP, as required.
- `server_name sechlahb.42.fr;` ties this config to the project's domain (matching the `/etc/hosts` entry and `DOMAIN_NAME` in `.env`).
- `root /var/www/html;` points at the same volume WordPress writes into, so NGINX serves the actual installed site rather than empty/static content.
- `ssl_certificate` / `ssl_certificate_key` reference the self-signed certificate and key generated for the domain (the browser warning on first visit is expected, since it isn't signed by a public CA).
- `ssl_protocols TLSv1.2 TLSv1.3;` restricts the handshake to those two protocol versions only, satisfying the subject's TLS requirement — older/weaker protocols like TLSv1.0/1.1 are refused.
- `location /` serves static files directly via `try_files`, falling back to a 404 if nothing matches.
- `location ~ \.php` is what makes PHP work: any request for a `.php` file is forwarded over FastCGI to `wordpress:9000` — the WordPress container's IP (resolved via Docker DNS) on the port php-fpm was configured to listen on in the Dockerfile's `sed` step. `SCRIPT_FILENAME` tells php-fpm which file on disk to execute.