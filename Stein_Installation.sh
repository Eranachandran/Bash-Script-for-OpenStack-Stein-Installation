#! /bin/bash

function host_config()
{
controller=$(echo "$ip"     "controller")
sed -i "/127.0.0.1/a$controller" /etc/hosts
}

function install_stein_packages()
{
#NTP Installation
apt -y install chrony

#OpenStack Stein repository
add-apt-repository cloud-archive:stein -y

#Upgrade packages
apt -y update && apt -y dist-upgrade

#Installing OpenStack Client
apt -y install python3-openstackclient

#Installing chrony
apt -y install chrony

#Installing mariadb
apt -y install mariadb-server python-pymysql

#Installing rabbit-mq
apt -y install rabbitmq-server

#Installing memcached
apt -y install memcached python-memcache

#Installing Keystone
apt -y install keystone

#Installing Glance
apt -y install glance

#Installing placement
apt -y install placement-api


#Installing Nova
apt -y install nova-api nova-conductor nova-consoleauth nova-novncproxy nova-scheduler
apt -y install nova-compute

#Installing Neutron
apt -y install neutron-server neutron-plugin-ml2 neutron-linuxbridge-agent neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent
apt -y install neutron-linuxbridge-agent

#Installing Horizon
apt -y install openstack-dashboard
}

function configuring_db()
{

#copy preconfig file
cp ./conf_files/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf
sed -i -e  "s/^\(bind-address\s*=\).*/\1 $ip/" /etc/mysql/mariadb.conf.d/50-server.cnf

#Restart the database service
service mysql restart

#####Delete anonymous users and  SET plugin = mysql_native_password starts######

echo "UPDATE mysql.user SET Password=PASSWORD('$maria_db_root_password') WHERE User='root';" | mysql
echo "DELETE FROM mysql.user WHERE User='';" | mysql
echo "UPDATE mysql.user SET plugin = 'mysql_native_password' WHERE User = 'root';" | mysql
echo "FLUSH PRIVILEGES;" | mysql

#####Delete anonymous users and  SET plugin = 'mysql_native_password' ends######


#######Database and Database user Creation Starts#######

#keystone database
echo "CREATE DATABASE $keystone_db_name;" | $maria_db_connect
echo "GRANT ALL PRIVILEGES ON $keystone_db_name.* TO '$keystone_db_user'@'localhost' IDENTIFIED BY '$keystone_db_password';" | $maria_db_connect
echo "GRANT ALL PRIVILEGES ON $keystone_db_name.* TO '$keystone_db_user'@'%' IDENTIFIED BY '$keystone_db_password';" | $maria_db_connect
echo "FLUSH PRIVILEGES;" | $maria_db_connect

#glance database
echo "CREATE DATABASE $glance_db_name;" | $maria_db_connect
echo "GRANT ALL PRIVILEGES ON $glance_db_name.* TO '$glance_db_user'@'localhost' IDENTIFIED BY '$glance_db_password';" | $maria_db_connect
echo "GRANT ALL PRIVILEGES ON $glance_db_name.* TO '$glance_db_user'@'%' IDENTIFIED BY '$glance_db_password';" | $maria_db_connect
echo "FLUSH PRIVILEGES;" | $maria_db_connect

#placement database
echo "CREATE DATABASE $placement_db_name;" | $maria_db_connect
echo "GRANT ALL PRIVILEGES ON $placement_db_name.* TO '$placement_db_user'@'localhost' IDENTIFIED BY '$placement_db_password';" | $maria_db_connect
echo "GRANT ALL PRIVILEGES ON $placement_db_name.* TO '$placement_db_user'@'%' IDENTIFIED BY '$placement_db_password';" | $maria_db_connect
echo "FLUSH PRIVILEGES;" | $maria_db_connect

#nova_api database
echo "CREATE DATABASE $nova_api_db_name;" | $maria_db_connect
echo "GRANT ALL PRIVILEGES ON $nova_api_db_name.* TO '$nova_db_user'@'localhost' IDENTIFIED BY '$nova_db_password';" | $maria_db_connect
echo "GRANT ALL PRIVILEGES ON $nova_api_db_name.* TO '$nova_db_user'@'%' IDENTIFIED BY '$nova_db_password';" | $maria_db_connect
echo "FLUSH PRIVILEGES;" | $maria_db_connect

#nova database
echo "CREATE DATABASE $nova_db_name;" | $maria_db_connect
echo "GRANT ALL PRIVILEGES ON $nova_db_name.* TO '$nova_db_user'@'localhost' IDENTIFIED BY '$nova_db_password';" | $maria_db_connect
echo "GRANT ALL PRIVILEGES ON $nova_db_name.* TO '$nova_db_user'@'%' IDENTIFIED BY '$nova_db_password';" | $maria_db_connect
echo "FLUSH PRIVILEGES;" | $maria_db_connect

#nova_cell0 database
echo "CREATE DATABASE $nova_cell0_db_name;" | $maria_db_connect
echo "GRANT ALL PRIVILEGES ON $nova_cell0_db_name.* TO '$nova_db_user'@'localhost' IDENTIFIED BY '$nova_db_password';" | $maria_db_connect
echo "GRANT ALL PRIVILEGES ON $nova_cell0_db_name.* TO '$nova_db_user'@'%' IDENTIFIED BY '$nova_db_password';" | $maria_db_connect
echo "FLUSH PRIVILEGES;" | $maria_db_connect

#neutron database
echo "CREATE DATABASE $neutron_db_name;" | $maria_db_connect
echo "GRANT ALL PRIVILEGES ON $neutron_db_name.* TO '$neutron_db_user'@'localhost' IDENTIFIED BY '$neutron_db_password';" | $maria_db_connect
echo "GRANT ALL PRIVILEGES ON $neutron_db_name.* TO '$neutron_db_user'@'%' IDENTIFIED BY '$neutron_db_password';" | $maria_db_connect
echo "FLUSH PRIVILEGES;" | $maria_db_connect

#######Database and Database user Creation ends#######

}

