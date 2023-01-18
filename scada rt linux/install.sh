##!/bin/sh
VERSION=1.1.9
#--- Enable check error -------------------------
SYS_TRAP='trap "exit 1" ERR '
trap "exit 1" ERR 2>/dev/null
if [ "$?" != 0 ]; then
	SYS_TRAP="set -e"
	set -e 2>/dev/null
fi


#--- Default values -----------------------------
MPLC_PATH=/opt/mplc4
MPLC_INIT=/etc/init.d/mplc4
MPLC_TAR=mplc.tar.gz
MPLC_BASE_PORT=31550
MPLC_USER=root
MPLC_RC_PRIORITY=99
MPLC_WDT=ON
MPLC_CFG_ONLY=OFF
MPLC_AUTOSTART_DELAY=0
MPLC_GROUP=$MPLC_USER
MPLC_START_SCRIPT=start_mplc.sh
MPLC_UNINSTALL_SCRIPT=uninstall.sh
MPLC_REPORT=OFF
MPLC_LOGS=OFF
MPLC_DUMP=OFF
MPLC_EXEMPLARS=0
MPLC_NETKEY=OFF

NGINX_PATH=
NGINX_TAR=nginx.tar.gz
NGINX_LOGS=/var/log/nginx
NGINX_PID_FILE=$NGINX_LOGS/nginx.pid
NGINX_CONFIG=conf/nginx-mplc.conf
NGINX_HTTP_POTR=80
NGINX_UPDATE=ON
NGINX_HTTP=ON
NGINX_HTTPS=OFF
NGINX_USER=root
NGINX_GZIP=ON

NODEJS_DIR=
NODEJS_TAR=nodejs.tar.gz

CODESYS_NAME=plclinux_rt
CODESYS_KILL=OFF

SYS_I386_DEP=OFF
SYS_SHELL=sh
SYS_PIDOF=pidof
SYS_UPDATE_RC=OFF

REGEX_NUM='^[0-9]+$'
REGEX_PORT='^[1-9][0-9]+$'

PLATFORM=
FAKE_INIT_D=

EXTRA_CREATE_NGINX_CFG=

OS_NAME=Linux
# Read predefined configs
if [ -e "cfg" ]; then
	. ./cfg
fi

#--- Base functions -----------------------------

get_mplc_init() {
	echo $MPLC_INIT
}

restart_mplc() {
	$(get_mplc_init) restart
}

mplc_rm() {
	for file in "$@"; do
		[ -e "$file" ] || continue
		rm -R "$file" # if remove "true" script exit after "done"
	done
}
mplc_loop() {
	local loop_i=$1
	local loop_for=$2
	if [ "$OS_NAME" == QNX ]; then
		echo "integer $loop_i=0; while ((i<\$$loop_for)); do i=i+1;"
	else
		echo "for $loop_i in \`seq 1 \$$loop_for\`; do "
	fi
}
mplc_get_dir() {
	echo $(mkdir -p $1; cd $1; pwd)
}

mplc_which() {
	local res=
	if [ -n "$(which which 2>/dev/null)" ]; then
		res=$(which $1 2>/dev/null)
	else
		for dir in $(echo $PATH | sed 's/:/ /g'); do
			res=$(find $dir -maxdepth 1 -name "$1" -type f)
			[ -n "$res" ] && break || true
		done
	fi
	echo $res
}

mplc_check() {
	if [ -n "$(mplc_which $1)" ]; then
		echo "ON"
	else
		echo "OFF"
	fi
}

#if matched return 0 else 1
#exemple --
#  reg='^a[0-9]+$' : grep regex
#  val="as2232"
#  [ $(mplc_regex $val $reg) == 0 ] && echo OK
mplc_regex() {
	local val=$1
	local reg=$2
	res=$(echo "$val" | grep -E "$reg")
	[ -n "$res" ] && echo 0 || echo 1
}

mplc_unzip() {
	local SRC_ARCHIVE=$1
	local DST_PATH=$2
	local TAR_GZIP=ON
	[ "$(tar --help 2>&1 | grep 'gzip')" == "" ] && TAR_GZIP="OFF"
	if [ $TAR_GZIP == "ON" ]; then
		tar xf $SRC_ARCHIVE -C $DST_PATH
	else
		cp $SRC_ARCHIVE tmp.tar.gz
		gzip -d tmp.tar.gz
		tar xf tmp.tar -C $DST_PATH
		rm tmp.tar
	fi
}

