#!/bin/bash

# add all utility functions
source ./utils.sh

# Global variables
TOOL_DIR=./Tools
LOGS_DIR=./Logs
CONFIG_DIR=./Config
MAPPING_DIR=./Mapping
TEMP_FILE=$LOGS_DIR/applicationToMigrate.json

####################################################################
# Create the Amplify Agents organization that host the applications
# 
# Output: OrganizationId
####################################################################
function createAmplifyAgentOrganizationIfNotExisting() {

    ORG_NAME="Amplify Agents"
    echo "createAmplifyAgentOrganizationIfNotExisting..." >&2

    getFromApiManager "organizations" "$LOGS_DIR/organizations.json"
    ORG_ID=$(cat "$LOGS_DIR/organizations.json" | jq -r '.[] | select( .name=="'"$ORG_NAME"'")' | jq -rc '.id')

    if [[ $ORG_ID == '' ]]
    then
        echo "$ORG_NAME organization does not exist yet, creating it..." >&2
        jq -n -f ./jq/agent-organization.jq --arg organizationName "$ORG_NAME" > "$LOGS_DIR/agent-organization.json"
        postToApiManagerJson "organizations" "$LOGS_DIR/agent-organization.json" "$LOGS_DIR/agent-organization-created.json"

        # get the ORG_ID
        ORG_ID=$(cat "$LOGS_DIR/agent-organization-created.json" | jq -rc '.id')

        # delete intermediate files
        rm -rf "$LOGS_DIR/agent-organization*.json"
    else
         echo "$ORG_NAME organization does exist." >&2
    fi

    # delete intermediate file
    rm -rf "$LOGS_DIR/organizations.json"

    # return the ORG_ID
    echo $ORG_ID
}

####################################################################
# Create or find a platform team based on the v7 Organization name
#
# Input:
# - $1: platfornOrgId
# - $2: v7OrganizationName
# Output: TEAM_GUID in platform
####################################################################
function createTeamFromOrganizationNameIfNotExisting() {

    local PLATFORM_ORGID=$1
    local TEAM_NAME=$2

    # do we create the corresponding team in Platform?
    TEAM_GUID=$(isPlatformTeamExisting $PLATFORM_ORGID "$TEAM_NAME")

    if [[ $TEAM_GUID == "" ]]; 
    then
        # create the missing platform team matching V7 organization $TEAM_NAME
        echo "  Create platform team $TEAM_NAME matching v7 organization..." >&2
        echo "  axway team create $PLATFORM_ORGID '$TEAM_NAME' --desc 'Automatically created'" >&2
        axway team create $PLATFORM_ORGID "$TEAM_NAME" --desc "Automatically created"

        # get the team GUID.
        TEAM_GUID=$(isPlatformTeamExisting $PLATFORM_ORGID "$TEAM_NAME")
    else
        echo "  Team $TEAM_NAME already exist in Platform - no need to re-create it" >&2
    fi 

    echo "$TEAM_GUID"
}

######################################################
# Granting Amplify Agents org the access to API
#
# Input:
# - $1: ApiID
# - $2: Anplify Agent orgqnization ID
# Ouptut: None
#######################################################
function grantApiAccessToAmplifyAgentsOrganization () {

    local V7_API_ID=$1
    local AGENT_V7_ORG_ID=$2

    echo "action=orgs&apiId=$V7_API_ID&grantOrgId=$AGENT_V7_ORG_ID" > "$LOGS_DIR/api-$V7_API_ID-grantaccess.txt"
    postToApiManagerUrlEncoded "proxies/grantaccess" "$LOGS_DIR/api-$V7_API_ID-grantaccess.txt" "$LOGS_DIR/api-$V7_API_ID-grantaccess-done.json"

    # cleanup intermediate files
    rm -rf "$LOGS_DIR/api-$V7_API_ID-grantaccess.txt"
    rm -rf "$LOGS_DIR/api-$V7_API_ID-grantaccess-done.json"
}

############################################################
# Creating the Markateplace Application if not existing yet
#
# Input:
# - $1: Application Name
# - $2: Owing team guid
# Ouptut: Marketplace Application ID
############################################################
function createMarketplaceApplicationIfNotExisting() {

    local MKT_APP_NAME="$1"
    local OWNING_TEAM_GUID="$2"

    echo "  is $MKT_APP_NAME exist on the Marketplace?" >&2
    # sanitize name for file name...
    local MKT_APP_NAME_SANITIZED=$(sanitizeName "$MKT_APP_NAME") 
    # sanitize name for query search...
    local MKT_APP_NAME_FOR_SEARCH=$(sanitizeNameForQuery "$MKT_APP_NAME")      

    # TODO check that it is the correct owning team too
    getFromMarketplace "$MARKETPLACE_URL/api/v1/applications?limit=10&offset=0&search=$MKT_APP_NAME_FOR_SEARCH&sort=-metadata.modifiedAt%2C%2Bname" "" "$LOGS_DIR/mkt-application-$MKT_APP_NAME_SANITIZED-search.json"
    MP_APPLICATION_ID=`cat "$LOGS_DIR/mkt-application-$MKT_APP_NAME_SANITIZED-search.json" | jq -r '.items[0].id'`

    if [[ $MP_APPLICATION_ID == null ]]
    then
        # TODO = Application icon
        #https://lbean018.lab.phx.axway.int:8075/api/portal/v1.4/applications/b876ab64-60b7-4393-8cc9-ffa56128d583/image
        #getFromApiManager

        # we can create it
        echo "      No it does not, creating application $MKT_APP_NAME..." >&2
        jq -n -f ./jq/mkt-application.jq --arg applicationTitle "$MKT_APP_NAME" --arg teamId $OWNING_TEAM_GUID > "$LOGS_DIR/mkt-application-$MKT_APP_NAME_SANITIZED.json"
        postToMarketplace "$MARKETPLACE_URL/api/v1/applications" "$LOGS_DIR/mkt-application-$MKT_APP_NAME_SANITIZED.json" "$LOGS_DIR/mkt-application-$MKT_APP_NAME_SANITIZED-created.json"
        echo "      Application $MKT_APP_NAME created on Marketplace" >&2
        MP_APPLICATION_ID=`cat "$LOGS_DIR/mkt-application-$MKT_APP_NAME_SANITIZED-created.json" | jq -r '.id'`
    else
        echo "      Application already exist in Marketplace." >&2
    fi

    # clean up temporary files
    rm -rf "$LOGS_DIR/mkt-application-$MKT_APP_NAME_SANITIZED*.json"

    echo "$MP_APPLICATION_ID"
}