function chrony()
{
#copy preconfig file
cp ./conf_files/chrony.conf /etc/chrony/chrony.conf

#restart chrony
service chrony restart

# verify NTP synchronization
chronyc sources
}

function rabbitmq()
{
#Add the openstack user
rabbitmqctl add_user openstack RABBIT_PASS

#Permit configuration, write, and read access for the openstack user
rabbitmqctl set_permissions openstack ".*" ".*" ".*"
}

function memcached()
{
#copy preconfig file
sed -i -e  "s/^\(-l\s*\).*/\1 $ip/" /etc/memcached.conf

#Restart the Memcached service
service memcached restart
}

function keystone()
{
#copy preconfig file
cp ./conf_files/keystone.conf /etc/keystone/keystone.conf


#Populating the Identity service database
su -s /bin/sh -c "keystone-manage db_sync" keystone

#Initialize Fernet key repositories
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

#Bootstrap the Identity service
keystone-manage bootstrap --bootstrap-password ADMIN_PASS \
  --bootstrap-admin-url http://controller:5000/v3/ \
  --bootstrap-internal-url http://controller:5000/v3/ \
  --bootstrap-public-url http://controller:5000/v3/ \
  --bootstrap-region-id RegionOne

#Restart the Apache service
export OS_USERNAME=admin
export OS_PASSWORD=ADMIN_PASS
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3

#Domain Creation
openstack domain create --description "An Example Domain" example

#Service project creation
openstack project create --domain default --description "Service Project" service

#demo project creation
openstack project create --domain default --description "Demo Project" myproject

#creating non-admin user
openstack user create --domain default --password MYUSER_PASS myuser

#creating my role
openstack role create myrole

#Add the myrole role to the myproject project and myuser user
openstack role add --project myproject --user myuser myrole

#Unset the temporary OS_AUTH_URL and OS_PASSWORD environment variable:
unset OS_AUTH_URL OS_PASSWORD

#As the admin user, request an authentication token
openstack --os-auth-url http://controller:5000/v3 \
  --os-project-domain-name Default --os-user-domain-name Default \
  --os-project-name admin --os-username admin --os-password ADMIN_PASS token issue

#As the myuser user created in the previous, request an authentication token
openstack --os-auth-url http://controller:5000/v3 \
  --os-project-domain-name Default --os-user-domain-name Default \
  --os-project-name myproject --os-username myuser --os-password MYUSER_PASS token issue
}