import_mplc_function() {
	cat <<EOL
mplc_kill(){
	kill -INT \$@ 2>/dev/null
}
mplc_regex(){
	local val=\$1
	local reg=\$2
	local res=\$(echo "\$val" | grep -E "\$reg")
	# echo "\$val -> \$reg : \$res : \$([ -n "\$res" ] && echo 0 || echo 1)" >> logs/start_log.txt
	[ -n "\$res" ] && echo 0 || echo 1
}
mplc_rm(){
	for file in "\$@"; do
		[ -e "\$file" ] && rm -R "\$file" || true
	done
}
mplc_nkill(){
	local pid=\$($SYS_PIDOF \$1 2>/dev/null)
	[ -z "\$pid" ] && return 0
	mplc_kill \$pid
}

mplc_fkill(){
	if [ -e "\$1" ]; then
		mplc_kill \$( cat "\$1" )
		local is_ok=\$?
		sleep 1
		if [ \$is_ok != 0 ]; then 
			mplc_rm "\$1"
		fi
	fi
}
EOL
}

#--- Get platform type --------------------------

if [ $(mplc_regex "$(uname -n)" "plc110") == 0 ]; then
	PLATFORM=PLC110
fi

#--- Preinstall section -------------------------

if [ $(mplc_check sysctl) == "ON" ]; then
	MPLC_DUMP=ON
fi

#--- Read user options --------------------------
opt=

for option; do
	opt="$opt `echo $option | sed -e \"s/\(--[^=]*=\)\(.* .*\)/\1'\2'/\"`"

	case "$option" in
	-*=*) value=`echo "$option" | sed -e 's/[-_a-zA-Z0-9]*=//'` ;;
	*) value="" ;;
	esac

	case "$option" in
		--prefix=*)                         MPLC_PATH="$(mplc_get_dir $value)"   ;;
		--kill-codesys)                     CODESYS_KILL="ON"                    ;;
		--with-https)                       NGINX_HTTPS=ON                       ;;
		--without-http)                     NGINX_HTTP=OFF
		                                    NGINX_HTTPS=ON                       ;;
		--http-port=*)                      NGINX_HTTP_POTR="$value"             ;;
		--without-nginx)                    NGINX_UPDATE="OFF"                   ;;
		--i386-dep)                         SYS_I386_DEP="ON"                    ;;
		--nowdt)                            MPLC_WDT="OFF"                       ;;
		--config-only)                      MPLC_CFG_ONLY="ON"                   ;;
		--start-delay=*)                    MPLC_AUTOSTART_DELAY="$value"        ;;
		--platform=*)                       PLATFORM="$value"                    ;;
		--with-reports)                     MPLC_REPORT=ON                       ;;
		--enable-log)                       MPLC_LOGS=ON                         ;;
		--disable-dump)                     MPLC_DUMP=OFF                        ;;
		--nginx-logdir=*)                   NGINX_LOGS="$value"
		                                    NGINX_PID_FILE=$NGINX_LOGS/nginx.pid ;;
		--nginx-disable-gzip)               NGINX_GZIP=OFF                       ;;
		--create-nginx-cfg=*)               NGINX_CONFIG="$value"
		                                    EXTRA_CREATE_NGINX_CFG="ON"          ;;
		--exemplars=*)                      MPLC_EXEMPLARS="$value"              ;;
		--netkey)                           MPLC_NETKEY=ON                       ;;
		-v)
			echo "Installer version $VERSION"
			exit 1                                                               ;;
		*)
			cat <<EOL
$0 availible options:
	--prefix=<path>            The path to the mplc4 installation (default: $MPLC_PATH)
	--kill-codesys             Disable runtime codesys
	--without-http             Disable HTTP protocol
	--with-https               Enable HTTPS protocol
	--http-port=<port>         Set another HTTP port (default: $NGINX_HTTP_POTR)
	--without-nginx	           Disable Nginx installation. Can be run without nginx.tar.gz
	--i386-dep                 Installing i386 dependency. Required for x64 arhitectures. WARNING: Internet connection required.
	--nowdt                    Disable using watchdog
	--config-only              Update only configs. Can be run without mplc.tar.gz and nginx.tar.gz
	--start-delay=<seconds>    MPLC autostart delay after reboot controller. (default: 0)
	--platform=<NAME>          Set specific platform, availible values (PLC110, REGUL)
	--with-reports             Enable reports build service
	--enable-log               Enable save log for each start mplc in new file
	--disable-dump             Disable mplc4 create dump
	--nginx-logdir=<dir>       Set dir for nginx logs and pid file
	--create-nginx-cfg=<path>  Generate nginx config file without install
	--exemplars=<N>            Count autostart exemplars
	--nginx-disable-gzip       disable gzip module for static(need on Android)
	--netkey                   Use network license key
EOL
			exit 1                                                               ;;
	esac
done

echo "NGINX_HTTPS=$NGINX_HTTPS"
echo "NGINX_HTTP=$NGINX_HTTP"

#--- Update default options ---------------------

