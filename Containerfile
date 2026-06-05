FROM docker.io/archlinux/archlinux:latest as archlinux
FROM docker.io/library/rust:1 as build

COPY cgroups_delegate/ /work

WORKDIR /work

RUN cargo build --release && cp /work/target/release/cgroups_delegate /

FROM docker.io/library/alpine:latest as tini

RUN apk add --no-cache tini-static

FROM archlinux as libkrun

RUN --mount=type=cache,target=/var/lib/pacman/sync,id=pacman-sync \
    --mount=type=cache,target=/var/cache/pacman/pkg,id=pacman-cache \
    pacman -Sy --needed --noconfirm base-devel git glibc gcc-libs libkrunfw pipewire virglrenderer \
    cargo patchelf clang bc python-pyelftools cpio

RUN bash -ex <<'EOF'
git clone https://github.com/containers/libkrun
cd libkrun
cargo fetch --locked --target "$(rustc --print host-tuple)"

export ZSTD_SYS_USE_PKG_CONFIG=1
make BLK=1 NET=1 EFI=0 GPU=1 SND=1 INPUT=1 VERBOSE=1

mkdir -p /target
pkgdir=/target

make DESTDIR="$pkgdir" PREFIX=/usr LIBDIR_Linux=lib install
install -Dm644 LICENSE "$pkgdir"/usr/share/licenses/$pkgname/LICENSE
EOF

# Skip libkrunfw for now since release version worked fine
# RUN bash -ex <<'EOF'
# git clone https://github.com/containers/libkrunfw
# cd libkrunfw
# make

# mkdir -p /target
# pkgdir=/target

# make DESTDIR="$pkgdir" PREFIX=/usr LIBDIR_Linux=lib install

# install -Dm644 LICENSE-GPL-2.0-only "$pkgdir"/usr/share/licenses/$pkgname/LICENSE-GPL-2.0-only
# install -Dm644 LICENSE-LGPL-2.1-only "$pkgdir"/usr/share/licenses/$pkgname/LICENSE-LGPL-2.1-only
# EOF

FROM archlinux

RUN --mount=type=cache,target=/var/lib/pacman/sync,id=pacman-sync \
    --mount=type=cache,target=/var/cache/pacman/pkg,id=pacman-cache \
    yes | pacman -Sy iptables-nft && \
    pacman -S --needed --noconfirm cri-o krun cni-plugins fuse-overlayfs crictl

COPY --from=libkrun /target/ /

COPY storage.conf /etc/containers/

COPY 30-krun.conf 00-cgroup.conf /etc/crio/crio.conf.d/

COPY --from=build /cgroups_delegate /usr/bin/cgroups_delegate

COPY --from=tini /sbin/tini-static /usr/bin/tini

ENTRYPOINT ["/usr/bin/cgroups_delegate", "/usr/bin/tini", "--", "/usr/bin/crio"]
