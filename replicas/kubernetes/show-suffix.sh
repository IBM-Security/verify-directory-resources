#!/bin/sh

##############################################################################
# Copyright contributors to the IBM Security Verify Directory project.
##############################################################################

#
# This script will show the contents of the replicated suffix.
#

admin_dn=`grep "^        dn:" deploy.yaml | awk ' { print $2 } '`
admin_pwd=`grep "^        pwd:" deploy.yaml | awk ' { print $2 } '`

if [ $# -ne 1 -a $# -ne 2 ] ; then
    echo "usage: $0 [proxy|replica-id] {-repeat}"
    exit 0
fi

if [ -z "$SECURE" ] ; then
    node_port=30389
    port=9389
    extra_args=
else
    node_port=30636
    port=9636
    extra_args="-Z -K /home/idsldap/idsslapd-idsldap/etc/server.kdb"
fi

show_suffix()
{
    if [ $1 != "proxy" ] ; then
        # Work out the port number.
        id=`kubectl get pods --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | grep replica-$1-`


        kubectl exec -it -c isvd-replica $id -- ldapsearch -h 127.0.0.1 \
            -p $port $extra_args -D $admin_dn -w $admin_pwd \
            -b "o=sample" "(objectclass=*)"

        rc=$?
    else
        if [ -z "$PROXY_ADDR" ] ; then
            echo "Error> the PROXY_ADDR environment variable must be set to "
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

        ldapsearch -H $ldap_uri -D $admin_dn -w $admin_pwd \
            -b "o=sample" "(objectclass=*)"

        rc=$?
    fi

    return $rc
}

if [ $# -eq 2 ] ; then
    if [ $2 != "-repeat" ] ; then
        echo "Error> An invalid option was provided."

        exit 1
    fi

    while [ 1 ] ; do
        show_suffix $1

        if [ $? -ne 0 ] ; then
            echo "An intermittent error took place, retrying...."

            show_suffix $1

            if [ $? -ne 0 ] ; then
                echo "The proxy is no longer available!"
                exit 1
            fi
        fi

        sleep 1
    done

else
    show_suffix $1
fi

