#!/bin/bash

# Sourcing user-provided env properties
#source ./config/env.properties

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
        jq -n -f ./jq/agent-organization.jq --arg organizationName "$ORG_NAME" > $LOGS_DIR/agent-organization.json
        postToApiManager "organizations" "$LOGS_DIR/agent-organization.json" "$LOGS_DIR/agent-organization-created.json"

        # get the ORG_ID
        ORG_ID=$(cat $LOGS_DIR/agent-organization-created.json | jq -rc '.id')

        # delete intermediate files
        rm -rf $LOGS_DIR/agent-organization*.json
    else
         echo "$ORG_NAME organization does exist." >&2
    fi

    # delete intermediate file
    rm -rf $LOGS_DIR/organizations.json

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
createTeamFromOrganizationNameIfNotExisting() {

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

############################################################
# Creating the Markateplace Application if not existing yet
#
# Input:
# - $1: Application Name
# - $2: Owing team guid
# Ouptut: Marketplace Application ID
############################################################"" "$LOGS_DIR/mkt-application-$MKT_APP_NAME_SANITIZED-search.json"
createMarketplaceApplicationIfNotExisting() {

    local MKT_APP_NAME="$1"
    local OWNING_TEAM_GUID="$2"

    echo "  is $MKT_APP_NAME exist on the Marketplace?" >&2
    # sanitize name for file name...
    local MKT_APP_NAME_SANITIZED=$(sanitizeName "$MKT_APP_NAME") 
    # sanitize name for query search...
    local MKT_APP_NAME_FOR_SEARCH=$(sanitizeNameForQuery "$MKT_APP_NAME")      

    # TODO check that it is the correct owning team too
    getFromMarketplace "$MARKETPLACE_URL/api/v1/applications?limit=10&offset=0&search=$MKT_APP_NAME_FOR_SEARCH&sort=-metadata.modifiedAt%2C%2Bname" "" "$LOGS_DIR/mkt-application-$MKT_APP_NAME_SANITIZED-search.json"
    MP_APPLICATION_ID=`cat $LOGS_DIR/mkt-application-$MKT_APP_NAME_SANITIZED-search.json | jq -r '.items[0].id'`

    if [[ $MP_APPLICATION_ID == null ]]
    then
        # TODO = Application icon
        #https://lbean018.lab.phx.axway.int:8075/api/portal/v1.4/applications/b876ab64-60b7-4393-8cc9-ffa56128d583/image
        #getFromApiManager

        # we can create it
        echo "      No it does not, creating application $MKT_APP_NAME..." >&2
        jq -n -f ./jq/mkt-application.jq --arg applicationTitle "$MKT_APP_NAME" --arg teamId $OWNING_TEAM_GUID > $LOGS_DIR/mkt-application-$MKT_APP_NAME_SANITIZED.json
        postToMarketplace "$MARKETPLACE_URL/api/v1/applications" $LOGS_DIR/mkt-application-$MKT_APP_NAME_SANITIZED.json $LOGS_DIR/mkt-application-$MKT_APP_NAME_SANITIZED-created.json
        echo "      Application $MKT_APP_NAME created on Marketplace" >&2
        MP_APPLICATION_ID=`cat $LOGS_DIR/mkt-application-$MKT_APP_NAME_SANITIZED-created.json | jq -r '.id'`
    else
        echo "      Application already exist in Marketplace." >&2
    fi

    echo "$MP_APPLICATION_ID"
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
createMarketplaceSubscriptionIfNotExisting() {

    local TEAM_NAME=$1
    local TEAM_GUID=$2
    local MP_PRODUCT_PLAN_NAME=$3
    local MP_PRODUCT_PLAN_ID=$4
    local MP_PRODUCT_NAME=$5
    local MP_PRODUCT_ID=$6
    local SUBSCRIPTION_TITLE="$PRODUCT_NAME - $PRODUCT_PLAN_NAME"
    local SANITIZE_PRODUCT_NAME=$(sanitizeName $PRODUCT_NAME)

    echo "              Checking if owning team ($TEAM_NAME) already has a subscription for product ($MP_PRODUCT_NAME) using plan ($MP_PRODUCT_PLAN_NAME)" >&2
    getFromMarketplace "$MARKETPLACE_URL/api/v1/subscriptions?product.id=$MP_PRODUCT_ID" "" "$LOGS_DIR/mkt-subscription-product-$SANITIZE_PRODUCT_NAME-search.json"
    NB_SUBSCRIPTION=`cat $LOGS_DIR/mkt-subscription-product-$SANITIZE_PRODUCT_NAME-search.json | jq -r '.totalCount'`

    if [[ $NB_SUBSCRIPTION != 0 ]]
    then
        # we can search within the list
        MP_SUBSCRIPTION_ID=`cat $LOGS_DIR/mkt-subscription-product-$SANITIZE_PRODUCT_NAME-search.json | jq '[ .items[] | select( .plan.id=="'$MP_PRODUCT_PLAN_ID'" and .owner.id=="'$TEAM_GUID'" ) ]' | jq -r '.[0].id'`

        # subscription not found?
        if [[ $MP_SUBSCRIPTION_ID == null ]]
        then
            echo "              No subscription found, creating the new one..." >&2
            jq -n -f ./jq/mkt-subscription.jq --arg subscriptionTitle "$SUBSCRIPTION_TITLE" --arg teamId $TEAM_GUID --arg planId $MP_PRODUCT_PLAN_ID --arg productId $MP_PRODUCT_ID > $LOGS_DIR/nkt-subscription-$PRODUCT_NAME_WITHOUT_SPACE.json
            postToMarketplace "$MARKETPLACE_URL/api/v1/subscriptions" $LOGS_DIR/nkt-subscription-$PRODUCT_NAME_WITHOUT_SPACE.json $LOGS_DIR/nkt-subscription-$PRODUCT_NAME_WITHOUT_SPACE-created.json
            error_post "Problem creating subscription on Marketplace." $LOGS_DIR/nkt-subscription-$PRODUCT_NAME_WITHOUT_SPACE-created.json
            echo "              Subscription created." >&2

            MP_SUBSCRIPTION_ID=$(cat $LOGS_DIR/nkt-subscription-$PRODUCT_NAME_WITHOUT_SPACE-created.json | jq -rc '.id')
        fi
    fi

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
createMarketplaceAccessRequestIfNotExisting() {

    local V7_APP_NAME=$1
    local V7_API_NAME=$2
    local PRODUCT_NAME=$3
    local MP_PRODUCT_ID=$4
    local MP_PRODUCT_VERSION_ID=$5
    local MP_SUBSCRIPTION_ID=$6
    local MP_APPLICATION_ID=$7

    local SANITIZE_PRODUCT_NAME=$(sanitizeName "$PRODUCT_NAME")
    local SANITIZE_APPLICATION_NAME=$(sanitizeName "$V7_APP_NAME")
    local LOG_FILE=$LOGS_DIR/mkt-product-$SANITIZE_PRODUCT_NAME-resource-search.json

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
            # TODO
            #getFromMarketplace "$MARKETPLACE_URL/api/v1/applications/$MP_APPLICATION_ID/accessRequests" "" "$LOGS_DIR/mkt-application-$SANITIZE_APPLICATION_NAME-access-search.json"

            echo "              Adding access for API ($V7_API_NAME) to $V7_APP_NAME" >&2
            local ACCESS_REQUEST_TITLE="$V7_APP_NAME"-"$V7_API_NAME"
            jq -n -f ./jq/mkt-accessrequest.jq --arg accessRequestTile "$ACCESS_REQUEST_TITLE" --arg productId "$MP_PRODUCT_ID" --arg productIdVersion "$MP_PRODUCT_VERSION_ID" --arg assetResourceId "$MP_ASSETRESOURCE_ID" --arg subscriptionId $MP_SUBSCRIPTION_ID > $LOGS_DIR/mkt-accessrequest-$SANITIZE_APPLICATION_NAME.json
            postToMarketplace "$MARKETPLACE_URL/api/v1/applications/$MP_APPLICATION_ID/accessRequests" $LOGS_DIR/mkt-accessrequest-$SANITIZE_APPLICATION_NAME.json $LOGS_DIR/mkt-accessrequest-$SANITIZE_APPLICATION_NAME-created.json
            error_post "Problem creating Access Request on Marketplace." $LOGS_DIR/mkt-accessrequest-$SANITIZE_APPLICATION_NAME-created.json
            echo "              AccessRequest created." >&2

            MP_ACCESS_REQUEST_ID=$(cat $LOGS_DIR/mkt-accessrequest-$SANITIZE_APPLICATION_NAME-created.json | jq -rc '.id')
            
        fi
    fi

    echo $MP_ACCESS_REQUEST_ID
}

#############################
# Approve the subscription is approval is manual
#
# Input:
# - $1: subscription ID
# Output: None
#############################
approveSubscription() {

    local SUBSCRIPTION_ID=$1

    # find the susbcription name
    getFromCentral "$CENTRAL_URL/apis/catalog/v1alpha1/subscriptions?query=metadata.id==$SUBSCRIPTION_ID" "" "$LOGS_DIR/susbcription-$SUBSCRIPTION_ID.json"

    SUBSCRIPTION_APPROVAL=$(jq -rc '.[].approval.state' "$LOGS_DIR/susbcription-$SUBSCRIPTION_ID.json")

    if [[ $SUBSCRIPTION_APPROVAL == "pending" ]]
    then
        SUBSCRIPTION_NAME=$(jq -rc '.[].name' "$LOGS_DIR/susbcription-$SUBSCRIPTION_ID.json")
        # build approval content
        jq -n -f ./jq/subscription-approval.jq --arg userGuid $USER_GUID > $LOGS_DIR/susbcription-$SUBSCRIPTION_ID-approval.json

        # post it
        putToCentral "$CENTRAL_URL/apis/catalog/v1alpha1/subscriptions/$SUBSCRIPTION_NAME/approval" "$LOGS_DIR/susbcription-$SUBSCRIPTION_ID-approval.json" "$LOGS_DIR/susbcription-$SUBSCRIPTION_ID-approved.json"
        error_exit "Failed to approve subscription" "$LOGS_DIR/susbcription-$SUBSCRIPTION_ID-approved.json"

        echo "              Subscription $SUBSCRIPTION_ID approved." >&2
    else
        echo "              Susbcription $SUBSCRIPTION_ID already approved!"
    fi

    # clean up intermediate files
    rm -rf $LOGS_DIR/susbcription-$SUBSCRIPTION_ID*
}

#####################################################################
# Create the marketplace access request based on the APP-API linkage
#
# Input:
# - $1: V7 application name
# Output: ACCESS_REQUEST_ID
#####################################################################
approveAndProvisionMarketplaceAccessRequest() {

    local V7_APP_NAME=$1
    local V7_APP_ID=$2
    local V7_API_ID=$3
    local ACCESS_REQUEST_TITLE=$4
    local ACCESS_REQUEST_TITLE_ENCODED=`printf %s "$ACCESS_REQUEST_TITLE" | jq -sRr @uri`
    local URL=$CENTRAL_URL'/apis/management/v1alpha1/accessrequests?query=title==%27'$ACCESS_REQUEST_TITLE_ENCODED'%27' 

    # find the Access request associated to the Marketplace Acces Request
    getFromCentral "$URL" "" $LOGS_DIR/accrequset-$ACCESS_REQUEST_TITLE_ENCODED.json

    # read existing information for the post (AccReq name + environment name)
    ACCESS_REQUEST_NAME=$(cat $LOGS_DIR/accrequset-$ACCESS_REQUEST_TITLE_ENCODED.json | jq -rc '.[].name')
    ACCESS_REQUEST_ENVIRONMENT_NAME=$(cat $LOGS_DIR/accrequset-$ACCESS_REQUEST_TITLE_ENCODED.json | jq -r '.[].metadata.scope.name')

    # mark it as provisioned (add the finalizers)
    jq --slurpfile file2 ./jq/agent-finalizer.json '(.[].finalizers += $file2)' $LOGS_DIR/accrequset-$ACCESS_REQUEST_TITLE_ENCODED.json > $LOGS_DIR/accrequset-$ACCESS_REQUEST_TITLE_ENCODED-finalizer.json

    # Remove references and status
    echo $(cat $LOGS_DIR/accrequset-$ACCESS_REQUEST_TITLE_ENCODED-finalizer.json  | jq -rc '.[]' | jq 'del(. | .status?, .metadata.references?, .references? )') > $LOGS_DIR/accrequset-$ACCESS_REQUEST_TITLE_ENCODED-update.json
    
    # Post to Central
    putToCentral "$CENTRAL_URL/apis/management/v1alpha1/environments/$ACCESS_REQUEST_ENVIRONMENT_NAME/accessrequests/$ACCESS_REQUEST_NAME" "$LOGS_DIR/accrequset-$ACCESS_REQUEST_TITLE_ENCODED-update.json" "$LOGS_DIR/accrequset-$ACCESS_REQUEST_TITLE_ENCODED-updated.json"
    error_exit "Problem while updating the access request agent information..." $LOGS_DIR/accrequset-$ACCESS_REQUEST_TITLE_ENCODED-updated.json

    # Add x-agent-details
    jq -n -f ./jq/agent-accreq-details.jq --arg accessID "$V7_API_ID" --arg applicationID $V7_APP_ID > $LOGS_DIR/agent-access-details-$V7_APP_ID.json

    # Post to Central
    putToCentral "$CENTRAL_URL/apis/management/v1alpha1/environments/$ACCESS_REQUEST_ENVIRONMENT_NAME/accessrequests/$ACCESS_REQUEST_NAME/x-agent-details" "$LOGS_DIR/agent-access-details-$V7_APP_ID.json" " $LOGS_DIR/accrequset-$ACCESS_REQUEST_TITLE_ENCODED-agent-details.json"
    error_exit "Problem while updating the agent details info..." $LOGS_DIR/accrequset-$ACCESS_REQUEST_TITLE_ENCODED-updated-state.json

    # Update status
    # mark it as done -> level = SUCCESS
    TIMESTAMP=$(date --utc +%FT%T.%3N%z)
    jq -n -f ./jq/agent-status-success.jq --arg timestampUTC "$TIMESTAMP" > $LOGS_DIR/agent-status-success.json
    putToCentral "$CENTRAL_URL/apis/management/v1alpha1/environments/$ACCESS_REQUEST_ENVIRONMENT_NAME/accessrequests/$ACCESS_REQUEST_NAME/status" "$LOGS_DIR/agent-status-success.json" " $LOGS_DIR/accrequset-$ACCESS_REQUEST_TITLE_ENCODED-updated-state.json"
    error_exit "Problem while updating the access request status..." $LOGS_DIR/accrequset-$ACCESS_REQUEST_TITLE_ENCODED-updated-state.json

    #clean up intermediate files
    rm -rf $LOGS_DIR/accrequset-$ACCESS_REQUEST_TITLE_ENCODED-finalizer.json
    rm -rf $LOGS_DIR/agent-access-details-$V7_APP_ID.json
    rm -rf $LOGS_DIR/agent-status-success.json
}

########################################################
# Migrate V7 Application into Marketplace Application
#
# Input parameters:
# 1- (optional) ApplicationName
########################################################
migrate_v7_application() {

    V7_APPLICATION_NAME_TO_MIGRATE=$1

    # Should we migrate all or just one?
    if [[ $V7_APPLICATION_NAME_TO_MIGRATE == '' ]]
    then
        # create the applicationList
        echo "Reading all applications" >&2
        getFromApiManager "applications" $TEMP_FILE
    else
        echo "Reading single application: $V7_APPLICATION_NAME_TO_MIGRATE" >&2
        getFromApiManager "applications" $LOGS_DIR/tmp.json
        # need to return an array for it to work regardless it is a single or multiple.
        cat $LOGS_DIR/tmp.json | jq  '[.[] | select(.name=="'"$V7_APPLICATION_NAME_TO_MIGRATE"'")]' >  $TEMP_FILE
        rm -rf $LOGS_DIR/tmp.json
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
            cat $MAPPING_DIR/$MAPPING_FILE_NAME | jq  '.[] | select(.ApplicationName=="'"$V7_APP_NAME"'")' | jq -rc '.Mapping' >  $LOGS_DIR/mapping-$V7_APP_NAME_SANITIZED.json

            # check there is some mapping
            if [[ `jq length $LOGS_DIR/mapping-$V7_APP_NAME_SANITIZED.json` != "" ]]
            then
                # find productID, productVersion and resourceID
                echo "      Mapping found." >&2

                # for each API assigned to the Application,
                cat $LOGS_DIR/app-$V7_APP_ID-apis.json | jq -rc ".[] | {apiId: .apiId}" | while IFS= read -r appApiLine ; do

                    V7_API_ID=$(echo $appApiLine | jq -r '.apiId')
                    V7_API_NAME=$(getAPIM_APIName "$V7_API_ID")
                    echo "          Found API: id=$V7_API_ID / name=$V7_API_NAME" >&2

                    # retrieve Product, and plan for creating the subscription
                    echo "              Searching corresponding productID and planID for creating the subscription..." >&2
                    PRODUCT_NAME=$(cat $LOGS_DIR/mapping-$V7_APP_NAME_SANITIZED.json | jq '.[] | select(.apiName=="'"$V7_API_NAME"'")' | jq -rc '.productName')
                    PRODUCT_PLAN_NAME=$(cat $LOGS_DIR/mapping-$V7_APP_NAME_SANITIZED.json | jq '.[] | select(.apiName=="'"$V7_API_NAME"'")' | jq -rc '.planName')

                    if [[ $PRODUCT_NAME != "" && $PRODUCT_PLAN_NAME != "" ]] 
                    then
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
                        approveSubscription "$MKT_SUBSCRIPTION_ID"

                        ## Access Request Management ##
                        echo "          Creating Access request..." >&2
                        MKT_ACCESS_REQUEST_TITLE="$V7_APP_NAME"-"$V7_API_NAME"
                        MKT_ACCESS_REQUEST_ID=$(createMarketplaceAccessRequestIfNotExisting "$V7_APP_NAME" "$V7_API_NAME" "$PRODUCT_NAME" "$MP_PRODUCT_ID" "$MP_PRODUCT_LATEST_VERSION_ID" "$MKT_SUBSCRIPTION_ID" "$MKT_APP_ID")
                        echo "          Access request created." >&2

                        # TODO = appove access request
                        echo "          Approving and Provisioning the Access Request..." >&2
                        PROVIDER_ACCESS_REQUEST=$(approveAndProvisionMarketplaceAccessRequest "$V7_APP_NAME" "$V7_APP_ID" "$V7_API_ID" "$MKT_ACCESS_REQUEST_TITLE")
                        echo "          Access Request activated." >&2

                        echo "          Provisioning the Credentials..." >&2
                        echo "          Access Request activated." >&2

                        echo "          Update ManageApp with the V7 APP ID..." >&2
                        echo "          Done." >&2

                    else
                        echo "          /!\ productName and/or planName for application ($V7_APP_NAME) and api ($V7_API_NAME) are not defined in the mapping, cannot proceed farther" >&2
                    fi

                done

                # creating credentials
                echo "      Creating credentials for application $V7_APP_NAME" >&2

                echo "          Creating credentials APIKEYS for application $V7_APP_NAME" >&2
                #https://lbean018.lab.phx.axway.int:8075/api/portal/v1.4/applications/4b3c2933-4307-44c1-aad3-51c2ee48a85a/apikeys
                createAndProvisionCredential
                echo "          Creating credentials OAUTH for application $V7_APP_NAME" >&2
                #https://lbean018.lab.phx.axway.int:8075/api/portal/v1.4/applications/4b3c2933-4307-44c1-aad3-51c2ee48a85a/oauth
                echo "          Creating credentials EXTERNAL for application $V7_APP_NAME" >&2
                #https://lbean018.lab.phx.axway.int:8075/api/portal/v1.4/applications/4b3c2933-4307-44c1-aad3-51c2ee48a85a/extclients

            else
                echo "      /!\ No mapping found... Cannot proceed farther" >&2
            fi

        else # It is  the Amplify Agents org - nothing to do
            echo "  Skipping team / app creation as already present in Marketplace" >&2
        fi

    done

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
    source $1
else 
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

# create the Amplify Agents organization if not exist and retrieve its ID or the Existing org ID.
AGENT_V7_ORG_ID=$(createAmplifyAgentOrganizationIfNotExisting)

echo ""
echo "Creating the Marketplace Application"
migrate_v7_application "Testing APP with missing org"
echo "Done."

#rm $LOGS_DIR/*

exit 0