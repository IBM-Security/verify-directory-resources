#!/bin/sh

##############################################################################
# Copyright contributors to the IBM Security Verify Directory project.
##############################################################################

set -e

#
# This script will remove the last replica from the environment.
#

##############################################################################
# Global variables.

suffix="o=sample"
principal_id=isvd-replica-1

if [ -z "$SECURE" ] ; then
    internal_port=9389
    ldap_port=$internal_port
else
    internal_port=9636
    ldap_port=0
fi

if [ -z "$PVC" ] ; then
    PVC=pvc.yaml
fi

if [ -z "$LICENSE_KEY" ] ; then
    echo "Error> The LICENSE_KEY environment variable must be set!"
    exit 1
fi

admin_dn=`grep "^        dn:" deploy.yaml | awk ' { print $2 } '`
admin_pwd=`grep "^        pwd:" deploy.yaml | awk ' { print $2 } '`

##############################################################################
# Wait for the user to hit enter before proceeding.

wait_to_proceed()
{
    if [ ! -z "$wait" ] ; then
        echo "Press enter to continue..." 
        read ans
    fi
}

##############################################################################
# Main line.

#
# Work out the last replica.
#

replica_num=0

while [ 1 ] ; do
    next_replica=`expr $replica_num + 1`
    replica_id="isvd-replica-$next_replica"

    set +e; kubectl get deployment $replica_id > /dev/null 2>&1; rc=$?; set -e

    if [ $rc -ne 0 ] ; then
        break
    fi

    replica_num=$next_replica
done

if [ $replica_num -eq 0 ] ; then
    echo "There are no replicas to be deleted."
    exit 1
fi

echo "replica: $replica_num"

replica_id="isvd-replica-$replica_num"

echo "--------------------------"
echo "Cleaning up the proxy...."
wait_to_proceed

servers=$(cat <<-END
        servers:
END
)

server_groups=$(cat <<-END
      server-groups:
      - name: 'group_a'
        servers:
END
)

PROXY_PREFIX=$(cat <<-END
    proxy:
      suffixes:
      - name: 'split_a'
        num-partitions: 1
        base: 'o=sample'
END
)

SERVER_TEMPLATE=$(cat <<-END
          - name: 'isvd-replica-xxx'
            role: 'primarywrite'
            index: 1
END
)

SERVER_GROUPS_TEMPLATE=$(cat <<-END
          - name: 'isvd-replica-xxx'
            id: 'isvd-replica-xxx'
            target: '--target--'
            bind-method: "Simple"
            user:
              dn: '$admin_dn'
              password: '$admin_pwd'
END
)

if [ $replica_num -eq 1 ] ; then
    kubectl delete -f proxy.yaml
    kubectl delete -f proxy-config.yaml
else
    set +e; current=`expr $replica_num - 1`; set -e

    while [ $current -gt 0 ] ; do
        if [ -z "$SECURE" ] ; then
            target=ldap://isvd-replica-$current:$internal_port
        else
            target=ldaps://isvd-replica-$current:$internal_port
        fi

        servers="$servers\n`echo "$SERVER_TEMPLATE" | sed "s|xxx|$current|g"`"
        server_groups="$server_groups\\n`echo "$SERVER_GROUPS_TEMPLATE" \
                | sed "s|xxx|$current|g" | sed "s|--target--|$target|g"`"
        set +e; current=`expr $current - 1`; set -e
    done

    tmp_file=/tmp/proxy-config.yaml

    sed "s|--license-key--|$LICENSE_KEY|g" proxy-config.yaml > $tmp_file
    echo "$PROXY_PREFIX" >> $tmp_file
    echo "$servers" >> $tmp_file
    echo "$server_groups" >> $tmp_file

    # Now we can update/create the config map.

    kubectl apply -f $tmp_file

    rm -f $tmp_file

    # Finally we need to perform a rolling restart of the proxies.
    kubectl rollout restart deployment isvd-proxy

    kubectl wait deployment isvd-proxy --for condition=Available=True \
                --timeout=300s
fi

#
# Now we want to delete the replication agreements between this replica
# and all other replicas.
#

set +e; current=`expr $replica_num - 1`; set -e

while [ $current -gt 0 ] ; do
    echo "--------------------------"
    echo "Removing replication agreement with replica $current...."
    wait_to_proceed

    pod=`kubectl get pods --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | grep replica-$current-`
    kubectl exec -it -c isvd-replica $pod -- isvd_manage_replica \
        -r -i $replica_id 

    set +e; current=`expr $current - 1`; set -e
done

echo "--------------------------"
echo "Cleaning up the deployment...."
wait_to_proceed

sed "s|replica-xxx|replica-$replica_num|g" deploy.yaml | kubectl delete -f -
sed "s|replica-xxx|replica-$replica_num|g" $PVC | kubectl delete -f -


