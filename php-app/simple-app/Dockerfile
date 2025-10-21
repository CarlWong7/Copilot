FROM php:8.2-apache

# Copy app into container
COPY . /var/www/simple-app

# Enable rewrite and point Apache at the public directory
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates \
    && a2enmod rewrite \
    && sed -ri 's!DocumentRoot /var/www/html!DocumentRoot /var/www/simple-app/public!g' /etc/apache2/sites-available/000-default.conf \
    && sed -ri "s!<Directory /var/www/html>!<Directory /var/www/simple-app/public>!g" /etc/apache2/apache2.conf || true \
    && chown -R www-data:www-data /var/www/simple-app \
    && rm -rf /var/lib/apt/lists/*

EXPOSE 80

CMD ["apache2-foreground"]
