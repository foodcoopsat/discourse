FROM ruby:3.3.6-bookworm AS base

ENV RAILS_ENV=production \
    DISCOURSE_SERVE_STATIC_ASSETS=true \
    RUBY_ALLOCATOR=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2 \
    RUBY_GLOBAL_METHOD_CACHE_SIZE=131072 \
    NODE_MAJOR=18

RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" > /etc/apt/sources.list.d/nodesource.list

RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update \
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
    lsb-release \
    postgresql-client \
    silversearcher-ag \
    vim-tiny \
    && rm -rf /var/lib/apt/lists/*

FROM base AS imagemagick_builder
RUN apt update && \
DEBIAN_FRONTEND=noninteractive apt-get -y install wget \
    autoconf build-essential \
    git \
    cmake \
    gnupg \
    libpcre3-dev \
    libfreetype6-dev \
    libbrotli-dev

ADD discourse_docker/image/base/install-imagemagick /tmp/install-imagemagick
RUN /tmp/install-imagemagick

FROM base AS complete
# add node and npm to path so the commands are available
# ENV NODE_PATH $NVM_DIR/v$NODE_VERSION/lib/node_modules
# ENV PATH $NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH

# Copy binary and configuration files for magick
COPY --from=imagemagick_builder /usr/local/bin/magick /usr/local/bin/magick
COPY --from=imagemagick_builder /usr/local/etc/ImageMagick-7 /usr/local/etc/ImageMagick-7
COPY --from=imagemagick_builder /usr/local/share/ImageMagick-7 /usr/local/share/ImageMagick-7

RUN npm install -g terser uglify-js pnpm@9 patch-package ember-cli express yarn


ENV OXIPNG_VERSION 8.0.0
ENV OXIPNG_SHA256 38e9123856bab64bb798c6630f86fa410137ed06e7fa6ee661c7b3c7a36e60fe

RUN curl -o oxipng.tar.gz -fSL "https://github.com/shssoichiro/oxipng/releases/download/v${OXIPNG_VERSION}/oxipng-${OXIPNG_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    && echo "$OXIPNG_SHA256 oxipng.tar.gz" | sha256sum -c - \
    && tar -xzf oxipng.tar.gz \
    && mv oxipng-*/oxipng /usr/bin/ \
    && rm -r oxipng*

RUN addgroup --gid 1000 discourse \
    && adduser --system --uid 1000 --ingroup discourse --shell /bin/bash discourse

WORKDIR /home/discourse/discourse

ENV DISCOURSE_VERSION 3.4.2


RUN git clone --branch v${DISCOURSE_VERSION} --depth 1 https://github.com/discourse/discourse.git . 

RUN bundle config build.nokogiri --use-system-libraries \
    && gem install bundler --conservative -v $(awk '/BUNDLED WITH/ { getline; gsub(/ /,""); print $0 }' Gemfile.lock) \
    && bundle config set without development test \
    && bundle config set path ./vendor/bundle\
    && bundle config set deployment true \
    && bundle install --jobs 8 


# yarn patch-package doesnt work
# RUN echo 'patch-package' > app/assets/javascripts/run-patch-package \
    # && yarn install --frozen-lockfile \
RUN pnpm install --frozen-lockfile
# RUN bundle exec rake yarn:install

ENV DISCOURSE_ASSIGN_VERSION=d8888c45899d607516c2bb4b7a3c116f8f6470f0
ENV DISCOURSE_CALENDAR_VERSION=90313ae82a6640c2c20a9264c04ae1a35fa5f7a9
ENV DISCOURSE_DATA_EXPLORER_VERSION=7922daf500c8a976a8fc046aac61133f9c327745
ENV DISCOURSE_DOCS_VERSION=2bd528a23d1c4b0eb09025e8b30d7c37f14dc371
ENV DISCOURSE_REACTIONS_VERSION=f87583d9054421869ba0de16c24ad15e32bbebe7
ENV DISCOURSE_CHECKLIST_VERSION=6fcf9fed5c3ae3baf9ddd1cca9cef4dc089996c1
ENV DISCOURSE_SOLVED_VERSION=f7bbffa6173b6e06a232e2eeaaef1e4da2d9cb8c
ENV DISCOURSE_GROUP_GLOBAL_NOTICE_VERSION=598c3f22d000d9eb11df073f8e8d749797624653
ENV DISCOURSE_MULTI_SSO_VERSION=e19fc0a860613a10dfc1e080484e3f2e76009da8
ENV DISCOURSE_VIRTMAIL_VERSION=7290b57663c73b1b888ddec7e12cd8f121bbc259

