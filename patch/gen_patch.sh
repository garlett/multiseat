#!/bin/bash

cd /tmp

git clone https://gitlab.freedesktop.org/garlett/wlroots-lease-multiseat
cd wlroots-lease-multiseat
git remote add -f b https://gitlab.freedesktop.org/wlroots/wlroots
git remote update
git diff remotes/b/master master > ../0001-wlr-add-drm-lease-support.patch
cd ..
#rm -R wlroots-lease-multiseat