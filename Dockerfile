# Fast Dev Container (fdevc:latest)
# Full-featured development environment based on Astral UV + Python 3.13 + Docker + dev tools on Debian Trixie Slim
# Optional tools: Node.js, Deno, Go, Rust
#
# ============================================================================
# TOOL VERSIONS - Edit these lines to customize your build:
# ============================================================================
# Set to "false" to disable a tool
# Set to "true" to use the pinned version below
# Set to a specific version string to use that version (e.g., "20" for Node, "1.23.0" for Go)

FROM ghcr.io/astral-sh/uv:python3.13-trixie-slim

# Tool installation flags - EDIT THESE to enable/disable tools
ENV NODE_INSTALL="true" \
    DENO_INSTALL="true" \
    GO_INSTALL="true" \
    RUST_INSTALL="true"

# Tool versions - EDIT THESE to change versions (used when flag is "true")
ENV NODE_VERSION="24" \
    DENO_VERSION="latest" \
    GO_VERSION="1.24.9" \
    RUST_TOOLCHAIN="stable"

# System configuration
ENV DEBIAN_FRONTEND=noninteractive \
    RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    GOPATH=/go \
    GOBIN=/go/bin \
    DENO_INSTALL=/usr/local \
    PATH=/usr/local/go/bin:/usr/local/cargo/bin:/go/bin:/usr/local/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_SYSTEM_PYTHON=1 \
    UV_COMPILE_BYTECODE=1 \
    GIT_DISCOVERY_ACROSS_FILESYSTEM=1 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    DOCKER_HOST=unix:///var/run/docker.sock

# Install system dependencies, Node.js (conditional), and Docker
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build essentials
    build-essential \
    cmake \
    pkg-config \
    make \
    autoconf \
    automake \
    libtool \
    # Crypto and compression libraries
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libffi-dev \
    liblzma-dev \
    # Version control
    git \
    git-lfs \
    # Network tools
    curl \
    wget \
    netcat-openbsd \
    # Text editors
    vim \
    nano \
    # Terminal tools
    tmux \
    # Shell utilities
    bash-completion \
    # File utilities
    zip \
    unzip \
    file \
    # Process and system tools
    procps \
    htop \
    tree \
    psmisc \
    lsof \
    strace \
    less \
    # JSON/YAML tools
    jq \
    # SSH client
    openssh-client \
    # Utils for Docker setup
    ca-certificates \
    gnupg \
    lsb-release \
    apt-transport-https \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    # Install Docker packages
    && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
    # Add Bullseye repo and install legacy libssl1.1 (for compatibility)
    && echo "deb http://deb.debian.org/debian bullseye main" >> /etc/apt/sources.list.d/bullseye.list \
    && apt-get update \
    && apt-get install -y libssl1.1 \
    # Cleanup
    && rm /etc/apt/sources.list.d/bullseye.list \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install Python dev tools using UV (much faster than pip)
RUN uv pip install --system --no-cache \
    # Package managers (UV is already included)
    pip-tools \
    poetry \
    # Code quality and formatting
    ruff \
    black \
    isort \
    # Type checking and linting
    mypy \
    pylint \
    # Testing
    pytest \
    pytest-cov \
    pytest-asyncio \
    # Interactive and notebooks
    ipython \
    jupyterlab \
    # Web frameworks
    fastapi \
    uvicorn[standard] \
    # Data validation
    pydantic \
    pydantic-settings \
    # HTTP clients
    httpx \
    aiohttp \
    requests \
    # CLI building
    typer \
    click \
    # Environment variables
    python-dotenv \
    # Terminal UI
    rich

# Install Node.js package managers and tools (conditional)
RUN if [ "${NODE_INSTALL}" != "false" ]; then \
    NODE_VER="${NODE_VERSION}"; \
    if [ "${NODE_INSTALL}" != "true" ]; then NODE_VER="${NODE_INSTALL}"; fi; \
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VER}.x" | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g --loglevel=error \
    npm@latest \
    yarn \
    pnpm \
    typescript \
    ts-node \
    tsx \
    nodemon \
    pm2 \
    concurrently \
    dotenv-cli \
    eslint \
    prettier \
    vite \
    turbo \
    vitest \
    rimraf \
    && npm cache clean --force; \
    fi

# Install Deno (conditional)
RUN if [ "${DENO_INSTALL}" != "false" ]; then \
    DENO_VER="${DENO_VERSION}"; \
    if [ "${DENO_INSTALL}" != "true" ]; then DENO_VER="${DENO_INSTALL}"; fi; \
    if [ "${DENO_VER}" = "latest" ]; then \
    curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh -s; \
    else \
    curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh -s "v${DENO_VER}"; \
    fi \
    && chmod +x /usr/local/bin/deno \
    fi

# Install Go (conditional)
RUN if [ "${GO_INSTALL}" != "false" ]; then \
    GO_VER="${GO_VERSION}"; \
    if [ "${GO_INSTALL}" != "true" ]; then GO_VER="${GO_INSTALL}"; fi; \
    curl -fsSL "https://go.dev/dl/go${GO_VER}.linux-amd64.tar.gz" -o /tmp/go.tar.gz \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz \
    && mkdir -p /go/src /go/bin \
    && chmod -R 777 /go; \
    fi

