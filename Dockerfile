# Development Container Template
# Based on Debian 12 (Bookworm) with Python 3.13, Node.js 22, and Rust latest

FROM python:3.13-slim-bookworm

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    NODE_VERSION=22 \
    RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

# Install system dependencies and tools
RUN apt-get update && apt-get install -y \
    # Build essentials
    build-essential \
    cmake \
    pkg-config \
    # Version control
    git \
    # Network tools
    curl \
    wget \
    # Text editors
    vim \
    nano \
    # Utils (for Node.js setup)
    ca-certificates \
    gnupg \
    lsb-release \
    # Clean up
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g npm@latest \
    && npm install -g yarn pnpm \
    && rm -rf /var/lib/apt/lists/*

# Install Rust latest stable
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable \
    && chmod -R a+w $RUSTUP_HOME $CARGO_HOME

# Set working directory
WORKDIR /workspace

# Keep container running
CMD ["tail", "-f", "/dev/null"]