if [ $(mplc_regex $MPLC_AUTOSTART_DELAY $REGEX_NUM) != 0 ]; then
	echo "Error start-delay: '$MPLC_AUTOSTART_DELAY' is bad number of seconds." >&2
	exit 1
fi

if [ $(mplc_regex $MPLC_EXEMPLARS $REGEX_NUM) != 0 ]; then
	echo "Error exemplars count number: '$MPLC_EXEMPLARS'." >&2
	exit 1
fi

if [ $(mplc_regex $NGINX_HTTP_POTR $REGEX_PORT) != 0 ] ||
	[ $(($NGINX_HTTP_POTR > 65535)) == 1 ]; then
	echo "Error http-port: '$NGINX_HTTP_POTR' is bad number port." >&2
	exit 1
fi

if [ "$EXTRA_CREATE_NGINX_CFG" != "ON" ]; then
	MPLC_START_SCRIPT=$MPLC_PATH/$MPLC_START_SCRIPT
	MPLC_UNINSTALL_SCRIPT=$MPLC_PATH/$MPLC_UNINSTALL_SCRIPT
	NGINX_PATH=$MPLC_PATH/nginx
	NGINX_CONFIG=$NGINX_PATH/$NGINX_CONFIG
	NODEJS_DIR=$MPLC_PATH/nodejs
fi

SYS_UPDATE_RC=$(mplc_check update-rc.d)

if [ $(mplc_check bash) == "ON" ]; then
	SYS_SHELL=bash
fi

if [ "$PLATFORM" == PLC110 ]; then
	FAKE_INIT_D=/etc/rc.local
	MPLC_INIT="$MPLC_PATH/init_mplc4.sh"
elif [ "$PLATFORM" == REGUL ]; then
	FAKE_INIT_D=/etc/init/system.main
	OS_NAME=QNX
elif [ "$PLATFORM" == QNX650_X86 ]; then
	FAKE_INIT_D=/etc/rc.d/rc.local
	OS_NAME=QNX
elif [ "$PLATFORM" == TREI ]; then
	FAKE_INIT_D=/fs/etfs/etc/rc.d/rc.local
	OS_NAME=QNX
elif [ "$PLATFORM" == SEREBRUM ]; then
	MPLC_INIT="/etc/init.d/S${MPLC_RC_PRIORITY}mplc4"
fi

if [ "$OS_NAME" == QNX ]; then
	SYS_PIDOF="slay -p"
	MPLC_INIT="$MPLC_PATH/init_mplc4.sh"
fi
#--- Platform dependence functions --------------

clear_old_installer() {
	if [ "$SYS_UPDATE_RC" == "ON" ]; then
		update-rc.d -f mplc4s remove >/dev/null 2>&1
	fi
	mplc_rm \
		/etc/init/mplc4d.sh \
		/etc/init.d/mplc4s \
		/etc/init.d/S99mplc \
		$MPLC_PATH/lighttpd \
		$MPLC_PATH/mplcstart.sh
}

create_user() {
	adduser -S $1 >/dev/null 2>&1 || true
}

add_autorun() {
	local INIT_SCRIPT=$1
	local FILE_NAME=$(basename $INIT_SCRIPT)
	local NN=$MPLC_RC_PRIORITY
	#$DEBUG && echo "start add_autorun "
	#$DEBUG && echo "INIT_SCRIPT=$1"
	if [ -n "$FAKE_INIT_D" ]; then
		#doesn't have normal init.d and so we need parse this shit
		cp $FAKE_INIT_D ./$(basename $FAKE_INIT_D).bak
		sed -ie "/^cd.*mplc/d; /#run mplc/d; /$FILE_NAME/d; s!.*mplcstart.sh.*!$INIT_SCRIPT start!g" $FAKE_INIT_D
		if [ -z "$(sed -n "/$FILE_NAME/p" $FAKE_INIT_D)" ]; then
			cat >>$FAKE_INIT_D <<EOL
#run mplc 
$INIT_SCRIPT start
EOL
		fi
		mplc_rm ./$(basename $FAKE_INIT_D).bak
	elif [ "$SYS_UPDATE_RC" == ON ]; then
		update-rc.d "$(basename $INIT_SCRIPT)" defaults $NN
	elif [ "$PLATFORM" == PLC210 ]; then
		local run_name=S${NN}_$FILE_NAME
		ln -sf $INIT_SCRIPT /etc/rc.d/$run_name
	else
		local run_name=S${NN}_$FILE_NAME
		local stop_name=K01_$FILE_NAME
		for num in 2 3 4 5; do
			mkdir -p /etc/rc${num}.d
			ln -sf $INIT_SCRIPT /etc/rc${num}.d/$run_name
		done
		for num in 0 1 6; do
			mkdir -p /etc/rc${num}.d
			ln -sf $INIT_SCRIPT /etc/rc${num}.d/$stop_name
		done
	fi
}