#####################################################################
# approve and provision the managed application on the provider side
# so that the agents knows about it
#
# Input:
# - $1: Marketplace Application ID
# - $2: APIM ApplicationID
# Output:
#####################################################################
function providerProvisionManagedApplication() {

    local MKT_APP_ID=$1
    local V7_APP_ID=$2

    # find the managedApplication corresponding to the Marketplace application
    getFromCentralWithRetry "$CENTRAL_URL/apis/management/v1alpha1/managedapplications?query=metadata.references.id==$MKT_APP_ID" "" "$LOGS_DIR/app-managedapp-$MKT_APP_ID.json"

    # read existing information for the post (AccReq name + environment name)
    MANAGED_APP_NAME=$(cat "$LOGS_DIR/app-managedapp-$MKT_APP_ID.json" | jq -rc '.[].name')
    MANAGED_APP_ENVIRONMENT_NAME=$(cat "$LOGS_DIR/app-managedapp-$MKT_APP_ID.json" | jq -r '.[].metadata.scope.name')

    # mark it as provisioned (add the finalizers)
    jq --slurpfile file2 ./jq/agent-app-finalizer.json '(.[].finalizers += $file2)' "$LOGS_DIR/app-managedapp-$MKT_APP_ID.json" > "$LOGS_DIR/app-managedapp-$MKT_APP_ID-finalizer.json"

    # Remove references and status
    cat "$LOGS_DIR/app-managedapp-$MKT_APP_ID-finalizer.json"  | jq -rc '.[]' | jq 'del(. | .status?, .metadata.references?, .references? )' > "$LOGS_DIR/app-managedapp-$MKT_APP_ID-update.json"
    
    # Post to Central
    putToCentral "$CENTRAL_URL/apis/management/v1alpha1/environments/$MANAGED_APP_ENVIRONMENT_NAME/managedapplications/$MANAGED_APP_NAME" "$LOGS_DIR/app-managedapp-$MKT_APP_ID-update.json" "$LOGS_DIR/app-managedapp-$MKT_APP_ID-updated.json"
    error_exit "Problem while updating the managedApplication agent information..." "$LOGS_DIR/app-managedapp-$MKT_APP_ID-updated.json"

    # adding x-agent-details
    jq -n -f ./jq/agent-app-details.jq --arg applicationID $V7_APP_ID --arg applicationName $MANAGED_APP_NAME > "$LOGS_DIR/agent-access-details-$MKT_APP_ID.json"

    # Post to Central
    putToCentral "$CENTRAL_URL/apis/management/v1alpha1/environments/$MANAGED_APP_ENVIRONMENT_NAME/managedapplications/$MANAGED_APP_NAME/x-agent-details" "$LOGS_DIR/agent-access-details-$MKT_APP_ID.json" "$LOGS_DIR/app-managedapp-$MKT_APP_ID-agent-details.json"
    error_exit "Problem while updating the agent details info..." "$LOGS_DIR/app-managedapp-$MKT_APP_ID-agent-details.json"

    # Update status
    # mark it as done -> level = SUCCESS
    TIMESTAMP=$(date --utc +%FT%T.%3N%z)
    jq -n -f ./jq/agent-status-success.jq --arg timestampUTC "$TIMESTAMP" > "$LOGS_DIR/agent-status-success.json"
    putToCentral "$CENTRAL_URL/apis/management/v1alpha1/environments/$MANAGED_APP_ENVIRONMENT_NAME/managedapplications/$MANAGED_APP_NAME/status" "$LOGS_DIR/agent-status-success.json" "$LOGS_DIR/app-managedapp-$MKT_APP_ID-updated-state.json"
    error_exit "Problem while updating the access request status..." "$LOGS_DIR/app-managedapp-$MKT_APP_ID-updated-state.json"

    #clean up intermediate files
    rm -rf "$LOGS_DIR/app-managedapp-$MKT_APP_ID*.json"
    rm -rf "$LOGS_DIR/agent-access-details-$MKT_APP_ID.json"
    rm -rf "$LOGS_DIR/agent-status-success.json"
}

####################################################################
# Create the Marketplace subscription based on the mapping supplied
#
# Input:
# - $1: Subscription owning team name
# - $2: Subscription owning team guid
# - $3: Product plan name
# - $4: Product plan ID
# - $5: Product name
# - $6: Product ID
# Output: Subscription ID
####################################################################
function createMarketplaceSubscriptionIfNotExisting() {

    local TEAM_NAME=$1
    local TEAM_GUID=$2
    local MP_PRODUCT_PLAN_NAME=$3
    local MP_PRODUCT_PLAN_ID=$4
    local MP_PRODUCT_NAME=$5
    local MP_PRODUCT_ID=$6
    local SUBSCRIPTION_TITLE="$PRODUCT_NAME - $PRODUCT_PLAN_NAME"
    local SANITIZE_PRODUCT_NAME=$(sanitizeName $PRODUCT_NAME)
    # we assume a subscription does not exist
    local CAN_CREATE_SUBSCRIPTION=1

    echo "              Checking if owning team ($TEAM_NAME) already has a subscription for product ($MP_PRODUCT_NAME) using plan ($MP_PRODUCT_PLAN_NAME)" >&2
    getFromMarketplace "$MARKETPLACE_URL/api/v1/subscriptions?product.id=$MP_PRODUCT_ID" "" "$LOGS_DIR/mkt-subscription-product-$SANITIZE_PRODUCT_NAME-search.json"
    NB_SUBSCRIPTION=`cat "$LOGS_DIR/mkt-subscription-product-$SANITIZE_PRODUCT_NAME-search.json" | jq -r '.totalCount'`

    if [[ $NB_SUBSCRIPTION != 0 ]]
    then
        # we can search within the list
        MP_SUBSCRIPTION_ID=`cat "$LOGS_DIR/mkt-subscription-product-$SANITIZE_PRODUCT_NAME-search.json" | jq '[ .items[] | select( .plan.id=="'$MP_PRODUCT_PLAN_ID'" and .owner.id=="'$TEAM_GUID'" ) ]' | jq -r '.[0].id'`

        # subscription not found?
        if [[ $MP_SUBSCRIPTION_ID != null ]]
        then
            # subscription found so no need to create a new one
            echo "              Subscription already exists, no need to create a new one." >&2
            CAN_CREATE_SUBSCRIPTION=0
        fi
    fi

    if [[ $CAN_CREATE_SUBSCRIPTION == 1 ]] 
    then
        echo "              No subscription found, creating the new one..." >&2
        jq -n -f ./jq/mkt-subscription.jq --arg subscriptionTitle "$SUBSCRIPTION_TITLE" --arg teamId $TEAM_GUID --arg planId $MP_PRODUCT_PLAN_ID --arg productId $MP_PRODUCT_ID > "$LOGS_DIR/nkt-subscription-$PRODUCT_NAME_WITHOUT_SPACE.json"
        postToMarketplace "$MARKETPLACE_URL/api/v1/subscriptions" "$LOGS_DIR/nkt-subscription-$PRODUCT_NAME_WITHOUT_SPACE.json" "$LOGS_DIR/nkt-subscription-$PRODUCT_NAME_WITHOUT_SPACE-created.json"
        error_post "Problem creating subscription on Marketplace." "$LOGS_DIR/nkt-subscription-$PRODUCT_NAME_WITHOUT_SPACE-created.json"
        echo "              Subscription created." >&2

        MP_SUBSCRIPTION_ID=$(cat "$LOGS_DIR/nkt-subscription-$PRODUCT_NAME_WITHOUT_SPACE-created.json" | jq -rc '.id')
    fi

    # clean up intermediate files
    rm -rf "$LOGS_DIR/nkt-subscription-$PRODUCT_NAME_WITHOUT_SPACE*.json"
    rm -rf "$LOGS_DIR/mkt-subscription-product-*.json"

    echo "$MP_SUBSCRIPTION_ID"                        
}

