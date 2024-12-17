#!/bin/bash -e

echo "$COS_ACCESS_SERVICE_ID_API_KEY_Z_TEAM" | docker login -u iamapikey --password-stdin icr.io
if [ $? -ne 0 ]; then
    echo "Docker login failed. Exiting script."
    exit 1
fi
package_name=$(echo $PACKAGE_NAME | tr '[:upper:]' '[:lower:]')
docker tag $IMAGE_NAME icr.io/currency-images/$package_name-s390x:$VERSION
docker push icr.io/currency-images/$package_name-s390x:$VERSION
if [ $? -ne 0 ]; then
    echo "Docker push failed. Exiting script."
    exit 1
fi
