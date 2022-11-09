#!/bin/sh

##############################################################################
# Copyright contributors to the IBM Security Verify Directory project.
##############################################################################

#
# This script is used to create a new user on the specified replica.
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
# This script will create the specified user on the specified replica.
#

if [ $# -ne 2 ] ; then
    echo "usage: $0 [user] [replica-id]"
    exit 1
fi

container=replica-$2

ldif=/tmp/a.ldif

cat <<EOF > $ldif
dn: cn=$1,o=sample
changetype: add
objectClass: inetOrgPerson
cn: $1
sn: $1
EOF

docker cp $ldif $container:$ldif

docker exec -it $container ldapadd -h 127.0.0.1 -p $port $extra_args \
    -D $admin_dn -w $admin_pwd -f $ldif

rm -f $ldif