#####################################################################
# Create the marketplace access request based on the APP-API linkage
#
# Input:
# - $1: V7 application name
# - $2: V7 API name
# - $3: Product name
# - $4: Marketplace product ID
# - $5: Marketplace product version ID
# - $6: Marketplace subscriptiopn ID
# - $7: Marketplace application ID
# Output: ACCESS_REQUEST_ID
#####################################################################
function createMarketplaceAccessRequestIfNotExisting() {

    local V7_APP_NAME=$1
    local V7_API_NAME=$2
    local PRODUCT_NAME=$3
    local MP_PRODUCT_ID=$4
    local MP_PRODUCT_VERSION_ID=$5
    local MP_SUBSCRIPTION_ID=$6
    local MP_APPLICATION_ID=$7

    local CREATE_ACCESS_REQUEST=1

    local SANITIZE_PRODUCT_NAME=$(sanitizeName "$PRODUCT_NAME")
    local SANITIZE_APPLICATION_NAME=$(sanitizeName "$V7_APP_NAME")
    local LOG_FILE="$LOGS_DIR/mkt-product-$SANITIZE_PRODUCT_NAME-resource-search.json"

    echo "              Finding assetResource identifier..." >&2
    getFromMarketplace "$MARKETPLACE_URL/api/v1/products/$MP_PRODUCT_ID/versions/$MP_PRODUCT_VERSION_ID/assetresources?limit=10&offset=0&search=" "" "$LOG_FILE"

    if [[ `jq length $LOG_FILE` != "" ]]
    then
        # something is found - why take the first one?
        MP_ASSETRESOURCE_ID=`cat "$LOG_FILE" | jq '[ .items[] | select( .title=="'"$V7_API_NAME"'" ) ]' | jq -r ' .[0].id'`

        if [[ $MP_ASSETRESOURCE_ID != null ]]
        then
            # checking if access already exits
            echo "              Checking if access already exist" >&2
            getFromMarketplace "$MARKETPLACE_URL/api/v1/applications/$MP_APPLICATION_ID/accessRequests" "" "$LOGS_DIR/mkt-application-$SANITIZE_APPLICATION_NAME-access-$MP_ASSETRESOURCE_ID-search.json"
            ACCESS_REQUEST_RESULT=$(cat "$LOGS_DIR/mkt-application-$SANITIZE_APPLICATION_NAME-access-$MP_ASSETRESOURCE_ID-search.json" | jq -rc '.totalCount')

            if [[ $ACCESS_REQUEST_RESULT != 0 ]]
            then

                echo "              Access request found, check if there is one for the specific resource" >&2
                # retrieve the correct one based on the RESOURCE_ID
                MP_ACCESS_REQUEST_ID=`cat "$LOGS_DIR/mkt-application-$SANITIZE_APPLICATION_NAME-access-$MP_ASSETRESOURCE_ID-search.json" | jq '[ .items[] | select( .assetResource.id=="'$MP_ASSETRESOURCE_ID'" ) ]' | jq -r '.[0].id'`

                if [[ $MP_ACCESS_REQUEST_ID != null ]]
                then
                    echo "              $V7_APP_NAME has already access to the API $V7_API_NAME" >&2
                    # no need to create a new one
                    CREATE_ACCESS_REQUEST=0
                fi
            fi

            if [[ $CREATE_ACCESS_REQUEST == 1 ]]
            then
                echo "              Adding access for API ($V7_API_NAME) to $V7_APP_NAME" >&2
                local ACCESS_REQUEST_TITLE="$V7_API_NAME - $V7_APP_NAME"
                jq -n -f ./jq/mkt-accessrequest.jq --arg accessRequestTile "$ACCESS_REQUEST_TITLE" --arg productId "$MP_PRODUCT_ID" --arg productIdVersion "$MP_PRODUCT_VERSION_ID" --arg assetResourceId "$MP_ASSETRESOURCE_ID" --arg subscriptionId $MP_SUBSCRIPTION_ID > "$LOGS_DIR/mkt-application-$SANITIZE_APPLICATION_NAME-access-$MP_ASSETRESOURCE_ID.json"
                postToMarketplace "$MARKETPLACE_URL/api/v1/applications/$MP_APPLICATION_ID/accessRequests" "$LOGS_DIR/mkt-application-$SANITIZE_APPLICATION_NAME-access-$MP_ASSETRESOURCE_ID.json" "$LOGS_DIR/mkt-application-$SANITIZE_APPLICATION_NAME-access-$MP_ASSETRESOURCE_ID-created.json"
                error_post "Problem creating Access Request on Marketplace." "$LOGS_DIR/mkt-application-$SANITIZE_APPLICATION_NAME-access-$MP_ASSETRESOURCE_ID-created.json"
                MP_ACCESS_REQUEST_ID=$(cat "$LOGS_DIR/mkt-application-$SANITIZE_APPLICATION_NAME-access-$MP_ASSETRESOURCE_ID-created.json" | jq -rc '.id')
            fi
        fi
    fi

    # clean up tenporary files
    rm -rf "$LOGS_DIR/mkt-application-$SANITIZE_APPLICATION_NAME*.json"
    rm -rf "$LOG_FILE"

    echo $MP_ACCESS_REQUEST_ID
}

#############################
# Approve the subscription is approval is manual
#
# Input:
# - $1: subscription ID
# Output: None
#############################
function providerApproveSubscription() {

    local SUBSCRIPTION_ID=$1

    # find the susbcription name
    getFromCentralWithRetry "$CENTRAL_URL/apis/catalog/v1alpha1/subscriptions?query=metadata.id==$SUBSCRIPTION_ID" "" "$LOGS_DIR/susbcription-$SUBSCRIPTION_ID.json"

    SUBSCRIPTION_APPROVAL=$(jq -rc '.[].approval.state' "$LOGS_DIR/susbcription-$SUBSCRIPTION_ID.json")

    if [[ $SUBSCRIPTION_APPROVAL == "pending" ]]
    then
        SUBSCRIPTION_NAME=$(jq -rc '.[].name' "$LOGS_DIR/susbcription-$SUBSCRIPTION_ID.json")
        # build approval content
        jq -n -f ./jq/subscription-approval.jq --arg userGuid $USER_GUID > "$LOGS_DIR/susbcription-$SUBSCRIPTION_ID-approval.json"

        # post it
        putToCentral "$CENTRAL_URL/apis/catalog/v1alpha1/subscriptions/$SUBSCRIPTION_NAME/approval" "$LOGS_DIR/susbcription-$SUBSCRIPTION_ID-approval.json" "$LOGS_DIR/susbcription-$SUBSCRIPTION_ID-approved.json"
        error_exit "Failed to approve subscription" "$LOGS_DIR/susbcription-$SUBSCRIPTION_ID-approved.json"

        echo "              Subscription $SUBSCRIPTION_ID approved." >&2
    else
        echo "              Susbcription $SUBSCRIPTION_ID already approved!"
    fi

    # clean up intermediate files
    rm -rf "$LOGS_DIR/susbcription-$SUBSCRIPTION_ID*"
}

##################################################
# Provider is approving the access in case needed
# MKT_APP_ID == Application.ID
# 
# Input:
# $1 - Marketplace application ID
# $2 - asset request ID
##################################################
providerApproveAccesRequest() {

    local MKT_APPLICATION_ID=$1
    local ASSET_REQUEST_ID=$2

    # let's find the application name first:
    local URL="$CENTRAL_URL/apis/catalog/v1alpha1/applications?query=metadata.id=='$MKT_APPLICATION_ID'"
    getFromCentralWithRetry "$URL" "" "$LOGS_DIR/application-$MKT_APPLICATION_ID.json"
    APPLICATION_NAME=$(cat "$LOGS_DIR/application-$MKT_APPLICATION_ID.json" | jq -rc '.[].name')

    # now we can find the access request
    URL="$CENTRAL_URL/apis/catalog/v1alpha1/applications/$APPLICATION_NAME/assetrequests/$ASSET_REQUEST_ID"
    getFromCentral "$URL" "" "$LOGS_DIR/application-$APPLICATION_NAME-asset-request-search.json"
    APPROVAL_STATE=$(cat "$LOGS_DIR/application-$APPLICATION_NAME-asset-request-search.json" | jq -rc '.approval.state.name')

    if [[ $APPROVAL_STATE == "pending" ]]
    then
        # approve it automatically
        putToCentral "$URL/approval" "./jq/assetrequest-approval.json" "$LOGS_DIR/application-$APPLICATION_NAME-asset-request-approved.json"
    else
        # already approved
        echo "              Access request is already aproved" >&2
    fi

    # clean up intermediate files
    rm -rf "$LOGS_DIR/application*"
}

