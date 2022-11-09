#!/bin/sh

##############################################################################
# Copyright contributors to the IBM Security Verify Directory project.
##############################################################################

#
# This script will list the users found within our managed suffix on all
# replicas.
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

if [ $# -eq 1 ] ; then
    if [ $1 = "-?" ] ; then
        echo "usage: $0 {proxy|<replica-num>}"
        exit 1
    fi
fi

#
# This script will check to see which users have been replicated.
#

check_pod()
{
    total=$(kubectl exec -it -c isvd-replica $1 -- ldapsearch -h 127.0.0.1 \
        -p $port $extra_args -D $admin_dn -w $admin_pwd \
        -b "o=sample" "(objectclass=inetOrgPerson)" cn | \
        grep "," | wc -l)

    echo "$1:\t$total"

    set +e
    kubectl exec -it -c isvd-replica $1 -- ldapsearch -h 127.0.0.1 \
        -p $port $extra_args -D $admin_dn -w $admin_pwd -S "+cn" \
        -b "o=sample" "(objectclass=inetOrgPerson)" cn  | grep ","
    set -e
}

if [ $# -eq 1 ] ; then


    if [ $1 = "proxy" ] ; then
        if [ -z "$PROXY_ADDR" ] ; then
            echo "Error> the PROXY_ADDR environment variable must be set to"
            echo "       the IP address of the proxy.  In an IBM cloud "
            echo "       environment the address can be obtained by calling: "
            echo "         ibmcloud cs workers -c <cluster-name> \ "
            echo "               --json | jq -r .[0].publicIP"

            exit 1
        fi

        if [ -z "$SECURE" ] ; then
            ldap_uri="ldap://$PROXY_ADDR:$node_port"
        else
            ldap_uri="ldaps://$PROXY_ADDR:$node_port"
            export LDAPTLS_REQCERT=never
        fi

        total=$(ldapsearch -H $ldap_uri -D $admin_dn -w $admin_pwd \
        -b "o=sample" "(objectclass=inetOrgPerson)" cn | \
        grep "," | grep -v '#' | wc -l)

        echo "$1:\t$total"

        set +e
        ldapsearch -H $ldap_uri -D $admin_dn -w $admin_pwd -S "+cn" \
            -b "o=sample" "(objectclass=inetOrgPerson)" cn  | \
            grep "," | grep -v '#'
        set -e
        
    else
        id=`kubectl get pods --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | grep replica-$1-`

        kubectl get pod $id >/dev/null 2>&1

        if [ $? -ne 0 ] ; then
            break
        fi

        check_pod $id
    fi
else
    num=1

    while [ 1 ] ; do
        id=`kubectl get pods --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | grep replica-$num-`

        kubectl get pod $id >/dev/null 2>&1

        if [ $? -ne 0 ] ; then
            break
        fi

        check_pod $id

        num=`expr $num + 1`
    done
fi

