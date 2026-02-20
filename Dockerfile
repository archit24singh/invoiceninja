ARG PHP_VERSION=8.2
ARG BAK_STORAGE_PATH=/var/www/app/docker-backup-storage/
ARG BAK_PUBLIC_PATH=/var/www/app/docker-backup-public/

# ─── Stage 1: Build React UI ──────────────────────────────────────────────────
FROM node:20-alpine AS reactbuild

RUN apk add --no-cache git

RUN git clone https://github.com/invoiceninja/ui.git /ui

WORKDIR /ui

RUN npm install && npm run build

# ─── Stage 2: PHP application ─────────────────────────────────────────────────
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

# Install system packages: nginx, supervisor, chromium (PDF), fonts, mysql client
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
        @composer \
    && rm /usr/local/bin/install-php-extensions

# Copy rootfs config and scripts into the image
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

# Copy local application source
COPY --chown=$UID:$UID . .

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

# Install PHP dependencies — skip artisan scripts that require a live .env
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-scripts \
    && composer dump-autoload --optimize --no-scripts

# Purge any stale build-time caches
RUN rm -f bootstrap/cache/config.php \
           bootstrap/cache/routes*.php \
           bootstrap/cache/packages.php \
           bootstrap/cache/services.php \
           bootstrap/cache/events.php

# Back up storage and public so the entrypoint can seed mounted volumes
RUN mv storage $BAK_STORAGE_PATH \
    && mv public $BAK_PUBLIC_PATH

# Copy compiled React UI from build stage
COPY --from=reactbuild /ui/dist /var/www/app/public/react

# Set ownership and permissions on React assets
RUN chown -R 1500:1500 /var/www/app/public/react \
    && find /var/www/app/public/react -type d -exec chmod 777 {} \; \
    && find /var/www/app/public/react -type f -exec chmod 777 {} \;

# Set ownership and fix memory_limit in php.ini
RUN mkdir -p /var/www/app/public \
    && chown -R 1500:1500 /var/lib/nginx /var/www/app/ \
    && sed -i 's/memory_limit = 128M/memory_limit = 256M/g' /usr/local/etc/php/php.ini

# Make all entrypoint scripts executable
RUN chmod +x /usr/local/bin/docker-entrypoint \
    && chmod +x /usr/local/bin/invoiceninja-init.sh \
    && chmod +x /usr/local/bin/shutdown.sh \
    && chmod +x /docker-entrypoint-init.d/10-init-in.sh

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]
CMD ["supervisord"]
