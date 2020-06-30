#!/bin/sh
#2020/6/28

#定义变量
JAVA_HOME=/opt/kedacom/jdk1.8.0_211
tomcat=/opt/kedacom/apache-tomcat-8.5.47
mysqlpwd=kedacom#123
username_pwd='-uroot -p'$mysqlpwd''
mysql_data=/opt/kedacom/mysqlhome/data

#centos 需安装gcc gcc-c++
#开启所需端口
init_pro ()
{
	p8080=`firewall-cmd --add-port=8080/tcp --permanent | grep -e success`
	sleep 1
	if [ p8080 = success ];then
	echolog   "8080端口开启成功"
	else
	echolog   "8080端口开启失败"
	fi
	p3306=`firewall-cmd --add-port=3306/tcp --permanent | grep -e success`
	sleep 1
	if [ p3306 = success ];then
	echolog  "3306端口开启成功"
	else
	echolog   "3306端口开启失败"
	fi
}

init_pkg()
{
	echolog "开始安装jdk..."

	tar -xvf $shell/pkg/jdk.tar.gz -C /opt/kedacom
	if [ $? != 0 ]; then 
	echolog   "jdk安装失败"
	exit
	fi
	echo export JAVA_HOME=/opt/kedacom/jdk1.8.0_211>>/etc/profile
	echo export JRE_HOME=/opt/kedacom/jdk1.8.0_211/jre>>/etc/profile
	echo export CLASSPATH=.:$JAVA_HOME/lib/dt.jar:$JAVA_HOME/lib/tools.jar >>/etc/profile
	sleep 1
	
	echolog "开始安装中间件..."
	sh  $shell/pkg/mid_setup.sh
	if [ $? != 0 ]; then
	echolog   "中间件安装失败"
	exit
	fi
	#添加开机自启
	echo "/opt/kedacom/MID/startup.sh " >>/etc/rc.d/rc.local
	sleep 1
	cp -r $shell/usr/lib/*  /usr/lib

	sleep 3
	cp -r $shell/lib64/*    /usr/lib64
    sleep 1  
	chmod +x /usr/lib/hostapp
	chmod +x /etc/rc.d/rc.local
	/opt/kedacom/MID/startup.sh
}


mysql_install()
{
	ulimit -n 65535
	ulimit -u unlimited
	systemctl stop firewalld
	echo "ulimit -s unlimited" >>/etc/profile
	echo "ulimit -q unlimited" >>/etc/profile
	echo "ulimit -n 1000000" >>/etc/profile
	source /etc/selinux/config
	mariadb=$(rpm -qa|grep mariadb)
	if [  -n "$mariadb" ];then
		echo "unuplod mariadb"
		rpm -e --nodeps $mariadb
	fi
	mysql=$(rpm -qa|grep mysql)
	if [  -n  "$mysql" ];then
         echo "unuplod mysql"
	 rpm -e --nodeps $mysql
	fi
	if [ ! -d  /opt/kedacom/mysqlhome/data ];then
       mkdir -p /opt/kedacom/mysqlhome/data
	   touch /opt/kedacom/mysqlhome/mysqld.log
	   chmod 666 /opt/kedacom/mysqlhome/mysqld.log
  fi
	groupadd mysql
useradd -g mysql mysql
sleep 1

chown -R mysql:mysql /opt/kedacom/mysqlhome/data
chmod -R 777 /opt/kedacom/mysqlhome/data
if [ -e /etc/my.cnf ];then
	touch /etc/my.cnf
else
	rm  -f /etc/my.cnf 
	touch /etc/my.cnf
fi
if [ -s /etc/my.cnf ];then
	sed -i 'i[mysql]' /etc/my.cnf 
else
	echo "[mysql]" >> /etc/my.cnf
fi
 sleep 1
 echo '[mysqld]' >>/etc/my.cnf 
 sleep 1
 echo 'port = 3306 ' >>/etc/my.cnf 
 sleep 1
 echo 'basedir=/opt/kedacom/mysql'>> /etc/my.cnf 
 sleep 1
 echo 'datadir=/opt/kedacom/mysqlhome/data'>> /etc/my.cnf
 sleep 1
 echo 'log-error=/opt/kedacom/mysqlhome/mysqld.log' >>/etc/my.cnf

ln -s /opt/kedacom/mysql/bin/mysql /usr/bin  
ln -s /opt/kedacom/mysql/bin/mysqladmin /usr/bin  
ln -s /opt/kedacom/mysql/bin/mysqld /usr/bin  
echolog  "开始安装mysql"
	tar -xvf $shell/pkg/mysql.tar.gz -C /opt/kedacom
	if [ $? != 0 ]; then 
	echo   "mysql安装失败"
	exit
	fi
	#添加环境变量
	echo export PATH=$PATH:$JAVA_HOME/bin:/opt/kedacom/mysql/bin  >>/etc/profile
	source /etc/profile
  mv /opt/kedacom/mysql-5.7.28-linux-glibc2.12-x86_64 /opt/kedacom/mysql
  chown -R mysql /opt/kedacom/mysql
  chgrp -R mysql /opt/kedacom/mysql
  /opt/kedacom/mysql/bin/mysqld --initialize --user=mysql --basedir=/opt/kedacom/mysql/ --datadir=/opt/kedacom/mysqlhome/data
#开启自启
cp /opt/kedacom/mysql/support-files/mysql.server /etc/init.d/mysql
chkconfig --add mysql
sleep 1
service mysql start
mysql_init_pwd=$(grep "temporary password" /opt/kedacom/mysqlhome/mysqld.log  |awk -F "[: ]" '{print $NF}')
echolog "MySQL初始化密码为：${mysql_init_pwd}"
mysqladmin -uroot -p${mysql_init_pwd} password "$mysqlpwd"

mysql $username_pwd  -e "flush privileges;"
mysql $username_pwd  -e "grant all privileges on *.* to root@'%' identified by '"$mysqlpwd"'"
	echolog "mysql 安装完成"
	systemctl restart mysql.service
	}
init_ngixn()
{
  rpm -ivh $shell/pkg/zlib-1.2.7-18.el7.x86_64.rpm
  rpm -ivh $shell/pkg/zlib-devel-1.2.7-18.el7.x86_64.rpm --force --nodeps
  echolog "开始安装prce..."
	tar -zxvf $shell/pkg/pcre-8.35.tar.gz -C /opt/kedacom/
	cd /opt/kedacom/pcre-8.35
	./configure
	make && make install
	echolog pcre-config --version

	echolog "开始安装nginx..."
	tar -zxvf $shell/pkg/nginx-1.16.1.tar.gz -C /opt/kedacom/
	cd /opt/kedacom/nginx-1.16.1
	./configure
	make && make install
	#添加开机自启
	echo "/usr/local/nginx/sbin/nginx" >>/etc/rc.d/rc.local
	echolog "启动nginx..."
	/usr/local/nginx/sbin/nginx
	if [ $? != 0 ]; then
	echo   "启动nginx失败"
	exit
	fi
	rm -rf /usr/local/nginx/conf/nginx.conf
  cp $shell/server/nginx.conf /usr/local/nginx/conf
  mkdir -p /opt/kedacom/iesweb/html
  cp -r $shell/server/static /opt/kedacom/iesweb/html
  cp $shell/server/index.html /opt/kedacom/iesweb/html
  /usr/local/nginx/sbin/nginx -s reload
  cp $shell/server/iesweb.jar     /opt/kedacom
  cd /opt/kedacom
  java -server -jar iesweb.jar
}	


echolog()
{
 echo $1 >> /opt/kedacom/echolog.log
 }

    shell=$(cd `dirname $0`; pwd)
    mkdir -p /opt/kedacom
    init_pro
    sleep 1
	  init_pkg
    sleep 1
    mysql_install
    sleep 1
    init_ngixn