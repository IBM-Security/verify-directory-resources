#!/bin/sh

##############################################################################
# Copyright contributors to the IBM Security Verify Directory project.
##############################################################################

#
# This script will list the users found within our managed suffix on all
# replicas.
#

set -e

admin_dn=`grep "^    dn:" replica-server.yaml | awk ' { print $2 } '`
admin_pwd=`grep "^    pwd:" replica-server.yaml | awk ' { print $2 } '`

if [ -z "$SECURE" ] ; then
    port=9389
    extra_args=
else
    port=9636
    extra_args="-Z -K /home/idsldap/idsslapd-idsldap/etc/server.kdb"
fi

#
# This script will check to see which users have been replicated.
#

check_container()
{
    total=$(docker exec -it $1 ldapsearch -h 127.0.0.1 -p $port $extra_args \
        -D $admin_dn -w $admin_pwd \
        -b "o=sample" "(objectclass=inetOrgPerson)" cn | \
        grep "," | wc -l)

    echo "$1:\t$total"

    set +e
    docker exec -it $1 ldapsearch -h 127.0.0.1 -p $port $extra_args \
        -D $admin_dn -w $admin_pwd -S "+cn" \
        -b "o=sample" "(objectclass=inetOrgPerson)" cn  | grep ","
    set -e
}

num=1

while [ 1 ] ; do
    id=replica-$num

    docker inspect $id >/dev/null 2>&1

    if [ $? -ne 0 ] ; then
        break
    fi

    check_container $id

    num=`expr $num + 1`
done

