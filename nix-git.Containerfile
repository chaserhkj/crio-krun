# Use a nix-built git version of CRI-O binary
FROM ghcr.io/nix-community/docker-nixpkgs/nix-flakes:latest-x86_64-linux as builder
ARG NIX_REF=github:chaserhkj/cri-o/userns-fuse-fix

RUN nix build ${NIX_REF}

RUN mkdir -p /target && cp result/bin/* /target/

FROM ghcr.io/chaserhkj/crio-krun:latest

COPY --from=builder /target/. /usr/bin