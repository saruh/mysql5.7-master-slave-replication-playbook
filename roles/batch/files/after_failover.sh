#!/bin/sh

#
# REF:
#   https://dev.mysql.com/doc/mysql-utilities/1.5/en/mysqlfailover.html
#
# echo "param 1: $1" >> /tmp/after_failover.log
# echo "param 2: $2" >> /tmp/after_failover.log
# echo "param 3: $3" >> /tmp/after_failover.log
# echo "param 4: $4" >> /tmp/after_failover.log
# echo "param 5: $5" >> /tmp/after_failover.log
# echo "param 6: $6" >> /tmp/after_failover.log

OLD_MASTER_HOST=$1
OLD_MASTER_PORT=$2
NEW_MASTER_HOST=$3
NEW_MASTER_PORT=$4

cat << EOS >> /tmp/after_failover.log
---------------------------------------------------------
[`date +"%Y/%m/%d %H:%M:%S"`]
OLD_MASTER_HOST=$OLD_MASTER_HOST
OLD_MASTER_PORT=$OLD_MASTER_PORT
NEW_MASTER_HOST=$NEW_MASTER_HOST
NEW_MASTER_PORT=$NEW_MASTER_PORT
EOS

#
# [Debug] ステータスを確認
#
# /usr/bin/ssh \
#   ha-user@$NEW_MASTER_HOST \
#   -i /etc/ssh/id_rsa \
#   -o StrictHostKeyChecking=no \
#   -o UserKnownHostsFile=/dev/null \
#   sudo crm configure show >> /tmp/after_failover.log 2>&1

#
# [新マスタ] VIP を移動
#
/usr/bin/ssh \
  ha-user@$NEW_MASTER_HOST \
  -i /etc/ssh/id_rsa \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  sudo crm resource move vip $NEW_MASTER_HOST force >> /tmp/after_failover.log 2>&1

#
# [新マスタ] read_onlyフラグをoffに設定
#
/usr/bin/mysql \
  -u root -proot -h $NEW_MASTER_HOST \
  -e "SET GLOBAL read_only = 0" >> /tmp/after_failover.log 2>&1

#
# [新マスタ] VIP を移動できるように後処理
#  本来は、VIPが一度移動したらその後はメンテナンスをするまで移動するべきではないと思うが、
#  とりあえず、scriptは記述しておく。（実行するかどうかは要検討）
#
# /usr/bin/ssh \
#   ha-user@$NEW_MASTER_HOST \
#   -i /etc/ssh/id_rsa \
#   -o StrictHostKeyChecking=no \
#   -o UserKnownHostsFile=/dev/null \
#   sudo crm resource unmove vip >> /tmp/after_failover.log 2>&1

#
# --- ここからは旧マスタへの処理 ---
# サーバが死んでいる場合はtimeoutになるまで時間がかかるので
# 旧マスタへの処理としては、優先度を下げて行う。
#

#
# [旧マスタ] VIPが旧マスタに残ってしまっている場合を考慮
#
#   *** VIPの取得方法は要検討 ***
#
/usr/bin/ssh \
  ha-user@$OLD_MASTER_HOST \
  -i /etc/ssh/id_rsa \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  sudo ip addr del 10.11.22.100/24 dev eth1 >> /tmp/after_failover.log 2>&1

#
# [旧マスタ] read_onlyフラグをoffに設定
#
/usr/bin/mysql \
  -u root -proot -h $OLD_MASTER_HOST \
  -e "SET GLOBAL read_only = 1" >> /tmp/after_failover.log 2>&1