RUN cd plugins \
    && curl -L https://github.com/discourse/discourse-assign/archive/${DISCOURSE_ASSIGN_VERSION}.tar.gz | tar -xz \
    && mv discourse-assign-* discourse-assign \
    && curl -L https://github.com/discourse/discourse-calendar/archive/${DISCOURSE_CALENDAR_VERSION}.tar.gz | tar -xz \
    && mv discourse-calendar-* discourse-calendar \
    && curl -L https://github.com/discourse/discourse-data-explorer/archive/${DISCOURSE_DATA_EXPLORER_VERSION}.tar.gz | tar -xz \
    && mv discourse-data-explorer-* discourse-data-explorer \
    && curl -L https://github.com/discourse/discourse-docs/archive/${DISCOURSE_DOCS_VERSION}.tar.gz | tar -xz \
    && mv discourse-docs-* discourse-docs \
    && curl -L https://github.com/discourse/discourse-reactions/archive/${DISCOURSE_REACTIONS_VERSION}.tar.gz  | tar -xz \
    && mv discourse-reactions-* discourse-reactions \
    && curl -L https://github.com/discourse/discourse-checklist/archive/${DISCOURSE_CHECKLIST_VERSION}.tar.gz | tar -xz \
    && mv discourse-checklist-* discourse-checklist \
    && curl -L https://github.com/discourse/discourse-solved/archive/${DISCOURSE_SOLVED_VERSION}.tar.gz | tar -xz \
    && mv discourse-solved-* discourse-solved \
    && curl -L https://github.com/foodcoopsat/discourse-group-global-notice/archive/${DISCOURSE_GROUP_GLOBAL_NOTICE_VERSION}.tar.gz | tar -xz \
    && mv discourse-group-global-notice-* discourse-group-global-notice \
    && curl -L https://github.com/foodcoopsat/discourse-multi-sso/archive/${DISCOURSE_MULTI_SSO_VERSION}.tar.gz | tar -xz \
    && mv discourse-multi-sso-* discourse-multi-sso \
    && curl -L https://github.com/foodcoopsat/discourse-virtmail/archive/${DISCOURSE_VIRTMAIL_VERSION}.tar.gz | tar -xz \
    && mv discourse-virtmail-* discourse-virtmail

# COPY plugins/discourse-virtmail plugins/discourse-virtmail

# RUN cd app/assets/javascripts/discourse && chown discourse:discourse -R . && su discourse -c 'ember build -prod'

# USER root

FROM complete AS builder

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
    && chown -R discourse /home/discourse/discourse \
    && mkdir /nonexistent/.config/configstore -p \
    && chown -R discourse /nonexistent/.config/configstore \
    && mkdir /nonexistent/.cache/yarn -p \
    && chown -R discourse /nonexistent/.cache/yarn \
    && su discourse -c 'bundle exec rake assets:precompile' \
    && su discourse -c 'bundle exec rake multisite:migrate'

FROM complete

RUN ln -sf /dev/stdout /home/discourse/discourse/log/production.log \
    && ln -sf /dev/stdout /var/log/nginx/access.log  \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
    && chown -R discourse /var/lib/nginx /var/log/nginx

COPY --from=builder --chown=discourse:discourse /home/discourse/discourse/app/assets/javascripts/discourse/dist ./app/assets/javascripts/discourse/dist
COPY --from=builder --chown=discourse:discourse /home/discourse/discourse/plugins ./plugins
COPY --from=builder --chown=discourse:discourse /home/discourse/discourse/public ./public
COPY --from=builder --chown=discourse:discourse /home/discourse/discourse/tmp ./tmp

# Create symlinks to imagemagick tools
RUN ln -s /usr/local/bin/magick /usr/local/bin/animate &&\
  ln -s /usr/local/bin/magick /usr/local/bin/compare &&\
  ln -s /usr/local/bin/magick /usr/local/bin/composite &&\
  ln -s /usr/local/bin/magick /usr/local/bin/conjure &&\
  ln -s /usr/local/bin/magick /usr/local/bin/convert &&\
  ln -s /usr/local/bin/magick /usr/local/bin/display &&\
  ln -s /usr/local/bin/magick /usr/local/bin/identify &&\
  ln -s /usr/local/bin/magick /usr/local/bin/import &&\
  ln -s /usr/local/bin/magick /usr/local/bin/magick-script &&\
  ln -s /usr/local/bin/magick /usr/local/bin/mogrify &&\
  ln -s /usr/local/bin/magick /usr/local/bin/montage &&\
  ln -s /usr/local/bin/magick /usr/local/bin/stream &&\
  test $(magick -version | grep -o -e png -e tiff -e jpeg -e freetype -e heic -e webp | wc -l) -eq 6

# Fix omniauth-discourse compatibility
RUN sed -i 's/URI.escape/CGI.escape/g' plugins/discourse-multi-sso/gems/*/gems/omniauth-discourse-1.0.0/lib/omniauth/strategies/discourse/sso.rb

COPY nginx.conf /etc/nginx/
RUN rm /home/discourse/discourse/config/initializers/100-verify_config.rb
RUN chown -R discourse /home/discourse/discourse

USER discourse

EXPOSE 3000
CMD ["bundle", "exec", "rails", "server", "--binding", "0.0.0.0"]
