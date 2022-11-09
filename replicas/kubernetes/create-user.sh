#!/bin/sh

##############################################################################
# Copyright contributors to the IBM Security Verify Directory project.
##############################################################################

#
# This script is used to create a new user on the specified replica.
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
# This script will create the specified user on the specified replica.
#

if [ $# -ne 2 ] ; then
    echo "usage: $0 [user] [proxy|replica-id]"
    exit 1
fi

ldif=/tmp/a.ldif

cat <<EOF > $ldif
dn: cn=$1,o=sample
changetype: add
objectClass: inetOrgPerson
cn: $1
sn: $1
EOF

if [ $2 != "proxy" ] ; then
    pod=`kubectl get pods --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | grep replica-$2-`

    kubectl cp -c isvd-replica $ldif $pod:$ldif

    kubectl exec -it -c isvd-replica $pod -- ldapadd -h 127.0.0.1 \
        -p $port $extra_args -D $admin_dn -w $admin_pwd -f $ldif
else
    if [ -z "$PROXY_ADDR" ] ; then
        echo "Error> the PROXY_ADDR environment variable must be set to the "
        echo "       IP address of the proxy.  In an IBM cloud environment "
        echo "       the address can be obtained by calling: "
        echo "         ibmcloud cs workers -c <cluster-name> \ "
        echo "               --json | jq -r .[0].publicIP"

        exit 1
    fi

    admin_dn=cn=manager,cn=ibmpolicies
    admin_pwd=secret

    if [ -z "$SECURE" ] ; then
        ldap_uri="ldap://$PROXY_ADDR:$node_port"
    else
        ldap_uri="ldaps://$PROXY_ADDR:$node_port"
        export LDAPTLS_REQCERT=never
    fi

    ldapadd -H $ldap_uri -D $admin_dn -w $admin_pwd -f $ldif
fi

rm -f $ldif

