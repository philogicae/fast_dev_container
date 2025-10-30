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

# Detect target architecture (auto-provided by buildx, fallback to runtime detection)
ARG TARGETARCH

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

# Install system dependencies and Docker
RUN apt-get update \
    # 1. Install prerequisites for adding new repositories
    && apt-get install -y --no-install-recommends \
    curl \
    gpg \
    apt-transport-https \
    ca-certificates \
    # 2. Add Docker GPG Key & Repository
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg \
    && chmod a+r /usr/share/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/debian trixie stable" > /etc/apt/sources.list.d/docker.list \
    # 3. Update apt lists after repositories are added
    && apt-get update \
    # 4. Install all packages in a single command
    && apt-get install -y --no-install-recommends \
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
    # Docker packages
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    # 5. Cleanup
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install "stable" Python dev tools using UV
RUN uv pip install --system --no-cache \
    # Package managers
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
    # Interactive and CLI
    ipython \
    typer \
    click \
    rich

# Install "library" Python tools that may change more often
RUN uv pip install --system --no-cache \
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
    # Notebooks
    jupyterlab \
    # Environment variables
    python-dotenv

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
    @google/gemini-cli \
    && npm cache clean --force; \
    fi

# Install Deno (conditional)
RUN if [ "${DENO_INSTALL}" != "false" ]; then \
    curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh -s \
    && chmod +x /usr/local/bin/deno; \
    fi

# Install Go (conditional)
RUN if [ "${GO_INSTALL}" != "false" ]; then \
    GO_VER="${GO_VERSION}"; \
    if [ "${GO_INSTALL}" != "true" ]; then GO_VER="${GO_INSTALL}"; fi; \
    ARCH="${TARGETARCH:-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')}"; \
    curl -fsSL "https://go.dev/dl/go${GO_VER}.linux-${ARCH}.tar.gz" -o /tmp/go.tar.gz \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz \
    && mkdir -p /go/src /go/bin \
    && chmod -R a+w /go; \
    fi

# Install Rust (conditional)
RUN if [ "${RUST_INSTALL}" != "false" ]; then \
    TOOLCHAIN="${RUST_TOOLCHAIN}"; \
    if [ "${RUST_INSTALL}" != "true" ]; then TOOLCHAIN="${RUST_INSTALL}"; fi; \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    --default-toolchain "${TOOLCHAIN}" \
    --profile minimal \
    --component rustfmt,clippy,rust-analyzer,rust-src \
    && chmod -R a+w /usr/local/rustup /usr/local/cargo; \
    fi

# Set working directory
WORKDIR /workspace

# Install fdevc, configure git, and generate build info file
RUN curl -fsSL https://raw.githubusercontent.com/philogicae/fast_dev_container/main/install | bash || true \
    && git config --global init.defaultBranch main \
    && git config --global core.editor nano \
    && git config --global pull.rebase false \
    && git config --global safe.directory '*' \
    && git config --global user.name "Dev Container" \
    && git config --global user.email "dev@container.local" \
    && git config --global color.ui auto \
    # Now, generate and save build info
    && ( \
    printf "\n\033[1;36m═══ ENVIRONMENT INFO ═══\033[0m\n"; \
    printf "\033[0;90m🐧 $(grep PRETTY_NAME /etc/os-release | cut -d'=' -f2 | tr -d '\"')\033[0m\n"; \
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
    if [ "${NODE_INSTALL}" != "false" ] && command -v gemini >/dev/null 2>&1; then \
    printf "\033[1;36m✨ Gemini CLI\033[0m \033[0;37m•\033[0m "; \
    fi; \
    printf "\033[1;35m📦 Fdevc\033[0m\n"; \
    printf "\033[1;32m✅ Ready for development!\033[0m\n\n"; \
    ) | tee /etc/container-info.txt \
    # Add to .bashrc
    && echo '' >> /root/.bashrc \
    && echo '# Display container info on login (once per session)' >> /root/.bashrc \
    && echo 'if [ -f /etc/container-info.txt ] && [ -z "$CONTAINER_INFO_SHOWN" ]; then' >> /root/.bashrc \
    && echo '    cat /etc/container-info.txt' >> /root/.bashrc \
    && echo '    export CONTAINER_INFO_SHOWN=1' >> /root/.bashrc \
    && echo 'fi' >> /root/.bashrc

# Add healthcheck (conditional based on installed tools)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["bash", "-c", "uv --version \
    && ([ \"${NODE_INSTALL}\" = \"false\" ] || node --version) \
    && ([ \"${DENO_INSTALL}\" = \"false\" ] || deno --version) \
    && ([ \"${GO_INSTALL}\" = \"false\" ] || go version) \
    && ([ \"${RUST_INSTALL}\" = \"false\" ] || rustc --version)"]

# Keep container running
CMD ["tail", "-f", "/dev/null"]