#####################################################################
# Approve and provision the access request and add the finalizers
# so that the agent is aware of it
#
# Input:
# - $1: V7 application name
# - $2: V7 application ID
# - $3: V7 api ID
# - $4: Marketplace Access Request ID (mapped to provider access request name)
# Output: ACCESS_REQUEST_ID
#####################################################################
function providerProvisionAccesRequest() {

    local V7_APP_NAME=$1
    local V7_APP_ID=$2
    local V7_API_ID=$3
    local MKT_ACCESS_REQUEST_ID=$4
    local URL=$CENTRAL_URL'/apis/management/v1alpha1/accessrequests?query=name==%27'$MKT_ACCESS_REQUEST_ID'%27' 

    # find the Access request associated to the Marketplace Acces Request (MKT-accessrequestID==AccessRequest-name)
    getFromCentralWithRetry "$URL" "" "$LOGS_DIR/accrequest-$MKT_ACCESS_REQUEST_ID.json"
#    error_exit "Error retrieving the Access Request on provider side" "$LOGS_DIR/accrequest-$MKT_ACCESS_REQUEST_ID.json"

    # read existing information for the post (AccReq name + environment name)
    ACCESS_REQUEST_NAME=$(cat "$LOGS_DIR/accrequest-$MKT_ACCESS_REQUEST_ID.json" | jq -rc '.[].name')
    ACCESS_REQUEST_ENVIRONMENT_NAME=$(cat "$LOGS_DIR/accrequest-$MKT_ACCESS_REQUEST_ID.json" | jq -r '.[].metadata.scope.name')

    # mark it as provisioned (add the finalizers)
    jq --slurpfile file2 ./jq/agent-accreq-finalizer.json '(.[].finalizers += $file2)' "$LOGS_DIR/accrequest-$MKT_ACCESS_REQUEST_ID.json" > "$LOGS_DIR/accrequest-$MKT_ACCESS_REQUEST_ID-finalizer.json"

    # Remove references and status
    cat "$LOGS_DIR/accrequest-$MKT_ACCESS_REQUEST_ID-finalizer.json"  | jq -rc '.[]' | jq 'del(. | .status?, .metadata.references?, .references? )' > "$LOGS_DIR/accrequest-$MKT_ACCESS_REQUEST_ID-update.json"
    
    # Post to Central
    putToCentral "$CENTRAL_URL/apis/management/v1alpha1/environments/$ACCESS_REQUEST_ENVIRONMENT_NAME/accessrequests/$ACCESS_REQUEST_NAME" "$LOGS_DIR/accrequest-$MKT_ACCESS_REQUEST_ID-update.json" "$LOGS_DIR/accrequest-$MKT_ACCESS_REQUEST_ID-updated.json"
#    error_post "Problem while updating the access request agent information..." "$LOGS_DIR/accrequest-$MKT_ACCESS_REQUEST_ID-updated.json"

    # Add x-agent-details
    jq -n -f ./jq/agent-accreq-details.jq --arg accessID "$V7_API_ID" --arg applicationID $V7_APP_ID > "$LOGS_DIR/agent-access-details-$V7_APP_ID.json"

    # Post to Central
    putToCentral "$CENTRAL_URL/apis/management/v1alpha1/environments/$ACCESS_REQUEST_ENVIRONMENT_NAME/accessrequests/$ACCESS_REQUEST_NAME/x-agent-details" "$LOGS_DIR/agent-access-details-$V7_APP_ID.json" "$LOGS_DIR/accrequest-$MKT_ACCESS_REQUEST_ID-agent-details.json"
#    error_post "Problem while updating the agent details info..." "$LOGS_DIR/accrequest-$MKT_ACCESS_REQUEST_ID-updated-state.json"

    # Update status
    # mark it as done -> level = SUCCESS
    TIMESTAMP=$(date --utc +%FT%T.%3N%z)
    jq -n -f ./jq/agent-status-success.jq --arg timestampUTC "$TIMESTAMP" > "$LOGS_DIR/agent-status-success.json"
    putToCentral "$CENTRAL_URL/apis/management/v1alpha1/environments/$ACCESS_REQUEST_ENVIRONMENT_NAME/accessrequests/$ACCESS_REQUEST_NAME/status" "$LOGS_DIR/agent-status-success.json" "$LOGS_DIR/accrequest-$MKT_ACCESS_REQUEST_ID-updated-state.json"
#    error_post "Problem while updating the access request status..." "$LOGS_DIR/accrequest-$MKT_ACCESS_REQUEST_ID-updated-state.json"

    #clean up intermediate files
    rm -rf "$LOGS_DIR/accrequest-$MKT_ACCESS_REQUEST_ID*.json"
    rm -rf "$LOGS_DIR/agent-access-details-$V7_APP_ID.json"
    rm -rf "$LOGS_DIR/agent-status-success.json"
}

###################################################
# Find the appropriate CredentialRequestDefinition
#
# Input:
# - $1 : credenitalType
# - $2 : app mapping - to find the CRD
# Output: CRD_ID if found / "" if not found
###################################################
function findCredentialRequestDefinition() {

    local CREDENTIAL_TYPE=$1
    local APP_MAPPING=$2
    local CRD_FOUND=""

#    logDebug "Search for corresponding CRD of type $CREDENTIAL_TYPE"
    # find CRDs from mapping file
    MAPPING_NUMBER=`jq length $APP_MAPPING`

    for (( i=0; i<$MAPPING_NUMBER; i++ )) ; {
        # extract information
        MAPPING_VALUE=$(cat $APP_MAPPING | jq -rc '.['$i']')
#        logDebug "$i = $MAPPING_VALUE"

        CRD_ID=$(echo $MAPPING_VALUE | jq -r '.credentialRequestDefinitionId')
        ENV_NAME=$(echo $MAPPING_VALUE | jq -r '.environment')
#        logDebug "CRD_ID to validate = $CRD_ID"

        if [[ $CRD_ID != "$TBD_VALUE" ]]
        then
            # find its details in CENTRAL
            local URL="$CENTRAL_URL/apis/catalog/v1alpha1/credentialrequestdefinitions?query=metadata.id==$CRD_ID"
            CRD_NAME=$(getFromCentral "$URL" ".[].name" "$LOGS_DIR/crds-$CRD_ID.json")
            error_exit "Failed to retrieve credential definition" "$LOGS_DIR/crds-$CRD_ID.json"

#            logDebug "CRD-NAME == $CRD_NAME"

            if [[ $CRD_NAME != '' ]]
            then
                case $CREDENTIAL_TYPE in
                    "$CREDENTIAL_TYPE_APIKEY")
#                        logDebug "Searching API Key"
                        if [[ $CRD_NAME == $CREDENTIAL_DEFINTION_APIKEY ]]
                        then
                            CRD_FOUND=$CRD_ID  
                            break
                        fi
                        ;;
                    "$CREDENTIAL_TYPE_OAUTH")
#                        logDebug "Searching OAuth"
                        if [[ $CRD_NAME == $CREDENTIAL_DEFINTION_OAUTH_PUBLIC_KEY || $CRD_NAME == $CREDENTIAL_DEFINTION_OAUTH_SECRET ]]
                        then
                            CRD_FOUND=$CRD_ID  
                            break
                        fi
                        ;;
                    "$CREDENTIAL_TYPE_EXTERNAL")
#                        logDebug "Searching External"
                        if [[ $CRD_NAME == *$CREDENTIAL_DEFINTION_EXTERNAL_ID ]]
                        then
                            CRD_FOUND=$CRD_ID  
                            break
                        fi
                        ;;
                esac
            fi
        fi
    }

#    logDebug "Found CRD = $CRD_FOUND"
    echo "$CRD_FOUND"
}

