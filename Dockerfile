FROM debian:13-slim

# Base tools + Claude Code from Anthropic's signed apt repo (latest channel).
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git procps \
 && install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://downloads.claude.ai/keys/claude-code.asc -o /etc/apt/keyrings/claude-code.asc \
 && echo "deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/latest latest main" \
      > /etc/apt/sources.list.d/claude-code.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends claude-code \
 && rm -rf /var/lib/apt/lists/*

# mise binary in the image; its data dir stays under /home/dev so per-project Node versions persist in the volume.
ENV MISE_INSTALL_PATH=/usr/local/bin/mise
RUN curl -fsSL https://mise.run | sh

RUN useradd -m -u 1000 -s /bin/bash dev
USER dev
WORKDIR /home/dev
ENV PATH=/home/dev/.local/share/mise/shims:$PATH \
    DISABLE_AUTOUPDATER=1

# Global default Node. Lands in the volume on first run; project pins override via mise.
RUN mise use -g node@lts

# Seeded once into the volume. .claude/ must exist owned by dev before the CLAUDE.md bind mount lands inside it.
COPY --chown=dev:dev home/settings.json .claude/settings.json
