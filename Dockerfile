ARG PHP_VERSION=7.3.2
ARG APCU_VERSION=5.1.18
ARG XDEBUG_VERSION=2.9.6

#####################################
##               PHP               ##
#####################################
FROM php:${PHP_VERSION}-apache AS php

ARG APCU_VERSION

WORKDIR /var/lib/php

EXPOSE 8000

# Install required system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
        libzip-dev \
        zlib1g-dev \
        libicu-dev \
        libmcrypt-dev \
		libfreetype6-dev \
		libpng-dev \
		libjpeg-dev \
        libmagickwand-dev \
        git \
        zip \
        vim \
        nano \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# RUN apt-get update

# Install the PHP extensions
RUN docker-php-ext-configure intl \
    && docker-php-ext-configure pdo_mysql --with-pdo-mysql=mysqlnd \
	&& docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        gd \
        intl \
        opcache \
        pdo_mysql \
        zip \
    && pecl install \
        apcu-${APCU_VERSION} \
        imagick \
    && docker-php-ext-enable \
        opcache \
        apcu \
        imagick \
    && docker-php-source delete \
    # Clean aptitude cache and tmp directory
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# configure apache document root as per the image documentation in addition rewrite header
ENV APP_HOME /var/www/html
ENV APACHE_DOCUMENT_ROOT /var/www/html/public

RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf
RUN sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

# Use the PORT environment variable in Apache configuration files.
RUN sed -i 's/80/${PORT}/g' /etc/apache2/sites-available/000-default.conf /etc/apache2/ports.conf

RUN a2enmod rewrite headers

#####################################
##         BUILD PROJECT           ##
#####################################

FROM php AS builder

WORKDIR /var/www/html
COPY ./www ./
COPY --from=composer /usr/bin/composer /usr/bin/composer

RUN composer global require hirak/prestissimo \
    && COMPOSER_MEMORY_LIMIT=-1 composer install \
    && composer global remove hirak/prestissimo

#####################################
##        DEVELOPMENT ENVIRONMENT  ##
#####################################
FROM builder AS dev

ENV APP_ENV=dev

COPY --chown=www-data --from=builder /var/www/html /var/www/html
COPY --from=builder /usr/bin/composer /usr/bin/composer
WORKDIR /var/www/html
RUN composer dump-autoload
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chgrp -R www-data /var/www/html/storage && chmod -R ug+rwx /var/www/html/storage /var/www/html/bootstrap
ENTRYPOINT ["sh","/usr/local/bin/entrypoint.sh"]


# TODO: TEST environment needs variable setup acordingly
#####################################
##              TEST               ##
#####################################
FROM php AS test

COPY --chown=www-data --from=assets-builder /var/www/symfony /var/www/symfony
WORKDIR /var/www/symfony

COPY --from=composer /usr/bin/composer /usr/bin/composer



#####################################
##              PROD               ##
#####################################
FROM php AS prod

ENV APP_ENV=prod

COPY --chown=www-data --from=assets-builder /var/www/symfony /var/www/symfony
# RUN pwd && ls
WORKDIR /var/www/symfony

COPY ./www ./

COPY --from=composer /usr/bin/composer /usr/bin/composer
# RUN mkdir /var/logger
# COPY --from=php /var/log/ /var/logger/
# RUN cd /var && ls
# RUN cd /var/logger && ls
# RUN cd ..
#RUN composer global require hirak/prestissimo \
#    && composer install \
#        --ignore-platform-reqs \
#        --no-ansi \
#        --no-dev \
#        --no-interaction \
#    && composer global remove hirak/prestissimo

RUN composer global require hirak/prestissimo \
    && COMPOSER_MEMORY_LIMIT=-1 composer install --no-dev \
    && composer global remove hirak/prestissimo



RUN composer dump-autoload
RUN pwd && ls

# Change the group ownership of the storage and bootstrap/cache directories to www-data
# Recursively grant all permissions, including write and execute, to the group
# RUN chgrp -R www-data /var/www/symfony && chmod -R ug+rwx /var/www/symfony /var/www/symfony
# RUN chown -R www-data:www-data /var
# COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh
COPY ./entrypoint.sh ./
# RUN chgrp -R www-data /var/www/symfony && chmod -R ug+rwx /var/www/symfony
RUN chgrp -R www-data /var/www/symfony/var && chmod -R ug+rwx /var/www/symfony/var

ENTRYPOINT ["sh","entrypoint.sh"]