#Add check user name in script if MPLC_USER != root
add_check_user() {
	if [ "$MPLC_USER" != "root" ]; then
		cat <<EOL
if [ "\$(whoami)" != "$MPLC_USER" ]; then
	echo Cant run from \$(whoami).\n \
		\$($(get_mplc_init) help)
	exit 1
fi
EOL
	fi
}

get_sh_cmd() {
	if [ "$MPLC_USER" != "root" ]; then
		echo "su - $MPLC_USER -s /bin/$SYS_SHELL -c "
	else
		echo "/bin/$SYS_SHELL -c "
	fi
}

#--- MPLC Scripts -------------------------------

create_mplc_scripts() {
	create_mplcstart_script $MPLC_START_SCRIPT \
		$MPLC_BASE_PORT \
		$MPLC_PATH \
		$NGINX_PATH \
		$NGINX_CONFIG \
		$NGINX_LOGS

	create_initd_script $MPLC_INIT \
		$MPLC_PATH \
		$MPLC_START_SCRIPT

	add_autorun $MPLC_INIT

	create_unistall_script $MPLC_UNINSTALL_SCRIPT
}

create_initd_script() {
	local SCRIPT_PATH=$1
	local MPLC_DIR=$2
	local START_SCRIPT=$3
	local EXEC_CMD="$(get_sh_cmd)"
	local KILL_CODESYS=
	if [ "$CODESYS_KILL" == "ON" ] && [ -n "$CODESYS_NAME" ]; then
		KILL_CODESYS="mplc_nkill $CODESYS_NAME"
	fi
	local DELAY=
	if [ "$MPLC_AUTOSTART_DELAY" != "0" ]; then
		DELAY="[ \$(mplc_regex \$0 '^/etc/rc[0-6].d/') != 0 ] || sleep $MPLC_AUTOSTART_DELAY;"
	fi
	if [ "$PLATFORM" == SEREBRUM ]; then
		OTHER="mount -o remount /"
	fi
	if [ "$PLATFORM" == PLC210 ]; then
		cat >$SCRIPT_PATH <<EOT
#!/bin/sh /etc/rc.common
START=99
STOP=10
#USE_PROCD=1
QUIET=""
MPLC_RUN_OPTS="\$2"
start(){
	__start \$1
    return 0
}
stop(){
	__stop
    return 0
}
restart() {
    __stop
	__start \$1
    return 0
}
EOT
	else
		cat >$SCRIPT_PATH <<EOT
#!/bin/$SYS_SHELL
### BEGIN INIT INFO
# Provides:          mplc4
# Required-Start:    
# Required-Stop:     
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start the MasterPLC server.
# Description:       Start the MasterPLC server.
### END INIT INFO
MPLC_RUN_OPTS="\$3"
EOT
	fi
	cat >>$SCRIPT_PATH <<EOT
$(import_mplc_function)
$OTHER
filter_warnings=
skips='/^nginx: \[alert\]/d'
do_start() {
	$DELAY
	$KILL_CODESYS
	cd "$MPLC_DIR"
	$EXEC_CMD "$START_SCRIPT \$1 '\$MPLC_RUN_OPTS'" 1>$MPLC_DIR/start.log 2>&1
}
do_stop() {
	mplc_fkill "$NGINX_PID_FILE" 	1> $MPLC_DIR/start.log 2>&1
	mplc_nkill mplc_service 		1>>$MPLC_DIR/start.log 2>&1
	mplc_nkill mplc					1>>$MPLC_DIR/start.log 2>&1
	while [ -n "\$($SYS_PIDOF mplc)" ]; do sleep 1; done;
	return 0
}

__start() {
	
	local OUT=
	if [ "\$1" == "local" ]; then
		cd "$MPLC_DIR"
		$EXEC_CMD "$START_SCRIPT \$1 '\$MPLC_RUN_OPTS'"
		#\$(do_start \$1 )
	else
		echo -n "Starting MasterPLC..."
		\$(do_start \$1) && echo "   OK" || echo "   BAD"
		cat $MPLC_DIR/start.log | sed -e "\$skips"
		mplc_rm $MPLC_DIR/start.log
	fi
	
}

__stop() {
	echo -n "Stopping MasterPLC..."
	local OUT=
	\$(do_stop) &&	echo "   OK" || echo "   BAD"
	cat $MPLC_DIR/start.log | sed -e "\$skips"
	mplc_rm $MPLC_DIR/start.log
}
EOT
	if [ "$PLATFORM" != PLC210 ]; then
		cat >>$SCRIPT_PATH <<EOT
case "\$1" in
  start)
    __start \$2
	;;
  stop)
    __stop
	;;
  restart|reload)
	__stop
	__start \$2
	;;
  *)
	echo \$"Usage: \$0 {start|stop|restart}"
	exit 1
