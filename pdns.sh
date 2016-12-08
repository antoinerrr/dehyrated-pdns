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
table_domains="domains"
table_records="records"

# Wait this value in seconds at max for all nameservers to be ready 
# with the deployed challange or fail if they are not
dns_sync_timeout_secs=90

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
# Extract TLD from domain
lastcmp=$(echo $domain | rev | cut -d "." -f2);
if [ ${#lastcmp} == 2 ]; then
    root_domain=$(echo $domain | rev | cut -d "." -f1-3 | rev) # ccTLDs
    root_length=2
else
    root_domain=$(echo $domain | rev | cut -d "." -f1-2 | rev) # TLD
    root_length=1
fi
done="no"

function mysql_exec { mysql $mysql_default_opts "${@}"; }

if [[ "$1" = "deploy_challenge" ]]; then
       id="$(mysql_exec -N -e "SELECT id      FROM $mysql_base.$table_domains WHERE name='$root_domain';")"
      soa="$(mysql_exec -N -e "SELECT content FROM $mysql_base.$table_records WHERE domain_id='$id' AND type='SOA'")"
    idSoa="$(mysql_exec -N -e "SELECT id      FROM $mysql_base.$table_records WHERE domain_id='$id' AND type='SOA'")"
   IFS=' ' read -r -a soArray <<< "$soa"
   soArray[2]=$((soArray[2]+1))
   soaNew="$( IFS=$' '; echo "${soArray[*]}" )"
   mysql_exec -e "UPDATE $mysql_base.$table_records SET content='$soaNew' WHERE id='$idSoa'"
   mysql_exec -e "INSERT INTO $mysql_base.$table_records (id,domain_id,name,type,content,ttl,prio,change_date) VALUES ('', '$id', '_acme-challenge.$domain','TXT','$token','5','0','$timestamp')"
 
   domain_without_trailing_dot=${domain%.}
   dots=${domain_without_trailing_dot//[^.]}
   if [ "${#dots}" -gt $root_length ]; then
       # certificate is for subdomain
       nameservers="$(dig -t ns +short ${domain#*.})"
   else
       # certificate is for domain itself, dont strip of a domain part
       nameservers="$(dig -t ns +short ${domain})"
   fi
   challenge_deployed=0
   for((timeout_counter=0,failed_servers=0;$timeout_counter<$dns_sync_timeout_secs;failed_servers=0,timeout_counter++)); do
     for nameserver in $nameservers;do
       if ! dig @$nameserver +short -t TXT _acme-challenge.$domain | grep -- "$token" > /dev/null; then
         failed_servers=1
       fi
     done
     [ "$failed_servers" == 0 ] && { challenge_deployed=1 ; break ; }
     sleep 1
     printf "."
   done
   if [ "$challenge_deployed" == "1" ]; then
     done="yes"
   else
     echo -e "\n\nERROR:"
     echo "Challenge could not be deployed to all nameservers. Timeout of $dns_sync_timeout_secs "
     echo "seconds reached. If your slave servers need more time to synchronize, increase value "
     echo "of variable dns_sync_timeout_secs in file $0."
     exit 1
   fi
fi

if [[ "$1" = "clean_challenge" ]]; then
    mysql_exec -e "DELETE FROM $mysql_base.$table_records WHERE content = '$token' AND type = 'TXT'"
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

