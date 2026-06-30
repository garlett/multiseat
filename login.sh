#!/bin/bash
clear
while true; do
    read -p "Enter your username: " usuario
    
    echo "Nothing will be displayed on the screen while you are entering the password for security reasons."
    if su -c true "$usuario"; then
        echo "Correct password. Starting desktop..."
        
        echo "$DRM_LEASE $usuario" > /tmp/multiseat_login.fifo
        # In 1 second the server will read the message and kill us cleanly.
        sleep 10 
    else
        echo "Error. Try again."
        sleep 2
        clear
    fi
done
