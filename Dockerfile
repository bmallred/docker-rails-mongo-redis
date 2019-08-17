FROM ubuntu:xenial

#
# Dependencies
#

# skip installing gem documentation
RUN set -eux; \
    mkdir -p /usr/local/etc; \
	{ \
		echo 'install: --no-document'; \
		echo 'update: --no-document'; \
	} >> /usr/local/etc/gemrc

RUN set -eux; \
    apt-get update -qq; \
    apt-get install -y --no-install-recommends \
            ca-certificates \
            gcc \
	    libc6-dev \
	    dpkg-dev \
	    libgdbm-dev \
	    ruby \
            make \
            build-essential \
            libpq-dev \
            tcl8.5 \
            nodejs \
            imagemagick \
            curl \
	    wget \
            git \
	    gnupg2 \
            libgmp3-dev \
            libgtkmm-3.0.1 \
            libnotify4 \
	    bison \
	    jq \
	    numactl; \
    if ! command -v ps > /dev/null; then \
        apt-get install -y --no-install-recommends procps; \
    fi; \
    if ! command -v gpg > /dev/null; then \
        apt-get install -y --no-install-recommends gnupg2 dirmngr; \
    elif gpg --version | grep -q '^gpg (GnuPG) 1\.'; then \
        apt-get install -y --no-install-recommends gnupg-curl; \
    fi; \
    rm -rf /var/lib/apt/lists/*;

#
# Ruby
#

ENV RUBY_MAJOR 2.4
ENV RUBY_VERSION 2.4.1
ENV RUBY_DOWNLOAD_SHA256 25da31b9815bfa9bba9f9b793c055a40a35c43c6adfb1fdbd81a09099f9b529c
ENV RUBYGEMS_VERSION 3.0.3

RUN wget -O ruby.tar.xz "https://cache.ruby-lang.org/pub/ruby/${RUBY_MAJOR%-rc}/ruby-$RUBY_VERSION.tar.xz"; \
    echo "$RUBY_DOWNLOAD_SHA256 *ruby.tar.xz" | sha256sum --check --strict; \
    \
    mkdir -p /usr/src/ruby; \
    tar -xJf ruby.tar.xz -C /usr/src/ruby --strip-components=1; \
    rm ruby.tar.xz; \
    \
    cd /usr/src/ruby; \
    \
    # hack in "ENABLE_PATH_CHECK" disabling to suppress:
    #   warning: Insecure world writable dir
    { \
        echo '#define ENABLE_PATH_CHECK 0'; \
        echo; \
        cat file.c; \
    } > file.c.new; \
    mv file.c.new file.c; \
    \
    autoconf; \
    gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
    ./configure --build="$gnuArch" --disable-install-doc --enable-shared; \
    make -j "$(nproc)"; \
    make install; \
    \
# apt-mark auto '.*' > /dev/null; \
# apt-mark manual $savedAptMark > /dev/null; \
    find /usr/local -type f -executable -not \( -name '*tkinter*' \) -exec ldd '{}' ';' \
         | awk '/=>/ { print $(NF-1) }' \
         | sort -u \
         | xargs -r dpkg-query --search \
         | cut -d: -f1 \
         | sort -u \
         | xargs -r apt-mark manual \
    ; \
# apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    \
    cd /; \
    rm -r /usr/src/ruby; \
    # make sure bundled "rubygems" is older than RUBYGEMS_VERSION (https://github.com/docker-library/ruby/issues/246)
    ruby -e 'exit(Gem::Version.create(ENV["RUBYGEMS_VERSION"]) > Gem::Version.create(Gem::VERSION))'; \
    gem update --system "$RUBYGEMS_VERSION" && rm -r /root/.gem/; \
    # verify we have no "ruby" packages installed
    ! dpkg -l | grep -i ruby; \
    [ "$(command -v ruby)" = '/usr/local/bin/ruby' ]; \
    # rough smoke test
    ruby --version; \
    gem --version; \
    bundle --version

# install things globally, for great justice
# and don't create ".bundle" in all our apps
ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_PATH="$GEM_HOME" \
    BUNDLE_SILENCE_ROOT_WARNING=1 \
    BUNDLE_APP_CONFIG="$GEM_HOME"
# path recommendation: https://github.com/bundler/bundler/pull/6469#issuecomment-383235438
ENV PATH $GEM_HOME/bin:$BUNDLE_PATH/gems/bin:$PATH
# adjust permissions of a few directories for running "gem install" as an arbitrary user
RUN mkdir -p "$GEM_HOME" && chmod 777 "$GEM_HOME"

#
# Rails
#

# RUN gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3
RUN gpg --version; \
    command curl -sSL https://rvm.io/mpapis.asc | gpg --import -; \
    command curl -sSL https://rvm.io/pkyczynski.asc | gpg --import -; \
    gpg --keyserver hkp://pool.sks-keyservers.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB; \
    bash -c "curl -sSL https://get.rvm.io | bash -s stable --ruby=$RUBY_VERSION --rails; exit 0"

#
# Gosu
#

ENV GOSU _VERSION 1.11

RUN savedAptMark="$(apt-mark showmanual)"; \
    dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')";
RUN wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
    wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
# verify the signature
    export GNUPGHOME="$(mktemp -d)"; \
    gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
    gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
    command -v gpgconf && gpgconf --kill all || :; \
    rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
# clean up fetch dependencies
# apt-mark auto '.*' > /dev/null; \
# [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
# apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    chmod +x /usr/local/bin/gosu; \
# verify that the binary works
    gosu --version; \
    gosu nobody true;

#
# Redis
# https://github.com/docker-library/redis/blob/master/5.0
#

RUN groupadd -r -g 999 redis && useradd -r -g redis -u 999 redis;

ENV REDIS_VERSION 5.0.5
ENV REDIS_DOWNLOAD_URL http://download.redis.io/releases/redis-5.0.5.tar.gz
ENV REDIS_DOWNLOAD_SHA 2139009799d21d8ff94fc40b7f36ac46699b9e1254086299f8d3b223ca54a375

RUN wget -O redis.tar.gz "$REDIS_DOWNLOAD_URL"; \
    echo "$REDIS_DOWNLOAD_SHA *redis.tar.gz" | sha256sum -c -; \
    mkdir -p /usr/src/redis; \
    tar -xzf redis.tar.gz -C /usr/src/redis --strip-components=1; \
    rm redis.tar.gz; \
# disable Redis protected mode [1] as it is unnecessary in context of Docker
# (ports are not automatically exposed when running inside Docker, but rather explicitly by specifying -p / -P)
# [1]: https://github.com/antirez/redis/commit/edd4d555df57dc84265fdfb4ef59a4678832f6da
    grep -q '^#define CONFIG_DEFAULT_PROTECTED_MODE 1$' /usr/src/redis/src/server.h; \
    sed -ri 's!^(#define CONFIG_DEFAULT_PROTECTED_MODE) 1$!\1 0!' /usr/src/redis/src/server.h; \
    grep -q '^#define CONFIG_DEFAULT_PROTECTED_MODE 0$' /usr/src/redis/src/server.h; \
# for future reference, we modify this directly in the source instead of just supplying a default configuration flag because apparently "if you specify any argument to redis-server, [it assumes] you are going to specify everything"
# see also https://github.com/docker-library/redis/issues/4#issuecomment-50780840
# (more exactly, this makes sure the default behavior of "save on SIGTERM" stays functional by default)
    \
    make -C /usr/src/redis -j "$(nproc)"; \
    make -C /usr/src/redis install; \
    \
# TODO https://github.com/antirez/redis/pull/3494 (deduplicate "redis-server" copies)
    serverMd5="$(md5sum /usr/local/bin/redis-server | cut -d' ' -f1)"; export serverMd5; \
    find /usr/local/bin/redis* -maxdepth 0 \
         -type f -not -name redis-server \
         -exec sh -eux -c ' \
             md5="$(md5sum "$1" | cut -d" " -f1)"; \
             test "$md5" = "$serverMd5"; \
         ' -- '{}' ';' \
         -exec ln -svfT 'redis-server' '{}' ';' \
    ; \
    \
    rm -r /usr/src/redis; \
    \
# apt-mark auto '.*' > /dev/null; \
# [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
# apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    \
    redis-cli --version; \
    redis-server --version

RUN mkdir /data && chown redis:redis /data
VOLUME /data 

#
# Mongo
# https://github.com/docker-library/mongo/blob/master/3.4
#

RUN groupadd -r mongodb && useradd -r -g mongodb mongodb;

ENV JSYAML_VERSION 3.13.0

RUN export GNUPGHOME="$(mktemp -d)"; \
    gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
    gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
    command -v gpgconf && gpgconf --kill all || :; \
    rm -r "$GNUPGHOME" /usr/local/bin/gosu.asc; \
    chmod +x /usr/local/bin/gosu; \
    gosu --version; \
    gosu nobody true; \
    \
    wget -O /js-yaml.js "https://github.com/nodeca/js-yaml/raw/${JSYAML_VERSION}/dist/js-yaml.js";
# TODO some sort of download verification here
# apt-mark auto '.*' > /dev/null; \
# apt-mark manual $savedAptMark > /dev/null;
# apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false
RUN mkdir /docker-entrypoint-initdb.d

ENV GPG_KEYS 0C49F3730359A14518585931BC711F9BA15703C6
RUN set -ex; \
	export GNUPGHOME="$(mktemp -d)"; \
	for key in $GPG_KEYS; do \
		gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
	done; \
	gpg --batch --export $GPG_KEYS > /etc/apt/trusted.gpg.d/mongodb.gpg; \
	command -v gpgconf && gpgconf --kill all || :; \
	rm -r "$GNUPGHOME"; \
	apt-key list

# Allow build-time overrides (eg. to build image with MongoDB Enterprise version)
# Options for MONGO_PACKAGE: mongodb-org OR mongodb-enterprise
# Options for MONGO_REPO: repo.mongodb.org OR repo.mongodb.com
# Example: docker build --build-arg MONGO_PACKAGE=mongodb-enterprise --build-arg MONGO_REPO=repo.mongodb.com .
ARG MONGO_PACKAGE=mongodb-org
ARG MONGO_REPO=repo.mongodb.org
ENV MONGO_PACKAGE=${MONGO_PACKAGE} MONGO_REPO=${MONGO_REPO}

ENV MONGO_MAJOR 3.4
ENV MONGO_VERSION 3.4.22
# bashbrew-architectures:amd64 arm64v8
RUN echo "deb http://$MONGO_REPO/apt/ubuntu xenial/${MONGO_PACKAGE%-unstable}/$MONGO_MAJOR multiverse" | tee "/etc/apt/sources.list.d/${MONGO_PACKAGE%-unstable}.list"

RUN set -x \
	&& apt-get update \
	&& apt-get install -y \
		${MONGO_PACKAGE}=$MONGO_VERSION \
		${MONGO_PACKAGE}-server=$MONGO_VERSION \
		${MONGO_PACKAGE}-shell=$MONGO_VERSION \
		${MONGO_PACKAGE}-mongos=$MONGO_VERSION \
		${MONGO_PACKAGE}-tools=$MONGO_VERSION \
	&& rm -rf /var/lib/apt/lists/* \
	&& rm -rf /var/lib/mongodb \
	&& mv /etc/mongod.conf /etc/mongod.conf.orig

RUN mkdir -p /data/db /data/configdb \
 && chown -R mongodb:mongodb /data/db /data/configdb
VOLUME /data/db /data/configdb

COPY docker-entrypoint.sh /usr/local/bin/
RUN ln -s usr/local/bin/docker-entrypoint.sh /entrypoint.sh # backwards compat (3.4)

#
# App specific
#

ENTRYPOINT ["docker-entrypoint.sh"]
EXPOSE 27017
EXPOSE 6379

RUN mkdir /app
WORKDIR /app