############################################
# Find the field possible value given a field in the CRD definition
# 1st find the default value
# If no default value, search the 1st item of an enum
# Default to "Dummy"
#
# Input: 
# - $1: field name
# - $2: crd definition file
# Output
# - String value
############################################for ()
findCredentialFieldValue () {
    local FIELD_NAME=$1
    local CRD_FILE=$2
    local FIELD_VALUE="Dummy"

    FIELD_PATH=".[].spec.schema.properties.$FIELD_NAME"
    FIELD_DEFINITION=$(cat $CRD_FILE | jq -rc ''$FIELD_PATH'')

    FIELD_DEFAULT_VALUE=$(echo $FIELD_DEFINITION | jq -rc '.default')
    if [[ $FIELD_DEFAULT_VALUE != null ]]
    then
        FIELD_VALUE=$FIELD_DEFAULT_VALUE
    else
        # no default valuem, try an enum
        FIELD_ENUM=$(echo $FIELD_DEFINITION | jq -rc '.enum')

        if [[ $FIELD_ENUM != null ]]
        then
            # we take the 1st one
            FIELD_VALUE=$(echo $FIELD_DEFINITION | jq -rc '.enum[0]')
        fi
    fi

    echo "$FIELD_VALUE"

}

############################################
# Create a provision credential
# Based on CRD requred fields, add some fake values
#
# Input: 
# - $1: field list
# - $2: crd definition file
# Output
# - file containing the information
############################################for ()
function createTheCredentialRequiredField() {
    local REQUIRED_FIELDS=$1
    local CRD_FILE=$2
    local OUTPUT_FILE=$3

    FIELD_NUMBER=$(echo $REQUIRED_FIELDS | jq length)

    if [[ $FIELD_NUMBER != 0 ]]
    then
        echo "{\"data\":{" > $OUTPUT_FILE
        for (( i=0; i<$FIELD_NUMBER; i++ )) ; {

            FIELD_NAME=$(echo $REQUIRED_FIELDS | jq -rc '.['$i']')
            FIELD_VALUE=$(findCredentialFieldValue $FIELD_NAME "$CRD_FILE")
            
            if [[ $i == 0 ]]
            then
                echo "\"$FIELD_NAME\":\"$FIELD_VALUE\"" >> $OUTPUT_FILE
            else
                echo ",\"$FIELD_NAME\":\"$FIELD_VALUE\"" >> $OUTPUT_FILE
            fi
        }
        echo "}}" >> $OUTPUT_FILE
    fi
}


############################################
# Create the provision section of credenital 
# so that user can see them in Marketplace
#
# Input:
# - $3: the credential type
# - $2: the credential value coming from v7 app
# - $3: encryption key file
# Output: the provisioning schema to add
# APIKEY    : "data": { "apiKey": "*****" }
# OAUTH     : "data": { "clientId": "clientName", "clientSecret": "*****" }
# EXTERNAL  : "data": { "clientId": "*****" }
############################################
function provisionCredentialValueForMarketplace () {
    local CREDENTIAL_TYPE="$1"
    local CREDENTIAL_VALUE="$2"
    local PUBLIC_KEY_FILE="$3"

    if [[ $CREDENTIAL_TYPE == $CREDENTIAL_TYPE_APIKEY ]]
    then
        # get the value to encrypt
        VALUE_TO_ENCRYPT=$(echo $CREDENTIAL_VALUE | jq -rc '.id')
        # get encrypted value
        ENCRYPTED_VALUE=$(cryptingCredentialValue "$PUBLIC_KEY_FILE" "$VALUE_TO_ENCRYPT")
        PROVISIONING_VALUE="{\"data\":{\"apiKey\": \"$ENCRYPTED_VALUE\"}}"
    else
        if [[ $CREDENTIAL_TYPE == $CREDENTIAL_TYPE_OAUTH ]]
        then
            # get the value to encrypt
            VALUE_TO_ENCRYPT=$(echo $CREDENTIAL_VALUE | jq -rc '.secret')
            # get encrypted value
            ENCRYPTED_VALUE=$(cryptingCredentialValue "$PUBLIC_KEY_FILE" "$VALUE_TO_ENCRYPT")
            PROVISIONING_VALUE="{\"data\":{\"clientId\": \"$CREDENTIAL_ID\", \"clientSecret\": \"$ENCRYPTED_VALUE\"}}"
        else
            if [[ $CREDENTIAL_TYPE == $CREDENTIAL_TYPE_EXTERNAL ]]
            then
                # we cannot encrypt anything since the secret is hosted on the external IDP. v7 App host only the clientId.
                CREDENTIAL_CLIENT_ID=$(echo $CREDENTIAL_VALUE | jq -rc '.clientId')
                ENCRYPTED_VALUE=$(cryptingCredentialValue "$PUBLIC_KEY_FILE" "Please refer to your provider to get the credential secret or rotate the credential.")
                PROVISIONING_VALUE="{\"data\":{\"clientId\": \"$CREDENTIAL_CLIENT_ID\", \"clientSecret\": \"$ENCRYPTED_VALUE\"}}"
            fi
        fi
    fi

    logDebug "providerValue for ($CREDENTIAL_TYPE)=$PROVISIONING_VALUE"
    echo $PROVISIONING_VALUE
}

