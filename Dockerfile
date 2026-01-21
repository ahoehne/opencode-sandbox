FROM debian:trixie-slim

ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TZ=UTC \
    TERM=xterm-256color

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    locales \
    npm \
    curl \
    chromium \
    vim \
    shellcheck \
    build-essential \
    cargo \
    libwebkit2gtk-4.1-dev \
    php-cli \
    php-common \
    php-json \
    php-mbstring \
    php-xml \
    php-zip \
    composer \
    && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -g ${USER_GID} opencodeuser && \
    useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/bash opencodeuser && \
    mkdir -p /workspace /home/opencodeuser/.opencode /home/opencodeuser/.config/opencode /home/opencodeuser/.local/share/opencode && \
    chown -R ${USER_UID}:${USER_GID} /home/opencodeuser && \
    chown -R ${USER_UID}:${USER_GID} /workspace

COPY --chown=${USER_UID}:${USER_GID} entrypoint.sh /home/opencodeuser/entrypoint.sh

USER opencodeuser
WORKDIR /home/opencodeuser

ENV NPM_CONFIG_PREFIX=/home/opencodeuser/.opencode
RUN chown -R ${USER_UID}:${USER_GID} /home/opencodeuser && chmod +x /home/opencodeuser/entrypoint.sh

ENV PATH="/home/opencodeuser/.opencode/bin:${PATH}"

WORKDIR /workspace

ENTRYPOINT ["/home/opencodeuser/entrypoint.sh"]

