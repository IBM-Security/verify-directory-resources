##############################################################################
# Copyright contributors to the IBM Security Verify Directory project.
##############################################################################

#
# This script is used to create the secret which holds the credentials for
# accessing the repository.
#

if [ $# -ne 3 ] ; then
    echo "usage: $0 [repo] [user] [key]"
    exit 1
fi

repo=$1
user=$2
key=$3

kubectl create secret docker-registry repo-creds \
    --docker-server=https://$repo \
    --docker-username=$user \
    --docker-password=$key \
    --docker-email=$user


