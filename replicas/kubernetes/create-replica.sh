#!/bin/sh

##############################################################################
# Copyright contributors to the IBM Security Verify Directory project.
##############################################################################

# This script is used to create a new replica.  The replica will be of the
# name isvd-replica-<num>, with isvd-replica-1 being the principal.
#
# If you want to pause the script after each step just export the 'wait=1' 
# environment variable prior to running the script.

set -e

##############################################################################
# Static global variables.

if [ -z "$SECURE" ] ; then
    internal_port=9389
    ldap_port=$internal_port
    extra_args=
else
    ldap_port=0
    internal_port=9636
    extra_args="-z"
fi

principal_id=isvd-replica-1

admin_dn=`grep "^        dn:" deploy.yaml | awk ' { print $2 } '`
admin_pwd=`grep "^        pwd:" deploy.yaml | awk ' { print $2 } '`

if [ -z "$PVC" ] ; then
    PVC=pvc.yaml
fi

if [ -z "$IMAGE_REPO" ] ; then
    IMAGE_REPO="icr.io/isvd"
fi

if [ -z "$IMAGE_TAG" ] ; then
    IMAGE_TAG="latest"
fi

if [ -z "$LICENSE_KEY" ] ; then
    echo "Error> The LICENSE_KEY environment variable must be set!"
    exit 1
fi

server_image=$IMAGE_REPO/verify-directory-server:$IMAGE_TAG
seed_image=$IMAGE_REPO/verify-directory-seed:$IMAGE_TAG
proxy_image=$IMAGE_REPO/verify-directory-proxy:$IMAGE_TAG

##############################################################################
# Wait for the user to press enter before proceeding.

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
# Work out the next replica to be used.
#

replica_num=1

while [ 1 ] ; do
    replica_id="isvd-replica-$replica_num"

    set +e; kubectl get deployment $replica_id > /dev/null 2>&1; rc=$?; set -e

    if [ $rc -ne 0 ] ; then
        break
    fi

    replica_num=`expr $replica_num + 1`
done

echo "--------------------------"
echo "Creating replica: $replica_id"
wait_to_proceed

replica_id="isvd-replica-$replica_num"

#
# Create the PVC.
#

sed "s|replica-xxx|replica-$replica_num|g" $PVC | kubectl create -f -

echo "--------------------------"
echo "Waiting for the pvc to become available..."
wait_to_proceed

kubectl wait --for=jsonpath='{.status.phase}'=Bound \
                                --timeout=300s pvc/replica-$replica_num-pvc

#
# Check to see whether we are creating the principal or a replica.  Additional
# steps are required when creating a replica.
#

if [ $replica_id != $principal_id ] ; then
    #
    # Step 1: Create the replication agreement between the principal and the
    #         new replica.
    #

    echo "--------------------------"
    echo "Setting up the replica agreement...."
    wait_to_proceed

    pod=`kubectl get pods --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | grep $principal_id-`

    kubectl exec -it -c isvd-replica $pod -- isvd_manage_replica \
            -ap $extra_args \
            -h $replica_id -p $internal_port -i $replica_id \
            -ph $principal_id -pp $internal_port

    #
    # Step 2: Stop the principal.
    #

    echo "--------------------------"
    echo "Stopping the principal...."
    wait_to_proceed

    kubectl scale --replicas=0 deployment/$principal_id

    #
    # Step 3: Make a copy of the database from the principal.
    #

    echo "--------------------------"
    echo "Starting the seed job...."
    wait_to_proceed

    sed "s|replica-xxx|replica-$replica_num|g" seed.yaml | \
        sed "s|principal-xxx|replica-1|g" | \
        sed "s|--image-repo--|$seed_image|g" | \
        sed "s|--license-key--|$LICENSE_KEY|g" | kubectl create -f -

    #
    # Wait for the job to complete.
    #

    echo "--------------------------"
    echo "Waiting for the seed job to complete...."
    kubectl wait --for=condition=complete --timeout=300s job/isvd-seed

    sed "s|replica-xxx|replica-$replica_num|g" seed.yaml | \
        sed "s|principal-xxx|replica-1|g" | kubectl delete -f -

    #
    # Step 4: For each existing replica we need to create the replication
    #         agreement and copy the replication queue status of the principal 
    #         for the new replica.
    #

    set +e; current=`expr $replica_num - 1`; set -e

    while [ $current -ge 2 ] ; do
        id="isvd-replica-$current"

        echo "--------------------------"
        echo "creating the replication agreement for: $id"
        wait_to_proceed

        # Create the replication agreement and copy the replication queue
        # status.

        pod=`kubectl get pods --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | grep replica-$current-`

        kubectl exec -it -c isvd-replica $pod -- isvd_manage_replica \
            -ar $extra_args \
            -h $replica_id -p $internal_port -i $replica_id \
            -s $principal_id

        # Move to the next replica.
        set +e; current=`expr $current - 1`; set -e
    done

    #
    # Step 5: Restart the principal.
    #

    echo "Done."
    echo "--------------------------"
    echo "Starting the principal...."
    wait_to_proceed

    kubectl scale --replicas=1 deployment/$principal_id
fi

#
# Step 6: Create and start the new replica
#

echo "Done."
echo "--------------------------"
echo "Creating and starting the replica...."
wait_to_proceed

sed "s|replica-xxx|replica-$replica_num|g" deploy.yaml | \
    sed "s|--port--|$ldap_port|g" | \
    sed "s|--image-repo--|$server_image|g" | \
    sed "s|--license-key--|$LICENSE_KEY|g" | kubectl create -f -

echo "Done."
echo "--------------------------"
echo "Waiting for the replica to become ready...."
wait_to_proceed

kubectl wait deployment $replica_id --for condition=Available=True \
                --timeout=300s

#
# Step 7. Update the proxy to point to this new replica.
#

echo "Done."
echo "--------------------------"
echo "Updating the proxy...."
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

current=$replica_num

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

# Finally we need to either start the proxy, or perform a rolling restart
# of the proxies.

if [ $replica_num -eq 1 ] ; then
    sed "s|--port--|$ldap_port|g" proxy.yaml | \
        sed "s|--image-repo--|$proxy_image|g" | kubectl create -f -
else
    kubectl rollout restart deployment isvd-proxy
fi

#
# Finished.
#

exit 0
