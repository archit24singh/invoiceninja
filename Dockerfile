FROM php:8.2-fpm

# Install system dependencies
RUN apt-get update && apt-get install -y \
        git \
        curl \
        libpng-dev \
        libonig-dev \
        libxml2-dev \
        libzip-dev \
        libgmp-dev \
        zip \
        unzip \
    && docker-php-ext-install \
        pdo_mysql \
        mysqli \
        bcmath \
        gd \
        mbstring \
        xml \
        zip \
        gmp \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Create Invoice Ninja user (uid 1500)
RUN groupadd -g 1500 invoiceninja && useradd -u 1500 -g 1500 -s /bin/bash invoiceninja

WORKDIR /var/www/app

# Copy application files
COPY . .

# Ensure all required framework directories exist (Git does not track empty dirs)
RUN mkdir -p \
        bootstrap/cache \
        storage/framework/sessions \
        storage/framework/views \
        storage/framework/cache/data \
        storage/logs \
        storage/app/public

# Install PHP dependencies — skip scripts that require a runtime .env
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-scripts \
    && composer dump-autoload --optimize --no-scripts

# Purge any stale build-time config/route/view caches
RUN rm -f bootstrap/cache/config.php \
           bootstrap/cache/routes*.php \
           bootstrap/cache/packages.php \
           bootstrap/cache/services.php \
           bootstrap/cache/events.php

# Set ownership to invoiceninja (1500:1500) and enforce permissions
RUN chown -R 1500:1500 /var/www/app \
    && chmod -R 775 storage bootstrap/cache \
    && find /var/www/app/public -type d -exec chmod 755 {} \; \
    && find /var/www/app/public -type f -exec chmod 644 {} \;

EXPOSE 9000

CMD ["php-fpm"]
