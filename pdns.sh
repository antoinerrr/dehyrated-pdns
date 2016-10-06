#!/usr/bin/env bash

# Author: @antoifon 
#
# Example how to deploy a DNS challange using powerdns
#

set -e
set -u
set -o pipefail
umask 077

mysql_base="pdns"
mysql_host="localhost"
mysql_user="root"
mysql_pass="password"

export            pw_file="$HOME/.letsencrypt_pdns_my.cnf"
export mysql_default_opts="--defaults-extra-file=$pw_file --host=$mysql_host --user=$mysql_user --silent"

# write the mysql password to file, do not specify it the command line(insecure)
touch $pw_file
chmod 600 $pw_file
cat >$pw_file <<EOF
[mysql]
password=$mysql_pass
EOF

   domain="${2}"
    token="${4}"
timestamp=$(date +%s)

IFS='.' read -a myarray_domain <<< "$domain"
root_domain="${myarray_domain[*]: -2:1}.${myarray_domain[*]: -1:1}"

done="no"

function mysql_exec { mysql $mysql_default_opts "${@}"; }

if [[ "$1" = "deploy_challenge" ]]; then
       id="$(mysql_exec -N -e "SELECT id      FROM $mysql_base.domains WHERE name='$root_domain';")"
      soa="$(mysql_exec -N -e "SELECT content FROM $mysql_base.records WHERE domain_id='$id' AND type='SOA'")"
    idSoa="$(mysql_exec -N -e "SELECT id      FROM $mysql_base.records WHERE domain_id='$id' AND type='SOA'")"
   IFS=' ' read -r -a soArray <<< "$soa"
   soArray[2]=$((soArray[2]+1))
   soaNew="$( IFS=$' '; echo "${soArray[*]}" )"
   mysql_exec -e "UPDATE $mysql_base.records SET content='$soaNew' WHERE id='$idSoa'"
   mysql_exec -e "INSERT INTO $mysql_base.records (id,domain_id,name,type,content,ttl,prio,change_date) VALUES ('', '$id', '_acme-challenge.$domain','TXT','$token','5','0','$timestamp')"

  # get nameservers for domain
  nameservers="$(dig -t ns +short ${domain#*.})"
  while :
    do
        failed_servers=0
        for nameserver in $nameservers;do
                if ! dig @$nameserver +short -t TXT _acme-challenge.$domain | grep -- "$token" > /dev/null
                then
                        failed_servers=1
                fi
        done
        # return only if every server has the challenge
        [ "$failed_servers" == 0 ] && break
        sleep 1
       printf "."
    done
   done="yes"
fi

if [[ "$1" = "clean_challenge" ]]; then
    mysql_exec -e "DELETE FROM $mysql_base.records WHERE content = '$token' AND type = 'TXT'"
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

