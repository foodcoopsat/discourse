FROM ruby:3.2 AS base

ENV RAILS_ENV=production \
    DISCOURSE_SERVE_STATIC_ASSETS=true \
    RUBY_ALLOCATOR=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2 \
    RUBY_GLOBAL_METHOD_CACHE_SIZE=131072

RUN curl --silent --location  https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y --no-install-recommends \
    brotli \
    ghostscript \
    gsfonts \
    imagemagick \
    jhead \
    jpegoptim \
    libjemalloc2 \
    liblqr-1-0 \
    libxml2 \
    nginx \
    nodejs \
    optipng \
    pngcrush \
    pngquant \
    postgresql-client-13; \
    npm install -g terser uglify-js yarn; \
    rm -rf /var/lib/apt/lists/*

ENV OXIPNG_VERSION 8.0.0
ENV OXIPNG_SHA256 38e9123856bab64bb798c6630f86fa410137ed06e7fa6ee661c7b3c7a36e60fe

RUN curl -o oxipng.tar.gz -fSL "https://github.com/shssoichiro/oxipng/releases/download/v${OXIPNG_VERSION}/oxipng-${OXIPNG_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    && echo "$OXIPNG_SHA256 oxipng.tar.gz" | sha256sum -c - \
    && tar -xzf oxipng.tar.gz \
    && mv oxipng-*/oxipng /usr/bin/ \
    && rm -r oxipng*

RUN addgroup --gid 1000 discourse \
    && adduser --system --uid 1000 --ingroup discourse --shell /bin/bash discourse

USER discourse
WORKDIR /home/discourse/discourse

ENV DISCOURSE_VERSION 3.0.1

RUN git clone --branch v${DISCOURSE_VERSION} --depth 1 https://github.com/discourse/discourse.git . \
    && rm config/initializers/100-verify_config.rb \
    && gem install bundler \
    && bundle config build.nokogiri --use-system-libraries \
    && bundle config set deployment true \
    && bundle config set without development test \
    && bundle install --jobs 8 \
    && yarn install --production \
    && yarn cache clean

RUN cd plugins \
    && curl -L https://github.com/discourse/discourse-assign/archive/1268048874bcd5c20c0eaf039284bafa9e4e80de.tar.gz | tar -xz \
    && mv discourse-assign-* discourse-assign \
    && curl -L https://github.com/discourse/discourse-calendar/archive/5c243e6e1524d92e485a39e16df43759a62f02a9.tar.gz | tar -xz \
    && mv discourse-calendar-* discourse-calendar \
    && curl -L https://github.com/discourse/discourse-data-explorer/archive/f51bc050a207c6cc97e3faeb6b527fe989fb285a.tar.gz | tar -xz \
    && mv discourse-data-explorer-* discourse-data-explorer \
    && curl -L https://github.com/discourse/discourse-docs/archive/bf1c4574a61b053c136e2b181ba2fedb6c16f838.tar.gz | tar -xz \
    && mv discourse-docs-* discourse-docs \
    && curl -L https://github.com/discourse/discourse-graphviz/archive/44cbf0a560baaa0457dc83601c6aa7054eebd7eb.tar.gz | tar -xz \
    && mv discourse-graphviz-* discourse-graphviz \
    && curl -L https://github.com/discourse/discourse-jitsi/archive/730dec01c66225ec9f4ba2a11242e1922dc8b000.tar.gz | tar -xz \
    && mv discourse-jitsi-* discourse-jitsi \
    && curl -L https://github.com/discourse/discourse-prometheus/archive/78324fbaa8cfa3040ee7e01ac793ad2515b6c004.tar.gz | tar -xz \
    && mv discourse-prometheus-* discourse-prometheus \
    && curl -L https://github.com/foodcoopsat/discourse-group-global-notice/archive/598c3f22d000d9eb11df073f8e8d749797624653.tar.gz | tar -xz \
    && mv discourse-group-global-notice-* discourse-group-global-notice \
    && curl -L https://github.com/foodcoopsat/discourse-multi-sso/archive/e0562a042c04455f0f978d984b8c8c2d763e981b.tar.gz | tar -xz \
    && mv discourse-multi-sso-* discourse-multi-sso \
    && curl -L https://github.com/foodcoopsat/discourse-virtmail/archive/cb50e37b23d7d1469eb38b706c471f75e1967d83.tar.gz | tar -xz \
    && mv discourse-virtmail-* discourse-virtmail

USER root

FROM base AS builder

RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
    && curl -fsSL https://packages.redis.io/gpg | apt-key add - \
    && echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && echo "deb https://packages.redis.io/deb $(lsb_release -cs) main" > /etc/apt/sources.list.d/redis.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends postgresql-15 redis

RUN /etc/init.d/redis-server start \
    && /etc/init.d/postgresql start \
    && echo " \
    CREATE USER discourse PASSWORD 'discourse';  \n\
    CREATE DATABASE discourse OWNER discourse;  \n\
    \\\\c discourse  \n\
    CREATE EXTENSION hstore;  \n\
    CREATE EXTENSION pg_trgm;" | su postgres -c psql \
    && su discourse -c 'bundle exec rake multisite:migrate' \
    && su discourse -c 'bundle exec rake assets:precompile'

FROM base

RUN ln -sf /dev/stdout log/production.log \
    && ln -sf /dev/stdout /var/log/nginx/access.log  \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
    && chown -R discourse /var/lib/nginx /var/log/nginx

COPY --from=builder --chown=discourse:discourse /home/discourse/discourse/app/assets/javascripts/discourse/dist ./app/assets/javascripts/discourse/dist
COPY --from=builder --chown=discourse:discourse /home/discourse/discourse/plugins ./plugins
COPY --from=builder --chown=discourse:discourse /home/discourse/discourse/public ./public

ADD nginx.conf /etc/nginx/

USER discourse

EXPOSE 3000
CMD ["bundle", "exec", "rails", "server", "--binding", "0.0.0.0"]
