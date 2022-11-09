#!/bin/sh

##############################################################################
# Copyright contributors to the IBM Security Verify Directory project.
##############################################################################

#
# This script is used to create the admin user on the specified replica.
#

set -e

admin_dn=`grep "^        dn:" deploy.yaml | awk ' { print $2 } '`
admin_pwd=`grep "^        pwd:" deploy.yaml | awk ' { print $2 } '`

if [ -z "$SECURE" ] ; then
    node_port=30389
    port=9389
    extra_args=
else
    node_port=30636
    port=9636
    extra_args="-Z -K /home/idsldap/idsslapd-idsldap/etc/server.kdb"
fi

#
# This script will create the admin user on the specified replica.
#

if [ $# -ne 1 ] ; then
    echo "usage: $0 [replica]"
    exit 1
fi

add_ldif=/tmp/add.ldif

cat <<EOF > $add_ldif
dn: cn=manager,cn=ibmpolicies
changetype: add
objectClass: inetOrgPerson
cn: manager
sn: manager
userpassword: secret
EOF

mod_ldif=/tmp/mod.ldif

cat <<EOF > $mod_ldif
dn: globalGroupName=GlobalAdminGroup,cn=ibmpolicies
changetype: modify
add: member
member: cn=manager,cn=ibmpolicies
EOF

pod=`kubectl get pods --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | grep replica-$1-`

kubectl cp -c isvd-replica $add_ldif $pod:$add_ldif
kubectl cp -c isvd-replica $mod_ldif $pod:$mod_ldif

kubectl exec -it -c isvd-replica $pod -- ldapadd -h 127.0.0.1 \
        -p $port $extra_args -D $admin_dn -w $admin_pwd -f $add_ldif

kubectl exec -it -c isvd-replica $pod -- ldapmodify -h 127.0.0.1 \
        -p $port $extra_args -D $admin_dn -w $admin_pwd -f $mod_ldif

rm -f $add_ldif
rm -f $mod_ldif