esac

exit $?
EOT
	fi
	chmod 755 $SCRIPT_PATH
	# ln -sf $SCRIPT_PATH /bin/mplc4
}

create_mplcstart_script() {
	local SCRIPT_PATH=$1
	local BASE_PORT=$2
	local MPLC_PATH=$3
	local NGINX_PATH=$4
	local NGINX_CONFIG=$5
	local LOGS_DIR=$6
	local MPLC_OPTS=
	local NODEJS_OPTS=
	local MPLC_URL="http://127.0.0.1:$NGINX_HTTP_POTR"

	if [ "$MPLC_WDT" != ON ]; then
		MPLC_OPTS="$MPLC_OPTS /nowdt"
	fi
	if [ "$MPLC_NETKEY" == ON ]; then
		MPLC_OPTS="$MPLC_OPTS /netkey"
	fi
	if [ "$MPLC_LOGS" == ON ]; then
		MPLC_OPTS="$MPLC_OPTS /log:log/mplc_\$CURDATE.txt"
		NODEJS_OPTS="$NODEJS_OPTS --log log/node_\$CURDATE.log"
	fi
	if [ "$MPLC_DUMP" == ON ]; then
		USE_DUMP=enable_dump
	fi
	if [ "$SYS_I386_DEP" == "ON" ]; then
		local OTHER_PATHS="/usr/lib/i386-linux-gnu"
	fi
	if [ "$MPLC_REPORT" == ON ]; then
		local REPORT_BUILDER=run_report_builder
	fi
	local CHECK_USER="$(add_check_user)"
	cat >$SCRIPT_PATH <<EOT
#!/bin/$SYS_SHELL
export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:$MPLC_PATH:$NGINX_PATH/lib:$OTHER_PATHS
CURDATE=\$(date +"%Y_%m_%d")
COUNT=$MPLC_EXEMPLARS
mkdir logs 2>/dev/null
echo "Started in \$(date +"%Y_%m_%d-%H:%M:%S")" > logs/start_log.txt
if [ -e $MPLC_PATH/prerun.sh ]; then 
	. $MPLC_PATH/prerun.sh 1>> logs/start_log.txt 2>&1
fi
enable_dump(){
	ulimit -c unlimited
	sysctl kernel.core_pattern=\$PWD/logs/%e.core 1>> logs/start_log.txt 2>&1
}
$USE_DUMP

$SYS_TRAP
START_OPTS="\$2"
INST_OPTS="$MPLC_OPTS"

$(import_mplc_function)

if [ "\$1" == "local" ]; then
	AS_LOCAL=TRUE
fi
if [ \$(mplc_regex "\$1" "$REGEX_NUM") == 0 ] ; then
	COUNT=\$1
fi

if [ -z "\$AS_LOCAL" ] && [ \$(mplc_regex "\$1" "$REGEX_NUM") != 0 ] ; then
	START_OPTS="\$START_OPTS \$1"
fi

start(){
	local PORT=\$1
	local PARAMS=\$2
	echo "Start mplc on \$PORT" >> logs/start_log.txt
	$MPLC_PATH/mplc_service \$PORT $MPLC_PATH/mplc new \$INST_OPTS \$START_OPTS \$PARAMS 1>> logs/start_log.txt 2>&1
}

run_with_check(){
	local NAME=\$1
	local CMD=\$2
	#\$3 - path to pidfile
	local TMP=\$( [ "\$3" ] && [ -e "\$3" ] && cat "\$3" )
	local PIDS=\$($SYS_PIDOF \$NAME 2>/dev/null) || true
	if [ "\$3" ] ; then
		if [ -z "\$PIDS" ] || [ \$(mplc_regex "\$PIDS" "\$TMP") != 0 ]; then
			mplc_rm \$3
			PIDS=
		else
			PIDS=\$TMP
		fi
	fi
	if [ -n "\$PIDS" ]; then
		if [ -z "\$AS_LOCAL" ]; then
			echo "\$NAME is already running. PID: \$PIDS"
		fi
	else
		\$(\$CMD)
	fi
}
run_nginx(){
	mkdir -p $LOGS_DIR/temp
	mkdir -p $LOGS_DIR/logs
	$NGINX_PATH/sbin/nginx -p \$PWD -c $NGINX_CONFIG
}
run_as_local(){
	$MPLC_PATH/mplc 1 2 \$INST_OPTS \$START_OPTS
}

run_as_service(){
	$CHECK_USER
	start $BASE_PORT
	$(mplc_loop i COUNT)
		start \$(($BASE_PORT + \$i)) "/ea:\$i"
	done
}

run_report_builder(){
	mplc_nkill node_ms4d
	$NODEJS_DIR/node_ms4d $NODEJS_DIR/index.js --mplc $MPLC_URL --exemplars \$COUNT $NODEJS_OPTS &
}

if [ -e "$NGINX_PATH/sbin/nginx" ]; then
	run_with_check nginx "run_nginx" $NGINX_PID_FILE
fi

if [ -n "\$AS_LOCAL" ]; then
	run_as_local
else
	run_with_check mplc_service "run_as_service \$1"
fi
$REPORT_BUILDER

EOT
	chmod 755 $SCRIPT_PATH
}

