# Build crun from source to enable krun
FROM rust:1 as build

COPY cgroups_delegate/ /work

WORKDIR /work

RUN cargo build --release && cp /work/target/release/cgroups_delegate /

FROM alpine as tini

RUN apk add --no-cache tini-static

FROM archlinux/archlinux

RUN --mount=type=cache,target=/var/lib/pacman/sync,id=pacman-sync \
    --mount=type=cache,target=/var/cache/pacman/pkg,id=pacman-cache \
    yes | pacman -Sy iptables-nft && \
    pacman -S --needed --noconfirm cri-o krun cni-plugins fuse-overlayfs crictl

COPY storage.conf /etc/containers/

COPY 30-krun.conf 00-cgroup.conf /etc/crio/crio.conf.d/

COPY --from=build /cgroups_delegate /usr/bin/cgroups_delegate

COPY --from=tini /sbin/tini-static /usr/bin/tini

ENTRYPOINT ["/usr/bin/cgroups_delegate", "/usr/bin/tini", "--", "/usr/bin/crio"]

CMD ["--cgroup-manager=cgroupfs"]
