#!/bin/bash

######################################################################
## Functions to deploy Fortress environment on localhost
######################################################################

## Prerequesites
function prerequesites {
    sudo apt-get update
    sudo apt-get install -y git
    # Dirty hack to be sure we resolve hostname properly
    sudo su -c 'echo "127.0.0.1 $HOSTNAME" >> /etc/hosts'
}

## JDK 1.7u55
function install_jdk7 {
    sudo mkdir -p /opt
    wget -P /tmp --no-check-certificate --no-cookies --header "Cookie: oraclelicense=accept-securebackup-cookie" http://download.oracle.com/otn-pub/java/jdk/7u55-b13/jdk-7u55-linux-x64.tar.gz

    sudo tar -xvzf /tmp/jdk-7u55-linux-x64.tar.gz -C /opt/
    sudo ln -s /opt/jdk1.7.0_55/ /opt/jdk

    echo 'export JAVA_HOME=/opt/jdk/' >> ~/.profile
    echo 'export PATH=${JAVA_HOME}/bin:${PATH}' >> ~/.profile
    source ~/.profile 

    sudo su -c "echo 'JAVA_HOME=/opt/jdk/' >> /etc/environment"
    source /etc/environment
}


## Maven 3
function install_maven3 {
    sudo apt-get install -y maven
}

## Apache Tomcat 7
function install_tomcat7 {
    sudo wget -P /tmp http://apache-mirror.rbc.ru/pub/apache/tomcat/tomcat-7/v7.0.70/bin/apache-tomcat-7.0.70.tar.gz
    sudo tar -xvzf /tmp/apache-tomcat-7.0.70.tar.gz -C /opt/
    sudo ln -s /opt/apache-tomcat-7.0.70 /opt/tomcat
    sudo su -c 'cat << TOMCATUSERS > /opt/tomcat/conf/tomcat-users.xml
<tomcat-users>
    <role rolename="manager-script"/>
    <role rolename="manager-gui"/>
    <user username="tcmanager" password="m@nager123" roles="manager-script"/>
    <user username="tcmanagergui" password="m@nager123" roles="manager-gui"/>
</tomcat-users>
TOMCATUSERS'

    # Force to use IPv4
    sudo su -c 'echo JAVA_OPTS=\"\$JAVA_OPTS -Djava.net.preferIPv4Stack=true -Djava.net.preferIPv4Addresses=true\" > /opt/tomcat/bin/setenv.sh'

    # Start it!
    sudo bash /opt/tomcat/bin/startup.sh
}

## Apache Fortress
# Clone Fortress repos
function clone_fortress_repos {
    cd ~
    git clone --branch 1.0.1 --depth 1 https://git-wip-us.apache.org/repos/asf/directory-fortress-core.git
    git clone --branch 1.0.1 --depth 1 https://git-wip-us.apache.org/repos/asf/directory-fortress-realm.git
    git clone --branch 1.0.1 --depth 1 https://git-wip-us.apache.org/repos/asf/directory-fortress-commander.git
    git clone --branch 1.0.1 --depth 1 https://git-wip-us.apache.org/repos/asf/directory-fortress-enmasse.git
}

# Update Fortress Core Properties for OpenLDAP
function update_fortress_properties_openldap {
    cp ~/directory-fortress-core/build.properties.example ~/directory-fortress-core/build.properties
    sed -e 's/ldap.server.type=.*/ldap.server.type=openldap/' -i ~/directory-fortress-core/build.properties
    sed -e 's/ldap.port=.*/ldap.port=389/' -i ~/directory-fortress-core/build.properties
    sed -e 's/suffix.name=.*/suffix.name=openldap/' -i ~/directory-fortress-core/build.properties
    sed -e 's/suffix.dc=.*/suffix.dc=org/' -i ~/directory-fortress-core/build.properties
    sed -e 's/root.dn=.*/root.dn=cn=Manager,${suffix}/' -i ~/directory-fortress-core/build.properties
    echo 'ldap.uris=ldap://${ldap.host}:${ldap.port}' >> ~/directory-fortress-core/build.properties
    echo 'suffix=dc=${suffix.name},dc=${suffix.dc}' >> ~/directory-fortress-core/build.properties
}

