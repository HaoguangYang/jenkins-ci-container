ARG UBUNTU_RELEASE=22.04
FROM ubuntu:${UBUNTU_RELEASE}

RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt/lists \
    apt-get update && apt-get install --no-install-recommends -y \
    openssh-client curl ca-certificates gnupg2 iptables

# Install Docker, Docker compose, and buildx
RUN curl -s https://download.docker.com/linux/static/stable/`uname -m`/ |\
    grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | sort -t . -k 1,1n -k 2,2n -k 3,3n | tail -n 1 > /tmp/docker_version \
    && curl -fsSL https://download.docker.com/linux/static/stable/`uname -m`/docker-`cat /tmp/docker_version`.tgz |\
    tar --strip-components=1 -xz -C /usr/local/bin \
    && rm /tmp/docker_version
RUN curl -s -I https://github.com/docker/compose/releases/latest |\
    awk -F '/' '/^location/ {print substr($NF, 1, length($NF)-1)}'  > /tmp/compose_version \
    && mkdir -p /usr/libexec/docker/cli-plugins/ \
    && curl -fsSL https://github.com/docker/compose/releases/download/`\
    cat /tmp/compose_version`/docker-compose-`uname -s`-`uname -m` > /usr/libexec/docker/cli-plugins/docker-compose \
    && chmod +x /usr/libexec/docker/cli-plugins/docker-compose \
    && rm /tmp/compose_version
## buildx is released as amd64, and uname calls it x86_64
RUN uname -m > /tmp/arch \
    && sed -i 's/x86_64/amd64/g' /tmp/arch \
    && curl -s -I https://github.com/docker/buildx/releases/latest |\
    awk -F '/' '/^location/ {print substr($NF, 1, length($NF)-1)}' > /tmp/buildx_version \
    && curl -fsSL https://github.com/docker/buildx/releases/download/`\
    cat /tmp/buildx_version`/buildx-`cat /tmp/buildx_version`.linux-`cat /tmp/arch` > /usr/libexec/docker/cli-plugins/docker-buildx \
    && chmod +x /usr/libexec/docker/cli-plugins/docker-buildx \
    && docker buildx install \
    && rm /tmp/arch /tmp/buildx_version

# nvidia container toolkit
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt/lists \
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
    gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
    && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list \
    && apt-get update && apt-get install --no-install-recommends -y nvidia-container-toolkit

# set up subuid/subgid so that "--userns-remap=default" works out-of-the-box
RUN set -eux; \
    useradd --system dockremap; \
    usermod -aG dockremap dockremap; \
    echo 'dockremap:165536:65536' >> /etc/subuid; \
    echo 'dockremap:165536:65536' >> /etc/subgid

ENV DOCKER_TLS_CERTDIR=/certs
RUN mkdir /certs /certs/client && chmod 1777 /certs /certs/client

# add dind
RUN echo $(curl -fsSL https://github.com/moby/moby/releases/tag/`\
    curl -s -I https://github.com/moby/moby/releases/latest | awk -F '/' '/^location/ {print substr($NF, 1, length($NF)-1)}'` |\
    grep "/commit/" | sed 's/.*\/commit\/\([a-z0-9]*\).*/\1/') | cut -d' ' -f1 > /tmp/dind_commit \
    && curl -fsSL https://raw.githubusercontent.com/moby/moby/`cat /tmp/dind_commit`/hack/dind > /usr/local/bin/dind \
    && chmod +x /usr/local/bin/dind && rm /tmp/dind_commit
ADD https://raw.githubusercontent.com/docker-library/docker/master/modprobe.sh /usr/local/bin/modprobe
ADD https://raw.githubusercontent.com/docker-library/docker/master/dockerd-entrypoint.sh /usr/local/bin/
ADD https://raw.githubusercontent.com/docker-library/docker/master/docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/dockerd-entrypoint.sh /usr/local/bin/docker-entrypoint.sh /usr/local/bin/modprobe

VOLUME /var/lib/docker
EXPOSE 2375 2376

ENTRYPOINT ["dockerd-entrypoint.sh"]
CMD []
