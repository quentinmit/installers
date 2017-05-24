#!/bin/bash
#
# Copyright (c) 2016 imm studios, z.s.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
##############################################################################
## COMMON UTILS

BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
TEMPDIR=/tmp/$(basename "${BASH_SOURCE[0]}")

function error_exit {
    printf "\n\033[0;31mInstallation failed\033[0m\n"
    cd $BASEDIR
    exit 1
}


function finished {
    printf "\n\033[0;92mInstallation completed\033[0m\n"
    cd $BASEDIR
    exit 0
}


if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   error_exit
fi

if [ ! -d $TEMPDIR ]; then
    mkdir $TEMPDIR || error_exit
fi

## COMMON UTILS
##############################################################################

NGINX_VERSION="1.13.0"
ZLIB_VERSION="1.2.11"
PCRE_VERSION="8.39"
OPENSSL_VERSION="1.1.0e"

MODULES=(
    "https://github.com/martastain/nginx-rtmp-module"
    "https://github.com/openresty/headers-more-nginx-module"
    "https://github.com/wandenberg/nginx-push-stream-module"
)

LIBS=(
    "http://zlib.net/zlib-${ZLIB_VERSION}.tar.gz"
    "ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/pcre-${PCRE_VERSION}.tar.gz"
    "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
)

function install_prerequisites {
    apt-get -y install \
        git \
        build-essential \
        curl \
        libxml2 \
        libxml2-dev \
        libxslt-dev
}

function download_all {
    cd $TEMPDIR
    INSTALLER_NAME="nginx-${NGINX_VERSION}"

    if [ ! -f ${INSTALLER_NAME}.tar.gz ]; then
        wget "http://nginx.org/download/${INSTALLER_NAME}.tar.gz" || return 1
    fi
    if [ ! -d ${INSTALLER_NAME} ]; then
        echo "Unpacking ${INSTALLER_NAME}"
        tar -xf ${INSTALLER_NAME}.tar.gz || return 1
    fi

    # Libs

    for LIB in ${LIBS[@]}; do
        LIBNAME=`basename ${LIB}`
        if [ ! -f ${LIBNAME} ]; then
            echo "Downloading ${LIBNAME}"
            wget ${LIB} || return 1
        fi
        if [ ! -d `basename ${LIB} | cut -f 1 -d "."` ]; then
            echo "Unpacking ${LIBNAME}"
            tar -xf ${LIBNAME} || return 1
        fi
    done

    # Modules

    for i in ${MODULES[@]}; do
        MNAME=`basename $i`
        if [ -d $MNAME ]; then
            cd $MNAME
            git pull || return 1
            cd ..
        else
            git clone $i || return 1
        fi
    done
}


function build_nginx {
    cd $TEMPDIR/nginx-${NGINX_VERSION}

    CMD="./configure \
        --prefix=/usr/share/nginx \
        --sbin-path=/usr/sbin/nginx \
        --conf-path=/etc/nginx/nginx.conf \
        --pid-path=/run/nginx.pid \
        --lock-path=/var/lock/nginx.lock \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --user=www-data \
        --group=www-data"

    CMD=$CMD" \
        --with-pcre=$TEMPDIR/pcre-$PCRE_VERSION \
        --with-zlib=$TEMPDIR/zlib-$ZLIB_VERSION \
        --with-openssl=$TEMPDIR/openssl-$OPENSSL_VERSION \
        --with-http_stub_status_module \
        --with-http_flv_module \
        --with-http_mp4_module \
        --with-http_random_index_module \
        --with-http_secure_link_module \
        --with-http_ssl_module \
        --with-http_sub_module \
        --with-http_v2_module \
        --with-http_xslt_module \
        --without-mail_pop3_module \
        --without-mail_smtp_module \
        --without-mail_imap_module"

    for i in ${MODULES[@]}; do
       MNAME=`basename $i`
       CMD=$CMD" --add-module=$TEMPDIR/$MNAME"
    done

    $CMD || return 1
    make && make install || return 1

    return 0
}

function post_install {
    echo "Running post-install configuration..."
    cd $BASEDIR

    HTMLDIR="/var/www"
    DEFAULTDIR="$HTMLDIR/default"

    if [ ! -d $HTMLDIR ]; then
        mkdir $HTMLDIR
    fi

    if [ ! -d $DEFAULTDIR ]; then
        mkdir $DEFAULTDIR
        cp nginx/http.conf $DEFAULTDIR/http.conf
        cp nginx/index.html $DEFAULTDIR/index.html
    fi

    cd $BASEDIR
    cp nginx/nginx.conf /etc/nginx/nginx.conf || return 1
    touch /etc/nginx/cache.conf || return 1
    touch /etc/nginx/ssl.conf || return 1
    cp nginx/nginx.service /lib/systemd/system/nginx.service || return 1

    return 0
}

function add_security {
    dhparam_path="/etc/ssl/certs/dhparam.pem"
    if [ ! -f $dhparam_path ]; then
        openssl dhparam -out $dhparam_path 4096
    fi
    cp nginx/ssl.conf /etc/nginx/ssl.conf
}

function start_nginx {
    echo "(re)starting NGINX service..."
    systemctl daemon-reload
    systemctl enable nginx
    systemctl stop nginx
    systemctl start nginx || error_exit
}


##############################################################################
# TASKS

install_prerequisites || error_exit
download_all || error_exit
build_nginx || error_exit
post_install || error_exit
add_security || error_exit
start_nginx || error_exit

finished