#--- Uninstaller block --------------------------
get_instaled_files() {
	cat <<EOL
$MPLC_PATH
$NGINX_PATH
EOL
}

remove_autorun() {
	local NN=$MPLC_RC_PRIORITY
	local FILE_NAME=$(basename $MPLC_INIT)
	local LINK_RUN=S${NN}_$(basename $MPLC_INIT)
	local LINK_STOP=K01_$(basename $MPLC_INIT)
	if [ -n "$FAKE_INIT_D" ]; then
		cat <<EOL
sed  -ie "/#run mplc/d; /$FILE_NAME/d" $FAKE_INIT_D
EOL
	elif [ "$SYS_UPDATE_RC" == "ON" ]; then
		cat <<EOL
update-rc.d -f $FILE_NAME remove
mplc_rm $MPLC_INIT
EOL
	else
		cat <<EOL
mplc_rm $MPLC_INIT
for num in 2 3 4 5; do
	mplc_rm /etc/rc\${num}.d/$LINK_RUN
done
for num in 0 1 6; do
	mplc_rm /etc/rc\${num}.d/$LINK_STOP
done
EOL
	fi
}

create_unistall_script() {
	local SCRIPT_PATH=$1
	local FILES="$(echo $(get_instaled_files))"
	cat >$SCRIPT_PATH <<EOT
#!/bin/$SYS_SHELL
$(import_mplc_function)

$(get_mplc_init) stop

echo "Remove from autostart"
$(remove_autorun)

echo "Remove installed files"
mplc_rm $FILES


EOT
	chmod 755 $SCRIPT_PATH
}
#--- Nginx config -------------------------------
install_nginx_config() {
	local CONFIG_PATH=$1
	local LOG_DIR=$2
	local HTTP_PORT=$3
	local USER_OPT=
	if [ -n "$NGINX_USER" ]; then
		USER_OPT="user $NGINX_USER;"
	fi
	local CONFIG_DIR="$(mplc_get_dir $(dirname $CONFIG_PATH))"
	local LOCATION_OPTS=$CONFIG_DIR/tmp.nginx.location_opt
	cat >$LOCATION_OPTS <<EOT
include fastcgi_params;
			add_header Access-Control-Allow-Origin * ;
			add_header X-Frame-Options ALLOWALL  ;
			if (\$request_method = 'OPTIONS') {
				 # Tell client that this pre - flight info is valid for 20 days
				add_header Access-Control-Allow-Origin * ;
				add_header 'Access-Control-Allow-Credentials' 'true' always;
				add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
				add_header 'Access-Control-Allow-Headers' 'Accept,Authorization,Cache-Control,Content-Type,DNT,If-Modified-Since,Keep-Alive,Origin,User-Agent,X-Requested-With' always;
				add_header 'Access-Control-Max-Age' 1728000;
				add_header 'Content-Type' 'text/plain charset=UTF-8';
				add_header 'Content-Length' 0;
				return 204;
			}
EOT

	local LOCATIONS=$CONFIG_DIR/tmp.nginx.locations
	cat >$LOCATIONS <<EOT
location ~ /(\d+)/Methods/(.*) {
			let \$fastcgi_port ( \$fastcgi_port_base + \$1 );
			fastcgi_pass  127.0.0.1:\$fastcgi_port;
			fastcgi_param  PATH_INFO /\$2;
			$(cat $LOCATION_OPTS)
		}
		location ~ /Methods/(.*) {
			fastcgi_pass fcgi_backend;
			fastcgi_keep_conn on;
			fastcgi_param  PATH_INFO /\$1;
			$(cat $LOCATION_OPTS)
		}
		location ~* ^.+\.(js)$ {
			add_header Cache-Control "no-cache, must-revalidate";
			root \$root_dir;
		}
		location / {
			index index.html;
			root \$root_dir;
		}
EOT
	local SERVER_HTTPS=$CONFIG_DIR/tmp.nginx.server_https
	if [ "$NGINX_HTTPS" == "ON" ]; then
		cat >$SERVER_HTTPS <<EOT
server {
		set \$fastcgi_port_base 30750;
		set \$root_dir "htdocs";
		server_name _;
		
		listen		443 ssl http2;
		ssl_certificate      server.crt;
		ssl_certificate_key  server.key;
		ssl_session_cache    shared:SSL:1m;
		ssl_session_timeout  5m;

		ssl_ciphers  HIGH:!aNULL:!MD5;
		ssl_prefer_server_ciphers  on;

		$(cat $LOCATIONS)
	}
EOT
	fi
	local SERVER_HTTP=$CONFIG_DIR/tmp.nginx.server_http
	if [ "$NGINX_HTTP" == "ON" ]; then
		cat >$SERVER_HTTP <<EOT
server {
		listen $HTTP_PORT default_server;
		server_name _;
		set \$fastcgi_port_base 30750;
		set \$root_dir "htdocs";
		
		$(cat $LOCATIONS)
	}
EOT
	fi
	local GZIP_OPTS=$CONFIG_DIR/tmp.nginx.gzip_on
	if [ "$NGINX_GZIP" == "ON" ]; then
		cat >$GZIP_OPTS <<EOT
gzip  on;
	gzip_min_length 1000;
	gzip_buffers     4 4k;
	gzip_types application/x-javascript text/css application/javascript text/javascript text/plain text/xml application/json application/vnd.ms-fontobject application/x-font-opentype application/x-font-truetype application/x-font-ttf application/xml font/eot font/opentype font/otf image/svg+xml image/svg image/vnd.microsoft.icon;
	gzip_disable "msie6";
	
EOT
	fi
	cat >$CONFIG_PATH <<EOT
worker_processes  1;
$USER_OPT
#error_log  $LOG_DIR/error.log;
#error_log  $LOG_DIR/error.log  notice;
#error_log  $LOG_DIR/error.log  info;
error_log	$LOG_DIR/error.log  crit;
pid			$NGINX_PID_FILE;

pcre_jit off;

events {
    worker_connections  256;
}

http {
	proxy_temp_path 		$LOG_DIR/temp/proxy;
	fastcgi_temp_path 		$LOG_DIR/temp/fastcgi;
	scgi_temp_path 			$LOG_DIR/temp/scgi;
	uwsgi_temp_path 		$LOG_DIR/temp/uwsgi;
	client_body_temp_path	$LOG_DIR/temp/client;
	
	access_log off;
	access_log  			$LOG_DIR/access.log;
	include					mime.types;
	default_type			application/octet-stream;

    sendfile        on;

    keepalive_timeout  65;
	tcp_nopush on;
	tcp_nodelay on;
	
	$([ -e $GZIP_OPTS ] && cat $GZIP_OPTS)
	
	upstream fcgi_backend {
		server 127.0.0.1:30750;
		keepalive 16;
	}
	$([ -e $SERVER_HTTP  ] && cat $SERVER_HTTP )
	$([ -e $SERVER_HTTPS ] && cat $SERVER_HTTPS)
}
EOT
	mplc_rm $SERVER_HTTP $SERVER_HTTPS $LOCATIONS $LOCATION_OPTS
}
#--- Help Info ----------------------------------

