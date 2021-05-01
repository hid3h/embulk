# alpineだとaws-cliが実行できないのでslim
FROM openjdk:8-jre-slim

ARG EMBULK_VERSION=0.9.23

RUN apt-get update \
    && apt-get install -y curl jq

RUN curl --create-dirs -o /usr/local/bin/embulk -L https://dl.embulk.org/embulk-${EMBULK_VERSION}.jar \
    && chmod +x /usr/local/bin/embulk

# aws-cliをインストール
# ARG AWS_CLI_VERSION=2.1.30
# RUN curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWS_CLI_VERSION}.zip -o awscliv2.zip \
#     && unzip awscliv2.zip \
#     && ./aws/install \
#     && rm awscliv2.zip \
#     && rm -rf aws 

# Embulkで使うライブラリをインストール
RUN embulk gem install embulk-input-mysql \
    && embulk gem install embulk-output-bigquery \
    && embulk gem install embulk-filter-ruby_proc
    # && embulk gem install jruby-openssl

RUN mkdir workspace
WORKDIR /workspace
COPY . /workspace