############################################
# Create a provision credential
#
# Input:
# - $1: V7 application ID
# - $1: credentials list
# - $2: credential type (APIKEY/OAUTH/External)
# - $3: Marketplace application ID
# - $5: Mapping information
# - $6: Encryption key coming from the corresponding ManagedApplication
# Ouput:
############################################
function createAndProvisionCredential () {

    local V7_APP_ID=$1
    local CREDENTIAL_LIST=$2
    local CREDENTIAL_TYPE=$3
    local MKT_APP_ID=$4
    local APP_MAPPING=$5
    local ENCRYPTION_KEY_FILE=$6

    # for each in the list do
    CREDENTIAL_NUMBER=`jq length $CREDENTIAL_LIST`
#    logDebug "Credential number to create: $CREDENTIAL_NUMBER"

    if [[ $CREDENTIAL_NUMBER > 0 ]]
    then

        for (( i=0; i<$CREDENTIAL_NUMBER; i++ )) ; {
            
            # extract information
            CREDENTIAL_VALUE=$(cat $CREDENTIAL_LIST | jq -rc '.['$i']')
#            logDebug "Credentials value ($i) = $CREDENTIAL_VALUE"

            CREDENTIAL_ID=$(echo $CREDENTIAL_VALUE | jq -rc '.id')
            if [[ $CREDENTIAL_TYPE == $CREDENTIAL_TYPE_APIKEY || $CREDENTIAL_TYPE == $CREDENTIAL_TYPE_OAUTH ]]
            then
                # APIKEY / OAuth internal
                CREDENTIAL_ID_SECRET=$(echo $CREDENTIAL_VALUE | jq -rc '.secret')
                CREDENTIAL_HASH=$(hashingCredentialValue "$CREDENTIAL_HASH_2_PARAM" "$CREDENTIAL_ID" "$CREDENTIAL_ID_SECRET")
            else
                # external clientID
                CREDENTIAL_CLIENT_ID=$(echo $CREDENTIAL_VALUE | jq -rc '.clientId')
                CREDENTIAL_HASH=$(hashingCredentialValue "$CREDENTIAL_HASH_3_PARAM" "$CREDENTIAL_ID" "$CREDENTIAL_CLIENT_ID")
            fi

#            logDebug "Credential hash = $CREDENTIAL_HASH"

            # get a credential request definition for the credential type
            CREDENTIAL_REQUEST_DEFINIITON=$(findCredentialRequestDefinition "$CREDENTIAL_TYPE" "$APP_MAPPING")

            if [[ $CREDENTIAL_REQUEST_DEFINIITON != "" ]]
            then
                # by definition, we create the credential as follows: $CREDENTIAL_TYPE_$COUNTER to ofuscate the v7 credential ID that is the API_KEY.
                CREDENTIAL_TITLE="$CREDENTIAL_TYPE"_"$i"

                # Search if credential already exist on consumer side
                local URL="$CENTRAL_URL/apis/management/v1alpha1/credentials?query=title==$CREDENTIAL_TITLE"
                getFromCentral "$URL" "" "$LOGS_DIR/credential-$CREDENTIAL_ID.json"
                error_exit "Cannot find credentials..." "$LOGS_DIR/credential-$CREDENTIAL_ID.json"

                FILE_LENGTH=$(jq length "$LOGS_DIR/credential-$CREDENTIAL_ID.json")

                if [[ $FILE_LENGTH != '' && $FILE_LENGTH != 0 ]] 
                then
                    echo "              Credential already exists, no need to create a new one."
                else
                    echo "              Credential not found, creating it..."

                    # generate credential payload...
                    jq -n -f ./jq/mkt-credential.jq --arg credentialTitle "$CREDENTIAL_TITLE" --arg credentialrequestdefinition "$CREDENTIAL_REQUEST_DEFINIITON" > "$LOGS_DIR/mkt-application-$MKT_APP_ID-credential-$CREDENTIAL_ID.json"

                    # add any mandatory information just for the query to not fail
#                    logDebug "Finding fields for CRD ($CREDENTIAL_REQUEST_DEFINIITON)...."
                    REQUIRED_FIELDS=$(cat "$LOGS_DIR/crds-$CREDENTIAL_REQUEST_DEFINIITON.json" | jq -rc '.[].spec.schema.required')
#                    logDebug "Found fields=$REQUIRED_FIELDS-"

                    if [[ $REQUIRED_FIELDS != null ]] then
                        echo "                  Adding mandatory fields..."
                        createTheCredentialRequiredField $REQUIRED_FIELDS "$LOGS_DIR/crds-$CREDENTIAL_REQUEST_DEFINIITON.json" "$LOGS_DIR/mkt-application-$MKT_APP_ID-credential-$CREDENTIAL_ID-fields.json"

                        # merge the files...
                        jq --argjson data "$(jq '.data' "$LOGS_DIR/mkt-application-$MKT_APP_ID-credential-$CREDENTIAL_ID-fields.json")" '.data = $data' "$LOGS_DIR/mkt-application-$MKT_APP_ID-credential-$CREDENTIAL_ID.json" > "$LOGS_DIR/mkt-application-$MKT_APP_ID-credential-$CREDENTIAL_ID-tmp.json"
                        mv "$LOGS_DIR/mkt-application-$MKT_APP_ID-credential-$CREDENTIAL_ID-tmp.json" "$LOGS_DIR/mkt-application-$MKT_APP_ID-credential-$CREDENTIAL_ID.json"
                    fi

                    # post to Marketplace...
                    echo "                  Creating the credential $CREDENTIAL_ID on Marketplace side...." >&2
                    postToMarketplace "$MARKETPLACE_URL/api/v1/applications/$MKT_APP_ID/credentials" "$LOGS_DIR/mkt-application-$MKT_APP_ID-credential-$CREDENTIAL_ID.json" "$LOGS_DIR/mkt-application-$MKT_APP_ID-credential-$CREDENTIAL_ID-created.json"
                    error_post "Error while creating credentials $CREDENTIAL_ID for Application $MKT_APP_ID" "$LOGS_DIR/mkt-application-$MKT_APP_ID-credential-$CREDENTIAL_ID-created.json"
                    echo "              Credential created." 

                    # provision on provider side...
                    echo "              Provider provision the credential..." >&2

                    # find credential and read it (MKT-credential-title==Credential-title)
                    URL=$CENTRAL_URL'/apis/management/v1alpha1/credentials?query=title=='$CREDENTIAL_TITLE'' 
                    # find the credential associated to the Marketplace credentials
                    getFromCentralWithRetry "$URL" "" "$LOGS_DIR/credential-$CREDENTIAL_ID-created.json"
                    error_exit "Failed to retrieve Cendential $CREDENTIAL_ID" "$LOGS_DIR/credential-$CREDENTIAL_ID-created.json"

                    CREDENTIAL_NAME=$(cat "$LOGS_DIR/credential-$CREDENTIAL_ID-created.json"  | jq -rc '.[].name')
                    CREDENTIAL_ENVIRONMENT_NAME=$(cat "$LOGS_DIR/credential-$CREDENTIAL_ID-created.json"  | jq -r '.[].metadata.scope.name')
#                    logDebug "CRDNAME=$CREDENTIAL_NAME-"

                    # mark it as provisioned (add the finalizers)
                    jq --slurpfile file2 ./jq/agent-credfential-finalizer.json '(.[].finalizers += $file2)' "$LOGS_DIR/credential-$CREDENTIAL_ID-created.json" > "$LOGS_DIR/credential-$CREDENTIAL_ID-finalizer.json"

                    # Remove references, status and resourceVersion to avoid issues.
                    cat "$LOGS_DIR/credential-$CREDENTIAL_ID-finalizer.json"  | jq -rc '.[]' | jq 'del(. | .status?, .metadata.references?, .references?, .metadata.resourceVersion? )' > "$LOGS_DIR/credential-$CREDENTIAL_ID-update.json"
                    
                    # Post to Central
                    putToCentral "$CENTRAL_URL/apis/management/v1alpha1/environments/$CREDENTIAL_ENVIRONMENT_NAME/credentials/$CREDENTIAL_NAME" "$LOGS_DIR/credential-$CREDENTIAL_ID-update.json" "$LOGS_DIR/credential-$CREDENTIAL_ID-finalizer.json"
                    error_post "Problem while updating the credential agent information..." "$LOGS_DIR/credential-$CREDENTIAL_ID-finalizer.json"
                    echo "                  Finalizer added to the credential..." >&2

                    # add credential encrypted values
#                    logDebug "PublicKey file=$ENCRYPTION_KEY_FILE"
                    provisionCredentialValueForMarketplace "$CREDENTIAL_TYPE" "$CREDENTIAL_VALUE" "$ENCRYPTION_KEY_FILE" > "$LOGS_DIR/credential-$CREDENTIAL_ID-data.json"
        
                    # Post to Central
                    putToCentral "$CENTRAL_URL/apis/management/v1alpha1/environments/$CREDENTIAL_ENVIRONMENT_NAME/credentials/$CREDENTIAL_NAME/data" "$LOGS_DIR/credential-$CREDENTIAL_ID-data.json" "$LOGS_DIR/credential-$CREDENTIAL_ID-data-updated.json"
                    error_post "Problem while updating the credential agent details info..." "$LOGS_DIR/credential-$CREDENTIAL_ID-data-updated.json"
                    echo "                  encrypted ddata added to the credential..." >&2

                    # Add x-agent-details
                    jq -n -f ./jq/agent-credential-details.jq --arg applicationID "$V7_APP_ID" --arg credentialReference $CREDENTIAL_HASH > "$LOGS_DIR/credential-$CREDENTIAL_ID-agent-details.json"

                    # Post to Central
                    putToCentral "$CENTRAL_URL/apis/management/v1alpha1/environments/$CREDENTIAL_ENVIRONMENT_NAME/credentials/$CREDENTIAL_NAME/x-agent-details" "$LOGS_DIR/credential-$CREDENTIAL_ID-agent-details.json" "$LOGS_DIR/credential-$CREDENTIAL_ID-agent-details-updated.json"
                    error_post "Problem while updating the credential agent details info..."$LOGS_DIR/credential-$CREDENTIAL_ID-agent-details-updated.json
                    echo "                  x-agent-details added to the credential..." >&2

                    # Update status
                    # mark it as done -> level = SUCCESS
                    TIMESTAMP=$(date --utc +%FT%T.%3N%z)
                    jq -n -f ./jq/agent-status-success.jq --arg timestampUTC "$TIMESTAMP" > "$LOGS_DIR/credential-$CREDENTIAL_ID-agent-status-success.json"
                    putToCentral "$CENTRAL_URL/apis/management/v1alpha1/environments/$CREDENTIAL_ENVIRONMENT_NAME/credentials/$CREDENTIAL_NAME/status" "$LOGS_DIR/credential-$CREDENTIAL_ID-agent-status-success.json" "$LOGS_DIR/credential-$CREDENTIAL_ID-agent-status-success-updated.json"
                    error_post "Problem while updating the access request status..." "$LOGS_DIR/credential-$CREDENTIAL_ID-agent-status-success-updated.json"

                    echo "              Credential provisioning done." >&2

                    # clean up temporary file
                    rm -rf "$LOGS_DIR/credential-$CREDENTIAL_ID*.json"
                    rm -rf "$LOGS_DIR/mkt-application-$MKT_APP_ID-credential-$CREDENTIAL_ID*.json"
                    rm -rf "$LOGS_DIR/value.txt"
                fi
            else
                echo "---<<WARNING>> No credential of type $CREDENTIAL_TYPE found in the mapping." >&2
            fi

            # clean up intermediate files
            rm -rf "$LOGS_DIR/crds-$CREDENTIAL_REQUEST_DEFINIITON.json"


        }
    else
        echo "No credential of type $CREDENTIAL_TYPE in the application $MKT_APP_ID" >&2
    fi
}

