FROM debian:bullseye-slim
ENV DEBIAN_FRONTEND=noninteractive

LABEL maintainer="Ryo Ota <nwtgck@nwtgck.org>"

# Versions
ENV NGINX_VERSION=nginx-1.21.4
ENV OPENRESTY_VERSION=openresty-1.21.4.1rc3
ENV QUICHE_NGINX_PATCH_1=1.16
ENV QUICHE_NGINX_PATCH_2=1.19.7
ENV QUICHE_VERSION=0.12.0
ENV PAGESPEED_INCUBATOR_VERSION=1.14.36.1

# Requirements
RUN rm /etc/apt/sources.list
Run echo "deb http://deb.debian.org/debian bullseye main" >> /etc/apt/sources.list
Run echo "deb http://deb.debian.org/debian/ bullseye-updates main" >> /etc/apt/sources.list
Run echo "deb http://security.debian.org/debian-security bullseye-security main" >> /etc/apt/sources.list

RUN apt update -y && apt upgrade -y --allow-downgrades && apt dist-upgrade -y --allow-downgrades && apt autoclean && apt clean && apt autoremove -y && apt -o DPkg::Options::="--force-confnew" -y install libcrypt1 libc-dev-bin libc-devtools libc6-dev-amd64-cross libc6-amd64-cross uuid-dev make build-essential curl wget libpcre3 libpcre3-dev zlib1g-dev git brotli patch git unzip cmake libssl-dev perl -y

# Rust
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
RUN rustup toolchain install nightly

# Openresty Install
RUN curl "https://openresty.org/download/${OPENRESTY_VERSION}.tar.gz" | tar zx
RUN mv ${OPENRESTY_VERSION} build

# Pagespeed
RUN cd build && wget "https://github.com/apache/incubator-pagespeed-ngx/archive/refs/heads/master.zip" && unzip master.zip
RUN cd build/incubator-pagespeed-ngx-master && curl https://dist.apache.org/repos/dist/release/incubator/pagespeed/${PAGESPEED_INCUBATOR_VERSION}/x64/psol-${PAGESPEED_INCUBATOR_VERSION}-apache-incubating-x64.tar.gz | tar zx

# Brotli
RUN cd build && git clone --recursive https://github.com/google/ngx_brotli

# Quiche
RUN cd build && git clone --recursive https://github.com/cloudflare/quiche && cd quiche && git checkout tags/${QUICHE_VERSION}
RUN cd build/quiche && rustup override set nightly
RUN cd build && mv quiche/nginx/nginx-${QUICHE_NGINX_PATCH_1}.patch bundle/${NGINX_VERSION}/nginx-${QUICHE_NGINX_PATCH_1}.patch
RUN cd build && curl -L https://raw.githubusercontent.com/angristan/nginx-autoinstall/master/patches/nginx-http3-${QUICHE_NGINX_PATCH_2}.patch -o bundle/${NGINX_VERSION}/nginx-http3-1.19.7.patch
RUN cd build/bundle/${NGINX_VERSION} && patch -p01 < nginx-${QUICHE_NGINX_PATCH_1}.patch; exit 0
RUN cd build/bundle/${NGINX_VERSION} && patch -p01 < nginx-http3-${QUICHE_NGINX_PATCH_2}.patch; exit 0

# Configure & Build & Install
RUN cd build && ./configure \
    --prefix=$PWD \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --user=nginx \
    --group=nginx \
    --with-pcre-jit \
    --with-ipv6 \
    --with-compat \
    --with-threads \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_mp4_module \
    --with-http_random_index_module \
    --with-http_realip_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-mail \
    --with-mail_ssl_module \
    --with-stream \
    --with-stream_realip_module \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --add-module=/build/incubator-pagespeed-ngx-master \
    --add-module=/build/ngx_brotli \
    --with-openssl=/build/quiche/quiche/deps/boringssl \
    --with-quiche=/build/quiche \
    && make -j2 && make install && rm -rf /build

# Cleanup
#RUN rm -rf /build && \
#   apt purge -y curl git build-essential cmake golang-go patch wget unzip && \
#   apt autoclean && apt clean && apt autoremove -y && \
#   rustup self uninstall -y && \
#   rm -rf /var/lib/apt/lists/*

CMD ["/usr/sbin/nginx", "-g", "daemon off;"]
