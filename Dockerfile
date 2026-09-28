ARG RUBY_VERSION=3.3.6
FROM docker.io/library/ruby:$RUBY_VERSION-slim

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential curl git libpq-dev libvips libyaml-dev pkg-config postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV BUNDLE_PATH="/usr/local/bundle" \
    RAILS_ENV="production" \
    RAILS_LOG_TO_STDOUT="true"

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

COPY bin/docker-entrypoint /usr/bin/
RUN chmod +x /usr/bin/docker-entrypoint bin/*

# builds/ is gitignored — compile CSS/JS into the image for Propshaft
RUN SECRET_KEY_BASE_DUMMY=1 ACTIVE_STORAGE_SERVICE=local \
    ./bin/rails active_admin:bundle_js dartsass:build assets:precompile

EXPOSE 3000
ENTRYPOINT ["docker-entrypoint"]
CMD ["./bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
