FROM docker.io/library/debian:trixie-slim

# The tools listed in the manual deployment checklist, baked in once.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      just \
      vim \
      bc \
      jq \
  && rm -rf /var/lib/apt/lists/*

RUN groupadd -g 1000 deployer \
  && useradd -m -u 1000 -g 1000 -s /bin/bash deployer

USER deployer
ENV HOME=/home/deployer
WORKDIR /home/deployer

ARG FOUNDRY_VERSION=1.7.1
# Foundry (forge, cast, anvil, chisel). foundryup keeps a second copy of every
# binary under versions/; hardlinking them saves ~200 MB.
RUN curl -fsSL https://foundry.paradigm.xyz | bash \
  && /home/deployer/.foundry/bin/foundryup --install ${FOUNDRY_VERSION} \
  && for f in /home/deployer/.foundry/versions/*/*; do \
       if [ -f "$f" ]; then ln -f "$f" "/home/deployer/.foundry/bin/$(basename "$f")"; fi; \
     done

ENV PATH=/home/deployer/.foundry/bin:$PATH

RUN echo 'PS1="\[\e[36m\]\u@\h\[\e[0m\]:\W\$ "' >> /home/deployer/.bashrc

RUN forge --version && cast --version && anvil --version && just --version

# The command is exactly what you pass, and defaults to a shell.
# pdeploy bind-mounts each project at its host path and passes a matching --workdir.
ENTRYPOINT []
CMD ["bash"]