## OpenLDAP
function install_openldap {
    sudo apt-get install -y slapd ldap-utils
    sudo service slapd stop
    # Delete auto-created dir
    sudo mv /etc/ldap/slapd.d/ /etc/ldap/old.slapd.d/
    # Copy schema examples from fortress
    sudo cp ~/directory-fortress-core/ldap/schema/{fortress.schema,rbac.schema} /etc/ldap/schema/
    # Update SLAPD conf
    sudo su -c 'cat <<SLAPDCONF > /etc/ldap/slapd.conf
include         /etc/ldap/schema/core.schema
include         /etc/ldap/schema/ppolicy.schema
include         /etc/ldap/schema/cosine.schema
include         /etc/ldap/schema/inetorgperson.schema
include         /etc/ldap/schema/nis.schema
include         /etc/ldap/schema/openldap.schema
include         /etc/ldap/schema/fortress.schema
include         /etc/ldap/schema/rbac.schema
disallow bind_anon
idletimeout 0
sizelimit 5000
timelimit 60
threads 8
loglevel 32768
gentlehup on
pidfile         /var/lib/ldap/slapd.pid
argsfile        /var/lib/ldap/slapd.args
modulepath      /usr/lib/ldap
moduleload      back_mdb.la
moduleload      ppolicy.la
moduleload  accesslog.la
### This one allows user to modify their own password (needed for pw policies):
### This also allows user to modify their own ftmod attributes (needed for audit):
access to attrs=userpassword
         by self write
         by * auth
### Must allow access to dn.base to read supported features on this directory:
access to dn.base="" by * read
access to dn.base="cn=Subschema" by * read
access to *
        by self write
        by anonymous auth
### Disable null base search of rootDSE
### This disables auto-discovery capabilities of clients.
# Changed -> access to dn.base="" by * read <- to the following:
access to dn.base=""
     by * none
password-hash {SSHA}
#######################################################################
# History DB Settings
#######################################################################
database         mdb
maxreaders 64
maxsize 1000000000
suffix          "cn=log"
rootdn      "cn=Manager,cn=log"
rootpw      "{SSHA}pSOV2TpCxj2NMACijkcMko4fGrFopctU"
index objectClass,reqDN,reqAuthzID,reqStart,reqAttr eq
directory       "/var/lib/ldap/hist"
access to *
    by dn.base="cn=Manager,cn=log" write
dbnosync
checkpoint   64 5
#######################################################################
# Default DB Settings
#######################################################################
database        mdb
maxreaders 64
maxsize 1000000000
suffix          "dc=openldap,dc=org"
rootdn      "cn=Manager,dc=openldap,dc=org"
rootpw      "{SSHA}pSOV2TpCxj2NMACijkcMko4fGrFopctU"
index uidNumber,gidNumber,objectclass eq
index cn,sn,ftObjNm,ftOpNm,ftRoleName,uid,ou eq,sub
index ftId,ftPermName,ftRoles,ftUsers,ftRA,ftARA eq
directory       "/var/lib/ldap/dflt"
overlay accesslog
logdb   "cn=log"
dbnosync
checkpoint      64 5
#######################################################################
# Audit Log Settings
#######################################################################
logops bind writes compare
logoldattr ftModifier ftModCode ftModId ftRC ftRA ftARC ftARA ftCstr ftId ftPermName ftObjNm ftOpNm ftObjId ftGroups ftRoles ftUsers ftType
logpurge 5+00:00 1+00:00
#######################################################################
# PW Policy Settings
#######################################################################
# Enable the Password Policy overlay to enforce password policies on this database.
overlay     ppolicy
ppolicy_default "cn=PasswordPolicy,ou=Policies,dc=openldap,dc=org"
ppolicy_use_lockout
ppolicy_hash_cleartext
SLAPDCONF'

    # Configure slapd dbs
    sudo mkdir -p /var/lib/ldap/{hist,dflt}
    sudo chown -R openldap:openldap /var/lib/ldap/

    # Set services address and remove user and group; use slapd.conf as default
#    sudo sed -e 's/SLAPD_CONF=.*/SLAPD_SERVICES=\/etc\/ldap\/slapd.conf/' -i /etc/default/slapd
    sudo sed -e 's/SLAPD_SERVICES=.*/SLAPD_SERVICES="ldap:\/\/localhost:389\/ ldaps:\/\/\/ ldapi:\/\/\/"/' -i /etc/default/slapd
    sudo sed -e 's/SLAPD_USER=.*//' -i /etc/default/slapd
    sudo sed -e 's/SLAPD_GROUP=.*//' -i /etc/default/slapd

    # Start it!
    sudo service slapd start
}