#####################################################
# Move v7 Application to Amplify Agents organization
# and remame it as TA expects it
#
# Input:
#  - $1: Original application name
#  - $2: Marketplace application ID
#  - $3: New organization ID
# Output: None
#####################################################
function moveV7appToAmplifyAgentsOrganization() {

    local V7_APPLICATION_NAME_TO_MIGRATE=$1
    local V7_APPLICATION_ID=$2
    local MKT_APP_ID=$3
    local AGENT_V7_ORG_ID=$4

    echo "              Finding the new name for $V7_APPLICATION_NAME_TO_MIGRATE" >&2
    # read ManagedApplication logical name based on the Marketplace application ID
    MANAGED_APP_NAME=$(getFromCentral "$CENTRAL_URL/apis/management/v1alpha1/managedapplications?query=metadata.references.id==$MKT_APP_ID" ".[].name" "$LOGS_DIR/app-managedapp-$MKT_APP_ID.json")
    echo "              New name found: $MANAGED_APP_NAME"

    # read it and replace name and organizationID
    echo "              Updating $V7_APPLICATION_NAME_TO_MIGRATE to $MANAGED_APP_NAME..." >&2
    cat $TEMP_FILE | jq  '[.[] | select(.name=="'"$V7_APPLICATION_NAME_TO_MIGRATE"'")]' | jq -rc '.[]' | jq '.name="'$MANAGED_APP_NAME'"' | jq '.organizationId="'$AGENT_V7_ORG_ID'"' > "$LOGS_DIR/app-move.json"

    # put it
    putToApiManager "applications/$V7_APP_ID" "$LOGS_DIR/app-move.json" "$LOGS_DIR/app-move-result.json"
    echo "              $MANAGED_APP_NAME created and moved into Amplify Agents organization" >&2

    # clean up intermediate files
    rm -rf "$LOGS_DIR/app-managedapp-$MKT_APP_ID.json"
    rm -rf "$LOGS_DIR/app-move.json"
    rm -rf "$LOGS_DIR/app-move-result.json"
}

