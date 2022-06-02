# multiseat
multiseat using single graphics card gpu, without nesting like xephr and others.

it is starting the instances of weston as drm client, each one with its own seat. 

tested with: two monitors on a nvdia 6200, two mouses and two keyboards.

RHATibnLUKUM and arson, tested on a RX550 with GL acceleration working! 

Need help to:

1) Make a script that uses logind to create sequential seats for each pair of USB keyboard and mouse;

2) Update drm-lease-manage.service to manage all cards;

3) Refer this repo around multi seat tutorials sites. 

![multiseat using single graphics card gpu](https://github.com/garlett/multiseat/blob/main/IMG_20220417_180350.jpg?raw=true)
