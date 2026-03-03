FROM php:8.2-fpm-alpine

# Install required PHP extensions and utilities
RUN apk add --no-cache \
    curl \
    git \
    unzip \
    libzip-dev \
    oniguruma-dev \
    && docker-php-ext-install pdo pdo_mysql zip mbstring exif pcntl

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Create non-root user
RUN addgroup -g 1000 -S appgroup && \
    adduser -u 1000 -S appuser -G appgroup

# Set working directory
WORKDIR /var/www/html

# Copy application files
COPY --chown=appuser:appgroup . /var/www/html/

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 9000

# Start PHP-FPM
CMD ["php-fpm"]

