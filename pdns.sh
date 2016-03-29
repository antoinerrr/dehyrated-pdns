#!/usr/bin/env bash

# Author: @antoifon 
#
# Example how to deploy a DNS challange using powerdns
#

set -e
set -u
set -o pipefail
umask 077

sql_base="pdns"
sql_host="localhost"
sql_user="root"
sql_pass="password"

domain="${2}"
token="${4}"
timestamp=$(date +%s)

IFS='.' read -a myarray_domain <<< "$domain"
root_domain="${myarray_domain[*]: -2:1}.${myarray_domain[*]: -1:1}"

done="no"

if [[ "$1" = "deploy_challenge" ]]; then
   id=`mysql -h'$mysql_host' -u'$mysql_user' -p'$mysql_pass' -s -N -e "SELECT id FROM '$mysql_base'.domains WHERE name='$root_domain'"`
   soa=`mysql -h'$mysql_host' -u'$mysql_user' -p'$mysql_pass' -s -N -e "SELECT content FROM '$mysql_base'.records WHERE domain_id='$id' AND type='SOA'"`
   idSoa=`mysql -h'$mysql_host' -u'$mysql_user' -p'$mysql_pass' -s -N -e "SELECT id FROM '$mysql_base'.records WHERE domain_id='$id' AND type='SOA'"`
   IFS=' ' read -r -a soArray <<< "$soa"
   soArray[2]=$((soArray[2]+1))
   soaNew=$( IFS=$' '; echo "${soArray[*]}" )
   mysql -h'$mysql_host' -u'$mysql_user' -p'$mysql_pass' -s -e "UPDATE '$mysql_base'.records SET content='$soaNew' WHERE id='$idSoa'"
   mysql -h'$mysql_host' -u'$mysql_user' -p'$mysql_pass' -s -e "INSERT INTO '$mysql_base'.records (id,domain_id,name,type,content,ttl,prio,change_date) VALUES ('', '$id', '_acme-challenge.$domain','TXT','\"$token\"','5','0','$timestamp')"

  while ! dig @8.8.8.8 -t TXT _acme-challenge.$domain | grep "$token" > /dev/null
    do
       printf "."
       sleep 3
    done
   done="yes"
fi

if [[ "$1" = "clean_challenge" ]]; then
    mysql -h'$mysql_host' -u'$mysql_user' -p'$mysql_pass' -s -e "DELETE FROM '$mysql_base'.records WHERE content = '\"$token\"' AND type = 'TXT'"
    done="yes"
fi

if [[ "${1}" = "deploy_cert" ]]; then
    # do nothing for now
    done="yes"
fi

if [[ ! "${done}" = "yes" ]]; then
    echo Unkown hook "${1}"
    exit 1
fi

exit 0
