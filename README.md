# REF
[yum repo linux-ha](http://linux-ha.osdn.jp/wp/archives/4051)
[pacemaker](http://qiita.com/takehironet/items/08716d3a9d1165f47b5c)

# 実行方法
- リソースの用意
```
vagrant up
```

- プロビジョニング
```
ansible-playbook -i test main.yml
```

- ログイン
```
#db1
ssh -i ~/.vagrant.d/insecure_private_key vagrant@10.11.22.101
#db2
ssh -i ~/.vagrant.d/insecure_private_key vagrant@10.11.22.102
#batch1
ssh -i ~/.vagrant.d/insecure_private_key vagrant@10.11.22.111
```

- クラスタ設定＆開始
```
#-----------------------------------------------------
# [db1,db2 共通]
#-----------------------------------------------------
# corosyncの事前起動が必要（無しの状態で以下のコマンドを実行するとOKに成るが起動できていない。）
# Upstartを利用してもできますが、ここではSysVを利用しています。
# pacemakerを起動させる時は、mysqldのレプリケーションの用意が完了してから
# 実行させた方が良いため、自動起動の登録はしません。
sudo service corosync start
sudo service pacemaker start

#-----------------------------------------------------
# [db1,db2 どちらか一方]
#-----------------------------------------------------
#
# http://clusterlabs.org/doc/
#   Pacemaker 1.1 for Corosync 2.x and pcs
#   -> Pacemaker Explained (en-US)
#
# [Property]
#   QUORUMの影響を無視、STONITHを無効化、Fail-Backを無効化
sudo crm configure property no-quorum-policy="ignore" \
                            stonith-enabled="false" \
                            default-resource-stickiness=INFINITY

# [Resource]
#   デフォルト設定
#     [詳細] フェイルバックを無効、稼働中のリソース監視(monitor)が1回の故障を検知すると Fail-Overを実施
#     [参考] http://friendsnow.hatenablog.com/entry/2013/05/29/235552
#sudo crm configure rsc_defaults resource-stickiness="INFINITY" \
#                   migration-threshold="1"

#   VIP監視
#     [詳細] crm ra info ocf:heartbeat:VIPcheck
#     [削除] crm configure delete vipchk
#     [参考] http://gihyo.jp/admin/serial/01/pacemaker/0003?page=3
#sudo crm configure primitive vipchk \
#  ocf:heartbeat:VIPcheck params target_ip="10.11.22.100" count=3 wait=5 \
#  op start   interval=0  timeout=60 on-fail="restart" \
#  op stop    interval=0  timeout=60 on-fail="ignore" \
#  op monitor interval=10 timeout=60 on-fail="restart" start-delay=0

#   VIP設定
sudo crm configure primitive vip \
  ocf:heartbeat:IPaddr2 \
    params \
     ip="10.11.22.100" \
     cidr_netmask="24" \
     nic="eth1"

#   メール送信
#     [参考] https://www.uramiraikan.net/Works/entry-2144.html
#     [補足] sendmailコマンドで事前にメールが届くことを確認しておいたほうが良い。
#sudo crm configure primitive mailto \
#  ocf:heartbeat:MailTo \
#    params \
#     email="to_mohi_low@hotmail.com" \
#     subject="[Notify] failover"

#   MySQL設定
#   レプリケーションはmysqlfailoverに任せるので、ここではリソースの監視のみを行う。
#   [参考] http://linux-ha.osdn.jp/wp/archives/3855
#   [参考] http://clusterlabs.org/doc/en-US/Pacemaker/1.1/html/Pacemaker_Explained/s-resource-options.html
#sudo crm configure primitive mysqld \
#  lsb:mysqld \
#    op start enabled="false" interval="0" \
#    op stop enabled="false" interval="0" \
#    op monitor enabled="true" interval="10s" timeout="20s" \
#    meta migration-threshold="2" failure-timeout="30s"

# [Group]
#   GROUP設定
#sudo crm configure group vip-grp \
#        vip mysqld

# [確認]
#   設定確認
sudo crm configure show

#   モニタリング (-Aをつけるとノードが確認出来る)
sudo crm_mon -A
```

- クラスタ検証
```
#-----------------------------------------------------
# [検証]
#-----------------------------------------------------

# (ネットワーク停止)
sudo /bin/bash -l -c 'ifdown eth1; sleep 10; ifup eth1'
--> 問題なく切り替わる
    * 復帰後、旧マスタのpacemaker及びcorosyncは停止していますので続けて運用するには両サービスとも再起動が必要。

# (Pacemaker 停止 or 再起動)
sudo service pacemaker (stop/restart)
--> 問題なく切り替わる

sudo kill -kill <pacemakerd pid>
--> vipが切り替わらない
    pacemakerdがいないだけで何も変わらない。
    [対応方法]
      pacemakerを起動(sudo service pacemaker start)
      監視しておいてpacemaerdが停止していたらアラートを出すように設定しておくと良さそう。
      * 誤ってcorosyncを停止してしまうと、一時的に両端末にvipが割り当てられてしまいます。
      * また、その状態でcorosyncの再起動後にpacemakerを起動するとvipがfailbackしてしまうので注意してください。

sudo kill -kill <pacemaker resource pid>
--> vipは切り替わらない
    例えば「/usr/libexec/pacemaker/cib」をkillした場合は、自動的に復活するので対応不要。

# (Corosync 停止)
# VIPが残ってしまうので一番厄介
sudo service corosync stop
--> vipが両端末についた状態になる
    pacemakerも連動して停止
    [対応方法]
      下記コマンドでVIPを手動で外した後、corosync,pacemakerを起動
      sudo ip addr del 10.11.22.100/24 dev eth1
      * 削除しない場合、corosync,pacemakerを起動した時にどちらのVIPが残るかわからなくなる。

sudo kill -kill <corosync pid>
--> sudo service corosync stop と同じ挙動

# (手動切り替え)
sudo crm resource move vip db2.localnet force
--> 問題なく切り替わるが以降VIPの自動切り替えができなくなる
    [対応方法]
      下記コマンドを実行して自動切り替えを可能にしておく
      sudo crm resource unmove vip

#-----------------------------------------------------
# [検証結果]
#-----------------------------------------------------
・pacemaker, corosyncの監視は必須
・corosync停止時にvipを削除する方法を考えなければならない。
```

- mysql replication 設定
```
#-----------------------------------------------------
# [batch1]
#-----------------------------------------------------
# [設定]
#   レプリケーション開始 (hostnameで指定した場合は、hostnameをHostとしてrpl_userが作成される。)
mysqlreplicate --master=root:root@db1.localnet:3306 --slave=root:root@db2.localnet:3306 --rpl-user=rpl_user:rpl_pass

# [確認]
#   Master/Slave状態を確認
#   片方だけがslaveが付いている状態であれば正常
mysqlrpladmin --master=root:root@db1.localnet --discover-slaves-login=root:root health
mysqlrpladmin --master=root:root@db2.localnet --discover-slaves-login=root:root health

#   レプリケーション・トポロジを表示
#   表示形式が違うだけで、上と表示される内容は同じ
mysqlrplshow --master=root:root@db1.localnet --discover-slaves-login=root:root
mysqlrplshow --master=root:root@db2.localnet --discover-slaves-login=root:root

#   レプリケーションの関係が正常であることを確認 (hostname)
#   slave側として動いている方は "Slave is stopped." になっているはず。
mysqlrplcheck --master=root:root@db1.localnet --slave=root:root@db2.localnet
mysqlrplcheck --master=root:root@db2.localnet --slave=root:root@db1.localnet


# [監視]
#   自動での切り替え
#   mysqlfailover開始 （candidatesは指定するとdb1->db2->db1とマスタを切り替えるとmysqlfailoverが落ちるので利用しない。）
mysqlfailover --master=root:root@db1.localnet --discover-slaves-login=root:root --force
* 起動scriptを作った方が良い、、、、、

#   手動での切り替え
#     - master:     現行マスタ
#     - new-master: 新マスタ
#     - demote-master: 現行マスタを新マスタのスレーブに降格
#     - rpl-user
mysqlrpladmin \
  --master=root:root@db2.localnet \
  --new-master=root:root@db1.localnet \
  --demote-master \
  --discover-slaves-login=root switchover

# [バックアップ/リストア]
#   バックアップ : mysqldump
#     - InnoDB onlyの環境なのでロックはしない（single-transaction, skip-lock-tables）
#     - binlogファイルをフラッシュして、新しいbinlogファイルを作成（flush-logs） ---> flush tables with read lock と同じ？？？？
#     - dump内にCHANGE MASTER TO句を追加（master-data=2）
#     - gtidを利用しているのでWarningが出ないように調整（triggers, routines, events）
#     [参考] http://qiita.com/ryounagaoka/items/7be0479a36c97618907f
mysqldump
  -u root -proot --all-databases \
  --single-transaction --skip-lock-tables \
  --flush-logs \
  --master-data=2 \
  --triggers --routines --events \
  | gzip -c > /vagrant/mysqldump.`date +"%Y%m%d_%I%M%S"`

#   リストア : mysql
mysql -u root -proot < /vagrant/mysqldump.`date +"%Y%m%d_%I%M%S"`
#     - mysqlrplicateでレプリケーション構築（バッチサーバにて）
mysqlreplicate --master=root:root@db2.localnet:3306 --slave=root:root@db1.localnet:3306 --rpl-user=rpl_user:rpl_pass
#     - 手動でレプリケーション構築（DBサーバにて）
mysql -u root -proot --prompt='slave> '
slave> stop slave;
slave> change master to master_host='db2.localnet', master_user='rpl_user', master_password='rpl_pass', master_auto_position=1
slave> start slave;
```



# 補足
- Vagrant
    - 起動  
      `vagrant up`
    - 停止  
      `vagnrat halt`
    - 削除  
      `vagrant destroy`
    - サンドボックス状態確認 (required: sahara)  
      `vagrant sandbox status`
    - サンドボックス開始 (required: sahara)  
      `vagrant sandbox on`
    - サンドボックスコミット (required: sahara)  
      `vagrant sandbox commit`
    - サンドボックスロールバック (required: sahara)  
      `vagrant sandbox rollback`

- Ansible
    - 実行前の確認  
      `ansible-playbook -i test main.yml --list-tasks`
    - 実行  
      `ansible-playbook -i test main.yml`
    - 実行(結果の詳細表示)  
      `ansible-playbook -i test main.yml -vv`
    - 実行(特定のタグのみ)  
      `ansible-playbook -i test main.yml -t mysqlfailover`

- MySQL
    - Binary Log の見方
        - 別ファイルに保存  
          `mysqlbinlog mysql-bin.xxxxxxxx > /tmp/xxxxxxx.log`
        - 確認したいワ−ドがある前後5行を表示  
          `grep -e "zzzzzzz:xx" -5 /tmp/xxxxxxx.log`
    - Turning
        - [参考](http://www.s-quad.com/wordpress/?p=989)

# Trouble Shooting
- VIPの設定エラー
```
#
# VIPを設定しようとするとエラーになる
#
[root@db1 ~]# crm configure primitive vip ocf:heartbeat:IPaddr2 params ip="10.11.22.100" cidr_netmask="24" nic="eth1"
ERROR: crm_verify: symbol lookup error: /usr/lib64/libpe_status.so.4: undefined symbol: g_list_free_full

#
# 「/usr/lib64/libpe_status.so.4」がどのパッケージでインストールされているのかを確認
#
[root@db1 ~]# rpm -qf /usr/lib64/libpe_status.so.4
pacemaker-libs-1.1.13-1.el6.x86_64

#
# 「pacemaker-libs-1.1.13-1.el6.x86_64」はpacemakerとバージョンが一致しているので原因の可能性はない。
# となると、このライブラリから別のものを呼び出して、そこでエラーになった可能性があるので、updateを試みる。
#
[root@db1 ~]# yum update
```