create_help_file() {
	cat >$1 <<EOL
Help for MasterPLC:
$(get_mplc_init) <start | stop | restart> [local | N ] ["mplc opts"]
    start          Runing MasterPLC (mplc_service, mplc and nginx processes). If
                    something was started  before, a  warning  will be displayed
                    (not restarted).
    stop           Full stop MasterPLC (mplc_service, mplc and nginx  processes)
    restart        Always use if MasterPLC is already running and need to reload

    local          Running MasterPLC in debug  mode  with output to the terminal
                    If MasterPLC is already running, nothing happens
    N              Number of MasterPLC services for launche
    
    "mplc opts"    Additional startup  options that will be passed when starting
                    MasterPLC exemple "/nowdt /imit"
EOL
}
#--- Instalation functions ----------------------

install_nginx_cfg() {
	[ "$NGINX_UPDATE" != "ON" ] && return 0
	#	echo -n "Install Nginx configs...     "
	mkdir -p $NGINX_PATH $NGINX_LOGS
	install_nginx_config $NGINX_CONFIG $NGINX_LOGS $NGINX_HTTP_POTR
	[ "$MPLC_USER" == "root" ] ||
		chown $MPLC_USER:$MPLC_GROUP -R $NGINX_PATH
	#	echo OK
}
install_nginx_bin() {
	[ "$NGINX_UPDATE" != "ON" ] && return 0
	echo -n "Install Nginx...       "
	mkdir -p $NGINX_PATH $NGINX_LOGS
	mplc_unzip $NGINX_TAR $NGINX_PATH 1>/dev/null
	[ "$MPLC_USER" == "root" ] ||
		chown $MPLC_USER:$MPLC_GROUP -R $NGINX_PATH
	echo OK
}
install_mplc_cfg() {
	echo -n "Update configs...      "
	mkdir -p $MPLC_PATH
	[ "$MPLC_LOGS" == "OFF" ] || mkdir $MPLC_PATH/log
	create_mplc_scripts
	[ "$MPLC_USER" == "root" ] ||
		chown $MPLC_USER:$MPLC_GROUP -R $MPLC_PATH
	echo OK
}
install_mplc_bin() {
	echo -n "Install MPLC4...       "
	mplc_unzip $MPLC_TAR $MPLC_PATH 1>/dev/null
	[ "$MPLC_USER" == "root" ] ||
		chown $MPLC_USER:$MPLC_GROUP -R $MPLC_PATH
	echo OK
}
install_report_service() {
	echo -n "Install ReportBuiler...       "
	mkdir -p $NODEJS_DIR
	mplc_unzip $NODEJS_TAR $NODEJS_DIR 1>/dev/null
	[ "$MPLC_USER" == "root" ] ||
		chown $MPLC_USER:$MPLC_GROUP -R $NODEJS_DIR
	echo OK
}
run_install() {
	echo "Install dir: $MPLC_PATH"
	local last_action=restart
	clear_old_installer
	if [ "$MPLC_USER" != "root" ]; then
		create_user $MPLC_USER
	fi
	install_mplc_cfg
	if [ "$MPLC_CFG_ONLY" == "OFF" ]; then
		$(get_mplc_init) stop
		last_action=start
		install_mplc_bin
		install_nginx_bin
	fi
	if [ "$MPLC_REPORT" == ON ]; then
		install_report_service
	fi
	install_nginx_cfg
	echo "Installed successfully"
	#--- Install Dependency -------------------------
	if [ "$SYS_I386_DEP" == "ON" ]; then
		echo "Installing i386 dependency .."
		source /etc/os-release 2>/dev/null || ID=unknown
		if [ "$ID" == "debian" ] || [ $(mplc_regex "$ID_LIKE" "debian") == 0 ]; then
			dpkg --add-architecture i386
			apt-get update
			if [ "$ID" == "astra" ]; then
				apt-get install -y ia32-libs
			else
				apt-get install -y libstdc++6:i386 libgcc1:i386 zlib1g:i386 libncurses5:i386
			fi
		elif [ $(mplc_regex "$ID_LIKE" "rhel") == 0 ]; then
			yum check-update -y
			yum install -y libstdc++.i686 libcrypt.i686
		elif [ "$ID" == "altlinux" ]; then
			# local pkg_src="/etc/apt/sources.list.d/temp.list"
			# echo "rpm [cert8] ftp://update.altsp.su/pub/distributions/ALTLinux c8/branch/x86_64 classic" >> $pkg_src
			# echo "rpm [cert8] ftp://update.altsp.su/pub/distributions/ALTLinux c8/branch/x86_64-i586 classic" >> $pkg_src
			apt-get update
			apt-get install -y i586-libstdc++6 libstdc++6 i586-libgcc1 || echo "[ERROR] Can't install x86 dependency"
			apt-get install -y i586-libcrypt || echo "[WARNING] pkg i586-libcrypt not found"
			#rm $pkg_src
		else
			echo "[WARNING] Unknown type OS: $ID:$VERSION_ID ($ID_LIKE)"
			echo "[WARNING] Can\'t install x86 dependency"
		fi
	fi

	#--- Run MPLC -----------------------------------
	$(get_mplc_init) $last_action
	echo ""
	create_help_file "$MPLC_PATH/help"
	cat $MPLC_PATH/help
}

if [ "$EXTRA_CREATE_NGINX_CFG" == ON ]; then
	install_nginx_config $NGINX_CONFIG $NGINX_LOGS $NGINX_HTTP_POTR
	exit 0
fi

#--- Check files --------------------------------
MISSING_FILES=
if [ "$MPLC_CFG_ONLY" != "ON" ]; then
	if [ "$NGINX_UPDATE" == "ON" ] && ! [ -e $NGINX_TAR ]; then
		MISSING_FILES="$NGINX_TAR"
	fi
	if ! [ -e $MPLC_TAR ]; then
		MISSING_FILES="$MISSING_FILES $MPLC_TAR"
	fi
fi
if [ -n "$MISSING_FILES" ]; then
	echo "Error: does not exist $MISSING_FILES"
	exit 1
fi

#--- Check root ---------------------------------
if [ "$OS_NAME" == Linux ] && [ "$(id -u)" != "0" ]; then
	echo "This script must be run as root" 1>&2
	exit 1
fi

#--- Run install ------------------------------

run_install
