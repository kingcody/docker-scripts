#!/bin/bash
# Generate a minimal filesystem for archlinux and load it into the local
# docker as "archlinux"
# requires root
set -e

PACSTRAP=$(which pacstrap)
[ "$PACSTRAP" ] || {
    echo "Could not find pacstrap. Run pacman -S arch-install-scripts"
    exit 1
}
EXPECT=$(which expect)
[ "$EXPECT" ] || {
    echo "Could not find expect. Run pacman -S expect"
    exit 1
}

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

IMAGE_NAME="$1"
[[ "$IMAGE_NAME" ]] && [[ "$(echo ${IMAGE_NAME} | sed -re 's/:.*/:/g')" == "$IMAGE_NAME" ]] && IMAGE_NAME="$(echo ${IMAGE_NAME} | sed -e 's/://g'):$(date +%Y.%m.%d)"
[[ ! "$IMAGE_NAME" ]] && IMAGE_NAME="arch-ds-devel-i686:$(date +%Y.%m.%d)"

ROOTFS=~/rootfs-arch-$$-$RANDOM
mkdir $ROOTFS

# custom base-devel install group
BASE_DEVEL="base-devel git openssh rsync strace net-tools dnsutils htop"

# digitally seamless related/prefered packages
DS_DEVEL="digitallyseamless-rootca yaourt"

#packages to ignore for space savings
PKGIGNORE=linux,jfsutils,lvm2,cryptsetup,groff,man-db,man-pages,mdadm,pciutils,pcmciautils,reiserfsprogs,s-nail,xfsprogs
 
expect <<EOF
  set timeout 60
  set send_slow {1 1}
  spawn pacstrap -C ${SCRIPT_DIR}/config/pacman.i686.conf -c -d -G -i $ROOTFS base $BASE_DEVEL $DS_DEVEL haveged --ignore $PKGIGNORE
  expect {
    "Install anyway?" { send n\r; exp_continue }
    "(default=all)" { send \r; exp_continue }
    "Proceed with installation?" { send "\r"; exp_continue }
    "skip the above package" {send "y\r"; exp_continue }
    "checking" { exp_continue }
    "loading" { exp_continue }
    "installing" { exp_continue }
  }
EOF

arch-chroot $ROOTFS /bin/sh -c "haveged -w 1024; pacman-key --init; pkill haveged; pacman -Rs --noconfirm haveged; pacman-key --populate archlinux"
arch-chroot $ROOTFS /bin/sh -c "ln -s /usr/share/zoneinfo/UTC /etc/localtime"
cat > $ROOTFS/etc/locale.gen <<DELIM
en_US.UTF-8 UTF-8
en_US ISO-8859-1
DELIM
arch-chroot $ROOTFS locale-gen

# install archlinuxfr repo
# arch-chroot $ROOTFS /bin/sh -c 'echo -e "\n[archlinuxfr]\nSigLevel = Never\nServer = http://repo.archlinux.fr/$arch" >> /etc/pacman.conf'
# install digitally seamless arch repo
# arch-chroot $ROOTFS /bin/sh -c 'echo -e "\n[digitallyseamless]\nSigLevel = Never\nServer = http://digitallyseamless.com/archlinux/repos/\$repo/\$arch" >> /etc/pacman.conf'

cp "${SCRIPT_DIR}/config/pacman.i686.conf" "${ROOTFS}/etc/pacman.conf"

arch-chroot $ROOTFS /bin/sh -c 'echo "Server = http://mirrors.kernel.org/archlinux/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist'

# udev doesn't work in containers, rebuild /dev
DEV=${ROOTFS}/dev
mv ${DEV} ${DEV}.old
mkdir -p ${DEV}
mknod -m 666 ${DEV}/null c 1 3
mknod -m 666 ${DEV}/zero c 1 5
mknod -m 666 ${DEV}/random c 1 8
mknod -m 666 ${DEV}/urandom c 1 9
mkdir -m 755 ${DEV}/pts
mkdir -m 1777 ${DEV}/shm
mknod -m 666 ${DEV}/tty c 5 0
mknod -m 600 ${DEV}/console c 5 1
mknod -m 666 ${DEV}/tty0 c 4 0
mknod -m 666 ${DEV}/full c 1 7
mknod -m 600 ${DEV}/initctl p
mknod -m 666 ${DEV}/ptmx c 5 2

tar --numeric-owner -C $ROOTFS -c . | docker import - $IMAGE_NAME
docker run -i -t $IMAGE_NAME echo Success.

IMAGE_NAME_SHORT="$(echo $IMAGE_NAME | sed -e 's/:.*//g')"
IMAGE_ID="$(docker images $IMAGE_NAME_SHORT | grep $IMAGE_NAME_SHORT | head -n 1 | awk '{print $3}')"
docker tag ${IMAGE_ID} ${IMAGE_NAME_SHORT}:latest

rm -rf $ROOTFS
