#!/bin/bash

until  mariadb-admin ping -h mariadb -u $USER -p$USER_PASSWORD --silent; do
    sleep 1
done

mkdir -p /run/php
cd /var/www/html


if ! wp core is-installed --path=/var/www/html --allow-root; then
    wp core download --path=/var/www/html --allow-root
    wp config create \
    --dbname="$MARIA_DB" \
    --dbuser="$USER" \
    --dbpass="$USER_PASSWORD" \
    --dbhost="mariadb" \
    --path=/var/www/html \
    --allow-root

   wp core install \
    --path=/var/www/html \
    --url="$DOMAIN_NAME" \
    --title="Inception" \
    --admin_user="${WP_ADMIN_USER}" \
    --admin_password="${WP_ADMIN_PASSWORD}" \
    --admin_email="${WP_ADMIN_EMAIL}" \
    --skip-email \
    --allow-root

wp user create \
    "${WP_USER}" \
    "${WP_USER_EMAIL}" \
    --role=author \
    --user_pass="${WP_USER_PASSWORD}" \
    --path=/var/www/html \
    --allow-root

    chown -R www-data:www-data /var/www/html
fi

exec /usr/sbin/php-fpm8.2 -F 