#!/bin/bash -e

# This script will deploy the Refinebio system using a dedicated AWS instance.
#   First it will use that instance to build up to date Docker images
#     and push them to Dockerhub.
#   Next it will use terraform to update our infrastructure and restart our services.
#   Finally it cleans up after itself.

# It has been written with the intention of being run from CircleCI as
#   part of our CI/CD process. It therefore assumes that the following
#   environment variables will be set:
#     - DEPLOY_IP_ADDRESS --  The IP address of the instance to run the deploy on.
#     - CIRCLE_TAG -- The tag that was pushed to CircleCI to trigger the deploy.
#         Will be used as the version for the system and the tag for Docker images.
#     - DOCKER_ID -- The username that will be used to log into Dockerhub.
#     - DOCKER_PASSWD -- The password that will be used to log into Dockerhub.
#     - KEY_FILENNAME -- The name to use for the decrypted SSH key file.
#     - OPENSSL_KEY -- The OpenSSl key which will be used to decrypt the SSH key.
#     - AWS_ACCESS_KEY_ID -- The AWS key id to use when interacting with AWS.
#     - AWS_SECRET_ACCESS_KEY -- The AWS secret key to use when interacting with AWS.


cd ~/refinebio

chmod 600 infrastructure/data-refinery-key.pem

run_on_deploy_box () {
    ssh -o StrictHostKeyChecking=no \
        -i infrastructure/data-refinery-key.pem \
        ubuntu@${DEPLOY_IP_ADDRESS} "cd refinebio && $1"
}

# Create file containing local env vars that are needed for deploy.
rm -f env_vars
echo "export CIRCLE_TAG=$CIRCLE_TAG" >> env_vars
echo "export DOCKER_ID=$DOCKER_ID" >> env_vars
echo "export DOCKER_PASSWD=$DOCKER_PASSWD" >> env_vars
echo "export KEY_FILENAME=$KEY_FILENAME" >> env_vars
echo "export OPENSSL_KEY=$OPENSSL_KEY" >> env_vars
echo "export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" >> env_vars
echo "export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" >> env_vars

# And checkout the correct tag.
run_on_deploy_box "git fetch"
run_on_deploy_box "git checkout $CIRCLE_TAG"

# Verify that the tag has been signed by a trusted team member.
run_on_deploy_box "bash .circleci/verify_tag.sh"

# Copy the necessary environment variables over.
scp -o StrictHostKeyChecking=no \
    -i infrastructure/data-refinery-key.pem \
    -r env_vars ubuntu@$DEPLOY_IP_ADDRESS:refinebio/env_vars

# Decrypt the secrets in our repo.
run_on_deploy_box "source env_vars && bash .circleci/git_decrypt.sh"

# Output to CircleCI
echo "Building new images"
# Output to the docker update log.
run_on_deploy_box "source env_vars && echo -e '######\nBuilding new images for $CIRCLE_TAG\n######'  &>> /var/log/docker_update.log 2>&1"
run_on_deploy_box "source env_vars && bash .circleci/update_docker_img.sh >> /var/log/docker_update.log 2>&1"
run_on_deploy_box "source env_vars && echo -e '######\nFinished building new images for $CIRCLE_TAG\n######'  &>> /var/log/docker_update.log 2>&1"

# Notify CircleCI that the images have been built.
echo "Finished building new images, running run_terraform.sh."

run_on_deploy_box "source env_vars && echo -e '######\nStarting new deploy for $CIRCLE_TAG\n######' >> /var/log/deploy.log 2>&1"
run_on_deploy_box "source env_vars && bash .circleci/run_terraform.sh >> /var/log/deploy.log 2>&1"
run_on_deploy_box "source env_vars && echo -e '######\nDeploying $CIRCLE_TAG finished!\n######' >> /var/log/deploy.log 2>&1"

# Don't leave secrets lying around.
## Clean out any files we've created or moved so git-crypt will relock the repo.
run_on_deploy_box "git clean -f"
run_on_deploy_box "git-crypt lock"