# Install Rust (conditional)
RUN if [ "${RUST_INSTALL}" != "false" ]; then \
    TOOLCHAIN="${RUST_TOOLCHAIN}"; \
    if [ "${RUST_INSTALL}" != "true" ]; then TOOLCHAIN="${RUST_INSTALL}"; fi; \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    --default-toolchain "${TOOLCHAIN}" \
    --profile minimal \
    --component rustfmt,clippy,rust-analyzer \
    && chmod -R a+w /usr/local/rustup /usr/local/cargo \
    && /usr/local/cargo/bin/cargo install cargo-watch cargo-edit --locked \
    && rm -rf /usr/local/cargo/registry; \
    fi

# Install fdevc (Fast Dev Container CLI)
RUN curl -fsSL https://raw.githubusercontent.com/philogicae/fast_dev_container/main/install | bash

# Configure git for better UX
RUN git config --global init.defaultBranch main \
    && git config --global core.editor nano \
    && git config --global pull.rebase false \
    && git config --global safe.directory '*' \
    && git config --global user.name "Dev Container" \
    && git config --global user.email "dev@container.local" \
    && git config --global color.ui auto

# Set working directory
WORKDIR /workspace

# Add healthcheck (conditional based on installed tools)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD uv --version \
    && ([ "${NODE_INSTALL}" = "false" ] || node --version) \
    && ([ "${DENO_INSTALL}" = "false" ] || deno --version) \
    && ([ "${GO_INSTALL}" = "false" ] || go version) \
    && ([ "${RUST_INSTALL}" = "false" ] || rustc --version) \
    || exit 1

# Generate and save build information to file (only installed tools shown)
RUN { \
    printf "\n\033[1;36m═══ ENVIRONMENT INFO ═══\033[0m\n"; \
    printf "\033[0;90m🐧 $(cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '\"')\033[0m\n"; \
    printf "\033[1;33m🐍 Python\033[0m \033[0;36m$(python --version 2>&1 | awk '{print $2}')\033[0m • \033[1;35mUV\033[0m \033[0;36m$(uv --version 2>&1 | awk '{print $2}')\033[0m • \033[1;35mPoetry\033[0m \033[0;36m$(poetry --version 2>&1 | awk '{print $NF}' | tr -d ')')\033[0m\n"; \
    if [ "${NODE_INSTALL}" != "false" ]; then \
    printf "\033[1;32m🟢 Node\033[0m \033[0;36m$(node --version)\033[0m • \033[1;32mnpm\033[0m \033[0;36m$(npm --version)\033[0m • \033[1;32mpnpm\033[0m \033[0;36m$(pnpm --version)\033[0m • \033[1;32myarn\033[0m \033[0;36m$(yarn --version)\033[0m\n"; \
    fi; \
    if [ "${DENO_INSTALL}" != "false" ]; then \
    printf "\033[1;36m🦕 Deno\033[0m \033[0;36m$(deno --version | head -n1 | awk '{print $2}')\033[0m\n"; \
    fi; \
    if [ "${GO_INSTALL}" != "false" ]; then \
    printf "\033[1;34m🐹 Go\033[0m \033[0;36m$(go version | awk '{print $3}' | sed 's/go//')\033[0m\n"; \
    fi; \
    if [ "${RUST_INSTALL}" != "false" ]; then \
    printf "\033[1;31m🦀 Rust\033[0m \033[0;36m$(rustc --version | awk '{print $2}')\033[0m • \033[1;31mCargo\033[0m \033[0;36m$(cargo --version | awk '{print $2}')\033[0m\n"; \
    fi; \
    printf "\033[1;34m🐳 Docker\033[0m \033[0;36m$(docker --version | awk '{print $3}' | tr -d ',')\033[0m • \033[1;34mCompose\033[0m \033[0;36m$(docker compose version --short)\033[0m\n"; \
    printf "\033[0;90m🔧 Git\033[0m \033[0;36m$(git --version | awk '{print $3}')\033[0m • \033[0;90mCMake\033[0m \033[0;36m$(cmake --version | head -n1 | awk '{print $3}')\033[0m • \033[0;90mMake\033[0m \033[0;36m$(make --version | head -n1 | awk '{print $3}')\033[0m\n"; \
    printf "\033[1;35m📦 fdevc\033[0m \033[1;32m✅ Ready for development!\033[0m\n\n"; \
    } | tee /etc/container-info.txt && \
    # Add to .bashrc to display on login (once per session)
    echo '' >> /root/.bashrc && \
    echo '# Display container info on login (once per session)' >> /root/.bashrc && \
    echo 'if [ -f /etc/container-info.txt ] && [ -z "$CONTAINER_INFO_SHOWN" ]; then' >> /root/.bashrc && \
    echo '    cat /etc/container-info.txt' >> /root/.bashrc && \
    echo '    export CONTAINER_INFO_SHOWN=1' >> /root/.bashrc && \
    echo 'fi' >> /root/.bashrc

# Keep container running
CMD ["tail", "-f", "/dev/null"]