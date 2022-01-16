#!/bin/bash

echo run this with a non root user capable of sudo, (wheel group)

# weston and drm lease manager builder on archlinux.
# this is intended for multiseat with one single graphics card,
# without using xorg xephyr or other nested solution 

# commented lines are not tested yet

cd ~ 

# sudo pacman -Syu git wget meson ninja

mkdir -p drm-lease-manager
cd drm-lease-manager
# git clone "https://gerrit.automotivelinux.org/gerrit/src/drm-lease-manager.git"
# meson build
# ninja -C build
# sudo ninja -C build install
cd ..


mkdir -p weston
cd weston

if ! [ -e PKGBUILD ]
then
    wget https://raw.githubusercontent.com/archlinux/svntogit-community/packages/weston/trunk/PKGBUILD

    echo "source+=(\"https://gerrit.automotivelinux.org/gerrit/gitweb?p=AGL/meta-agl-devel.git;a=blob_plain;f=meta-agl-drm-lease/recipes-graphics/weston/weston/\"{0001-backend-drm-Add-method-to-import-DRM-fd,0001-compositor-do-not-request-repaint-in-output_enable,0002-Add-DRM-lease-support,0004-launcher-direct-handle-seat0-without-VTs}\".patch\")" >> PKGBUILD
    # 0003-launcher-do-not-touch-VT-tty-while-using-non-default,   ### merged on master already

    echo "md5sums+=('SKIP'{,,,})" >> PKGBUILD

    # sed -e "s/ -D  simples-dmabuf-drm=auto//" PKGBUILD    # unknow bug
fi

rm src/weston-*/compositor/drm-lease.{c,h} > /dev/null # patch does not keep track of previus created files

makepkg -i -s --skippgpcheck # TODO: insert keys on current user 


# drm-lease-manger &
# systemctl start drm-lease-manger 

# weston --drm-lease=card0-HDMI-A-1