## Apache Directory Studio
function install_ds {
    source /etc/environment
    source ~/.profile
    wget -P /tmp  http://apache-mirror.rbc.ru/pub/apache/directory/studio/2.0.0.v20151221-M10/ApacheDirectoryStudio-2.0.0.v20151221-M10-linux.gtk.x86_64.tar.gz
    tar -xvf /tmp/ApacheDirectoryStudio-2.0.0.v20151221-M10-linux.gtk.x86_64.tar.gz -C ~/
}


## Apache Fortress
# Build Fortress core artefacts
function load_ldap_data_from_fortress {
    source /etc/environment 
    source ~/.profile
    cd ~/directory-fortress-core
    mvn clean install

    # Update LDAPData XML
    sudo sed -e 's/@USR_MIN_CONN@/1/' -i ~/directory-fortress-core/ldap/setup/refreshLDAPData.xml
    sudo sed -e 's/@USR_MAX_CONN@/10/' -i ~/directory-fortress-core/ldap/setup/refreshLDAPData.xml
    sudo sed -e 's/@SERVER_TYPE@/openldap/' -i ~/directory-fortress-core/ldap/setup/refreshLDAPData.xml

    # Load data
    cd ~/directory-fortress-core
    mvn install -Dload.file=./ldap/setup/refreshLDAPData.xml
    mvn install -Dload.file=./ldap/setup/DelegatedAdminManagerLoad.xml
}

## Fortress Realm (LIB)
function install_fortress_realm {
    source /etc/environment
    source ~/.profile
    cd ~/directory-fortress-realm/
    mvn clean install
    # Copy JAR to Tomcat libs
    sudo cp ~/directory-fortress-realm/proxy/target/fortress-realm-proxy-*.jar /opt/tomcat/lib/
}


## Fortress Commander (WEB)
function install_fortress_commander {
    source /etc/environment
    source ~/.profile
    cd ~/directory-fortress-commander/
    cp ~/directory-fortress-core/config/fortress.properties ~/directory-fortress-commander/src/main/resources
    mvn install -Dload.file=./src/main/resources/FortressWebDemoUsers.xml
    mvn tomcat:deploy
    # Auth as in web as "test" "password"
}

## Fortress Enmasse (REST)
function install_fortress_enmasse {
    source /etc/environment
    source ~/.profile
    cd ~/directory-fortress-enmasse/
    cp ~/directory-fortress-core/config/fortress.properties ~/directory-fortress-enmasse/src/main/resources
    mvn install -Dload.file=./src/main/resources/FortressRestServerPolicy.xml
    mvn tomcat:deploy
    # To test:
    # mvn test -Dtest=EmTest
    # Test  curl: 
    # curl --user demouser4:password -X POST -d @userRead.xml -H "Accept: text/xml" -H "Content-Type: text/xml" http://localhost:8080/fortress-rest-1.0-RC41-SNAPSHOT/userRead
}

## Standalone Keystone installed by Devstack
function standalone_keystone {
cd ~
git clone https://git.openstack.org/openstack-dev/devstack

MY_IP=`/sbin/ifconfig eth0|grep inet|head -1|sed 's/\:/ /'|awk '{print $3}'`
ADMIN_PASSWORD="admin"

cat << DEVSTACKCONF > ~/devstack/local.conf
[[local|localrc]]
ADMIN_PASSWORD=admin
DATABASE_PASSWORD=$ADMIN_PASSWORD
RABBIT_PASSWORD=$ADMIN_PASSWORD
SERVICE_PASSWORD=$ADMIN_PASSWORD
#FIXED_RANGE=172.31.1.0/24
#FLOATING_RANGE=192.168.20.0/25
HOST_IP=$MY_IP
SERVICE_IP_VERSION=4
disable_all_services
enable_service key rabbit mysql horizon
DEVSTACKCONF

cd ~/devstack
./stack.sh
}

######################################################################
## Run it!
######################################################################
prerequesites
install_jdk7
install_maven3
install_tomcat7
clone_fortress_repos
update_fortress_properties_openldap
install_openldap
install_ds
load_ldap_data_from_fortress
install_fortress_realm
install_fortress_commander
install_fortress_enmasse
# IF needed, install Keystone + Horizon
#standalone_keystone
