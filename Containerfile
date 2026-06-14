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
    pacman -Sy --needed --noconfirm base-devel git sudo

WORKDIR /var/build

RUN mkdir -p /var/build/libkrun

COPY <<'EOF' /var/build/libkrun/PKGBUILD
_pkgname=libkrun
pkgname=${_pkgname}-git
pkgver=1.18.1
pkgrel=1
pkgdesc="A dynamic library providing Virtualization-based process isolation capabilities"
url='https://github.com/containers/libkrun'
arch=('x86_64')
license=('Apache-2.0')
conflicts=("$_pkgname")
provides=("$_pkgname")
makedepends=('cargo' 'patchelf' 'clang' 'rustup')
depends=('glibc' 'gcc-libs' 'libkrunfw' 'pipewire' 'virglrenderer')
source=("git+https://github.com/containers/libkrun")
sha256sums=('SKIP')

pkgver() {
  cd "$_pkgname"
  ( set -o pipefail
    git describe --tags --long 2>/dev/null | sed 's/\([^-]*-g\)/r\1/;s/-/./g' ||
    printf "r%s.%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
  )
}
prepare() {
  rustup default stable
  rustup target add $(uname -m)-unknown-linux-musl
  cd "$_pkgname"

  cargo fetch --locked --target "$(rustc --print host-tuple)"
}

build() {
  cd "$_pkgname"

  export ZSTD_SYS_USE_PKG_CONFIG=1
  make BLK=1 NET=1 EFI=0 GPU=1 SND=1 INPUT=1 VERBOSE=1
}

package() {
  cd "$_pkgname"

  make DESTDIR="$pkgdir" PREFIX=/usr LIBDIR_Linux=lib install
}
EOF

RUN bash -ex <<'EOF'
useradd -m build
passwd -d build
echo "build ALL=(ALL) NOPASSWD: /usr/bin/pacman" >> /etc/sudoers

cd /var/build/libkrun
chown -R build .

pacman -Syy
sudo -u build -- makepkg -s --needed --noconfirm

pkg_count=$(ls libkrun-git-v*.pkg.tar.zst|wc -l)
[[ "$pkg_count" != "1" ]] && exit 1

mkdir -p /output
cp libkrun-git-v*.pkg.tar.zst /output/

EOF

FROM archlinux

RUN --mount=type=cache,target=/var/lib/pacman/sync,id=pacman-sync \
    --mount=type=cache,target=/var/cache/pacman/pkg,id=pacman-cache \
    yes | pacman -Sy iptables-nft && \
    pacman -S --needed --noconfirm cri-o krun passt cni-plugins fuse-overlayfs crictl

RUN --mount=from=libkrun,target=/tmp/pkgs \
    yes | pacman -U --needed /tmp/pkgs/output/*.pkg.tar.zst

COPY storage.conf /etc/containers/

COPY 30-krun.conf 00-cgroup.conf /etc/crio/crio.conf.d/

COPY --from=build /cgroups_delegate /usr/bin/cgroups_delegate

COPY --from=tini /sbin/tini-static /usr/bin/tini

ENTRYPOINT ["/usr/bin/cgroups_delegate", "/usr/bin/tini", "--", "/usr/bin/crio"]
