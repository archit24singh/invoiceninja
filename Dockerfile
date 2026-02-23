ARG PHP_VERSION=8.2
ARG BAK_STORAGE_PATH=/var/www/app/docker-backup-storage/
ARG BAK_PUBLIC_PATH=/var/www/app/docker-backup-public/

# ─── Stage 1: Official release — pre-built vendor/ and compiled public/ ───────
FROM alpine AS official

RUN apk add --no-cache curl tar grep \
    && mkdir -p /var/www/app \
    && DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/invoiceninja/invoiceninja/releases/latest" \
         | grep -o '"browser_download_url": "[^"]*invoiceninja\.tar"' \
         | cut -d '"' -f 4) \
    && curl -fsSL "$DOWNLOAD_URL" | tar -x -C /var/www/app

# ─── Stage 2: Custom source — your fork with all code changes ─────────────────
FROM alpine AS source

RUN apk add --no-cache git \
    && git clone --depth=1 --branch v5-stable \
         https://github.com/archit24singh/invoiceninja.git /var/www/app

# ─── Stage 3: PHP application ─────────────────────────────────────────────────
FROM php:${PHP_VERSION}-fpm-alpine

ARG UID=1500
ARG BAK_STORAGE_PATH
ARG BAK_PUBLIC_PATH

ENV INVOICENINJA_USER=invoiceninja
ENV BAK_STORAGE_PATH=$BAK_STORAGE_PATH
ENV BAK_PUBLIC_PATH=$BAK_PUBLIC_PATH
ENV IS_DOCKER=true
ENV APP_ENV=production
ENV LOG=errorlog
ENV SNAPPDF_EXECUTABLE_PATH=/usr/bin/chromium-browser

# Use production php.ini
RUN mv /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini

# Install mlocati PHP extension installer
COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/

# Install system packages
RUN apk add --no-cache \
        mariadb-connector-c \
        font-isas-misc \
        ttf-freefont \
        ttf-dejavu \
        supervisor \
        mysql-client \
        chromium \
        nginx

# Install PHP extensions
RUN install-php-extensions \
        bcmath \
        exif \
        gd \
        gmp \
        intl \
        mysqli \
        opcache \
        pdo_mysql \
        zip \
    && rm /usr/local/bin/install-php-extensions

# Copy rootfs config and scripts
COPY rootfs /

# Create invoiceninja user (uid/gid 1500)
RUN addgroup --gid=$UID -S "$INVOICENINJA_USER" \
    && adduser --uid=$UID \
        --disabled-password \
        --gecos "" \
        --home "/var/www/app" \
        --ingroup "$INVOICENINJA_USER" \
        "$INVOICENINJA_USER"

WORKDIR /var/www/app

# 1. Base: official tarball — provides pre-installed vendor/ and compiled public/
COPY --from=official --chown=$UID:$UID /var/www/app .

# 2. Overlay: your fork — applies all code changes on top.
#    vendor/ is not present in the repo (.gitignore), so the tarball's vendor/ is preserved.
#    public/ from the repo (uncompiled) overwrites the tarball's compiled version here.
COPY --from=source --chown=$UID:$UID /var/www/app .

# 3. Restore: compiled public/ from the official tarball, replacing the uncompiled version
COPY --from=official --chown=$UID:$UID /var/www/app/public ./public

# Wire up the React SPA entry point
RUN ln -sf /var/www/app/resources/views/react/index.blade.php /var/www/app/public/index.html

# Ensure all required runtime directories exist
RUN mkdir -p \
        bootstrap/cache \
        storage/framework/sessions \
        storage/framework/views \
        storage/framework/cache/data \
        storage/logs \
        storage/app/public \
        public/logo \
        /run/nginx

# Remove any committed .env and purge stale build-time caches
RUN rm -f .env \
           bootstrap/cache/config.php \
           bootstrap/cache/routes*.php \
           bootstrap/cache/packages.php \
           bootstrap/cache/services.php \
           bootstrap/cache/events.php

# Back up storage and public so the entrypoint can seed mounted volumes at runtime
RUN mv storage $BAK_STORAGE_PATH \
    && mv public $BAK_PUBLIC_PATH

# Fix ownership and php.ini memory limit
RUN mkdir -p /var/www/app/public \
    && chown -R $UID:$UID /var/lib/nginx /var/www/app/ \
    && sed -i 's/memory_limit = 128M/memory_limit = 256M/g' /usr/local/etc/php/php.ini

# Make all entrypoint scripts executable
RUN chmod +x /usr/local/bin/docker-entrypoint \
    && chmod +x /usr/local/bin/invoiceninja-init.sh \
    && chmod +x /usr/local/bin/shutdown.sh \
    && chmod +x /docker-entrypoint-init.d/10-init-in.sh

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]
CMD ["supervisord"]
