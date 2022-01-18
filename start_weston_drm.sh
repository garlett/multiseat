#!/bin/bash

sudo systemctl start drm-lease-manAger 

weston --drm-lease=card0-VGA-1

