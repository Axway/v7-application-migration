#!/bin/bash

# add all utility functions
source ./utils.sh

# Global variables
LOGS_DIR=./Logs
CONFIG_DIR=./Config
MAPPING_DIR=./Mapping
TEMP_FILE=$LOGS_DIR/applicationListTemp.json
OUTPUT_FILE=$MAPPING_DIR/mappingAPP-Product-generated.json


####################################################
# Finding product where the APIs is used
# In case multiple product matches, list them all
#
# Input:
# - $1: v7 API name (is APIService title)
# - $2: v7 API ID
# Output:
# - file containing appropriate ingo
#####################################################
function findProductInformation() {

    local V7_API_NAME="$1"
    local V7_API_ID="$2"
    local PRODUCT_NAME_FOUND=$TBD_VALUE
    local PRODUCT_PLAN_NAME_FOUND=$TBD_VALUE
    local ENVIRONMENT_NAME_FOUMD=$TBD_VALUE
    local CREDENTIAL_REQUEST_DEFINITION_ID_FOUND="$TBD_VALUE"
    local APISERV_INSTANCE_ID="$TBD_VALUE"
    local noError=0

    echo "      Looking for product for API ($V7_API_NAME - $V7_API_ID)" >&2 

    # find the service
    local V7_API_NAME_FOR_SEARCH=$(sanitizeNameForQuery "$V7_API_NAME")      
    local URL=$CENTRAL_URL'/apis/management/v1alpha1/apiservices?query=title==%27'$V7_API_NAME_FOR_SEARCH'%27' 
    getFromCentral "$URL" "" "$LOGS_DIR/api-srv-$V7_API_ID-search.json"
    error_exit "---<<WARNING>> Unable to retrieve API ($V7_API_NAME)" "$LOGS_DIR/api-srv-$V7_API_ID-search.json"

    API_NUMBER=`jq length "$LOGS_DIR/api-srv-$V7_API_ID-search.json"`

    if [[ $API_NUMBER == 0 ]]
    then
        echo "---<<WARNING>> API ($V7_API_NAME) not found. Please check that Discovery Agent has discovered API ($V7_API_NAME)" >&2
    else
        # there could be multiple API with same name, only the x-agent-details.externalAPIID can highlight the correct one
        jq '[.[] | select(.["x-agent-details"].externalAPIID == "'"$V7_API_ID"'")]' "$LOGS_DIR/api-srv-$V7_API_ID-search.json" > "$LOGS_DIR/api-srv-$V7_API_ID-filtered.json"

        NB_API_SERVICE_FOUND=`jq length "$LOGS_DIR/api-srv-$V7_API_ID-filtered.json"`

        if [[ $NB_API_SERVICE_FOUND != 0 ]]
        then
            if [[ $NB_API_SERVICE_FOUND > 1 ]]
            then
                echo "---<<WARNING>> API ($V7_API_NAME) has been found multiple times. Please remove any duplicate prior to proceed." >&2
            else
                APISERV_NAME=$(cat "$LOGS_DIR/api-srv-$V7_API_ID-filtered.json" | jq -rc '.[].name' )
                APISERV_ID=$(cat "$LOGS_DIR/api-srv-$V7_API_ID-filtered.json" | jq -rc '.[].metadata.id' )
                ENVIRONMENT_NAME_FOUMD=$(cat "$LOGS_DIR/api-srv-$V7_API_ID-filtered.json" | jq -rc '.[].metadata.scope.name' )
                echo "          We found APIService we are looking for: $APISERV_NAME ($APISERV_ID) from $ENVIRONMENT_NAME_FOUMD environment" >&2
                
                # find Asset /!\ use id instead of name
                getFromCentral "$CENTRAL_URL/apis/catalog/v1alpha1/assets?query=metadata.references.id==$APISERV_ID" "" "$LOGS_DIR/api-srv-$V7_API_ID-asset.json"
                error_exit "---<<WARNING>> Unable to retrieve Asset linked to API ($V7_API_NAME)" "$LOGS_DIR/api-srv-$V7_API_ID-asset.json"

                ASSET_NUMBER=`jq length "$LOGS_DIR/api-srv-$V7_API_ID-asset.json"`

                if [[ $ASSET_NUMBER == 0 ]]
                then
                    echo "---<<WARNING>> No asset is managing $V7_API_NAME... You need to have at least one asset/product/plan to run the migration." >&2
                else
                    if [[ $ASSET_NUMBER > 1 ]]
                    then
                        echo "---<<WARNING>> API ($V7_API_NAME) is embedded in multiple assets. You will need to manually update the mapping file and select appropriate Product and Plan" >&2
                    else
                        # Read the asset name
                        ASSET_NAME=$(cat "$LOGS_DIR/api-srv-$V7_API_ID-asset.json" | jq -rc '.[].name')
                        ASSET_ID=$(cat "$LOGS_DIR/api-srv-$V7_API_ID-asset.json" | jq -rc '.[].metadata.id')
                        echo "          We found the asset ($ASSET_NAME : $ASSET_ID) that manage API ($V7_API_NAME)..." >&2

                        # read the asset resource to find the CRD_ID
                        # find API Service instance
                        getFromCentral "$CENTRAL_URL/apis/management/v1alpha1/environments/$ENVIRONMENT_NAME_FOUMD/apiserviceinstances?query=metadata.references.id==$APISERV_ID" "" "$LOGS_DIR/api-srv-$V7_API_ID-instance.json"
                        error_exit "---<<WARNING>> Unable to retrieve API Service Instance for ($APISERV_NAME)" "$LOGS_DIR/api-srv-$V7_API_ID-instance.json"

                        #/!\ several instance possible...
                        APISERV_INSTANCE_NUMBER=`jq length "$LOGS_DIR/api-srv-$V7_API_ID-instance.json"`
                        if [[ $APISERV_INSTANCE_NUMBER > 1 ]]
                        then
                            echo "---<<WARNING>> API ($V7_API_NAME) has several API Service Instance..." >&2
                        else

                            APISERV_INSTANCE_NAME=$(cat "$LOGS_DIR/api-srv-$V7_API_ID-instance.json" | jq -rc '.[].name')
                            APISERV_INSTANCE_ID=$(cat "$LOGS_DIR/api-srv-$V7_API_ID-instance.json" | jq -rc '.[].metadata.id')

                            # find AssetResources having the APIServiceInstance
                            getFromCentral "$CENTRAL_URL/apis/catalog/v1alpha1/assets/$ASSET_NAME/assetresources?query=metadata.references.id==$APISERV_INSTANCE_ID" "" "$LOGS_DIR/api-srv-$V7_API_ID-asset-resources.json"
                            error_exit "---<<WARNING>> Unable to retrieve Asset resources for asset ($ASSET_NAME)" "$LOGS_DIR/api-srv-$V7_API_ID-asset-resources.json"

                            ASSET_RESOURCE_NAME=$(cat "$LOGS_DIR/api-srv-$V7_API_ID-asset-resources.json" | jq -rc '.[].name')
                            ASSET_RESOURCE_CRD_ID=$(jq -rc '.[].metadata.references[] | select(.kind == "CredentialRequestDefinition").id' "$LOGS_DIR/api-srv-$V7_API_ID-asset-resources.json")

                            if [[ $ASSET_RESOURCE_CRD_ID == '' ]]
                            then
                                echo "Assert credential request definition not found" >&2
                            else
                                CREDENTIAL_REQUEST_DEFINITION_ID_FOUND=$ASSET_RESOURCE_CRD_ID
                                echo "          Assert credential request definition found" >&2
                            fi

                        # find product
                        getFromCentral "$CENTRAL_URL/apis/catalog/v1alpha1/products?query=metadata.references.id==$ASSET_ID" "" "$LOGS_DIR/api-srv-$V7_API_ID-product.json"
                        error_exit "---<<WARNING>> Unable to retrieve Product linked to Asset ($ASSET_NAME)" "$LOGS_DIR/api-srv-$V7_API_ID-product.json"

                            PRODUCT_NUMBER=`jq length "$LOGS_DIR/api-srv-$V7_API_ID-product.json"`

                            if [[ $PRODUCT_NUMBER == 0 ]]
                            then
                                    echo "---<<WARNING>> API ($V7_API_NAME) is part of an asset ($ASSET_NAME) that is not embed in any product." >&2
                            else
                                if [[ $PRODUCT_NUMBER > 1 ]]
                                then
                                        echo "---<<WARNING>> API ($V7_API_NAME) is part of an asset ($ASSET_NAME) that is embed in multiple products." >&2
                                else
                                    PRODUCT_NAME_FOUND=$(cat "$LOGS_DIR/api-srv-$V7_API_ID-product.json" | jq -rc '.[].title')
                                    PRODUCT_ID=$(cat "$LOGS_DIR/api-srv-$V7_API_ID-product.json" | jq -rc '.[].metadata.id')
                                    echo "          Found the product - $PRODUCT_NAME_FOUND" >&2

                                    # Now find the plan
                                    getFromCentral "$CENTRAL_URL/apis/catalog/v1alpha1/productplans?query=metadata.references.id==$PRODUCT_ID" "" "$LOGS_DIR/api-srv-$V7_API_ID-product-plans.json"
                                    error_exit "---<<WARNING>> Unable to retrieve Product plan linked to Product ($PRODUCT_NAME_FOUND)" "$LOGS_DIR/api-srv-$V7_API_ID-product-plans.json"

                                    PRODUCT_PLAN_NUMBER=`jq length "$LOGS_DIR/api-srv-$V7_API_ID-product-plans.json"`

                                    if [[ $PRODUCT_PLAN_NUMBER == 0 ]]
                                    then
                                        echo "---<<WARNING>> API ($V7_API_NAME) is part of a product ($PRODUCT_NAME_FOUND) that has no plan. You need to create a plan to perform the migration successfully." >&2
                                    else 
                                        if [[ $PRODUCT_PLAN_NUMBER> 1 ]]
                                        then
                                            echo "---<<WARNING>> API ($V7_API_NAME) is part of a product ($PRODUCT_NAME_FOUND) that have multiple plans. You need to choose which one to apply" >&2
                                        else
                                            # only 1 plan found
                                            PRODUCT_PLAN_ID=$(cat "$LOGS_DIR/api-srv-$V7_API_ID-product-plans.json" | jq -rc '.[].metadata.id')
                                            PRODUCT_PLAN_NAME=$(cat "$LOGS_DIR/api-srv-$V7_API_ID-product-plans.json" | jq -rc '.[].name')

                                            #TODO check if plan is activated?

                                            # find the Quota for the AssetResources.
                                            getFromCentral "$CENTRAL_URL/apis/catalog/v1alpha1/quotas?query=metadata.references.name==$ASSET_RESOURCE_NAME" "" "$LOGS_DIR/api-srv-$V7_API_ID-product-plan-quota.json"
                                            error_exit "---<<WARNING>> Unable to retrieve product ($PRODUCT_NAME_FOUND) quotas" "$LOGS_DIR/api-srv-$V7_API_ID-product-plan-quota.json"

                                            # filter with plan name
                                            jq '[.[] | select(.metadata.scope.name == "'"$PRODUCT_PLAN_NAME"'")]' "$LOGS_DIR/api-srv-$V7_API_ID-product-plan-quota.json" > "$LOGS_DIR/api-srv-$V7_API_ID-product-plan-filtered.json"

                                            QUOTA_NUMBER=`jq length "$LOGS_DIR/api-srv-$V7_API_ID-product-plan-filtered.json"`

                                            if [[ $QUOTA_NUMBER != 0 ]]
                                            then 
                                                # found a plan that handle the current API
                                                PRODUCT_PLAN_NAME_FOUND=$(cat "$LOGS_DIR/api-srv-$V7_API_ID-product-plans.json" | jq -rc '.[].title')

                                                # allow to clean up intermediate files
                                                noError=1
                                            else
                                                echo "---<<WARNING>> API ($V7_API_NAME) is not part of any plan quota of the product ($PRODUCT_NAME_FOUND}. You need to create a plan for this service." >&2
                                            fi
                                        fi
                                    fi
                                fi
                            fi
                        fi
                    fi
                fi
            fi
        else
            # API does not contain correct APIM identifier
            echo "---<<WARNING>> API ($V7_API_NAME) does not contain the correct API Manager API ID. Either the API has not been discovered or the agent is too old." >&2
        fi
    fi

    if [[ $noError == 1 ]]
    then
        # clean up intermediate files when no errors occured
        deleteFile $LOGS_DIR/api-srv-"$V7_API_ID"*.json
    fi

    # compute final result
    echo `jq -n -f ./jq/mapping-product-info.jq --arg productName "$PRODUCT_NAME_FOUND" --arg productPlanName "$PRODUCT_PLAN_NAME_FOUND" --arg environmentName "$ENVIRONMENT_NAME_FOUMD" --arg apiServiceInstanceId "$APISERV_INSTANCE_ID" --arg credentialRequestDefinition "$CREDENTIAL_REQUEST_DEFINITION_ID_FOUND"`
}

