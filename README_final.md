


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
2. 
3. 
5. 
6. 

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

#### 3.1 Verificar detalles de la red de docker 

Debemos verificar la red que utilizaremos el rango de IP que entrega para poder configurar la ip de l

	root@web-server:~# docker network ls 
	NETWORK ID     NAME      DRIVER    SCOPE 
	44f20ce78e7f   bridge    bridge    local 
	1321da81e196   host      host      local 
	4ba1b3e7c2e6   none      null      local





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




## Diagramas de red y arquitectura


```mermaid
sequenceDiagram
```
Diagrama de red:

```mermaid
graph LR
A((Nube)) ----> B((192.168.0.100 / 10.0.0.100))
B --> C(Web1 10.0.0.20)
B --> D(Web2 10.0.0.21)
C --> E(Almacen 10.0.0.10)
D --> E(Almacen 10.0.0.10)




```
Diagrama de arquitectura:

```mermaid
graph LR
A((Nube)) ----> B((Servidor Proxy))
B --> C(Servidor Web 1)
B --> D(Servidor Web 2)
C --> E(Servidor Almacenamiento)
D --> E(Servidor Almacenamiento)





<!--stackedit_data:
eyJoaXN0b3J5IjpbOTgxNTU2OTY3LC05MzY2OTY0MjYsLTY0Nj
QzMjc3OCwtMTk5MjkyOTk2MiwxNTkxODU0NDgwLDI1NDA5Mjg1
NCwtMzQ4MTE2MzA5LC0xOTczNjM2Nzg0LC0xODMzMzc0OTU2XX
0=
-->