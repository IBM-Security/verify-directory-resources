#!/bin/sh

##############################################################################
# Copyright contributors to the IBM Security Verify Directory project.
##############################################################################

#
# This script will show the contents of the replicated suffix.
#

admin_dn=`grep "^    dn:" replica-server.yaml | awk ' { print $2 } '`
admin_pwd=`grep "^    pwd:" replica-server.yaml | awk ' { print $2 } '`

if [ $# -ne 1 ] ; then
    echo "usage: $0 [replica-id]"
    exit 0
fi

if [ -z "$SECURE" ] ; then
    port=9389
    extra_args=
else
    port=9636
    extra_args="-Z -K /home/idsldap/idsslapd-idsldap/etc/server.kdb"
fi

# Work out the port number.
id=replica-$1

docker exec -it $id ldapsearch -h 127.0.0.1 -p $port $extra_args -D $admin_dn \
        -w $admin_pwd -b "o=sample" "(objectclass=*)"