function glance()
{
#copy preconfig file
cp ./conf_files/glance-api.conf /etc/glance/glance-api.conf
cp ./conf_files/glance-registry.conf /etc/glance/glance-registry.conf

#Source the admin credentials to gain access to admin-only CLI commands
. admin-openrc

#Create the glance user
openstack user create --domain default --password GLANCE_PASS glance

#Add the admin role to the glance user and service project
openstack role add --project service --user glance admin

#Create the glance service entity
openstack service create --name glance \
  --description "OpenStack Image" image

#Create the Image service API endpoints
openstack endpoint create --region RegionOne image public http://controller:9292
openstack endpoint create --region RegionOne image internal http://controller:9292
openstack endpoint create --region RegionOne image admin http://controller:9292

#Populate the Image service database
su -s /bin/sh -c "glance-manage db_sync" glance

#Restart the Image services
service glance-registry restart
service glance-api restart

sleep 10s

#Source the admin credentials to gain access to admin-only CLI commands
. admin-openrc

#Download the source image
wget http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img

#upload image to the glance
openstack image create "cirros5" \
  --file cirros-0.4.0-x86_64-disk.img \
  --disk-format qcow2 --container-format bare \
  --public

#Confirm upload of the image and validate attributes
openstack image list
}

function placement()
{
#copy preconfig file
cp ./conf_files/placement.conf /etc/placement/placement.conf

#Create a Placement service user
openstack user create --domain default --password PLACEMENT_PASS placement

#Add the Placement user to the service project with the admin role
openstack role add --project service --user placement admin

#Create the Placement API entry in the service catalog
openstack service create --name placement \
  --description "Placement API" placement

#Create the Placement API service endpoints
openstack endpoint create --region RegionOne placement public http://controller:8778
openstack endpoint create --region RegionOne placement internal http://controller:8778
openstack endpoint create --region RegionOne placement admin http://controller:8778

#Populate the placement database
su -s /bin/sh -c "placement-manage db sync" placement

#Reload the web server to adjust to get new configuration settings for placement
service apache2 restart

#Source the admin credentials to gain access to admin-only CLI commands
. admin-openrc

#Perform status checks to make sure everything is in order
placement-status upgrade check
}

function nova()
{
#copy preconfig file
cp ./conf_files/nova.conf /etc/nova/nova.conf
sed -i -e  "s/^\(my_ip\s*=\).*/\1 $ip/" /etc/nova/nova.conf
sed -i -e  "s/^\(novncproxy_base_url\s*=\).*/\1 http:\/\/$ip:6080\/vnc_auto.html/" /etc/nova/nova.conf


#Source the admin credentials to gain access to admin-only CLI commands
. admin-openrc

#Create the nova user
openstack user create --domain default --password NOVA_PASS nova

#Add the admin role to the nova user
openstack role add --project service --user nova admin

#Create the nova service entity
openstack service create --name nova --description "OpenStack Compute" compute

#Create the Compute API service endpoints
openstack endpoint create --region RegionOne compute public http://controller:8774/v2.1
openstack endpoint create --region RegionOne compute internal http://controller:8774/v2.1
openstack endpoint create --region RegionOne compute admin http://controller:8774/v2.1

#Populate the nova-api database
su -s /bin/sh -c "nova-manage api_db sync" nova

#Register the cell0 database
su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova

#Create the cell1 cell
su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova

#Populate the nova database
su -s /bin/sh -c "nova-manage db sync" nova

#Verify nova cell0 and cell1 are registered correctly
su -s /bin/sh -c "nova-manage cell_v2 list_cells" nova

#Restart the Compute services
service nova-api restart
service nova-consoleauth restart
service nova-scheduler restart
service nova-conductor restart
service nova-novncproxy restart

#Determine whether your compute node supports hardware acceleration for virtual machines
egrep -c '(vmx|svm)' /proc/cpuinfo

#Restart the Compute service
service nova-compute restart

#Source the admin credentials to enable admin-only CLI commands
. admin-openrc

sleep 10s

#Discover compute hosts
su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova


#Source the admin credentials to enable admin-only CLI commands
. admin-openrc
openstack compute service list

#List API endpoints in the Identity service to verify connectivity with the Identity service
openstack catalog list

#List images in the Image service to verify connectivity with the Image service
openstack image list

#Check the cells and placement API are working successfully and that other necessary prerequisites are in place
nova-status upgrade check
}

