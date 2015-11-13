#!/bin/sh
#
# Simple mysqlfailover init.d script conceived to work on Linux systems
# as it does use of the /proc filesystem.
# chkconfig: - 85 15
# description: mysqlfailover
# processname: mysqlfailover

. /etc/rc.d/init.d/functions

EXEC=/usr/bin/mysqlfailover
prog=$(basename $EXEC)

PIDFILE=/var/run/mysqlfailover.pid
LOGFILE=/tmp/mysqlfailover.log
PORT=3306
fouser=root
fopass={{ dbrootpassword }}
rpluser={{ dbrpluser }}
rplpass={{ dbrplpassword }}
#current_master=10.11.22.101
#new_master=10.11.22.102
intervalsec=15
exec_failchk=/usr/local/bin/failchk.sh
#exec_before=/usr/local/bin/before_failover.sh
exec_after=/usr/local/bin/after_failover.sh
#exec_postfail=/usr/local/bin/post_failover.sh

get_current_master() {
	for h in `grep "db.\.localnet" /etc/hosts |cut -f1`; do
		is_slave=`/usr/bin/mysql -u root -proot -h $h -e "show slave status \G" 2> /dev/null |wc -l`
		if [ $is_slave -eq 0 ]; then
			if [ "$current_master" = "" ]; then
				current_master=$h
			else
				failure
				echo "multi-master configuration is not supported"
				exit 1
			fi
		else
			if [ "$new_master" = "" ]; then
				new_master=$h
			else
				failure
				echo "not started replication"
				exit 1
			fi
		fi
	done
}

start() {
	get_current_master

	if [ -f $PIDFILE ]
	then
		failure
		echo "$PIDFILE exists, process is already running or crashed"
	else
		$EXEC --master=${fouser}:${fopass}@${current_master}:${PORT} \
		--discover-slaves-login=${fouser}:${fopass} \
		--log=${LOGFILE} --pidfile=${PIDFILE} -i ${intervalsec} \
		--rpl-user=${rpluser}:${rplpass} \
		--exec-after=${exec_after} \
		--failover-mode=auto --daemon=start -vv --force
		##--candidate=${fouser}:${fopass}@${new_master}:${PORT} \
		##–exec-before=${exec_before} \
		##--exec-post-failover=${exec_postfail} \
		##--exec-fail-check=${exec_failchk} \
		success
		echo "mysqlfailover started"
	fi
}
stop() {
	if [ ! -f $PIDFILE ]
	then
		echo "$PIDFILE does not exist, process is not running"
	else
		PID=$(cat $PIDFILE)
		$EXEC --log=${LOGFILE} --pidfile=${PIDFILE} \
		--daemon=stop -vv
		while [ -x /proc/${PID} ]
		do
			echo "Waiting for mysqlfailover to shutdown …"
			sleep 1
		done
		success
		echo "mysqlfailover stopped"
	fi
}

rh_status() {
	status $prog
}

case "$1" in
	start)
		start
		;;
	stop)
		stop
		;;
	restart)
		stop
		start
		;;
	status)
		rh_status
		;;
	*)
		echo "Please use start or stop as first argument"
		;;
esac
