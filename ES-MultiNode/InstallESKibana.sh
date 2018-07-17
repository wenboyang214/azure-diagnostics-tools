#!/bin/bash
# Copyright (c) Microsoft.  All rights reserved.
# Licensed under ELASTIC LICENSE
##
# Author : Wenbo Yang  July/16/2018
##
# Reference: https://github.com/Azure/azure-diagnostics-tools/blob/master/ELK-Semantic-Logging/ELK/AzureRM/logstash-on-ubuntu/logstash-install-ubuntu.sh
# Reference: https://github.com/Azure/azure-quickstart-templates/blob/master/elasticsearch/scripts/elasticsearch-ubuntu-install.sh
# Reference: https://github.com/Azure/azure-quickstart-templates/blob/master/elasticsearch-vmss/install-elasticsearch.sh
# Reference: https://github.com/Azure/azure-diagnostics-tools/blob/master/ES-MultiNode/es-ubuntu-install.sh
##


# Log method to control/redirect log output
log()
{
    echo "$1"
    logger "$1"
}

if [ "${UID}" -ne 0 ];
then
    log "Script executed without root permissions"
    echo "You must be root to run this program." >&2
    exit 3
fi

# TEMP FIX - Re-evaluate and remove when possible
# This is an interim fix for hostname resolution in current VM
grep -q "${HOSTNAME}" /etc/hosts
if [ $? == 0 ]
then
  echo "${HOSTNAME} found in /etc/hosts"
else
  echo "${HOSTNAME} not found in /etc/hosts"
  # Append it to the hosts file if not there
  echo "127.0.0.1 ${HOSTNAME}" >> /etc/hosts
  log "hostname ${HOSTNAME} added to /etc/hosts"
fi


#Loop through options passed
while getopts :p:c:m:e:k:h optname; do
  log "Option $optname set with value ${OPTARG}"
  case $optname in
    p) #set cluster name
      FIRSTPRIVATEIP=${OPTARG}
      ;;
    c) #set cluster name
      NODECOUNT=${OPTARG}
      ;;
    e) #set master mode
      ES_DOWNLOAD_URL=${OPTARG}
      ;;
    k) #set master mode
      KIBANA_DOWNLOAD_URL=${OPTARG}
      ;;
    h) #show help
      help
      exit 2
      ;;
    \?) #unrecognized option - show help
      echo -e \\n"Option -${BOLD}$OPTARG${NORM} not allowed."
      help
      exit 2
      ;;
  esac
done