function neutron()
{
#copy preconfig file
cp ./conf_files/neutron.conf /etc/neutron/neutron.conf
cp ./conf_files/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini
cp ./conf_files/linuxbridge_agent.ini /etc/neutron/plugins/ml2/linuxbridge_agent.ini
sed -i -e  "s/^\(physical_interface_mappings\s*=\).*/\1 provider:$network_interface/" /etc/neutron/plugins/ml2/linuxbridge_agent.ini 
sed -i -e  "s/^\(local_ip\s*=\).*/\1 $ip/" /etc/neutron/plugins/ml2/linuxbridge_agent.ini
cp ./conf_files/l3_agent.ini /etc/neutron/l3_agent.ini
cp ./conf_files/dhcp_agent.ini /etc/neutron/dhcp_agent.ini
cp ./conf_files/metadata_agent.ini /etc/neutron/metadata_agent.ini
sed -i -e  "s/^\(nova_metadata_host\s*=\).*/\1 $ip/" /etc/neutron/metadata_agent.ini

#Source the admin credentials to enable admin-only CLI commands
. admin-openrc

#Create the neutron user
openstack user create --domain default --password NEUTRON_PASS neutron

#Add the admin role to the neutron user
openstack role add --project service --user neutron admin

#Create the neutron service entity
openstack service create --name neutron --description "OpenStack Networking" network

#Create the Networking service API endpoints
openstack endpoint create --region RegionOne network public http://controller:9696
openstack endpoint create --region RegionOne network internal http://controller:9696
openstack endpoint create --region RegionOne network admin http://controller:9696

#Populate the database
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

#Restart the Compute API service
service nova-api restart

#Restart the Networking services
service neutron-server restart
service neutron-linuxbridge-agent restart
service neutron-dhcp-agent restart
service neutron-metadata-agent restart
service neutron-l3-agent restart

#Restart the Compute service
service nova-compute restart

#Restart the Linux bridge agent
service neutron-linuxbridge-agent restart

sleep 10s
#List agents to verify successful launch of the neutron agents
openstack network agent list
}

function horizon()
{
#copy preconfig file
cp ./conf_files/local_settings.py /etc/openstack-dashboard/local_settings.py
cp ./conf_files/openstack-dashboard.conf /etc/apache2/conf-available/openstack-dashboard.conf
sed -i -e  "s/^\(OPENSTACK_HOST\s*=\).*/\1 '$ip'/" /etc/openstack-dashboard/local_settings.py
sed -i -e  "s/^\(\s*'LOCATION'\s*:\).*/\1 '$ip:11211', /" /etc/openstack-dashboard/local_settings.py

#Reload the web server configuration
service apache2 reload
}

######MariaDB Credentials Starts ######
maria_db_user="root"

#selecting new passsword for maria db root user
maria_db_root_password="pyronoidninja"

maria_db_port="3306"
maria_db_connect="mysql -h localhost -u$maria_db_user -p$maria_db_root_password --port=$maria_db_port"

######MariaDB Credentials ends ######

####### Application databases with name and password Starts ########

# Keystone:
keystone_db_name="keystone"
keystone_db_user="keystone"
keystone_db_password="KEYSTONE_DBPASS"

# Glance
glance_db_name="glance"
glance_db_user="glance"
glance_db_password="GLANCE_DBPASS"

# Placement
placement_db_name="placement"
placement_db_user="placement"
placement_db_password="PLACEMENT_DBPASS"

# Nova_api
nova_api_db_name="nova_api"

# Nova
nova_db_name="nova"
nova_db_user="nova"
nova_db_password="NOVA_DBPASS"

# Nova_cell0
nova_cell0_db_name="nova_cell0"

# Neutron
neutron_db_name="neutron"
neutron_db_user="neutron"
neutron_db_password="NEUTRON_DBPASS"

####### Application databases with name and password ends ########

####Getting Provider NIC name and IP Address starts #####

ip=$(ip route get 8.8.8.8 | awk 'NR == 1 {print $7; exit }')
network_interface=$(ip route get 8.8.8.8 | awk 'NR == 1 {print $5 ; exit }')

####Getting Provider NIC name and IP Address ends #####

#######OpenStack Stein Installation Starts  ##############

host_config
install_stein_packages
configuring_db
chrony
rabbitmq
memcached
keystone
glance
placement
nova
neutron
horizon

#######OpenStack Stein Installation ends  ##############