#####################################
# Create the mapping file
#####################################
function generateMappingFile() {

    # create the file
    echo "Initializing Mapping file ($OUTPUT_FILE)" >&2
    echo "[]" > $OUTPUT_FILE

    echo "-$APP_NAME_TO_MIGRATE-" >&2
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
        rm -rf $LOGS_DIR/tmp.json
    fi

    # loop over the result and keep interesting data (name / description / org)
    cat $TEMP_FILE | jq -rc ".[] | {appId: .id, orgId: .organizationId, appName: .name}" | while IFS= read -r line ; do

        #echo "line=$line" >&2
        # read values
        V7_APP_ID=$(echo $line | jq -r '.appId')
        V7_ORG_ID=$(echo $line | jq -r '.orgId')
        V7_APP_NAME=$(echo $line | jq -r '.appName')

        # read organization name for creating the corresponding team name if needed
        v7_ORG_NAME=$(getAPIM_OrganizationName "$V7_ORG_ID")
        echo "  TEAM_NAME=$v7_ORG_NAME / APP_NAME=$V7_APP_NAME" >&2

        # Adding the organization as a team in Amplify?
        if [[ "$v7_ORG_NAME" != "Amplify Agents" ]]; then

            # create the mapping header (APP / owner)
            # Add  
            echo "  Create Application ($V7_APP_NAME) mapping section..." >&2
            jq -n -f ./jq/mapping-template.jq --arg applicationName "$V7_APP_NAME" --arg owningTeam "$v7_ORG_NAME" > $MAPPING_DIR/mapping-app.json

            # for each application, find the API.
            getFromApiManager "applications/$V7_APP_ID/apis" "$LOGS_DIR/app-$V7_APP_ID-apis.json" > "$LOGS_DIR/app-api-$V7_APP_ID-list.json"

            # for each API, find the product and plan that match it
            cat "$LOGS_DIR/app-$V7_APP_ID-apis.json" | jq -rc ".[] | {apiId: .apiId}" | while IFS= read -r appApiLine ; do

                V7_API_ID=$(echo $appApiLine | jq -rc '.apiId')
                V7_API_NAME=$(getAPIM_APIName "$V7_API_ID")

                # check that the API is not retired
                V7_API_RETIRED=$(getAPIM_APIRetired "$V7_API_ID")

                if [[ "$V7_API_RETIRED" == "false" ]]; then
                    # search product Information
                    PRODUCT_INFORMATION=$(findProductInformation "$V7_API_NAME" "$V7_API_ID")

                    # extract values
                    PRODUCT_NAME=$(echo $PRODUCT_INFORMATION | jq -rc '.productName')
                    PRODUCT_PLAN_NAME=$(echo $PRODUCT_INFORMATION | jq -rc '.productPlanName')
                    EMVIRONMENT_NAME=$(echo $PRODUCT_INFORMATION | jq -rc '.apiEnvironmentName')
                    CRD_ID=$(echo $PRODUCT_INFORMATION | jq -rc '.credentialRequestDefinition')
                    APISERVICE_INSTANCE_ID=$(echo $PRODUCT_INFORMATION | jq -rc '.apiServiceInstanceId')
                
                    # create the mapping-api piece
                    echo "      create mapping-API for API ($V7_API_NAME)" >&2 
                    jq -n -f ./jq/mapping-template-api.jq --arg apiName "$V7_API_NAME" --arg productName "$PRODUCT_NAME" --arg productPlanName "$PRODUCT_PLAN_NAME" --arg environment "$EMVIRONMENT_NAME" --arg apiServiceInstanceId "$APISERVICE_INSTANCE_ID" --arg credentialRequestDefinitionId "$CRD_ID" > $MAPPING_DIR/mapping-api.json

                    # add it to the Mapping array
                    echo "      add current into application mapping array" >&2
                    jq --slurpfile file2 $MAPPING_DIR/mapping-api.json '(.Mapping += $file2)' $MAPPING_DIR/mapping-app.json > $MAPPING_DIR/mapping-app-temp.json
                    mv $MAPPING_DIR/mapping-app-temp.json $MAPPING_DIR/mapping-app.json
                else
                    echo "---<<WARNING>> API - $V7_API_NAME with id $V7_API_ID is retired - Ignoring it for the mapping." >&2

                fi
            done

            # add current Application mapping into the target file
            echo "  Adding application mapping section into the output generated file" >&2
            jq --slurpfile file2 $MAPPING_DIR/mapping-app.json '(. += $file2)' $OUTPUT_FILE > $MAPPING_DIR/tempFile.json
            mv $MAPPING_DIR/tempFile.json $OUTPUT_FILE

            # clean intermediate files
            deleteFile $MAPPING_DIR/mapping-app.json
            deleteFile $MAPPING_DIR/mapping-api.json
            deleteFile $LOGS_DIR/app-"$V7_APP_ID"-apis.json
            deleteFile $LOGS_DIR/app-api-"$V7_APP_ID"-list.json
        fi

    done

    deleteFile $TEMP_FILE

}


#########
# Main
#########

echo ""
echo "==============================================================================" 
echo "== Creating API/APP mapping file fron API Manager and Central               ==" 
echo "== API Manager access and Amplify Platform access are required              =="
echo "== curl and jq programs are required                                        =="
echo "==============================================================================" 
echo ""

if [[ $1 != null ]]
then
    source $1

    if [[ $MAPPING_FILE_NAME != null ]]
    then
        OUTPUT_FILE=$MAPPING_DIR/$MAPPING_FILE_NAME
        echo "Set sepecific output Mapping file: $OUTPUT_FILE"
    fi
else
    echo "We are using the default env.properties"
    source $CONFIG_DIR/env.properties
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

echo ""
echo "Creating the Mapping file"
generateMappingFile 
echo "Done."

#rm $LOGS_DIR

exit 0
