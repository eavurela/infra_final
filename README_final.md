


> Written with [StackEdit](https://stackedit.io/).


Web Server

Instalación de docker, en la máquina de servidor web

	apt update && apt install docker docker.io

Instalación de docker compose:


	curl -SL https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-linux-x86_64 -o /usr/bin/docker-compose
	chmod +x /usr/bin/docker-compose

docker pull wordpress:4.6.1-php7.0

ISTEA
Edgardo Vurela
Infraestructura de Servidores


# Balanceo de carga web y almacenamiento centralizado

En el siguiente documento se encontrará la información necesaria para montar un sistema de alta disponibilidad web escalable horizontalmente. 
La demostración se ejecutará en un ambiente local generado con Oracle VirtualBox, pero a nivel configuración es replicable a otros virtualizadores de infraestructura o servidores físicos. 
En la generación de este laboratorio se utilizará Ubuntu 20.04.6 LTS.

		- Instancia Proxy 
		- Instancia Web-Server
		- Instancia Almacen 
		- Instancia Web-Server Docker
		
Se utlizarán servicios de nginx como servidor proxy y servidor web, apache2 como servidor web, y el protocolo sshfs para compartir archivos entre instancias. 
Se generará una primera plantilla con configuraciones básicas, que será luego replicada. 


# Configuración de red en Virtual Box 


		** Instancia Proxy** 
		
			- Adaptador de red 1: Adaptador puente 
			- Adaptador de red 2: Adaptador NAT
		
		** Instancia Web-Server**
		
			- Adaptador de red 1: Adaptador NAT
			- 
		** Instancia Almacen**
		
			- Adaptador de red 1: Adaptador NAT


## Configuración de plantilla 

Ingresar al servidor con usuario y contraseña generads en la instalación.

Necesitaremos para el acceso a las demás instancias, la configuración del servidor ssh. 

	sudo su 
	apt update && apt install -y ssh 
		   
Luego debemos crear llaves de acceso ssh y proveer de acceso ssh, debemos ingresar el siguiente comando aceptando todo, generará un par de llaves en el directorio por defecto /home/usuario/.ssh, en caso estemos como root en /root/.ssh

	ssh-keygen -t rsa

Considerando que las llaves generadas, nos servirán de acceso para las réplicas. Podremos generar el archivo de llaves autorizadas. 

	cat /root/.ssh/id_rsa.pub > /root/.ssh/authorized_keys


Para descargar los archivos que servirán de template en la configuración de red para los diferentes servidores. 


	# git clone git@github.com:eavurela/infra_final.git

Se generará el directorio "infra_final" con los siguientes archivos: 

	# ls infra_final/
	proxy.conf  sshfs.conf  web.conf

En cada uno de los archivos, estará la configuración base, en caso exista más de un componente se deberá modificar la IP

## Configuración del servidor proxy 

En esta etapa se generarán las conexiones para: 

0. Configuración de la red
1. Redirección de solicitudes de redes internas a internet
2. Redirección de solicitudes http desde internet al servidor web 
3. Activación del VirtualHost

### 0. Configuración de la red 

Copiar el archivo de configuración de proxy descargado y pegarlo en el archivo .yaml 

	root@servidor-proxy:/# cp /infra_final/proxy.conf /etc/netplan/00-installer-config.yaml

Aplicar la configuración de red. 

	root@servidor-proxy:/# netplan apply

#### Detalle de configuración de red. 

La interfaz **enp0s9** con ip estática privada, correspondiente a la interfaz de nat. 
La interfaz **enp0s8** con ip estática puente, correspondiente al a interfaz que llamaremos pública, con acceso a internet. 
		
		network:
		  ethernets:
			enp0s9:
		      addresses:
		        - 10.0.0.100/24
			  nameservers:
		        addresses:
		          - 10.0.0.1
		    enp0s8:
		      addresses:
		        - 192.168.0.100/24
		      nameservers:
		        addresses:
		          - 8.8.8.8
		        search:
		          - 4.4.4.4
		      routes:
		        - to: default
		          via: 192.168.0.1
		  version: 2
		  
### 1. Redirección de solicitudes de redes internas a internet

Considerando que es el único host con doble interfaz de red, y único con salida a internet deberá funcionar con nexo de las solicitudes a internet desde las instancias en la red interna. 

Configurar iptables para redireccionar solicitudes. 
	
	root@servidor-proxy:/$ sudo su
Con la siguiente sentencia se habilita el reenvio de paquetes ipv4 

	root@servidor-proxy:/# sysctl net.ipv4.ip_forward=1.
Con la siguiente regla de iptables se permite el nateo y el enmascaramiento de paquetes. Se declara la interfaz de red enp0s8, que es la interfaz puente en el laboratorio.

	root@servidor-proxy:/# iptables -t nat -A POSTROUTING -o enp0s8 -j MASQUERADE

Se pueden agregar al cron del usuario para que se levanten de forma automática. 

	root@servidor-proxy:/# echo "@reboot sleep 10 && sysctl net.ipv4.ip_forward=1" >> /var/spool/cron/crontabs/root | chgrp crontab /var/spool/cron/crontabs/root
	root@servidor-proxy:/# echo "@reboot sleep 15 && iptables -t nat -A POSTROUTING -o enp0s8 -j MASQUERADE" >> /var/spool/cron/crontabs/root | chgrp crontab /var/spool/cron/crontabs/root


### 2. Redirección de solicitudes http desde internet al servidor web

Necesitaremos instalar el software que utilizaremos para redireccionar el tráfico, mediante un proxy pass. 

	root@servidor-proxy:/# apt update -y && apt install -y nginx 

Una vez instalado, necesitaremos configurar un VirtualHost que será el encargado de la redirección. 
En la siguiente configuración se puede ver que las consultas al puerto 80 http serán redirecciónadas a http://backend, configurado como la lista de las ips detalladas en upstream backend. En este caso, el servidor web corre en la ip "10.0.0.20", luego el servidor Docker con el balanceo de cargas interno corre en el host 10.0.0.21, escuchando el servicio en el puerto 8000. 

		root@servidor-proxy:/# nano /etc/nginx/sites-available/balanceo
		
		upstream backend { 
			server 10.0.0.20;
			server 10.0.0.21:8000;
		## <nombre><ip-del-servidor-web-interno>;	 
		} 
		server { 
				listen 80; 
				server_name istea.laboratorio; 
		##      server_name <direccion_web>
				location / { 
					proxy_set_header Host $host; 
					proxy_set_header X-Real-IP $remote_addr; 
					proxy_pass http://backend; 
				} 
		}


### 3. Activación VirtualHost 

Para activar el sitio web configurado, es necesario generar un link simbolico entre el archivo generado en el directorio de sitios disponibles, al directorio de sitios activados. 

	root@servidor-proxy:/# ln -s /etc/nginx/sites-available/balanceo /etc/nginx/sites-enabled/

Comprobar la configuración de nginx

	root@servidor-proxy:/# nginx -t 
	nginx: the configuration file /etc/nginx/nginx.conf syntax is ok 
	nginx: configuration file /etc/nginx/nginx.conf test is successful

Aplicar la configuración 

	root@servidor-proxy:/# systemctl reload nginx


## Configuración del servidor de almacenamiento 

Se necesitará: 
1. Creación de un nuevo medio virtual 
2. Configuración de la red 
3. Configuración de nombre de host
4. Creación de partición
5. Configuración del sistema de archivos
6. Montaje de la unidad 
7. Configuración del directorio compartido, con usuario y permisos 
8. Configuración de la unidad para el montaje automático 

### 1. Creación de un nuevo medio virtual 

Para configurar el servidor en cuestión en VirtualBox se deberá generar un volumen nuevo que será el almacenamiento compartido por los servidores web, en dónde estará el sitió. 

Se debe generar un nuevo medio virtual

	Archivo/Herramientas/Administrador de medios virtuales/

![enter image description here](https://i.ibb.co/ynYnkc6/imagen-2023-10-29-171202377.png)

Luego deberán seleccionar

	Crear/VDI/Seleccionar tamaño y ubicación/Terminar 

Luego deberán ingresar a la configuración de la instancia 

	Almacenamiento/Controlador SATA/Añadir unidad de disco/ seleccionar unidad creada

### 2. Configuración de la red 

Ingreso al sistema con usuario y contraseña generados en la instalación del a imagen. 

Copiar archivo de configuración de red para el sevidor de almacenamiento. 

		$ sudo su 
		# cp /infra_final/sshfs.conf /etc/netplan/00-installer-config.yaml

#### Detalle de configuración de red. 

La interfaz **enp0s8** con ip estática privada, correspondiente a la interfaz de nat. Y se configura el gateway como la ip interna del servidor proxy. 

		network:
		  ethernets:
		    enp0s8:
		      addresses:
		        - 10.0.0.10/24
		      nameservers:
		        addresses:
		          - 8.8.8.8
		        search:
		          - 4.4.4.4
		      routes:
		        - to: default
		          via: 10.0.0.100
		  version: 2
		  
Aplicar configuración de red 

	# netplan apply
Prueba de conectividad 

	# ping 8.8.8.8
	PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data. 
	64 bytes from 8.8.8.8: icmp_seq=1 ttl=115 time=14.5 ms 
	64 bytes from 8.8.8.8: icmp_seq=2 ttl=115 time=16.4 ms 
	64 bytes from 8.8.8.8: icmp_seq=3 ttl=115 time=11.1 ms



En caso como en la captura tengamos respuesta, significa que se aplicó correctamente el archivo de configuración, y hay salida a internet, mediante el servidor proxy. 

### 3. Configuración de nombre de host 

Con la siguiente sentencia se configura el nombre de host. Programa  < argumento > < nombre-host >

	hostnamectl set-hostname sshfs-server

### 4. Creación de partición, versión extendida. 

Verificamos los dispositivos conectados. 

		root@sshfs-server:~# lsblk 
		
		NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT 
		loop0    7:0    0 91,9M  1 loop /snap/lxd/24061 
		loop1    7:1    0 49,9M  1 loop /snap/snapd/18357 
		loop2    7:2    0 63,3M  1 loop /snap/core20/1828 
		loop3    7:3    0 63,5M  1 loop /snap/core20/2015 
		sda      8:0    0   25G  0 disk 
		├─sda1   8:1    0    1M  0 part 
		└─sda2   8:2    0   25G  0 part / 
		sdb      8:16   0    4G  0 disk 
		└─sdb1   8:17   0    4G  0 part /opt 
		sdc      8:32   0    2G  0 disk 
		sr0     11:0    1 1024M  0 rom
En este caso, crearemos la partición en el volumen sdc 

		fdisk /dev/sdc
		
		root@sshfs-server:~# fdisk /dev/sdc 
		
		Welcome to fdisk (util-linux 2.34).  
		Changes will remain in memory only, until you decide to write them. 
		Be careful before using the write command. 
		Device does not contain a recognized partition table. 
		Created a new DOS disklabel with disk identifier 0x5c0c924e. 

Creamos una nueva tabla de particiones vacía DOS 

	Command (m for help): o
	Created a new DOS disklabel with disk identifier 0x066099e5. 

Agregamos una nueva partición primaria número 1, iniciado con el sector 2048 y terminando con el último sector disponible del dispositivo.

	Command (m for help): n 
	Partition type 
	p   primary (0 primary, 0 extended, 4 free) 
	e   extended (container for logical partitions) 

	Select (default p): p 
	Partition number (1-4, default 1): 1 
	First sector (2048-4194303, default 2048): 
	Last sector, +/-sectors or +/-size{K,M,G,T,P} (2048-4194303, default 4194303): 
	
	Created a new partition 1 of type 'Linux' and of size 2 GiB. 

Guardamos y salimos
	
	Command (m for help): w
	The partition table has been altered. 
	Calling ioctl() to re-read partition table. 
	Syncing disks.

### 5. Configuración del sistema de archivos 

Verificamos el dispositivo sdc y la partición creada sdc1 

	root@sshfs-server:~# lsblk
	..
	sdc      8:32   0    2G  0 disk 
	└─sdc1   8:33   0    2G  0 part
	..

Creamos sistema de archivos ext4 para la partición sdc1 

		root@sshfs-server:~# mkfs.ext4 /dev/sdc1 
		
		mke2fs 1.45.5 (07-Jan-2020) 
		Creating filesystem with 524032 4k blocks and 131072 inodes 
		Filesystem UUID: 5277292d-4356-4e0c-8cfa-f2c5c2a25915 
		Superblock backups stored on blocks: 
			 32768, 98304, 163840, 229376, 294912 
		Allocating group tables: done 
		Writing inode tables: done 
		Creating journal (8192 blocks): done 
		Writing superblocks and filesystem accounting information: done

### 4-5.b  Creación de partición, y Configuración de FS (versión acotada). 

Para ahorrar pasos en el proceso, y evitar una shell interavtiva en la creación de particiones (agiliza el trabajo en scripts), se puede instalar 'xfsprogs'

	# apt update && apt install xfsprogs -y
Formateo.

	# mkfs.xfs /dev/sdc
Con estos dos simples comandos, se puede generar algo análogo a los  pasos 4 y 5. 


### 6. Montaje de la unidad 

Para que el dispositivo instalado sea accesible, luego de generar la tabla de particiones y el sistema de archivos, es necesario montar la unidad en alguna ubicación. 

Creamos el directorio en dónde se montará el dispositivo 

	root@sshfs-server:~# mkdir /opt/web-server/

Montamos la unidad en dicho directorio 

	root@sshfs-server:~# mount /dev/sdc1 /opt

Verificamos la unidad 

	root@sshfs-server:~# df -h
	..
	/dev/sdc1       2,0G   24K  1,9G   1% /opt/
	..

### 7.  Configuración del directorio compartido, con usuario y permisos

Llegada esta altura tenemos el siguiente escenario: 

Servidor apache2 consultado por el usuario www-data, que debe tener permisos en el volumen compartido. Para securizar el servidor necesitamos que sea restringido al máximo. 

Se debe crear el usuario www-data en el servidor de almacenamiento, y otorgarle el owner del directorio montado. Luego www-data desde el servidor web podrá acceder al contenido. 

Creación de usuario, configurando con -d el directorio home del usuario a crear y con -m la creación del directorio en caso no exista. 

	useradd -s /bin/bash -d /opt/webserver -m webserver

Configuración de contraseña 

	passwd webserver

Se creará el usuario, forzando el home de dicho usuario al directorio /opt/webserver/ 

		root@sshfs-server:/opt# ls -lh 
		..  
		drwx------ 2 root     root      16K oct 29 15:48 lost+found  
		drwxr-xr-x 3 www-data www-data 4,0K oct 29 17:08 webserver
		..
Como se observa, el usuario y grupo del directorio /opt/webserver es www-data

		drwxr-xr-x 3 www-data www-data 4,0K oct 29 17:08 webserver

### 8. Configuración de la unidad para el montaje automático 

Para hacer persistente el montaje debemos editar el archivo /etc/fstab. En este caso envio la salida del echo al final del archivo /etc/fstab

		root@sshfs-server:~# echo "/dev/sdb1   /opt   ext4   defaults   0   2" >> /etc/fstab


## Configuración del servidor web 

Para la configuración del servidor web se necesitará: 
 
0. Configuracion del hostname
1. Configuración de la red 
2. Instalación del servidor apache2 e  Instalación de servicio sshfs 
3. Montaje de volumen compartido del sitio web
4. Configuración del VirtualHost
5. Activación del sitio web 
6. Configuración de la unidad para el montaje automático 

### 0. Configuración del hostname 

		sudo hostnamectl set-hostname web-server

### 1.Configuración de la red 

Ingreso al sistema con usuario y contraseña generados en la instalación del a imagen. 

Copiar archivo de configuración de red para el sevidor web. 

		$ sudo su 
		root@web-server:~# cp /infra_final/web.conf /etc/netplan/00-installer-config.yaml
		
#### Detalle de configuración de red. 

La interfaz **enp0s8** con ip estática privada, correspondiente a la interfaz de nat. Y se configura el gateway como la ip interna del servidor proxy. 

		network:
		  ethernets:
		    enp0s8:
		      addresses:
		        - 10.0.0.20/24
		      nameservers:
		        addresses:
		          - 8.8.8.8
		        search:
		          - 4.4.4.4
		      routes:
		        - to: default
		          via: 10.0.0.100
		  version: 2
		  
Aplicar configuración de red 

		root@web-server:~# netplan apply
Prueba de conectividad 

	# ping 8.8.8.8
	PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data. 
	64 bytes from 8.8.8.8: icmp_seq=1 ttl=115 time=14.5 ms 
	64 bytes from 8.8.8.8: icmp_seq=2 ttl=115 time=16.4 ms 
	64 bytes from 8.8.8.8: icmp_seq=3 ttl=115 time=11.1 ms

### 2. Instalación del servidor apache2 y SSHFS

Para instalar el servicio web y el servicio sshfs, es necesario ejecutar los siguientes comandos.

	root@web-server:~# apt update -y && apt install -y apache2
	root@web-server:~# apt install -y sshfs
	
### 3. Montaje de volumen compartido del sitio web

Con el siguiente comando se puede montar mediante ssh el volumen del servidor de almacenamiento en dónde se encuentra el sitio web

	root@web-server:~# sshfs -o allow_other,default_permissions root@10.0.0.10:/opt/webserver /var/www/network_volume

Verificar que el volumen haya quedado montado:

	root@web-server:~# df -h
	..
	root@10.0.0.10:/opt/webserver  3,9G   68K  3,7G   1% /var/www/network_volume
	..
### 4. Configuración del VirtualHost

Duplicaremos el archivo de configuración por defecto, utilizándolo como plantilla. Luego aplicaremos los cambios necesarios. 

	root@web-server:/# cp /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/istea.laboratorio.conf

Modificar las directivas **ServerName**, con el nombre del sitio web generado, y **DocumentRoot** con el directorio en dónde se encontrará el sitio web. En este caso, se utilizará el punto de montaje del almacenamiento compartido mediante el protocolo sshfs. 

	root@web-server:/# nano /etc/apache2/sites-available/istea.laboratorio.conf

		 ..
		 # However, you must set it for any further virtual host explicitly.  
		 ServerName istea.laboratorio 
		 #ServerAdmin webmaster@localhost  
		 DocumentRoot /var/www/network_volume
		 ..
Tocar Control  + 0 para guardar ,  luego Control + X para salir. 

### 5. Activación del sitio web 
Para activar el sitio web agregado en la lista de sitios disponibles se puede crear un link simbólico o usar la herramienta de apache. 

Utilizando herrmienta de apache

	root@web-server:~# a2ensite <ServerName>

En este caso 

	root@web-server:~# a2ensite istea.laboratorio
	Enabling site istea.laboratorio. 
	To activate the new configuration, you need to run: 
	systemctl reload apache2
Es necesario recargar el servicio web 

	root@web-server:~# systemctl reload apache2

### 6. Configuración de la unidad para el montaje automático 
Configurar el montaje automático mediante un cron: 

	root@web-server:/var/www/network_volume# crontab -e
	no crontab for root - using an empty one 
	Select an editor.  To change later, run 'select-editor'. 
	 1. /bin/nano        <---- easiest 
	 2. /usr/bin/vim.basic 
	 3. /usr/bin/vim.tiny 
	 4. /bin/ed 
	 Choose 1-4 [1]: 1 

En el editor que se abre, agregar una línea:

	..
	# m h  dom mon dow   command
	@reboot sleep 10 && sshfs root@10.0.0.10:/opt/webserver /var/www/network_volume
	..
En el reinicio, se debería ejecutar solo el montaje, y considerando que en la plantilla se han agregado las llaves, debe conectarse solo.

## Configuración de servidor docker 

Para la configuración del servidor docker se necesitará: 
 
0. Configuracion del hostname, configuración de la red, instalación del servicio sshfs y configuración de la unidad para montaje automático. 
1. Instalación de Docker 
2. Instalación de Docker Composer
3. Configuración de balanceo
	-	3.1 Configurar detalles de la red de docker 
	3.2 Creación del contenedor balanceador. 
		-	3.2.1 Generar una imagen del contenedor con nuestro archivo de configuración. 
		-	3.2.2 Montar un directorio local en la configuración de nginx, para que tome de forma dinámica los cambios. 
		-	3.2.3  Copiar el archivo de configuración con el contenedor en ejecución
4. Configuración de contenedor web-server
5. 

### 0. Configuraciones heredadas. 

Considerando que el servidor Docker, expondrá servicios web y se conectará al almacenamiento compartido, parte de las configuraciones serán similares. 

Se configura la red, el servicio sshfs, el hostname y el montaje automático. 

	servidor_clone/infra_final# bash web-inicial.sh 
	
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

Agregado al script posterior. 

		# instalación de docker # 
		apt install docker docker.io -y 
		# Instalacion de copose# 
		curl -SL https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-linux-x86_64 -o /usr/bin/docker-compose 
		chmod +x /usr/bin/docker-compose

### 1. Instalación de Docker

Para la instalación de Docker en ubuntu se debe ejecutar: 

	root@web-server:~# apt install docker docker.io -y

Para verificar que se haya instalado correctamente podemos utulizar el comando, nos listará los procesos de Docker corriendo en este caso ninguno. 

	root@web-server:~# docker ps 
	CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES

### 2. Instalación de Docker Composer

Como usuario sudo descargamos el archivo y generamos el binario 

	root@web-server:~# curl -SL https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-linux-x86_64 -o /usr/bin/docker-compose 

	 % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current 
	 Dload  Upload   Total   Spent    Left  Speed 
	 0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0 
	 100 56.8M  100 56.8M    0     0  10.8M      0  0:00:05  0:00:05 --:--:-- 13.4M

Luego damos permisos de ejecución al binario y probamos su funcionamiento

	root@web-server:~# chmod +x /usr/bin/docker-compose

Probar el funcionamiento

	root@web-server:~# docker-compose version

### 3. Configuración de balanceo

Para la configuración del balanceo dentro de docker, necesitaremos un contenedor Nginx para balancear y contenedores que oficien de servidor web. 
Con se vio anteriormente debemos dentro del archivo de configuración de nginx, detallar las IPs o hostnames a dónde direccionaremos el tráfico, por lo tanto son datos que debemos averiguar o generar. 

#### 3.1 Configurar detalles de la red de docker 

Podemos configurar la red y luego en la red creada agregar los nuevos contenedores. Para crear la red ejecutamos lo siguiente: 
	
	docker network create --subnet=172.18.0.0/16 red_infra
	
Luego verificamos las redes existentes

	root@web-server:~# docker network ls 
	NETWORK ID     NAME      DRIVER    SCOPE 
	44f20ce78e7f   bridge    bridge    local 
	1321da81e196   host      host      local 
	4ba1b3e7c2e6   none      null      local
	34b4c1670d1a   red_infra   bridge    local

Como se puede ver por defecto nos genero una red de tipo bridge, podemos analizar sus configuraciones: 

	docker network inspect red_infra
	...
	 "Name": "red_infra", 
	 "Id": "34b4c1670d1afc6586dbb43143444c13c392ac5bf4c7ec53c0e5461bff6c2e46", 
	 "Created": "2023-12-06T17:46:20.171468188Z", 
	 "Scope": "local", 
	 "Driver": "bridge", 
	 "EnableIPv6": false, 
		 "IPAM": { 
		 "Driver": "default", 
		 "Options": {}, 
		 "Config": [ 
			 { 
				 "Subnet": "172.18.0.0/16"
			 } 
	...

Como se puede observar, la red bridge es un /16 con dirección de ip 172.18.0.0, Podemos entonces, generar contenedores con direcciones entre   172.18.0.2 - 172.18.255.254.

#### 3.2 Creación del contenedor balanceador. 
En este punto tenemos por lo menos tres opciones para realizar. 

 1. Generar una imagen del contenedor con nuestro archivo de configuración. 
 2. Montar un directorio local en la configuración de nginx, para que tome de forma dinámica los cambios. 
 3. Copiar el archivo de configuración con el contenedor en ejecución.

#### 3.2.1 Generar una imagen del contenedor con nuestro archivo de configuración. 

Primero debemos generar le archivo de configuración de Nginx. 

	upstream backend { 
		 server 172.18.0.100; 
		 server 172.18.0.110; 
		 } 

	server { 
			 listen 80; 
			 server_name istea.laboratorio; 
			 location / { 
					proxy_set_header Host $host ; 
					proxy_set_header X-Real-Ip $remote_addr ; 
					proxy_pass http://backend; 
			} 

	}
Luego generaremos el Dockerfile, en dónde se detallan las instrucciones para la creación del a imagen. 

	root@web-server:/docker/red/balanceo# nano Dockerfile
	
	FROM nginx:alpine
	COPY balanceo.conf /etc/nginx/conf.d/balanceo.conf

Luego debemos construir la imagen con el archivo de configuración. Posados en el mismo directorio que el Dockerfile ejecutamos: 

	root@web-server:/docker/red/balanceo# docker build -t balanceo-nginx .
	DEPRECATED: The legacy builder is deprecated and will be removed in a future release.
            Install the buildx component to build images with BuildKit:
            https://docs.docker.com/go/buildx/

	Sending build context to Docker daemon  3.072kB
	Step 1/2 : FROM nginx:alpine
	alpine: Pulling from library/nginx
	c926b61bad3b: Pull complete
	eb2797aa8e79: Pull complete
	47df6ca4b6bc: Pull complete
	5ea1ba8ab969: Pull complete
	6a4b140a5e7c: Pull complete
	c99555e79d52: Pull complete
	f9302969eafd: Pull complete
	d7fb62c2e1cc: Pull complete
	Digest: sha256:3923f8de8d2214b9490e68fd6ae63ea604deddd166df2755b788bef04848b9bc
	Status: Downloaded newer image for nginx:alpine
	 ---> 01e5c69afaf6
	Step 2/2 : COPY balanceo.conf /etc/nginx/conf.d/balanceo.conf
	 ---> c1eb12a07a57
	Successfully built c1eb12a07a57
	Successfully tagged balanceo-nginx:latest
	
Verificamos la creación de la imagen:

	root@web-server:/docker/red/balanceo# docker images 
	REPOSITORY       TAG       IMAGE ID       CREATED         SIZE 
	balanceo-nginx   latest    c1eb12a07a57   7 seconds ago   42.6MB

Ejecutar el contenedor: 

	docker run <ejecuta el contenedor>
		   -d  <como daemon, no captura la terminal>
		   -p  <mapeo de puertos puerto_anfitrion:puerto_contenedor>
		   --name <nombre del contenedor (opcional)>
		   nombre de la imagen

	docker run -d -p 8000:80 --ip 172.18.0.100 --network red_infra --name balanceador balanceo-nginx
	ebd49374b88fe202965e524f085c88c244705df33ded2963a9c61a92288c4ff3
	oot@web-server:/docker/red/balanceo# docker ps
	CONTAINER ID   IMAGE            COMMAND                  CREATED         STATUS         PORTS                                   NAMES 
	ebd49374b88f   balanceo-nginx   "/docker-entrypoint.…"   3 seconds ago   Up 2 seconds   0.0.0.0:8000->80/tcp, :::8000->80/tcp   balanceador

#### 3.2.2 Montar un directorio local en la configuración de nginx, para que tome de forma dinámica los cambios. 
En este caso ejecutaremos el contenedor, con la imagen nginx:alpine utilizando un "bind mount". Se montará un directorio del host anfitrión en el contenedor. 

	docker -v (mapeo de directorios)<directorio_anfitrion>:<directorio_contenedor>
	
	docker run -d -p 8000:80 --ip 172.18.0.100 --network red_infra --name balanceador -v /docker/red/balanceo/balanceo.conf:/etc/nginx/conf.d/balanceo.conf nginx:alpine

#### 3.2.3 Copiar el archivo de configuración con el contenedor en ejecución
Activo un nginx:alpine con la configuración de nginx por defecto. 

	docker run -d -p 4000:80 --ip 172.18.0.100 --network red_infra  --name balanceador-copy nginx:alpine

	docker cp balanceo.conf balanceador-copy:/etc/nginx/conf.d/ 
	Successfully copied 2.05kB to balanceador-copy:/etc/nginx/conf.d/
Ahora para que aplique la configuración debemos reiniciar el contenedor.

	docker restart balanceador-copy
	
### 4. Configuración de contenedor web-server

Considerando que el directorio de la aplicación web, estará en el volumen compartido por el servidor de almacenamiento. 
Debemos mapear el volumen que ya tenemos instalado, a los contenedores que ejecuten el servicio web. 
Entonces: 

 1. Verificar volumen montado
 2. Ejecutar contenedor nginx o apache2 con IPs balanceadas por el contenedor de balanceo, considerando que el "DocumentRoot" debe corresponder a un "bind mount" del volumen del servidor SSHFS. 

#### 4.1 Verificar volumen montado

	root@web-server:/# df -h 
	Filesystem                     Size  Used Avail Use% Mounted on 
	tmpfs                           96M  1,7M   95M   2% /run 
	/dev/sda2                      9,8G  5,5G  3,9G  59% / 
	tmpfs                          479M     0  479M   0% /dev/shm 
	tmpfs                          5,0M     0  5,0M   0% /run/lock 
	tmpfs                           96M  4,0K   96M   1% /run/user/0 
	root@10.0.0.10:/opt/webserver  3,9G   88K  3,7G   1% /share_volume 
	overlay                        9,8G  5,5G  3,9G  59%/var/lib/docker/overlay2/f47c7584a63304ffb26718f1b503bb3b5a3ff30d660dcc203a44cee86c44e126/merged 
	..
#### 4.2 Ejecutar contenedor. 
Debe contener: 

 1. IP estática, configurada en el balanceo.conf
 2. network infra-red
 3. No requiere mapeo de puertos al anfitrión 
 4. bind mount del directorio /share_volume
 5. Nombre del contenedor
 
 #### 4.2.1 Contenedor Nginx 
 Ejecutar el comando:
 
	 docker run --name web-red-infra --ip 172.18.0.110 --network red_infra -v /share_volume/docker-web:/usr/share/nginx/html -d nginx
https://hub.docker.com/_/nginx

 #### 4.2.2 Contenedor Apache2
 Ejecutar el comando:

	docker run -it --name web-red-infra2 --ip 172.18.0.100 --network red_infra -v /share_volume/docker-web:/usr/local/apache2/htdocs/ -d httpd:2.4

https://hub.docker.com/_/httpd

**Consideraciones**: No tiene ningún sentido tener dos servicios web diferentes, dado que duplicamos el tamaño de almacenamiento en imágenes de docker. 

## 5. Utilización de Docker compose

Toda la configuración anterior de docker, puede ser generada en un solo archivo y ejecutada de una única vez. 

Para la configuración mediante el compose se necesita: 

 1. Generar archivo docker-compose.yml
 2. Dentro del archivo configurar los servicios 
 3. Ejecutar el yml mediante el comando "docker-compose up -d" 
 4. Luego verificar el funcionamiento. 

### 5.1 Generar el archivo docker-compose.yml

El siguiente archivo de configuración ha sido generado, con las mismas características del anterior proyecto, siguiendo la documentación:
https://anderfernandez.com/blog/tutorial-docker-compose/#Networks-en-Docker-Compose
https://sysadm.es/docker-container-misma-red/ 
https://sysadm.es/docker-port-y-expose/ | expose / port 
https://docs.docker.com/compose/compose-file/compose-file-v3/ | Docker Configs 

	root@web-server:/docker/red/balanceo# nano docker-compose.yml

	version: '3'

	services:
	    balan_compo:
	        image: 'nginx:stable-alpine3.17-slim'
	        restart: always
	        networks:
	            - infra_compose
	        configs:
	            - source: nginx_conf
	              target: /etc/nginx/conf.d/balanceo.conf
	        ports:
	            - 10000:80

	    web-app1:
	        image: 'nginx:stable-alpine3.17-slim'
	        restart: always
	        depends_on:
	            - balan_compo
	        volumes:
	            -  /share_volume/docker-web:/usr/share/nginx/html
	        networks:
	            - infra_compose
	        expose:
	            - 80

	    web-app2:
	        image: 'nginx:stable-alpine3.17-slim'
	        restart: always
	        depends_on:
	            - balan_compo
	        volumes:
	            - /share_volume/docker-web:/usr/share/nginx/html
	        networks:
	            - infra_compose
	        expose:
	            - 80


		networks:
		  infra_compose:
		    driver: bridge

		configs:
		  nginx_conf:
		    file: /docker/red/balanceo/balanceo2.conf

Detalle del archivo de configuración: 
	
	version: '3' | Usa la versión 3 de docker compose
	
**services**: Aqui dentro se deben especificar los contenedores a levantar 
**networks**: Aqui se detallará la creación de redes y el tipo de red, en este caso nombre infra_compose de tipo bridge
**configs**: En caso quiera enviar un archivo de configuración, lo determino acá nginx_conf es la variable y file: "ruta_al_archivo_host".

Tomando de referencia: 

	    balan_compo:
	        image: 'nginx:stable-alpine3.17-slim'
	        restart: always
	        networks:
	            - infra_compose
	        configs:
	            - source: nginx_conf
	              target: /etc/nginx/conf.d/balanceo.conf
	        ports:
	            - 10000:80

**image**: Declara la imagen de docker-hub utilizada, en caso quiera usar una propia local debería ser "build"
**restart**: en caso el contenedor se apague se detalla que se reinicie de forma automática. 
**networks**: se define la red a utilizar, se usa la red "infra_compose" declarada para su creación en "networks" 
**configs**: se declara un origen, en este caso el archivo del anfitirón que se busca para la configuración, y un target o destino, que es el archivo que debe generar en el contenedor. 
**ports**: mapeo de puertos entre anfitrión y contenedor, se configura <puerto_anfitrion>:<puerto_contenedor>
**expose**: utilizado en los web-servers declara que se exponga el puerto 80, puerto de escucha de Nginx. pero no necesita ser mapeado externamente, dado que será consultado por el balanceador.  
**volumes**: bind mount mediante docker compose, se mapea un directorio del anfitrion a un directorio del contenedor. 
En este caso se hace coincidir el volumen del sshfs con el directoryroot por defecto de nginx. 

**Consideraciones**: 

Llegado a este punto, el docker-compose.yml solo depende de. 

 - [ ] Path del montaje de volumen
 - [ ] Localización del config_file

Por lo tanto, podemos cambiando esas únicas variables, levantar el mismo laboratorio con la ejecución de pocos comandos. 
A ello! 

En una copia de la virtual de template ejecuto:

	#git clone git@github.com:eavurela/infra_final.git

Luego ejecuto el script de instalación web y docker. 

	root@web-server-final:~# bash infra_final/script/web-inicial.sh

Luego modifico docker_compose con la ruta del archivo de config nueva. 

	root@web-server-final:~# sed -i 's/docker/red/balanceo/balanceo2.conf/root/infra_final/docker/balanceo.conf/g'  infra_final/script/docker-compose.yml

Finalmente ejecuto el compose 

	root@web-server-final:~# cd infra_final/script/
	root@web-server-final:~/infra_final/script#docker-compose up -d

	[+] Running 3/9
	⠴ web-app1 Pulling                                                                                                                                                                                                                    	 5.5s 	
	⠼ web-app2 Pulling                                                                                                                                                                                                                    5.5s 
	⠼ balan_compo 6 layers [⣿⣿⣿⣿⠀⠀]    958B/958B    Pulling                                                                                                                                                                               5.5s 
	  ✔ 1207c741d8c9 Pull complete                                                                                                                                                                                                       1.0s 
	  ✔ a23d11eaa182 Download complete                                                                                                                                                                                                    1.0s 
	  ✔ 0341e0d720db Download complete                                                                                                                                                                                                    0.7s 
	  ⠼ 3dc25df9202e Downloading [==================================================>]     958B/958B                                                                                                                                      1.4s 
	  ⠼ c02db9c48356 Waiting                                                                                                                                                                                                              1.4s 
	  ⠼ 0f187c37abb8 Waiting                                                                                                                                                                                                              1.4s
	  [+] Running 4/9
	  ⠦ web-app1 Pulling                                                                                                                                                                    5.6s 
	  ⠴ web-app2 Pulling                                                                                                                                                                    5.6s 
	  ⠴ balan_compo 6 layers [⣿⣿⣿⣿⠀⠀]      0B/0B      Pulling                                                                                                                               5.6s 
	  ✔ 1207c741d8c9 Pull complete                                                                                                                                                        1.0s 
	  ✔ a23d11eaa182 Pull complete                                                                                                                                                        1.0s 
	  ✔ 0341e0d720db Download complete                                                                                                                                                    0.7s 
	  ✔ 3dc25df9202e Download complete                                                                                                                                                    1.4s 
	  ⠴ c02db9c48356 Waiting                                                                                                                                                             	
	  1tmpfs                           96M  4,0K   96M   1% /run/user/0	
	  root@10.0.0.10:/opt/webserver  3,9G   88K  3,7G   1% /share_volume
	  root@web-server-final:~/infra_final/script# ls
	  docker-compose.yml  web-inicial.sh
	  root@web-server-final:~/infra_final/script# docker-compose up -d
	  [+] Running 5/9
	  ⠧ web-app1 Pulling                                                                                                                                                                                                                    5.7s 
	  ⠦ web-app2 Pulling                                                                                                                                                                                                                    5.7s 
	  ⠦ balan_compo 6 layers [⣿⣿⣿⣿⣿⠀]      0B/0B      Pulling                                                                                                                                                                               5.7s 
	  ✔ 1207c741d8c9 Pull complete                                                                                                                                                                                                        1.0s 
	  [+] Running 9/982 Pull complete
	  ✔ web-app1 Pulled                                                                                                                                                                 5.8s
	  ✔ web-app2 Pulled                                                                                                                                                                 5.8s
	  ✔ balan_compo 6 layers [⣿⣿⣿⣿⣿⣿]      0B/0B      Pulled                                                                                                                            5.8s
	  ✔ 1207c741d8c9 Pull complete                                                                                                                                                    1.0s
	  ✔ a23d11eaa182 Pull complete                                                                                                                                                    1.0s
	  ✔ 0341e0d720db Pull complete                                                                                                                                                    0.7s
	  ✔ 3dc25df9202e Pull complete                                                                                                                                                    1.4s
	  ✔ c02db9c48356 Pull complete                                                                                                                                                    1.6s
	  ✔ 0f187c37abb8 Pull complete                                                                                                                                                    1.7s
	  [+] Building 0.0s (0/0)                                                                                                                                                 
	  docker:default
	  [+] Running 4/4
	  ✔ Network script_infra_compose    Created                                                                                                                                         0.1s
	  ✔ Container script-balan_compo-1  Started                                                                                                                                         0.5s
	  ✔ Container script-web-app1-1     Started                                                                                                                                         0.0s
	  ✔ Container script-web-app2-1     Started                                                                                                                                         0.0s

Como se puede ver el nombre del contenedor, se genera con el directorio-nombre_del_servicio.

	root@web-server-final:~/infra_final/script# docker ps 
	CONTAINER ID   IMAGE                          COMMAND                  CREATED         STATUS         PORTS                                     NAMES 
	446342f5ffa1   nginx:stable-alpine3.17-slim   "/docker-entrypoint.…"   5 minutes ago   Up 5 minutes   80/tcp                                    script-web-app2-1 
	deeab2e6ee2b   nginx:stable-alpine3.17-slim   "/docker-entrypoint.…"   5 minutes ago   Up 5 minutes   80/tcp                                    script-web-app1-1 
	1d871fd0bf50   nginx:stable-alpine3.17-slim   "/docker-entrypoint.…"   5 minutes ago   Up 5 minutes   0.0.0.0:10000->80/tcp, :::10000->80/tcp   script-balan_compo-1

	
	
	

## Escalabilidad horizontal 

En el caso que dicha estructura necesite ser escalable de forma horizontal, se debería replicar el host identificado como **"Servidor Web"**. 

Luego de dicha clonación o replicación es necesario: 

### Cambiar hostname 

	root@web-server:~# hostnamectl set-hostname web-server1

### Modificar dirección IP del clon:

Con la utilización del comando sed, se puede buscar y reemplazar dentro de un archivo, en este caso se busca la dirección IP generada en la plantilla para el servidor web, por la siguiente en la subnet. 

En este caso la red era 10.0.0.20, y se cambia por 10.0.0.21. Como el cambio aplica al último octeto se simplifica con: 


	root@web-server1:~# sed -i 's/20/21/g' /etc/netplan/00-installer-config.yaml

Se aplican los cambios: 

	root@web-server1:~# netplan apply

**Agregar el host al servidor proxy**

Para agregar el host al servidor proxy que balancea se debe agregar la IP del nuevo host de servidor web al VirtualHost:

		root@servidor-proxy:/# nano /etc/nginx/sites-available/balanceo
		
		upstream backend { 
			server 10.0.0.20;
			server 10.0.0.21;
		## <nombre><ip-del-servidor-web-interno>;	 
		} 
		
		server { 
				listen 80; 
				server_name istea.laboratorio; 
		##      server_name <direccion_web>
				location / { 
					proxy_set_header Host $host; 
					proxy_set_header X-Real-IP $remote_addr; 
					proxy_pass http://backend; 
				} 
		}

Luego probar y recargar el servicio: 

	root@servidor-proxy:/# nginx -t 
	root@servidor-proxy:/# service nginx reload

Con esta configuración el servidor proxy debería enviar a la red interna solicitudes a ambos servidores web.		

## Bibliografía. 

IPTABLES -      https://serverfault.com/questions/233427/iptables-forwarding-masquerading
HOSTNAME - https://www.hostinger.com.ar/tutoriales/como-cambiar-hostname-ubuntu
RED -               https://www.solvetic.com/tutoriales/article/10984-configurar-ip-estatica-en-ubuntu-server-22-04/	
PROXY -           https://kinsta.com/es/blog/proxy-inverso/
DockerNgix     https://hub.docker.com/_/nginx










<!--stackedit_data:
eyJoaXN0b3J5IjpbMjYwNDMzNzA3LDE4MjQzNTY4MzQsLTE5Nj
g1MDg5ODcsLTM3MjEyNDA2MywxNzc4NjQ5MzA1LDIwNzQ5NjM4
MSwxNTE4OTY0OTM3LDgzMzc0OTQ0LC05NjA5MjMwMTUsNjY2Mj
E3MzcsLTY4OTk3ODEyNCw3NDQ3MzQsLTkzNjY5NjQyNiwtNjQ2
NDMyNzc4LC0xOTkyOTI5OTYyLDE1OTE4NTQ0ODAsMjU0MDkyOD
U0LC0zNDgxMTYzMDksLTE5NzM2MzY3ODQsLTE4MzMzNzQ5NTZd
fQ==
-->