########################################################
# Migrate V7 Application into Marketplace Application
#
# Input parameters:
# 1- (optional) ApplicationName
########################################################
migrate_v7_application() {

    # Should we migrate all or just one?
    if [[ $APP_NAME_TO_MIGRATE == '' ]]
    then
        # create the applicationList
        echo "Reading all applications" >&2
        getFromApiManager "applications" $TEMP_FILE
    else
        echo "Reading single application: $APP_NAME_TO_MIGRATE" >&2
        getFromApiManager "applications" "$LOGS_DIR/tmp.json"
        # need to return an array for it to work regardless it is a single or multiple.
        cat "$LOGS_DIR/tmp.json" | jq  '[.[] | select(.name=="'"$APP_NAME_TO_MIGRATE"'")]' >  $TEMP_FILE
        rm -rf "$LOGS_DIR/tmp.json"
    fi

    # loop over the result and keep interesting data (name / description / org)
    cat $TEMP_FILE | jq -rc ".[] | {appId: .id, orgId: .organizationId, appName: .name, appDesc: .description}" | while IFS= read -r line ; do

        #echo "line=$line"
        # read values
        V7_APP_ID=$(echo $line | jq -r '.appId')
        V7_ORG_ID=$(echo $line | jq -r '.orgId')
        V7_APP_NAME=$(echo $line | jq -r '.appName')
        V7_APP_DESCRIPTION=$(echo $line | jq -r '.appDesc')

        # read organization name for creating the corresponding team name if needed
        v7_ORG_NAME=$(getAPIM_OrganizationName "$V7_ORG_ID")
        echo "  TEAM_NAME=$v7_ORG_NAME / APP_NAME=$V7_APP_NAME" >&2
        V7_APP_NAME_SANITIZED=$(sanitizeName "$V7_APP_NAME")

        # Adding the organization as a team in Amplify?
        if [[ "$v7_ORG_NAME" != "Amplify Agents" ]]; then

            echo "  Organization is not the Amplify Agents one, checking if corresponding team exists..." >&2
            TEAM_GUID=$(createTeamFromOrganizationNameIfNotExisting $PLATFORM_ORGID "$v7_ORG_NAME")

            ## Application management ##
            MKT_APP_ID=$(createMarketplaceApplicationIfNotExisting "$V7_APP_NAME" $TEAM_GUID)

            ## Subscription Management ##
            echo "      Creating access request for application $V7_APP_NAME" >&2
            # list APIs assigned to the Application
            getFromApiManager "applications/$V7_APP_ID/apis" "$LOGS_DIR/app-$V7_APP_ID-apis.json"

            # retieve mappings associated to the Application
            echo "      Searching mapping assigned to the Application..." >&2
            cat $MAPPING_DIR/$MAPPING_FILE_NAME | jq  '.[] | select(.ApplicationName=="'"$V7_APP_NAME"'")' | jq -rc '.Mapping' >  "$LOGS_DIR/mapping-$V7_APP_NAME_SANITIZED.json"

            # check there is some mapping
            if [[ `jq length "$LOGS_DIR/mapping-$V7_APP_NAME_SANITIZED.json"` != "" ]]
            then
                # find productID, productVersion and resourceID
                echo "      Mapping found." >&2

                # for each API assigned to the Application,
                cat "$LOGS_DIR/app-$V7_APP_ID-apis.json" | jq -rc ".[] | {apiId: .apiId}" | while IFS= read -r appApiLine ; do

                    V7_API_ID=$(echo $appApiLine | jq -r '.apiId')
                    V7_API_NAME=$(getAPIM_APIName "$V7_API_ID")
                    echo "          Found API: id=$V7_API_ID / name=$V7_API_NAME" >&2

                    # retrieve Product, and plan for creating the subscription
                    echo "              Searching corresponding productID and planID for creating the subscription..." >&2
                    PRODUCT_NAME=$(cat "$LOGS_DIR/mapping-$V7_APP_NAME_SANITIZED.json" | jq '.[] | select(.apiName=="'"$V7_API_NAME"'")' | jq -rc '.productName')
                    PRODUCT_PLAN_NAME=$(cat "$LOGS_DIR/mapping-$V7_APP_NAME_SANITIZED.json" | jq '.[] | select(.apiName=="'"$V7_API_NAME"'")' | jq -rc '.planName')

                    if [[ $PRODUCT_NAME != $TBD_VALUE && $PRODUCT_PLAN_NAME != $TBD_VALUE ]] 
                    then
                        # Grant access to the API to Amplify Agents org
                        echo "          Granting Amplify Agents org accees to API $V7_API_ID..."
                        grantApiAccessToAmplifyAgentsOrganization "$V7_API_ID" "$AGENT_V7_ORG_ID"
                        echo "          Access granted."

                        # read product ID
                        echo "          Reading productId fron productName=$PRODUCT_NAME" >&2
                        MP_PRODUCT_IDENTIFIERS=$(getMarketplaceProductIdFromProductName "$PRODUCT_NAME")
                        MP_PRODUCT_ID=$(echo $MP_PRODUCT_IDENTIFIERS | jq -rc '.productId')
                        MP_PRODUCT_LATEST_VERSION_ID=$(echo $MP_PRODUCT_IDENTIFIERS | jq -rc '.productLatestVersionId')
                        # read plan ID
                        echo "          Reading planId fron productName=$PRODUCT_NAME" >&2
                        MP_PRODUCT_PLAN_ID=$(getMarketplacePlanIdFromPlanName "$MP_PRODUCT_ID" "$PRODUCT_PLAN_NAME")

                        # create the subscription
                        echo "          Creating a subscritpion..." >&2
                        MKT_SUBSCRIPTION_ID=$(createMarketplaceSubscriptionIfNotExisting "$v7_ORG_NAME" "$TEAM_GUID" "$PRODUCT_PLAN_NAME" "$MP_PRODUCT_PLAN_ID" "$PRODUCT_NAME" "$MP_PRODUCT_ID")
                        echo "          Subscription ID=$MKT_SUBSCRIPTION_ID" >&2

                        # Approve the subscription if manual porocess in place
                        echo "          Approving the Subscription..." >&2
                        providerApproveSubscription "$MKT_SUBSCRIPTION_ID"

                        ## Access Request Management ##
                        echo "          Creating Access request..." >&2
                        MKT_ACCESS_REQUEST_ID=$(createMarketplaceAccessRequestIfNotExisting "$V7_APP_NAME" "$V7_API_NAME" "$PRODUCT_NAME" "$MP_PRODUCT_ID" "$MP_PRODUCT_LATEST_VERSION_ID" "$MKT_SUBSCRIPTION_ID" "$MKT_APP_ID")
                        echo "          Access request created." >&2

                        echo "          Approve Access request..." >&2
                        providerApproveAccesRequest "$MKT_APP_ID" "$MKT_ACCESS_REQUEST_ID"
                        echo "          Access request approved." >&2

                        echo "          Provisioning the Access Request..." >&2
                        providerProvisionAccesRequest "$V7_APP_NAME" "$V7_APP_ID" "$V7_API_ID" "$MKT_ACCESS_REQUEST_ID"
                        echo "          Access Request provisioned." >&2
                    else
                        echo "          /!\ productName and/or planName for application ($V7_APP_NAME) and api ($V7_API_NAME) are not defined in the mapping, cannot proceed farther" >&2
                    fi

                done

                # clean up intermediate file
                rm -rf "$LOGS_DIR/app-$V7_APP_ID-apis.json"

                # provison the ManageApplication - created only once an accessrequest is added to the application
                echo "      Provisioning the corresponding Managed application...." 
                providerProvisionManagedApplication "$MKT_APP_ID" "$V7_APP_ID"
                echo "      Managed Application provisioned." 

                # reading ManagedApplication encryption key
                getFromCentralWithRetry "$CENTRAL_URL/apis/management/v1alpha1/managedapplications?query=metadata.references.id==$MKT_APP_ID" "" "$LOGS_DIR/app-managedapp-$MKT_APP_ID.json"
                PUBLIC_KEY_FILE="$LOGS_DIR/app-managedapp-$MKT_APP_ID-publicKey.pem"
                cat "$LOGS_DIR/app-managedapp-$MKT_APP_ID.json" | jq -rc '.[].spec.security.encryptionKey' > "$PUBLIC_KEY_FILE"

                # creating credentials
                echo "      Creating credentials for application $V7_APP_NAME" >&2

                echo "          Creating credentials APIKEYS for application $V7_APP_NAME" >&2
                getAPIM_Credentials "$V7_APP_ID" "$CREDENTIAL_TYPE_APIKEY" "$LOGS_DIR/app-$V7_APP_ID-apikeys.json" 
                createAndProvisionCredential "$V7_APP_ID" "$LOGS_DIR/app-$V7_APP_ID-apikeys.json" "$CREDENTIAL_TYPE_APIKEY" "$MKT_APP_ID" "$LOGS_DIR/mapping-$V7_APP_NAME_SANITIZED.json" "$PUBLIC_KEY_FILE"

                echo "          Creating credentials OAUTH for application $V7_APP_NAME" >&2
                getAPIM_Credentials "$V7_APP_ID" "$CREDENTIAL_TYPE_OAUTH" "$LOGS_DIR/app-$V7_APP_ID-oauth.json" 
                createAndProvisionCredential "$V7_APP_ID" "$LOGS_DIR/app-$V7_APP_ID-oauth.json" "$CREDENTIAL_TYPE_OAUTH" "$MKT_APP_ID" "$LOGS_DIR/mapping-$V7_APP_NAME_SANITIZED.json" "$PUBLIC_KEY_FILE"

                echo "          Creating credentials EXTERNAL for application $V7_APP_NAME" >&2
                getAPIM_Credentials "$V7_APP_ID" "$CREDENTIAL_TYPE_EXTERNAL" "$LOGS_DIR/app-$V7_APP_ID-external.json" 
                createAndProvisionCredential "$V7_APP_ID" "$LOGS_DIR/app-$V7_APP_ID-external.json" "$CREDENTIAL_TYPE_EXTERNAL" "$MKT_APP_ID" "$LOGS_DIR/mapping-$V7_APP_NAME_SANITIZED.json" "$PUBLIC_KEY_FILE"

                # clean up intermediate files
                rm -rf "$LOGS_DIR/app-$V7_APP_ID-apikeys.json"
                rm -rf "$LOGS_DIR/app-$V7_APP_ID-oauth.json" 
                rm -rf "$LOGS_DIR/app-$V7_APP_ID-external.json"
                rm -rf "$PUBLIC_KEY_FILE"

                ## Update V7 application: move it to Amplify Agents org / update its name so that TA still work
                echo "      Updating v7 application $V7_APP_NAME...."
                moveV7appToAmplifyAgentsOrganization "$V7_APP_NAME" "$V7_APP_ID" "$MKT_APP_ID" "$AGENT_V7_ORG_ID"
                echo "      v7 application [$V7_APP_NAME] updated and move to the Amplify Agents organization"
            else
                echo "      /!\ No mapping found... Cannot proceed farther" >&2
            fi

            # clean up intermediate files
            rm -rf "$LOGS_DIR/mapping-$V7_APP_NAME_SANITIZED.json"

        else # It is  the Amplify Agents org - nothing to do
            echo "  Skipping team / app creation as already present in Marketplace" >&2
        fi

    done

    rm -rf "$TEMP_FILE"
}

#########
# Main
#########

echo ""
echo "==============================================================================" 
echo "== Creating Amplify platform team from the organization name in API Manager ==" 
echo "== API Manager access and Amplify Platform access are required              =="
echo "== curl and jq programs are required                                        =="
echo "==============================================================================" 
echo ""

if [[ $1 != null ]]
then
    # supplied config file
    source $1
else 
    # default env config file
    source ./Config/env.properties
fi

echo "Checking pre-requisites (axway CLI, curl and jq)"
# check that axway CLI is installed
if ! command -v axway &> /dev/null
then
    echo "axway CLI could not be found. Please be sure you can run axway CLI on this machine"
    exit 1
fi

#check that curl is installed
if ! command -v curl &> /dev/null
then
    echo "curl could not be found. Please be sure you can run curl command on this machine"
    exit 1
fi

#check that jq is installed
if ! command -v jq &> /dev/null
then
    echo "jq could not be found. Please be sure you can run jq command on this machine"
    exit 1
fi
echo "All pre-requisites are available" 

#login to the platform
loginToPlatform

mkdir -p $LOGS_DIR

# create the Amplify Agents organization if not exist and retrieve its ID or the Existing org ID.
AGENT_V7_ORG_ID=$(createAmplifyAgentOrganizationIfNotExisting)

echo ""
echo "Creating the Marketplace Application"
migrate_v7_application
echo "Done."

exit 0