#!/bin/bash

# Configuración de hostname
hostnamectl set-hostname web-server
# Configuracion de red
cp /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yamlBK
cp /infra_final/web.conf /etc/netplan/00-installer-config.yaml
# Aplicar cambios de configuracion
netplan apply
# Actualización de paquetes e instalación de sshfs
apt update -y && apt install -y sshfs 
# Creación de directorio de montaje
mkdir -p /share_volume
#Conexión al sshfs
sshfs -o allow_other,default_permissions root@10.0.0.10:/opt/webserver  /share_volume
echo "@reboot sleep 10 && sshfs root@10.0.0.10:/opt/webserver /share_volume" > /var/spool/cron/crontabs/root | chgrp crontab /var/spool/cron/crontabs/root
