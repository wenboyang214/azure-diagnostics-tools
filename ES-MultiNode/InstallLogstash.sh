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
    logger "$1
}

if [ "${UID}" -ne 0 ];
then
    log "Script executed without root permissions"
    echo "You must be root to run this program." >&2
    exit 3
fi

#Loop through options passed
while getopts :n:g:h optname; do
  log "Option $optname set with value ${OPTARG}"
  case $optname in
    l) #set logstash downloading URI
      LOGSTASH_DOWNLOAD_URL=${OPTARG}
      ;;
    g) #set logstash configuration string
      CONF_FILE_ENCODED_STRING=${OPTARG}
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

# Install Logstash with Debian Package manually
install_logstash_with_plugin()
{
    log "Installing Logstash"
    sudo wget -q "$LOGSTASH_DOWNLOAD_URL" -O logstash.deb
    sudo dpkg -i logstash.deb
    log "Installing logstash-input-azureblob"
    cd /usr/share/logstash
    ./bin/logstash-plugin install logstash-input-azureblob
    log "Installing logstash-output-azure_loganalytics"
    ./bin/logstash-plugin install logstash-output-azure_loganalytics
}

# Configure logstash
configure_logstash()
{
    #configure
    log "Decoding configuration string"
    echo ${CONF_FILE_ENCODED_STRING} > logstash.conf.encoded
    DECODED_STRING=$(base64 -d logstash.conf.encoded)
    echo $DECODED_STRING > ~/logstash.conf
    log "Installing user configuration named logstash.conf"
    sudo \cp -f ~/logstash.conf /etc/logstash/conf.d/
    log "Configure start up service"
    sudo update-rc.d logstash defaults 95 10
    sudo service logstash start
}

log " --------------begin------------------- "
install_java
install_logstash_with_plugin
configure_logstash
