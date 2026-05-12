# Multi-stage Dockerfile for Laravel app (PHP 8.2 + Apache)
# Stage 1: install PHP dependencies via Composer
FROM composer:2 AS composer
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader --no-progress
COPY . /app
RUN composer dump-autoload -o

# Final stage: PHP + Apache
FROM php:8.2-apache

# System deps and PHP extensions needed by Laravel
RUN apt-get update && apt-get install -y --no-install-recommends \
    libzip-dev zlib1g-dev libpng-dev libjpeg-dev libfreetype6-dev git unzip \
  && docker-php-ext-configure gd --with-freetype --with-jpeg \
  && docker-php-ext-install pdo pdo_mysql mbstring exif pcntl bcmath gd zip \
  && a2enmod rewrite headers

# Copy application code from composer stage
COPY --from=composer /app /var/www/html

# Ensure the webroot points to Laravel's public folder
ENV APACHE_DOCUMENT_ROOT /var/www/html/public
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
 && sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

# Permissions for storage and cache
RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache || true

EXPOSE 80

# Default command
CMD ["apache2-foreground"]
