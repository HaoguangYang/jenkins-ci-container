FROM jenkins/agent:latest-alpine

USER root

RUN /bin/sh -c "apk add --no-cache docker-cli docker-cli-buildx docker-cli-compose pigz && \
    rm -rf /tmp/*.apk /tmp/gcc /tmp/gcc-libs.tar* /tmp/libz /tmp/libz.tar.xz /var/cache/apk/*"

USER jenkins
