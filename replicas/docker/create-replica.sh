#!/bin/sh

##############################################################################
# Copyright contributors to the IBM Security Verify Directory project.
##############################################################################

# This script is used to create a new replica.  The replica will be of the
# name replica-<num>, with replica-1 being the principal.
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

if [ -z "$LICENSE_KEY" ] ; then
    echo "Error> the LICENSE_KEY environment variable must be set!"
    exit 1
fi

if [ -z "$IMAGE_REPO" ] ; then
    IMAGE_REPO=icr.io/isvd
fi

if [ -z "$IMAGE_TAG" ] ; then
    IMAGE_TAG=latest
fi

principal_port=$internal_port
principal_id=replica-1
principal_volume="isvd_replica_1"

admin_dn=`grep "^    dn:" replica-server.yaml | awk ' { print $2 } '`
admin_pwd=`grep "^    pwd:" replica-server.yaml | awk ' { print $2 } '`

seed_image=$IMAGE_REPO/verify-directory-seed:${IMAGE_TAG}
server_image=$IMAGE_REPO/verify-directory-server:${IMAGE_TAG}

docker_network=isvd.replica

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
# Create the docker network if it doesn't already exist.
#

set +e; docker network inspect $docker_network >/dev/null 2>&1; rc=$?; set -e

if [ $rc -ne 0 ] ; then
    docker network create $docker_network
fi

#
# Work out the next replica to be used.
#

replica_num=1

while [ 1 ] ; do
    replica_id="replica-$replica_num"

    set +e; docker inspect $replica_id > /dev/null 2>&1; rc=$?; set -e

    if [ $rc -ne 0 ] ; then
        break
    fi

    replica_num=`expr $replica_num + 1`
done

echo "--------------------------"
echo "Creating replica: $replica_id"
wait_to_proceed

replica_port=`expr $principal_port + $replica_num - 1`
replica_id="replica-$replica_num"
replica_volume="isvd_replica_$replica_num"

if [ $replica_id != $principal_id ] ; then
    #
    # Step 1: Creating the replication agreement between the principal and the
    #         new replica.
    #

    echo "--------------------------"
    echo "Setting up the replica agreement...."
    wait_to_proceed

    docker exec -it $principal_id isvd_manage_replica \
            -ap $extra_args \
            -h $replica_id -p $internal_port -i $replica_id \
            -ph $principal_id -pp $internal_port

    #
    # Step 2: Stop the principal.
    #

    echo "--------------------------"
    echo "Stopping the principal...."
    wait_to_proceed

    docker stop $principal_id

    #
    # Step 3: Make a copy of the database from the principal.
    #

    echo "Done."
    echo "--------------------------"
    echo "Cleaning any old replica data...."
    wait_to_proceed

    docker volume rm -f $replica_volume

    echo "Done."
    echo "--------------------------"
    echo "Starting the seed job...."
    wait_to_proceed

    docker run -it --rm \
        --hostname isvd-seed --name isvd-seed \
        -v $PWD:/mnt/data \
        -v $principal_volume:/var/isvd/source \
        -v $replica_volume:/var/isvd/data \
        -e YAML_CONFIG_FILE=/mnt/data/sds-seed.yaml \
        -e LICENSE_KEY=$LICENSE_KEY \
        $seed_image

    #
    # Step 4: For each existing replica we need to create the replication
    #         agreement and copy the replication queue status of the principal 
    #         for the new replica.
    #

    set +e; current=`expr $replica_num - 1`; set -e

    while [ $current -ge 2 ] ; do
        port=`expr $principal_port + $current`
        id="replica-$current"

        echo "--------------------------"
        echo "creating the replication agreement for: $id"
        wait_to_proceed

        # Create the replication agreement and copy the replication queue
        # status.
        docker exec -it $id isvd_manage_replica \
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

    docker start $principal_id
fi

#
# Step 6: Create and start the new replica
#

echo "Done."
echo "--------------------------"
echo "Creating and starting the replica...."
wait_to_proceed

docker run \
    -p $replica_port:$internal_port \
    -d \
    --hostname $replica_id --name $replica_id \
    -v $replica_volume:/var/isvd/data \
    -v $PWD:/mnt/data \
    -e YAML_CONFIG_FILE=/mnt/data/replica-server.yaml \
    -e SERVER_ID=$replica_id \
    -e LDAP_PORT=$ldap_port \
    -e LICENSE_KEY=$LICENSE_KEY \
    --network $docker_network \
    $server_image

