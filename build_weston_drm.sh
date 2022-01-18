#!/bin/bash

echo "run this with a non root user capable of sudo, (wheel group)"

# weston and drm lease manager builder on archlinux.
# this is intended for multiseat with one single graphics card,
# without using xorg xephyr or other nested solution 

cd ~ 

if ! [ -d drm-lease-manager ]
then
    sudo pacman -Syu git meson ninja wget
    git clone "https://gerrit.automotivelinux.org/gerrit/src/drm-lease-manager.git"
    cd drm-lease-manager
    meson build
    ninja -C build
    sudo ninja -C build install
    cd ..
fi


mkdir -p weston
cd weston

if ! [ -e PKGBUILD ]
then
    # link ../drm-lease-manager/build/libdlmclient/libdlmclient.so .

    cp ../000*.patch .

    wget https://raw.githubusercontent.com/archlinux/svntogit-community/packages/weston/trunk/PKGBUILD

    sed -i 's/-D simple-dmabuf-drm=auto//g' PKGBUILD

    echo "md5sums+=('SKIP'{,,,})" >> PKGBUILD

    echo "source+=(\"https://gerrit.automotivelinux.org/gerrit/gitweb?p=AGL/meta-agl-devel.git;a=blob_plain;f=meta-agl-drm-lease/recipes-graphics/weston/weston/\"{0001-backend-drm-Add-method-to-import-DRM-fd,0001-compositor-do-not-request-repaint-in-output_enable,0002-Add-DRM-lease-support,0004-launcher-direct-handle-seat0-without-VTs}\".patch\")" >> PKGBUILD
    # 0003-launcher-do-not-touch-VT-tty-while-using-non-default,   ### merged on master already
else
    sudo pacman -R weston
    rm src/weston-*/compositor/drm-lease.{c,h} 2>/dev/null # patch does not keep track of previus created files
fi

makepkg -f -i -s --skippgpcheck # TODO: insert keys on current user 
cd..

# ./start_weston_drm.sh