# Usage: get_discovery_endpoints start_address node_count
# Example: get_discovery_endpoints 10.0.1.4 3
# (returns ["10.0.1.4", "10.0.1.5", "10.0.1.6"]
get_discovery_endpoints()
{
    declare start_address=$1
    declare address_prefix=${start_address%.*}     # Everything up to last dot (not including)
    declare -i address_suffix_start=${start_address##*.}  # Last part of the address, interpreted as a number
    declare retval='['
    declare -i i
    declare -i suffix
    
    for (( i=0; i<$2; ++i )); do
        suffix=$(( address_suffix_start + i ))
        retval+="\"${address_prefix}.${suffix}\", "
    done
    
    retval=${retval:0:-2}               # Remove last comma and space
    retval+=']'
    
    echo $retval
}

# Install Oracle Java
install_java()
{
    log "Installing Java"
    add-apt-repository -y ppa:webupd8team/java
    apt-get -y update  > /dev/null
    echo debconf shared/accepted-oracle-license-v1-1 select true | sudo debconf-set-selections
    echo debconf shared/accepted-oracle-license-v1-1 seen true | sudo debconf-set-selections
    apt-get -y install oracle-java8-installer  > /dev/null
    java -version
    if [ $? -ne 0 ]; then
        log "Java installation failed"
        exit 1
    fi
}

# Install ES with Debian Package manually
install_es()
{
    log "Installing Elaticsearch"
    sudo wget -q "$ES_DOWNLOAD_URL" -O elasticsearch.deb
    sudo dpkg -i elasticsearch.deb
}

# Install Kibana with Debina Package manually
install_kibana()
{
    log "Installing Kibana"
    sudo wget -q "$KIBANA_DOWNLOAD_URL" -O kibana.deb
    sudo dpkg -i kibana.deb
}


# Configure elasticsearch
configure_es()
{
    log "Update configuration"
    mv /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.bak
    echo "cluster.name: elasticsearch" >> /etc/elasticsearch/elasticsearch.yml
    echo "node.name: ${HOSTNAME}" >> /etc/elasticsearch/elasticsearch.yml
    declare -i minimum_master_nodes=$((($NODECOUNT / 2) + 1))
    echo "discovery.zen.minimum_master_nodes: 2" >> /etc/elasticsearch/elasticsearch.yml
    discovery_endpoints=$(get_discovery_endpoints $FIRSTPRIVATEIP $NODECOUNT)
    echo $discovery_endpoints
    echo "discovery.zen.ping.unicast.hosts: $discovery_endpoints" >> /etc/elasticsearch/elasticsearch.yml
    echo "network.host: ${HOSTNAME}" >> /etc/elasticsearch/elasticsearch.yml
    echo "http.port: 9200" >> /etc/elasticsearch/elasticsearch.yml
    echo "bootstrap.memory_lock: true" >> /etc/elasticsearch/elasticsearch.yml

    echo "node.master: true" >> /etc/elasticsearch/elasticsearch.yml
    echo "node.data: true" >> /etc/elasticsearch/elasticsearch.yml

    sudo /bin/systemctl daemon-reload
    sudo /bin/systemctl enable elasticsearch.service
    sudo systemctl start elasticsearch.service
    #sudo systemctl stop elasticsearch.service
    sleep 30

    if [ `systemctl is-failed elasticsearch.service` == 'failed' ];
    then
        log "Elasticsearch unit failed to start"
        exit 1
    fi
}

# Configure kibana
configure_kibana()
{
    echo "server.host: \"${HOSTNAME}\"" >> /etc/kibana/kibana.yml
    echo "elasticsearch.url: \"http://${HOSTNAME}:9200\"" >> /etc/kibana/kibana.yml
    sudo /bin/systemctl enable kibana.service
    sudo systemctl start kibana.service
    #sudo systemctl stop kibana.service
    sleep 10
    
    if [ `systemctl is-failed kibana.service` == 'failed' ];
    then
        log "Kibana unit failed to start"
        exit 1
    fi    
}

configure_system()
{
    echo "options timeout:1 attempts:5" >> /etc/resolvconf/resolv.conf.d/head
    resolvconf -u
    ES_HEAP=`free -m |grep Mem | awk '{if ($2/2 >31744)  print 31744;else printf "%.0f", $2/2;}'`
    echo "ES_JAVA_OPTS=\"-Xms${ES_HEAP}m -Xmx${ES_HEAP}m\"" >> /etc/default/elasticsearch
    echo "JAVA_HOME=$JAVA_HOME" >> /etc/default/elasticsearch
    echo 'MAX_OPEN_FILES=65536' >> /etc/default/elasticsearch
    echo 'MAX_LOCKED_MEMORY=unlimited' >> /etc/default/elasticsearch
   
    #https://www.elastic.co/guide/en/elasticsearch/reference/current/setting-system-settings.html#systemd
    mkdir -p /etc/systemd/system/elasticsearch.service.d
    touch /etc/systemd/system/elasticsearch.service.d/override.conf
    echo '[Service]' >> /etc/systemd/system/elasticsearch.service.d/override.conf
    echo 'LimitMEMLOCK=infinity' >> /etc/systemd/system/elasticsearch.service.d/override.conf
    sudo systemctl daemon-reload
}

log " ---------------begin------------------- "
install_java
log "Master Node install elasticsearch and kibana"
log "Install configure and start elasticsearch"
install_es
configure_system
configure_es
log "Install configure and start kibana"
install_kibana
configure_kibana
