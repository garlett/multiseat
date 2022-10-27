# multiseat
multiseat using single graphics card gpu, without nesting like xephr and others.

what it does:
- download and install pacman packages
- download, patch and compiles tomcl, drm-lease-manger and weston
- creates configuration for: keyboards, mouses and videos
- apply kmv config on the seats
- start weston service for each seat with non-root user
- start weston kiosk mode and the application (works on 10.0.2 but not on 11.0.0)

tested with: two monitors on a nvdia 6200, two mouses and two keyboards.

RHATibnLUKUM and arson, tested on a RX550 with GL acceleration working! 

***Need help on refering this repo on multi seat tutorials.***

![multiseat using single graphics card gpu](https://github.com/garlett/multiseat/raw/main/not%20nested%20multiseat%20using%20single%20graphics%20card%20gpu.jpg?raw=true)
