#!/bin/bash
clear
while true; do
    read -p "Ingresa tu usuario: " usuario
    
    if su -c true "$usuario"; then
        echo "Contraseña correcta. Iniciando escritorio..."
        
        # Escribimos el Lease actual y el usuario en el buzón
        echo "$DRM_LEASE $usuario" > /tmp/multiseat_login.fifo
        
        # Nos quedamos durmiendo. 
        # En 1 segundo el servidor leerá el mensaje y nos matará limpiamente.
        sleep 10 
    else
        echo "Error. Intenta de nuevo."
        sleep 2
        clear
    fi
done
