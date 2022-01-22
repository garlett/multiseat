#!/bin/bash

# weston and drm lease manager builder on archlinux.
# this is intended for multiseat with one single graphics card,
# without using xorg xephyr or other nested solution 

# run this with a non root user capable of sudo, (wheel group)

cd 
if ! [ -d drm-lease-manager ]
then
    echo -e "\e[1;31m[weston builder]\e[0m installing required arch packages .... " 
    sudo pacman -Syu git meson ninja wget || exit 1

    echo -e "\e[1;31m[weston builder]\e[0m git clone and build drm-lease-mangaer .... "  
    git clone "https://gerrit.automotivelinux.org/gerrit/src/drm-lease-manager.git" || exit 2
    cd drm-lease-manager 
    meson build || exit 3
    ninja -C build || exit 4
    sudo ninja -C build install || exit 5

    echo -e "\e[1;31m[weston builder]\e[0m linking dlmclient library .... " 
    cd /usr/
    sudo mkdir -p include/libdlmclient || exit 6
    for file in local/include/libdlmclient/dlmclient.h local/lib/pkgconfig/libdlmclient.pc local/lib/libdlmclient.so* 
    do
        sudo ln -s /usr/$file $( dirname ${file/local\//} ) || exit 7
    done
fi


cd
mkdir -p weston || exit 8
cd weston

if ! [ -e PKGBUILD ]
then
    echo -e "\e[1;31m[weston builder]\e[0m preparing weston arch package .... "  

    cp ../000*.patch .

    wget https://raw.githubusercontent.com/archlinux/svntogit-community/packages/weston/trunk/PKGBUILD || exit 9

    sed -i 's/-D simple-dmabuf-drm=auto//g' PKGBUILD

    echo "md5sums+=('SKIP'{,,,})" >> PKGBUILD

    echo "source+=(\"https://gerrit.automotivelinux.org/gerrit/gitweb?p=AGL/meta-agl-devel.git;a=blob_plain;f=meta-agl-drm-lease/recipes-graphics/weston/weston/\"{0001-backend-drm-Add-method-to-import-DRM-fd,0001-compositor-do-not-request-repaint-in-output_enable,0002-Add-DRM-lease-support,0004-launcher-direct-handle-seat0-without-VTs}\".patch\")" >> PKGBUILD
    # 0003-launcher-do-not-touch-VT-tty-while-using-non-default,   ### merged on master already

    echo "sistem service scrip " # > /..../drm-lease-manager.  || exit 10
else
    echo -e "\e[1;31m[weston builder]\e[0m removing previus weston build .... "  
    sudo pacman -R weston  || exit 11
    rm src/weston-*/compositor/drm-lease.{c,h} 2>/dev/null  || exit 12 # patch does not keep track of previus newly created files
fi


echo -e "\e[1;31m[weston builder]\e[0m building weston .... "  
makepkg -f -i -s --skippgpcheck || exit 13 # TODO: insert keys on current user 
echo -e "\e[1;31m[weston builder]\e[0m now you need to switch to root ( su ) and run ./start_weston_drm.sh" 

