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

docker_network=isvd.replica

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
    replica_id="replica-$next_replica"

    set +e; docker inspect $replica_id > /dev/null 2>&1; rc=$?; set -e

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

replica_id="replica-$replica_num"
replica_volume="isvd_replica_$replica_num"

#
# Now we want to delete the replication agreements between this replica
# and all other replicas.
#

set +e; current=`expr $replica_num - 1`; set -e

while [ $current -gt 0 ] ; do
    id="replica-$current"

    echo "--------------------------"
    echo "Removing replication agreement with $id...."
    wait_to_proceed

    docker exec -it $id isvd_manage_replica \
        -r -i $replica_id 

    set +e; current=`expr $current - 1`; set -e
done

echo "--------------------------"
echo "Cleaning up the container...."
wait_to_proceed

docker stop $replica_id
docker rm $replica_id
docker volume rm -f $replica_volume

if [ $replica_num -eq 1 ] ; then
    docker network rm $docker_network
fi

