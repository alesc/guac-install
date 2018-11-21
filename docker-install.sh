#!/bin/bash

# Version number of Guacamole to install
GUACVERSION="0.9.14"

# Get script arguments for non-interactive mode
while [ "$1" != "" ]; do
    case $1 in
        -m | --mysqlpwd )
            shift
            mysqlpwd="$1"
            ;;
        -g | --guacpwd )
            shift
            guacpwd="$1"
            ;;
    esac
    shift
done

# Get MySQL root password and Guacamole User password
if [ -n "$mysqlpwd" ] && [ -n "$guacpwd" ]; then
        mysqlrootpassword=$mysqlpwd
        guacdbuserpassword=$guacpwd
else
    echo 
    while true
    do
        read -s -p "Enter a MySQL ROOT Password: " mysqlrootpassword
        echo
        read -s -p "Confirm MySQL ROOT Password: " password2
        echo
        [ "$mysqlrootpassword" = "$password2" ] && break
        echo "Passwords don't match. Please try again."
        echo
    done
    echo
    while true
    do
        read -s -p "Enter a Guacamole User Database Password: " guacdbuserpassword
        echo
        read -s -p "Confirm Guacamole User Database Password: " password2
        echo
        [ "$guacdbuserpassword" = "$password2" ] && break
        echo "Passwords don't match. Please try again."
        echo
    done
    echo
fi

# Start MySQL
docker run --restart=always --detach --name=mysql --env="MYSQL_ROOT_PASSWORD=$mysqlrootpassword" mysql

# Sleep to let MySQL load (there's probably a better way to do this)
echo "Waiting 30 seconds for MySQL to load"
sleep 30

# Create the Guacamole database and the user account
# SQL Code
SQLCODE="
create database guacamole_db; 
create user 'guacamole_user'@'%' identified by '$guacdbuserpassword'; 
GRANT SELECT,INSERT,UPDATE,DELETE ON guacamole_db.* TO 'guacamole_user'@'%'; 
create user 'guacamole_user'@'localhost' identified by '$guacdbuserpassword';
GRANT SELECT,INSERT,UPDATE,DELETE ON guacamole_db.* TO 'guacamole_user'@'localhost';
flush privileges;"

# Execute SQL Code
echo $SQLCODE |  docker exec -i mysql mysql -p$mysqlrootpassword

docker run --rm guacamole/guacamole /opt/guacamole/bin/initdb.sh --mysql > initdb.sql
cat initdb.sql | docker exec -i mysql mysql -p$mysqlrootpassword guacamole_db

docker run --restart=always --name guacd -d guacamole/guacd
docker run --restart=always --name guacamole  --link mysql:mysql --link guacd:guacd -e MYSQL_HOSTNAME=127.0.0.1 -e MYSQL_DATABASE=guacamole_db -e MYSQL_USER=guacamole_user -e MYSQL_PASSWORD=$guacdbuserpassword --detach -p 8080:8080 guacamole/guacamole

rm initdb.sql

# Patch for latest mysql version compatibility
docker exec -it guacamole bash -c "
wget https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-8.0.13.tar.gz
tar xf mysql-connector-java-8.0.13.tar.gz
rm mysql-connector-java-8.0.13.tar.gz
mv mysql-connector-java-8.0.13/mysql-connector-java-8.0.13.jar /opt/guacamole/mysql/
rm /opt/guacamole/mysql/mysql-connector-java-5.1.35-bin.jar
"
docker restart guacamole
