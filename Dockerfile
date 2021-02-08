FROM openjdk:8-jre-alpine

ENV EMBULK_VERSION=0.9.23

# タイムゾーンをAsia/Tokyoに変更
RUN apk --update add tzdata && \
    cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    apk del tzdata

# 必要なライブラリを取得
RUN apk add --no-cache \
    curl \
    g++ \
    gcc \
    glib-dev \
    make \
    libc6-compat

ENV LANG ja_JP.UTF-8
ENV LANGUAGE ja_JP:ja
ENV LC_ALL ja_JP.UTF-8

ENV PATH=${PATH}:/usr/local/bin

# Embulk 本体をインストールする
RUN wget -q https://dl.bintray.com/embulk/maven/embulk-${EMBULK_VERSION}.jar -O /bin/embulk \
    && chmod +x /bin/embulk

# Embulkで使うライブラリをインストール
RUN embulk gem install embulk-input-s3 && \
    embulk gem install embulk-output-bigquery

# add embulk user
RUN adduser -D -h /home/embulk embulk
RUN mkdir workspace
WORKDIR /home/embulk/workspace
USER embulk
