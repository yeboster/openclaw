FROM node:22-bookworm@sha256:cd7bcd2e7a1e6f72052feb023c7f6b722205d3fcab7bbcbd2d1bfdab10b1e935

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

RUN apt-get update && apt-get install -y socat libasound2 python3-pip && rm -rf /var/lib/apt/lists/*

# Gmail CLI
RUN curl -L https://github.com/steipete/gogcli/releases/download/v0.9.0/gogcli_0.9.0_linux_arm64.tar.gz \
  | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/gog

# Google Places CLI
RUN curl -L https://github.com/steipete/goplaces/releases/download/v0.2.1/goplaces_0.2.1_darwin_arm64.tar.gz \
  | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/goplaces

# ElevenLabs CLI (Sag)
RUN curl -L https://github.com/Yeboster/sag/releases/download/v0.23.4/sag_0.23.4_linux_arm64.tar.gz \
  | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/sag

# Models usage
RUN curl -L https://github.com/steipete/CodexBar/releases/download/v0.18.0-beta.2/CodexBarCLI-v0.18.0-beta.2-linux-aarch64.tar.gz \
  | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/codexbar

# Obsidian CLI
RUN curl -L https://github.com/Yakitrak/obsidian-cli/releases/download/v0.2.3/obsidian-cli_0.2.3_linux_arm64.tar.gz \
  | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/obsidian-cli

# Github
RUN curl -L https://github.com/cli/cli/releases/download/v2.86.0/gh_2.86.0_linux_arm64.tar.gz \
  | tar -xz --strip-components=2 -C /usr/local/bin gh_2.86.0_linux_arm64/bin/gh && chmod +x /usr/local/bin/gh

# Install ClawdHub CLI (Skills) & MCPorter CLI (MPC)
RUN npm install -g --prefix /usr/local clawdhub mcporter

WORKDIR /app
RUN chown node:node /app

# Version for image label/env; set by CI (date on main, tag on v*) or --build-arg VERSION=...
ARG VERSION
ENV OPENCLAW_VERSION=${VERSION}
LABEL org.opencontainers.image.version="${VERSION}"

ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

COPY --chown=node:node package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY --chown=node:node ui/package.json ./ui/package.json
COPY --chown=node:node patches ./patches
COPY --chown=node:node scripts ./scripts

USER node
RUN pnpm install --frozen-lockfile

# Optionally install Chromium and Xvfb for browser automation.
# Build with: docker build --build-arg OPENCLAW_INSTALL_BROWSER=1 ...
# Adds ~300MB but eliminates the 60-90s Playwright install on every container start.
# Must run after pnpm install so playwright-core is available in node_modules.
USER root
ARG OPENCLAW_INSTALL_BROWSER=""
RUN if [ -n "$OPENCLAW_INSTALL_BROWSER" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends xvfb && \
      mkdir -p /home/node/.cache/ms-playwright && \
      PLAYWRIGHT_BROWSERS_PATH=/home/node/.cache/ms-playwright \
      node /app/node_modules/playwright-core/cli.js install --with-deps chromium && \
      chown -R node:node /home/node/.cache/ms-playwright && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

USER node
COPY --chown=node:node . .
RUN pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

ENV NODE_ENV=production

# Security hardening: Run as non-root user
# The node:22-bookworm image includes a 'node' user (uid 1000)
# This reduces the attack surface by preventing container escape via root privileges
USER node

# Start gateway server with default config.
# Binds to loopback (127.0.0.1) by default for security.
#
# For container platforms requiring external health checks:
#   1. Set OPENCLAW_GATEWAY_TOKEN or OPENCLAW_GATEWAY_PASSWORD env var
#   2. Override CMD: ["node","openclaw.mjs","gateway","--allow-unconfigured","--bind","lan"]
CMD ["node", "openclaw.mjs", "gateway", "--allow-unconfigured"]
